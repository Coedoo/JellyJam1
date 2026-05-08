package game

import "core:mem"

import "core:math"
import "core:math/ease"
import "core:math/linalg/glsl"
import "core:fmt"

import "core:strings"

import rl "vendor:raylib"

Color :: [4]f32

ToV2 :: proc(p: iv2) -> v2 {
    return {f32(p.x), f32(p.y)}
}

/////////
// Context management
/////////

Id :: distinct u32


uiCtx: UIContext

UIContext :: struct {
    transientArena: mem.Arena,
    transientAllocator: mem.Allocator,

    input: Input,

    nodes: [dynamic; 1024]UINode,

    hotId: Id,
    activeId: Id,

    hashStack: [dynamic; 256]Id,
    parentStack: [dynamic; 256]^UINode,

    // Layout
    popLayoutAfterUse: bool,
    layoutStack: [dynamic; 16]Layout,

    defaultLayout: Layout,
    panelLayout: Layout,
    textLayout: Layout,
    buttonLayout: Layout,

    nextNodePos: Maybe(v2),
    nextNodeOrigin: Maybe(v2),

    // Styles
    popStyleAfterUse: bool,
    stylesStack: [dynamic; 16]Style,

    defaultStyle: Style,
    panelStyle: Style,
    textStyle: Style,
    buttonStyle: Style,

    disabled: bool,

    clippingStack: [dynamic; 128]RectInt,
}

Input :: struct {
    mousePos: iv2,
    mouseDelta: v2,

    leftMousePressed: bool,
    leftMouseDown: bool,
    leftMouseReleased: bool
}

/////////
// Nodes
/////////

NodeFlag :: enum {
    DrawBackground,
    DrawText,
    BackgroundTexture,

    Clickable,

    Floating,

    AnchoredPosition,

    ScrollX,
    ScrollY,

    Clip,
}

NodeFlags :: distinct bit_set[NodeFlag]

UINode :: struct {
    using PerFrameData : struct {
        parent: ^UINode,

        firstChild:  ^UINode,
        lastChild:   ^UINode,
        prevSibling: ^UINode,
        nextSibling: ^UINode,
        childrenCount: int,

        touchedThisFrame: bool,

        flags: NodeFlags,
    },

    id: Id,

    text: string,
    // textSize: v2,

    texture: rl.Texture,
    textureSource: RectInt,
    tint: Maybe(Color),

    origin: v2,

    timeSinceHot: f32,

    targetPos: v2,
    targetSize: v2,

    viewOffset: v2,

    folded: bool,
    disabled: bool,

    using style: Style,
    using layout: Layout,
}

UINodeInteraction :: struct {
    clicked: bool,

    hovered: bool,
    scroll: bool,

    dragging: bool,
}

/////////
// Style
/////////
LayoutAxis :: enum {
    X,
    Y,
}

NodeSizeType :: enum {
    None,
    Fixed,
    Text,
    Children,
    ParentPercent
}

NodePreferredSize :: struct {
    type: NodeSizeType,
    value: f32,
    strictness: f32,
}

AligmentX :: enum {
    Left, Middle, Right,
}
AligmentY :: enum {
    Top, Middle, Bottom,
}
Aligment :: struct {
    y: AligmentY,
    x: AligmentX,
}

Style :: struct {
    font: rl.Font,
    fontSize: int,
    textAligment: Aligment,

    textColor: Color,
    bgColor: Color,

    disabledBgColor: Color,

    hotColor: Color,
    activeColor: Color,

    padding: RectInt,

    hotAnimTime: f32,
    hotAnimEase: ease.Ease,
    hotScale: f32,
}

Layout :: struct {
    childrenAxis: LayoutAxis,
    childrenAligment: Aligment,

    spacing: int,

    preferredSize: [LayoutAxis]NodePreferredSize,
}

UIAnchor :: enum {
    TopLeft,
    TopCenter,
    TopRight,
    MiddleLeft,
    MiddleCenter,
    MiddleRight,
    BotLeft,
    BotCenter,
    BorRight,
}

UIAnchorToPercent: [UIAnchor]v2 = {
    .TopLeft      = {0,   0},
    .TopCenter    = {0.5, 0},
    .TopRight     = {1,   0},
    .MiddleLeft   = {0,   0.5},
    .MiddleCenter = {0.5, 0.5},
    .MiddleRight  = {1,   0.5},
    .BotLeft      = {0,   1},
    .BotCenter    = {0.5, 1},
    .BorRight     = {1,   1},
}

InitUI :: proc(uiCtx: ^UIContext) {
    memory := make([]byte, mem.Megabyte) // @LEAK
    mem.arena_init(&uiCtx.transientArena, memory)
    uiCtx.transientAllocator = mem.arena_allocator(&uiCtx.transientArena)

    // font := LoadDefaultFont(renderCtx)
    uiCtx.defaultStyle = {
        // font = font,
        fontSize = 40,
        textAligment = {.Middle, .Middle},

        textColor = {1, 1, 1, 1},
        bgColor = {1, 1, 1, 1},

        disabledBgColor = {0.3, 0.3, 0.3, 1},

        hotColor = {0.4, 0.4, 0.4, 1},
        activeColor = {0.6, 0.6, 0.6, 1},

        // padding = {3, 3, 3, 3},

        hotAnimTime = 0.1,
        hotAnimEase = .Cubic_Out,
        hotScale = 1,
    }

    uiCtx.defaultLayout = {
        childrenAxis = .Y,
        childrenAligment = { .Top, .Left },

        spacing = 5,

        preferredSize = {.X = {.Fixed, 100, 1},  .Y = {.Fixed, 30, 1}},
    }

    uiCtx.panelStyle = uiCtx.defaultStyle
    uiCtx.panelStyle.bgColor = {0.2, 0.2, 0.2, 0.9}
    uiCtx.panelStyle.padding = { 3, 3, 3, 3 }

    uiCtx.panelLayout = uiCtx.defaultLayout
    uiCtx.panelLayout.childrenAligment = {.Middle, .Middle}
    uiCtx.panelLayout.preferredSize = {.X = {.Children, 0, 1}, .Y = {.Children, 0, 1}}

    uiCtx.textStyle = uiCtx.defaultStyle
    uiCtx.textLayout = uiCtx.defaultLayout
    uiCtx.textLayout.preferredSize = {.X = {.Text, 0, 1}, .Y = {.Text, 0, 1}}

    uiCtx.buttonStyle = uiCtx.defaultStyle
    uiCtx.buttonStyle.bgColor = {0.05, 0.1, 0.9, 1}
    uiCtx.buttonStyle.hotColor = {1, 0.3, 0.5, 1}
    uiCtx.buttonStyle.activeColor = {1, 0.5, 0.6, 1}
    uiCtx.buttonStyle.hotScale = 1.1
    uiCtx.buttonStyle.padding = { 3, 3, 3, 3 }

    uiCtx.buttonLayout = uiCtx.defaultLayout
    uiCtx.buttonLayout.preferredSize = {.X = {.Text, 0, 1}, .Y = {.Text, 0, 1}}
}

PushParent :: proc(parent: ^UINode) {
    append(&uiCtx.parentStack, parent)
    
    if parent.id != 0 {
        append(&uiCtx.hashStack, parent.id)
    }

    if .Clip in parent.flags {
        append(&uiCtx.clippingStack, NodeRect(parent))
    }
}

PopParent :: proc() {
    parent := pop(&uiCtx.parentStack)

    if parent.id != 0 {
        pop(&uiCtx.hashStack)
    }

    if .Clip in parent.flags {
        pop(&uiCtx.clippingStack)
    }
}

PushId :: proc {
    PushIdBytes,
    PushIdStr,
    PushIdPtr,
    PushIdInt,
}

PushIdPtr :: proc(ptr: rawptr) {
    ptr := ptr
    bytes := cast([^]byte) (&ptr)
    PushIdBytes(bytes[:size_of(ptr)])
}

PushIdStr :: proc(str: string) {
    // @Note: I believe this doesn't transmute content of the string
    // but only pointer + length
    PushIdBytes(transmute([]byte) str)
}

PushIdBytes :: proc(bytes: []byte) {
    id := GetIdBytes(bytes)
    append(&uiCtx.hashStack, id)
}

PushIdInt :: proc(#any_int i: int) {
    i := i
    PushIdPtr(&i)
}

PopId :: proc() {
    pop(&uiCtx.hashStack);
}

GetId :: proc {
    GetIdPtr,
    GetIdStr,
    GetIdBytes,
}

GetIdPtr :: proc(ptr: rawptr) -> Id {
    return GetIdBytes(([^]byte)(ptr)[:size_of(ptr)])
}

GetIdStr :: proc(str: string) -> Id {
    return GetIdBytes(transmute([]byte) str)
}

GetIdBytes :: proc(bytes: []byte) -> Id {
    /* 32bit fnv-1a hash */
    HASH_INITIAL :: 2166136261
    hash :: proc(hash: ^Id, data: []byte) {
        size := len(data)
        cptr := ([^]u8)(raw_data(data))
        for ; size > 0; size -= 1 {
            hash^ = Id(u32(hash^) ~ u32(cptr[0])) * 16777619
            cptr = cptr[1:]
        }
    }

    prev := uiCtx.hashStack[len(uiCtx.hashStack) - 1] if len(uiCtx.hashStack) != 0 else HASH_INITIAL
    hash(&prev, bytes)

    return prev
}

uiFmt :: proc(args: ..any) -> string {
    return fmt.aprint(..args, allocator = uiCtx.transientAllocator)
}

NodeRect :: proc(node: ^UINode) -> RectInt {
    left  := i32(node.targetPos.x)
    top   := i32(node.targetPos.y)
    right := i32(node.targetPos.x + node.targetSize.x)
    bot   := i32(node.targetPos.y + node.targetSize.y)

    return {left, right, top, bot}
}

IsPointOverUI :: proc(point: iv2) -> bool {
    for node in uiCtx.nodes {
        checkFlags := NodeFlags{ .DrawBackground, .DrawText, .BackgroundTexture }
        // fmt.println(node.flags, checkFlags <= node.flags)
        if card(checkFlags & node.flags) != 0 {
            left  := node.targetPos.x
            top   := node.targetPos.y
            right := node.targetPos.x + node.targetSize.x
            bot   := node.targetPos.y + node.targetSize.y

            if f32(point.x) >= left &&
               f32(point.x) <= right &&
               f32(point.y) >= top  &&
               f32(point.y) <= bot
            {
                return true
            }
        }
    }

    return false
}

DoLayoutParentPercent :: proc(node: ^UINode) {
    for axis in LayoutAxis {
        size := node.preferredSize[axis]

        // if size.type == .ParentPercent {
        //     parent := node.parent
        //     parentPadding := parent.padding.left + parent.padding.right

        //     node.targetSize[axis] = parent.targetSize[axis] * size.value - f32(parentPadding)
        // }
        if size.type == .ParentPercent {

            parent := node.parent
            for parent != nil {
                if parent.preferredSize[axis].type != .Children {
                    parentPadding := parent.padding.left + parent.padding.right

                    node.targetSize[axis] = parent.targetSize[axis] * size.value - f32(parentPadding)
                    break
                }

                parent = parent.parent
            }
        }
    }

    for next := node.firstChild; next != nil; next = next.nextSibling {
        DoLayoutParentPercent(next)
    }
}

DoLayoutChildren :: proc(node: ^UINode) {
    for next := node.firstChild; next != nil; next = next.nextSibling {
        DoLayoutChildren(next)
    }

    for axis in LayoutAxis {
        size := node.preferredSize[axis]

        if size.type == .Children {
            node.targetSize[axis] = 0 
            for next := node.firstChild; next != nil; next = next.nextSibling {
                if .Floating in next.flags {
                    continue
                }

                if axis == node.childrenAxis {
                    node.targetSize[axis] += next.targetSize[axis]
                    if next.nextSibling != nil {
                        node.targetSize[axis] += f32(node.spacing)
                    }
                }
                else {
                    node.targetSize[axis] = max(node.targetSize[axis], next.targetSize[axis])
                }
            }

            // @NOTE @TODO: I'm sure this can be done better
            // if axis == node.childrenAxis {
            //     node.targetSize[axis] += f32(node.childrenCount - 1) * f32(node.spacing)
            // }

            if axis == .X {
                node.targetSize.x += f32(node.padding.left + node.padding.right)
            }
            else {
                node.targetSize.y += f32(node.padding.top + node.padding.bot)
            }
        }
    }
}

ResolveLayoutContraints :: proc(node: ^UINode) {
    childrenSize: v2
    childrenMinSize: v2

    for child := node.firstChild; child != nil; child = child.nextSibling {
        childrenSize += child.targetSize
        childrenMinSize.x += child.targetSize.x * (1 - child.preferredSize[.X].strictness)
        childrenMinSize.y += child.targetSize.y * (1 - child.preferredSize[.Y].strictness)
    }

    childrenSize[node.childrenAxis] += f32(node.childrenCount - 1) * f32(node.spacing)
    childrenSize.x += f32(node.padding.left + node.padding.right)
    childrenSize.y += f32(node.padding.top + node.padding.bot)

    maxSize := node.targetSize
    violation := childrenSize - maxSize


    for child := node.firstChild; child != nil; child = child.nextSibling {
        for axis, i in LayoutAxis {
            // i := cast(int) axis
            if child.preferredSize[axis].type == .ParentPercent {
                child.targetSize[i] = node.targetSize[i] * child.preferredSize[axis].value
            }
        }
    }

    // @TODO: what to do when childrenMinSize == 0?
    for i in 0..=1 {
        axis := LayoutAxis(i)
        if violation[i] > 0 {
            // if axis == node.childrenAxis {
                for child := node.firstChild; child != nil; child = child.nextSibling {
                    toRemove := child.targetSize[i] * (1 - child.preferredSize[axis].strictness)

                    if toRemove == 0 {
                        continue
                    }

                    scaledRemove :=  violation[i] * (toRemove / childrenMinSize[i])
                    child.targetSize[i] -= scaledRemove
                }
            // }
            // else {
            //     for child := node.firstChild; child != nil; child = child.nextSibling {
            //         if child.targetSize[i] > maxSize[i] {
            //             child.targetSize[i] = maxSize[i]
            //         }
            //     }
            // }
        }

        // for child := node.firstChild; child != nil; child = child.nextSibling {
        //     if child.preferredSize[axis].type == .ParentPercent {
        //         child.targetSize[i] = node.targetSize[i] * child.preferredSize[axis].value
        //     }
        // }
    }


    for next := node.firstChild; next != nil; next = next.nextSibling {
        ResolveLayoutContraints(next)
    }
}

DoFinalLayout :: proc(node: ^UINode) {
    nodePos := node.targetPos - node.targetSize * node.origin
    if node.childrenAxis == .X {
        childrenSize := node.targetSize.x - f32(node.padding.left + node.padding.right)
        childPos: f32

        switch node.childrenAligment.x {
        case .Left:   childPos = nodePos.x + f32(node.padding.left)
        case .Middle: childPos = nodePos.x + (node.targetSize.x - childrenSize) / 2
        case .Right:  childPos = nodePos.x + (node.targetSize.x - childrenSize) - f32(node.padding.right)
        }

        for next := node.firstChild; next != nil; next = next.nextSibling {
            if .Floating in next.flags {
                continue
            }

            // if .AnchoredPosition in next.flags {
            //     next.targetPos = 
            //         node.targetPos + node.targetSize * next.anchoredPosPercent + next.anchoredPosOffset
            //     continue
            // }

            if .Floating not_in next.flags {
                next.targetPos.x = childPos
                
                switch node.childrenAligment.y {
                case .Top:
                    next.targetPos.y = nodePos.y
                    next.targetPos.y += f32(node.padding.top)
                case .Middle:
                    sizeWithoutPadding := node.targetSize.y - f32(node.padding.top + node.padding.bot)
                    next.targetPos.y = nodePos.y + (sizeWithoutPadding - next.targetSize.y) / 2
                    next.targetPos.y += f32(node.padding.bot)
                case .Bottom:
                    next.targetPos.y = nodePos.y + (node.targetSize.y - next.targetSize.y)
                    next.targetPos.y -= f32(node.padding.bot)
                }
            }

            next.targetPos += node.viewOffset

            childPos += next.targetSize.x + f32(node.spacing)
        }
    }
    else {
        childrenSize := node.targetSize.y - f32(node.padding.top + node.padding.bot)
        childPos: f32
        switch node.childrenAligment.y {
        case .Top:    childPos = nodePos.y + f32(node.padding.top)
        case .Middle: childPos = nodePos.y + (node.targetSize.y - childrenSize) / 2
        case .Bottom: childPos = nodePos.y + (node.targetSize.y - childrenSize) - f32(node.padding.bot)
        }

        for next := node.firstChild; next != nil; next = next.nextSibling {
            if .Floating in next.flags {
                continue
            }

            // if .AnchoredPosition in next.flags {
            //     next.targetPos = 
            //         node.targetPos + node.targetSize * next.anchoredPosPercent + next.anchoredPosOffset
            //     continue
            // }

            if .Floating not_in next.flags {

                next.targetPos.y = childPos
                switch node.childrenAligment.x {
                case .Left:
                    next.targetPos.x = nodePos.x
                    next.targetPos.x += f32(node.padding.left)
                case .Middle:
                    sizeWithoutPadding := node.targetSize.x - f32(node.padding.left + node.padding.right)
                    next.targetPos.x = nodePos.x + (sizeWithoutPadding - next.targetSize.x) / 2
                    next.targetPos.x += f32(node.padding.left)
                case .Right:
                    next.targetPos.x = nodePos.x + (node.targetSize.x - next.targetSize.x)
                    next.targetPos.x -= f32(node.padding.right)
                }
            }

            next.targetPos += node.viewOffset

            childPos += next.targetSize.y + f32(node.spacing)
        }
    }

    for next := node.firstChild; next != nil; next = next.nextSibling {
        DoFinalLayout(next)
    }
}

DoLayout :: proc() {
    for &node in uiCtx.nodes {
        for size, i in node.preferredSize {
            if size.type == .Fixed {
                node.targetSize[i] = node.preferredSize[i].value
            }
        }

        if node.preferredSize[.X].type == .Text ||
           node.preferredSize[.Y].type == .Text
        {
             // MeasureText(node.text, node.font, f32(node.fontSize))
            // textSize := rl.MeasureText(strings.clone_to_cstring(node.text, context.temp_allocator), i32(node.fontSize))

            font := node.font != {} ? node.font : rl.GetFontDefault()
            textSize := rl.MeasureTextEx(font, strings.clone_to_cstring(node.text, context.temp_allocator), f32(node.fontSize), 3)
            paddedSize := v2 {
                f32(node.padding.left + node.padding.right),
                f32(node.padding.top + node.padding.bot),
            }

            for size, i in node.preferredSize {
                if size.type == .Text {
                    node.targetSize[i] = f32(textSize[i]) + paddedSize[i]
                }
            }
        }
    }

    DoLayoutParentPercent(&uiCtx.nodes[0])

    for &node in uiCtx.nodes {
        if .Clickable not_in node.flags || node.hotAnimTime == 0 {
            continue
        }

        t := ease.ease(node.hotAnimEase, node.timeSinceHot / node.hotAnimTime)
        node.targetSize *= math.lerp(f32(1), node.hotScale, t)
    }

    DoLayoutChildren(&uiCtx.nodes[0])
    ResolveLayoutContraints(&uiCtx.nodes[0])
    DoFinalLayout(&uiCtx.nodes[0])
}


// Style and Layout

NextNodeStyle :: proc(style: Style) {
    append(&uiCtx.stylesStack, style)
    uiCtx.popStyleAfterUse = true
}

NextNodeLayout :: proc(layout: Layout) {
    append(&uiCtx.layoutStack, layout)
    uiCtx.popLayoutAfterUse = true
}

PushStyle :: proc(style: Style) {
    append(&uiCtx.stylesStack, style)
}

PopStyle :: proc() {
    pop(&uiCtx.stylesStack)
}

BeginLayout :: proc(
    text: string = "",
    axis:= LayoutAxis.X,
    aligmentX := AligmentX.Middle,
    aligmentY := AligmentY.Middle
)
{
    node := AddNode(text, {}, uiCtx.defaultStyle, uiCtx.defaultLayout)

    node.preferredSize[.X] = {.Children, 0, 1}
    node.preferredSize[.Y] = {.Children, 0, 1}

    node.childrenAligment = { aligmentY, aligmentX }
    node.childrenAxis = axis

    PushParent(node)
}

@(deferred_none=EndLayout)
LayoutBlock :: proc(
    text: string,
    axis:= LayoutAxis.X,
    aligmentX := AligmentX.Middle,
    aligmentY := AligmentY.Middle
) -> bool
{
    BeginLayout(text, axis, aligmentX, aligmentY)
    return true
}

EndLayout :: proc() {
    PopParent()
}

UIBegin :: proc(screenWidth, screenHeight: int) {
    // Clean up 
    #reverse for &node, i in uiCtx.nodes {
        if node.touchedThisFrame == false || node.id == 0 {
            unordered_remove(&uiCtx.nodes, i)
        }

        node.touchedThisFrame = false
    }

    free_all(uiCtx.transientAllocator)
    uiCtx.hotId = 0

    // Setup
    root := AddNode("root", {}, uiCtx.defaultStyle, uiCtx.defaultLayout)
    root.preferredSize = {.X = {.Fixed, f32(screenWidth), 1}, .Y = {.Fixed, f32(screenHeight), 1}}

    append(&uiCtx.clippingStack, RectInt{-max(i32), max(i32), -max(i32), max(i32)})


    PushParent(root)

}

UIEnd :: proc() {
    PopParent()
    pop(&uiCtx.clippingStack)

    assert(len(uiCtx.parentStack) == 0)
    assert(len(uiCtx.hashStack) == 0)
    assert(len(uiCtx.stylesStack) == 0)
    assert(len(uiCtx.layoutStack) == 0)
    assert(len(uiCtx.clippingStack) == 0)

    DoLayout()
}

NextNodePosition :: proc(pos: v2, origin := v2{0.5, 0.5}) {
    uiCtx.nextNodePos = pos
    uiCtx.nextNodeOrigin = origin
}

FindNode :: proc(id: Id) -> ^UINode {
    for &node in uiCtx.nodes {
        if node.id == id {
            return &node
        }
    }

    return nil
}

CreateNode :: proc(text: string) -> ^UINode {
    id: Id
    res: ^UINode

    idStr: string
    textStr: string

    idIdx := strings.index(text, "##")
    if idIdx != -1 {
        ok: bool
        idStr, ok = strings.substring(text, idIdx + 2, len(text))
        assert(ok)

        textStr, ok = strings.substring(text, 0, idIdx)
        assert(ok)
    }
    else {
        idStr = text
        textStr = text
    }

    if text != "" {
        id = GetId(idStr)
        for &node in uiCtx.nodes {
            if node.id == id {
                res = &node
                break
            }
        }
    }

    if res == nil {
        node := UINode {
            id = id,
        }

        assert(len(uiCtx.nodes) + 1 < cap(uiCtx.nodes))
        append(&uiCtx.nodes, node)
        res = &uiCtx.nodes[len(uiCtx.nodes) - 1]
    }

    res.text = textStr

    return res
}

AddNode :: proc(text: string, flags: NodeFlags, 
    style := uiCtx.defaultStyle,
    layout := uiCtx.defaultLayout) -> ^UINode
{
    node := CreateNode(text)

    mem.zero_item(&node.PerFrameData)

    if len(uiCtx.stylesStack) > 0 {
        node.style = uiCtx.stylesStack[len(uiCtx.stylesStack) - 1]
        if uiCtx.popStyleAfterUse {
            pop(&uiCtx.stylesStack)
            uiCtx.popStyleAfterUse = false
        }
    }
    else {
        node.style = style
    }

    if len(uiCtx.layoutStack) > 0 {
        node.layout = uiCtx.layoutStack[len(uiCtx.layoutStack) - 1]
        if uiCtx.popLayoutAfterUse {
            pop(&uiCtx.layoutStack)
            uiCtx.popLayoutAfterUse = false
        }
    }
    else {
        node.layout = layout
    }

    node.flags = flags
    node.touchedThisFrame = true

    if pos, ok := uiCtx.nextNodePos.?; ok {
        node.flags += { .Floating }
        node.targetPos = pos

        uiCtx.nextNodePos = nil
    }

    if origin, ok := uiCtx.nextNodeOrigin.?; ok {
        node.origin = origin

        uiCtx.nextNodeOrigin = nil
    }

    if len(uiCtx.parentStack) != 0 {
        parent := uiCtx.parentStack[len(uiCtx.parentStack) - 1]

        if parent.lastChild != node {
            if .Floating in node.flags {
                // @REWRITE:
                parent = &uiCtx.nodes[0]
            }

            if parent.firstChild == nil {
                parent.firstChild = node
            }

            node.prevSibling = parent.lastChild
            if parent.lastChild != nil {
                parent.lastChild.nextSibling = node
            }

            parent.lastChild = node

            node.parent = parent
            parent.childrenCount += 1
        }
        else {
            fmt.eprintln("Duplicate node:", node.text)
        }
    }

    node.disabled = uiCtx.disabled

    return node
}


ClipRect :: proc(rect: ^RectInt, clippinRect: RectInt) {
    rect.left  = max(rect.left,  clippinRect.left)
    rect.top   = max(rect.top,   clippinRect.top)
    rect.right = min(rect.right, clippinRect.right)
    rect.bot   = min(rect.bot,   clippinRect.bot)
}

IsPointInsideUIRect :: proc(point: iv2, rect: RectInt) -> bool {
    return i32(point.x) > rect.left &&
           i32(point.x) < rect.right &&
           i32(point.y) > rect.top &&
           i32(point.y) < rect.bot
}

GetNodeInteraction :: proc(node: ^UINode) -> (result: UINodeInteraction) {

    if .Clickable in node.flags {
        rect := NodeRect(node)
        isInside := IsPointInsideUIRect(uiCtx.input.mousePos, rect)

        if isInside {
            result.hovered = true

            if uiCtx.input.leftMousePressed {
                uiCtx.activeId = node.id
            }

            if uiCtx.activeId == 0 {
                uiCtx.hotId = node.id
            }

            if uiCtx.activeId == node.id && 
               uiCtx.input.leftMouseReleased
            {
                uiCtx.activeId = 0
                result.clicked = true
            }
        }

        // if we release an active node outside it's rect, don't trigger the clicked event
        if isInside == false && 
           uiCtx.activeId == node.id && 
           uiCtx.input.leftMouseReleased
        {
            uiCtx.activeId = 0
        }

        if node.id == uiCtx.hotId {
            node.timeSinceHot += rl.GetFrameTime()
        }
        else {
            node.timeSinceHot -= rl.GetFrameTime()
        }

        // fmt.println(uiCtx.activeId, uiCtx.input.leftMouseDown, uiCtx.input.mouseDelta)
        if node.id == uiCtx.activeId && uiCtx.input.leftMouseDown && uiCtx.input.mouseDelta != 0 {
            result.dragging = true
        }

        node.timeSinceHot = clamp(node.timeSinceHot, 0, node.hotAnimTime)

    }

    // fmt.println(uiCtx.hotId)

    return
}

@(deferred_none=EndPanel)
Panel :: proc(
    text: string, 
    aligment: Maybe(Aligment) = nil,
    size: Maybe(iv2) = nil,
    texture: rl.Texture = {},
) -> bool
{
    node := AddNode(text, { .DrawBackground }, uiCtx.panelStyle, uiCtx.panelLayout)
    if al, ok := aligment.?; ok {
        node.childrenAligment = al
    }

    if texture != {} {
        node.flags += { .BackgroundTexture }
        node.texture =  texture
    }

    if size, ok := size.?; ok {
        node.preferredSize[.X] = {.Fixed, f32(size.x), 1}
        node.preferredSize[.Y] = {.Fixed, f32(size.y), 1}
    }

    PushParent(node)

    return true
}

EndPanel :: proc() {
    PopParent()
}

// @(deferred_none=EndPanel2)
// Panel2 :: proc(
//     size: iv2,
//     aligment: Maybe(Aligment) = nil,
//     texture: TexHandle = {},
// ) -> bool
// {
//     node := AddNode("", { .DrawBackground }, uiCtx.panelStyle, uiCtx.panelLayout)
//     if al, ok := aligment.?; ok {
//         node.childrenAligment = al
//     }

//     if texture != {} {
//         node.flags += { .BackgroundTexture }
//         node.texture =  texture
//     }

//     node.preferredSize[.X] = {.Fixed, f32(size.x), 1}
//     node.preferredSize[.Y] = {.Fixed, f32(size.y), 1}

//     PushParent(node)

//     Scroll("Scroll")

//     return true
// }

// EndPanel2 :: proc() {
//     EndScroll()
//     PopParent()
// }

// @(deferred_none=EndContainer)
// UIContainer :: proc(text: string, anchor: UIAnchor, 
//     anchorOffset := v2{0, 0},
//     layoutAxis := LayoutAxis.X,
//     alignment: Maybe(Aligment) = nil) -> bool
// {
//     container := AddNode(text, {})
//     container.childrenAxis = layoutAxis
//     container.preferredSize[.X] = {.Children, 0, 1}
//     container.preferredSize[.Y] = {.Children, 0, 1}

//     if al, ok := alignment.?; ok {
//         container.childrenAligment = al
//     }

//     container.flags += { .AnchoredPosition }

//     container.origin = UIAnchorToPercent[anchor]
//     container.anchoredPosPercent = container.origin

//     container.anchoredPosOffset = anchorOffset

//     PushParent(container)

//     return true
// }

// EndContainer :: proc() {
//     PopParent()
// }

@(deferred_none=EndHeader)
Header :: proc(text: string) -> bool {
    header := AddNode(uiFmt(">", text), {.DrawBackground, .DrawText, .Clickable}, style = uiCtx.buttonStyle)
    header.preferredSize[.X] = {.ParentPercent, 1, 1}
    header.preferredSize[.Y] = {.Fixed, 40, 1}

    header.textAligment ={ .Middle, .Left }

    inter := GetNodeInteraction(header)
    if inter.clicked {
        header.folded = !header.folded
    }

    content := AddNode("", {})
    content.layout = content.parent.layout
    content.preferredSize[.X] = {.Children, 0, 1}
    content.preferredSize[.Y] = {.Children, 0, 1}

    content.padding.left = 15

    PushParent(content)
    PushId(text)

    return header.folded == false
}

EndHeader :: proc() {
    PopId()
    PopParent()
}

// Scroll :: proc(text: string) {
//     viewportStyle := uiCtx.panelStyle
//     viewportStyle.padding = { 0, 0, 0, 0 }

//     viewPort := AddNode(text, { .ScrollX, .ScrollY, .Clip }, style = viewportStyle)
//     viewPort.preferredSize[.X] = {.ParentPercent, 1, 1}
//     viewPort.preferredSize[.Y] = {.ParentPercent, 1, 1}

//     PushParent(viewPort)

//     SCROLL_SIZE :: 10

//     /////

//     scrollY := AddNode("ScrollY", { .DrawBackground, .AnchoredPosition })
//     scrollY.preferredSize[.X] = {.Fixed, SCROLL_SIZE, 1}
//     scrollY.preferredSize[.Y] = {.ParentPercent, 1, 1}

//     scrollY.origin = {1, 0.5}
//     scrollY.anchoredPosPercent = {1, 0.5}

//     PushParent(scrollY)

//     sliderY := AddNode("SliderY", { .DrawBackground, .Clickable, .AnchoredPosition })

//     sliderY.preferredSize[.X] = {.ParentPercent, 1, 1}
//     sliderY.preferredSize[.Y] = {.ParentPercent, 0, 1}
//     sliderY.bgColor = {0, 0, 0, 1}
//     sliderY.origin = {0.5, 0.5}

//     sliderY.anchoredPosPercent = {-0.5, 0}

//     PopParent()

//     /////

//     // scrollX := AddNode("ScrollX", { .DrawBackground, .AnchoredPosition })
//     // scrollX.preferredSize[.X] = {.ParentPercent, 1, 1}
//     // scrollX.preferredSize[.Y] = {.Fixed, 10, 1}

//     // scrollX.origin = {0.5, 1}
//     // scrollX.anchoredPosPercent = {0.5, 1}

//     // PushParent(scrollX)

//     // sliderX := AddNode("SliderX", { .DrawBackground, .Clickable })
//     // sliderX.preferredSize[.X] = {.ParentPercent, 1, 1}
//     // sliderX.preferredSize[.Y] = {.Fixed, 10, 1}

//     // PopParent()

//     content := AddNode("content", { }, style = viewportStyle)

//     content.preferredSize[.X] = {.Fixed, viewPort.targetSize.x - SCROLL_SIZE - 2, 1}
//     content.preferredSize[.Y] = {.Children, 0, 1}

//     PushParent(content)

//     inter := GetNodeInteraction(viewPort)
//     if inter.scroll {
//         content.viewOffset.y += f32(input.scroll) * 20
//         content.viewOffset.y = clamp(content.viewOffset.y, -content.targetSize.y, 0)

//         // fmt.println(content.viewOffset)
//     }

//     fillPercent := clamp(viewPort.targetSize.y / content.targetSize.y, 0, 1)
//     sliderY.preferredSize[.Y].value = fillPercent
//     sliderY.anchoredPosPercent.y = math.lerp(
//         f32(-0.5 + fillPercent / 2), 
//         0.5 - fillPercent / 2, 
//         -content.viewOffset.y / content.targetSize.y
//     )

//     interY := GetNodeInteraction(sliderY)
//     if interY.cursorPressed {
//         // fmt.println(input.mouseDelta.y)
//         off := f32(input.mouseDelta.y)
//         off = content.targetSize.y * (off / (scrollY.targetSize.y - fillPercent * scrollY.targetSize.y))

//         content.viewOffset.y -= off
//         content.viewOffset.y = clamp(content.viewOffset.y, -content.targetSize.y, 0)
//     }

//     if fillPercent == 1 {
//         content.viewOffset.y = 0
//     }
// }

// EndScroll :: proc() {
//     PopParent()
//     PopParent()
// }

/////////
// Windows
/////////

// UIBeginWindow :: proc(text: string, isOpen: ^bool = nil) -> bool {
//     if isOpen != nil && isOpen^ == false {
//         return false 
//     }

//     background := AddNode(
//         text, 
//         { .DrawBackground, .Floating },
//         uiCtx.defaultStyle, uiCtx.defaultLayout
//     )
//     background.bgColor = {0, 0.5, 0.3, 0.8}

//     background.childrenAxis = .Y
//     background.preferredSize[.X] = {.Children, 0, 1}
//     background.preferredSize[.Y] = {.Children, 0, 1}

//     // // SetLayout(background, .Container)
//     PushParent(background)

//     header := AddNode("Header", {.Clickable})
//     header.preferredSize[.X] = {.ParentPercent, 1, 0}
//     header.preferredSize[.Y] = {.Fixed, 30, 1}
//     header.childrenAxis = .X
//     // // header.isFloating = true

//     interaction := GetNodeInteraction(header)
//     if interaction.cursorPressed {
//         background.targetPos += ToV2(input.mouseDelta)
//         // fmt.println(background.targetPos)
//     }

//     PushParent(header)

//         // UILabel(text)
//         label := AddNode(text, { .DrawText }, uiCtx.textStyle, uiCtx.defaultLayout)
//         label.preferredSize[.X] = {.Text, 1, 1}
//         label.preferredSize[.Y] = {.Text, 1, 1}

//         spacer := AddNode("Spacer", {})
//         spacer.preferredSize[.X] = {.ParentPercent, 1, 0}
//         spacer.preferredSize[.Y] = {.ParentPercent, 1, 0}

//         // TODO: close button
//         if isOpen != nil {
//             if UIButton("X") {
//                 isOpen^ = false
//             }
//         }

//     PopParent()

//     return true
// }

// UIEndWindow :: proc() {
//     PopParent()
// }

/////////
// Controls
/////////

UIButton :: proc(text: string) -> bool {
    return cast(bool) UIButtonI(text).clicked
}

UIButtonI :: proc(text: string) -> UINodeInteraction {
    node := AddNode(text, 
            { .DrawBackground, .Clickable, .DrawText },
            style = uiCtx.buttonStyle,
            layout = uiCtx.buttonLayout
        )

    interaction := GetNodeInteraction(node)
    return interaction
}

// ImageButton :: proc(
//         image: TexHandle, 
//         text: Maybe(string) = nil, 
//         maybeSize: Maybe(iv2) = nil, 
//         texSource: Maybe(RectInt) = nil
//     ) -> bool
// {

//     return cast(bool) ImageButtonI(image, text, maybeSize, texSource).cursorReleased
// }

ImageButtonI :: proc(
        image: rl.Texture, 
        text: Maybe(string) = nil, 
        size: Maybe(iv2) = nil, 
        texSource: Maybe(RectInt) = nil
    ) -> UINodeInteraction
{

    bgText := text.? or_else fmt.tprint("btn_", image.id)
    node := AddNode(bgText, {.Clickable, .DrawBackground}, uiCtx.panelStyle, uiCtx.panelLayout)
    node.bgColor = {0, 0, 0, 0}
    node.activeColor = {1, 1, 1, 0.5}
    node.hotColor = {1, 1, 1, 0.6}

    interaction := GetNodeInteraction(node)

    PushParent(node)

    UIImage(image, size = size, source = texSource)
    if t, ok := text.?; ok {
        UILabel(text)
    }

    PopParent()

    return interaction
}

UILabel :: proc(params: ..any, sep := " ") {
    t := fmt.aprint(..params, sep = sep, allocator = uiCtx.transientAllocator)
    node := AddNode(t, { .DrawText }, uiCtx.textStyle, uiCtx.textLayout)
}

UIImage :: proc(
        image: rl.Texture, 
        size: Maybe(iv2) = nil,
        source: Maybe(RectInt) = nil,
        tint: Maybe(Color) = nil,
    ) -> ^UINode
{
    id := fmt.aprint("Tex", image.id, allocator = uiCtx.transientAllocator)
    node := AddNode(id, {.BackgroundTexture})

    node.texture = image
    node.textureSource = source.? or_else {}

    s := size.? or_else { int(image.width), int(image.height) }

    node.preferredSize[.X] = {.Fixed, f32(s.x), 1}
    node.preferredSize[.Y] = {.Fixed, f32(s.y), 1}

    node.tint = tint

    return node
}


UISpacer :: proc(size: int) {
    layout: Layout
    layout.preferredSize = {
        .X = {.Fixed, f32(size), 1},
        .Y = {.Fixed, f32(size), 1}
    }
    node := AddNode("", {}, {}, layout)
}


UISliderInt :: proc(value: ^int, #any_int min, max: int) -> (res: bool) {
    temp := cast(f32) value^
    result := UISlider(&temp, f32(min), f32(max))

    value^ = cast(int) temp
    return result
}

UISliderIntLabel :: proc(label: string, value: ^int, #any_int min, max: int) -> (res: bool) {
    temp := cast(f32) value^
    result := UISliderLabel(label, &temp, f32(min), f32(max))

    value^ = cast(int) temp
    return result
}


UISliderLabel :: proc(label: string, value: ^f32, min, max: f32) -> bool {
    BeginLayout()
    UILabel(label)
    res := UISlider(value, min, max)
    EndLayout()

    return res
}

UISlider :: proc(value: ^f32, min, max: f32) -> (res: bool) {
    PushId(value)

    parent := AddNode("Slider", {.DrawBackground})
    parent.preferredSize[.X] = {.Fixed, 200, 1}
    parent.preferredSize[.Y] = {.Fixed, 20, 1}
    parent.layout.childrenAxis = .X
    parent.layout.childrenAligment = { .Middle, .Middle }
    parent.bgColor = {0.5, 0.5, 0.5, 0.5}

    handleSize :: 18
    PushParent(parent)

        UISpacer(5)

        style := uiCtx.textStyle
        style.fontSize = 25

        valueLayout := uiCtx.textLayout
        valueLayout.preferredSize[.X] = {.Fixed, 30, 1}

        NextNodeStyle(style)
        NextNodeLayout(valueLayout)
        UILabel(fmt.tprintf("%.2v", value^))

        UISpacer(handleSize / 2)

        slideArea := AddNode("slide", { .DrawBackground })
        slideArea.bgColor = {1, 1, 1, 1}
        slideArea.preferredSize[.X] = {.ParentPercent, 1, 0}
        slideArea.preferredSize[.Y] = {.Fixed, 5, 1}
        slideArea.layout.childrenAxis = .X
        slideArea.layout.childrenAligment = { .Middle, .Left }
        slideArea.padding = {0, 0, 0, 0}
        slideArea.spacing = 0

        // fmt.println(parent.targetSize, slideArea.targetSize)

        inter := GetNodeInteraction(parent)
        if inter.dragging || inter.clicked {
            // deltaPct := uiCtx.input.mouseDelta.x / parent.targetSize.x
            // value^ += deltaPct * (max - min)
            // value^ = clamp(value^, min, max)


            rect := NodeRect(slideArea)
            mousePct := f32(uiCtx.input.mousePos.x - int(rect.left)) / f32(rect.right - rect.left)
            // fmt.println(mousePct)
            value^ = mousePct * (max - min)
            value^ = clamp(value^, min, max)
        }

        PushParent(slideArea)
            valuePct := value^ / (max - min)

            layout: Layout
            layout.preferredSize = {
                .X = {.ParentPercent, valuePct, 1},
                .Y = {}
            }
            node := AddNode("", {}, {}, layout)

            handle := AddNode("handle", {.DrawBackground })
            handle.bgColor = {0, 0, 0, 1}
            handle.textColor = {1, 1, 1, 1}
            handle.preferredSize[.X] = {.Fixed, 20, 1}
            handle.preferredSize[.Y] = {.Fixed, handleSize, 1}
            handle.origin = {0.5, 0}

        PopParent()

        UISpacer(handleSize / 2)

    PopParent()
    PopId()

    // if LayoutBlock(text, axis = .X) {
    //     label := AddNode(text, { .DrawText }, uiCtx.textStyle, uiCtx.textLayout)
    //     label.preferredSize[.X] = {.ParentPercent, 0.5, 0}

    //     UILabel(fmt.tprintf("%f", value^))

    //     slideArea := AddNode(fmt.tprint("slide", text), { .DrawBackground })
    //     slideArea.bgColor = {1, 1, 1, 1}
    //     slideArea.preferredSize[.X] = {.Fixed, 120, 0}
    //     slideArea.preferredSize[.Y] = {.Fixed, 5, 1}


    //     PushParent(slideArea)

    //         handleId := fmt.aprint("handle", text, allocator = uiCtx.transientAllocator)
    //         handle := AddNode(handleId, {.DrawBackground, .Clickable, .Floating})
    //         handle.origin = {0.5, 0.5}
    //         // handle.anchoredPosPercent = {0, 0.5}
    //         // handle.anchoredPosOffset = {0, 0}

    //         interaction := GetNodeInteraction(handle)

    //         left := slideArea.targetPos.x
    //         right := slideArea.targetPos.x + slideArea.targetSize.x

    //         if value != nil {
    //             // normalizedValue := (value^ - min) / (max - min)
    //             // handle.targetPos.x = glsl.lerp(left, right, normalizedValue)
    //             // handle.anchoredPosPercent = {normalizedValue, 0.5}
    //         }
    //         // else {
    //         //     // handle.targetPos.x = left
    //         //     handle.anchorOffset = {0, 0}
    //         // }

    //         if interaction.clicked {
    //             handle.targetPos = ToV2(uiCtx.input.mousePos)
    //             handle.targetPos.x = clamp(handle.targetPos.x, left, right)

    //             if value != nil {
    //                 normalized := ((handle.targetPos.x - left) / (right - left))
    //                 value^ = glsl.lerp(min, max, normalized)
    //             }
    //         }

    //         handle.bgColor = {0, 0, 0, 1}
    //         handle.preferredSize[.X] = {.Fixed, 16, 1}
    //         handle.preferredSize[.Y] = {.Fixed, 30, 1}

    //     PopParent()
    // }

    return
}

UICheckbox :: proc(text: string, value: ^bool) -> (res: bool) {
    if LayoutBlock(text, axis = .X) {
        checkbox := AddNode(fmt.tprint("X##", text), {.DrawBackground, .Clickable})
        checkbox.preferredSize[.X] = {.Fixed, 25, 1}
        checkbox.preferredSize[.Y] = {.Fixed, 25, 1}
        checkbox.textColor = {0, 0, 0, 1}

        PushParent(checkbox)
        check := AddNode(fmt.tprint("check##", text), {})
        check.bgColor = {0, 0, 0, 1}
        check.preferredSize[.X] = {.ParentPercent, 1, 1}
        check.preferredSize[.Y] = {.ParentPercent, 1, 1}

        if value^ do check.flags += {.DrawBackground}
        
        PopParent()

        interaction := GetNodeInteraction(checkbox)
        if interaction.clicked {
            value^ = !value^
            res = true
        }

        label := AddNode(text, { .DrawText }, uiCtx.textStyle, uiCtx.textLayout)
        label.preferredSize[.X] = {.Fixed, 200, 0}
    }

    return
}

///////////////////////////////

ToRLColor :: proc(color: Color) -> rl.Color{
    return {
        u8(color.r * 255),
        u8(color.g * 255),
        u8(color.b * 255),
        u8(color.a * 255),
    }
}

DrawNode :: proc(node: ^UINode) {
    nodeCenter := node.targetPos + node.targetSize / 2 - node.targetSize * node.origin


    if .Clip in node.flags {
        // left  := i32(node.targetPos.x)
        // top   := i32(node.targetPos.y)
        // right := i32(node.targetPos.x + node.targetSize.x)
        // bot   := i32(node.targetPos.y + node.targetSize.y)

        // BeginScissors(left, top, right, bot)
        rl.BeginScissorMode(
            i32(node.targetPos.x),
            i32(node.targetPos.y),
            i32(node.targetSize.x),
            i32(node.targetSize.y)
        )
    }

    if .DrawBackground in node.flags {
        color := node.bgColor

        if .Clickable in node.flags {
            if node.id == uiCtx.activeId {
                color = node.activeColor
            }
            else if node.id == uiCtx.hotId {
                color = node.hotColor
            }
        }

        if node.disabled {
            color = node.disabledBgColor
        }

        if tint, ok := node.tint.?; ok {
            color *= tint
        }

        rl.DrawRectanglePro(
            {node.targetPos.x, node.targetPos.y, node.targetSize.x, node.targetSize.y},
            node.origin * node.targetSize,
            0,
            ToRLColor(color)
        )

        // rl.DrawRectangleLines(
        //     i32(node.targetPos.x),
        //     i32(node.targetPos.y),
        //     i32(node.targetSize.x),
        //     i32(node.targetSize.y),
        //     rl.GREEN
        // )
    }

    if .BackgroundTexture in node.flags {
        color := node.bgColor

        if node.id == uiCtx.activeId {
            color = node.hotColor
        }
        else if node.id == uiCtx.hotId {
            color = node.activeColor
        }

        if tint, ok := node.tint.?; ok {
            color *= tint
        }

        source := rl.Rectangle{0, 0, f32(node.texture.width), f32(node.texture.height)}
        if node.textureSource != {} {
            width := node.textureSource.right - node.textureSource.left
            height := node.textureSource.top - node.textureSource.bot

            source = rl.Rectangle{
                f32(node.textureSource.left),
                f32(node.textureSource.bot),
                f32(node.textureSource.left + width),
                f32(node.textureSource.bot + height),
            }
        }
        
        destination := rl.Rectangle{node.targetPos.x, node.targetPos.y, node.targetSize.x, node.targetSize.y}
        rl.DrawTexturePro(node.texture, source, destination, node.origin, 0, ToRLColor(color))
    }

    if .DrawText in node.flags {
        // textSize := MeasureText(node.text, node.font, f32(node.fontSize))
        font := node.font != {} ? node.font : rl.GetFontDefault()

        text := strings.clone_to_cstring(node.text, context.temp_allocator)
        textSize := rl.MeasureTextEx(font, text, f32(node.fontSize), 3)

        pos: v2

        switch node.textAligment.x {
        case .Left:   pos.x = node.targetPos.x
        case .Middle: pos.x = node.targetPos.x + (node.targetSize.x - textSize.x) / 2 - node.targetSize.x * node.origin.x
        case .Right: pos.x = node.targetPos.x + (node.targetSize.x - textSize.x) - node.targetSize.x * node.origin.x
        }


        switch node.textAligment.y {
        case .Top:   pos.y = node.targetPos.y
        case .Middle: pos.y = node.targetPos.y + (node.targetSize.y - textSize.y) / 2 - node.targetSize.y * node.origin.y
        case .Bottom: pos.y = node.targetPos.y + (node.targetSize.y - textSize.y) - node.targetSize.y * node.origin.y
        }
        // pos := node.targetPos + (node.targetSize - textSize) / 2 - node.targetSize * node.origin

        color := node.textColor
        if tint, ok := node.tint.?; ok {
            color *= tint
        }

        // DrawText(
        //     node.text,
        //     pos,
        //     fontHandle = node.font,
        //     fontSize   = f32(node.fontSize),
        //     color      = node.textColor,
        // )

        rl.DrawTextEx(font, text, pos, f32(node.fontSize), 3, ToRLColor(node.textColor))
    }

    for next := node.firstChild; next != nil; next = next.nextSibling {
        DrawNode(next)
    }

    if .Clip in node.flags {
        // EndScissors()
        rl.EndScissorMode()
    }
}

DrawUI :: proc() {
    // BeginScreenSpace()

    // fmt.println(len(ctx.nodes))
    if len(uiCtx.nodes) > 0 {
        DrawNode(&uiCtx.nodes[0])
    }

    // EndScreenSpace()
}

// CreateUIDebugString :: proc() -> string {
//     b: strings.Builder
//     strings.builder_init(&b, allocator = context.temp_allocator)

//     PrintNode :: proc(node: UINode, builder: ^strings.Builder, indent: ^int) {
//         for i in 0..<indent^ {
//             fmt.sbprint(builder, "    ")
//         }
//         fmt.sbprintln(builder, "-", node.text, node.id)

//         indent^ += 1
//         for child := node.firstChild; child != nil; child = child.nextSibling {
//             PrintNode(child^, builder, indent)
//         }
//         indent^ -= 1
//     }

//     indent := 0
//     PrintNode(uiCtx.nodes[0], &b, &indent)

//     return strings.to_string(b)
// }