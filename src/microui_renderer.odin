package game

import "core:strings"
import "core:fmt"
import "core:unicode/utf8"

import mu "vendor:microui"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

FONT_SPACING :: 2
SCROLL_SPEED :: 20

defaultFont: rl.Font
iconsTexture: rl.Texture2D
runesBuffer: [dynamic; 64]rune

// Generated with rGuiIcons
// Icons data is defined by bit array (every bit represents one pixel)
// Those arrays are stored as unsigned int data arrays, so every array
// element defines 32 pixels (bits) of information
ICON_SIZE :: 16
ICON_COUNT :: 6
ELEMS_PER_ICON :: 8
ICONS := []u32{
        0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000, 0x00000000,      // NONE
    0x00000000, 0x10080000, 0x04200810, 0x01800240, 0x02400180, 0x08100420, 0x00001008, 0x00000000,      // CLOSE
    0x00000000, 0x00000000, 0x10000000, 0x04000800, 0x01040200, 0x00500088, 0x00000020, 0x00000000,      // CHECK
    0x00000000, 0x00400000, 0x01c000c0, 0x07c003c0, 0x07c00fc0, 0x01c003c0, 0x004000c0, 0x00000000,      // COLLAPSED
    0x00000000, 0x00000000, 0x00000000, 0x0ff81ffc, 0x03e007f0, 0x008001c0, 0x00000000, 0x00000000,      // EXPANDED
    0x60000000, 0x78007000, 0x7e007c00, 0x7f807f00, 0x7fe07fc0, 0x7ff87ff0, 0x7ffe7ffc, 0x00007ffe,      // RESIZE
}


muiGetTextWidth :: proc(font: mu.Font, text: string) -> (width: i32) {
    font := (cast(^rl.Font)font)^

    for r in text {
        index := rl.GetGlyphIndex(font, r)

        if font.glyphs[index].advanceX == 0 {
            width += i32(font.recs[index].width) + FONT_SPACING
        }
        else {
            width += font.glyphs[index].advanceX + FONT_SPACING
        }
    }

    return
}

muiGetTextHeight :: proc(font: mu.Font) -> i32 {
    f := cast(^rl.Font)font
    return f.baseSize
}

muiInit :: proc() -> ^mu.Context {
    ret := new(mu.Context)
    mu.init(ret);

    ret.text_width = muiGetTextWidth
    ret.text_height = muiGetTextHeight

    defaultFont = rl.GetFontDefault()
    ret.style.font = cast(mu.Font) &defaultFont

    // Create icons texture
    texWidth :: ICON_SIZE * ICON_COUNT
    texHeight :: ICON_SIZE

    texData: [texWidth * texHeight]u32

    for iconIdx in 0..<ICON_COUNT {
        for elemIdx in 0..<ELEMS_PER_ICON {
            idx := iconIdx * ELEMS_PER_ICON + elemIdx
            v := ICONS[idx]

            lower  :=  v & 0x0000FFFF
            higher := (v & 0xFFFF0000) >> 16

            for i in 0..<16 {
                color:u32 = lower & (1 << u32(i)) != 0 ? 0xFFFFFFFF : 0x00000000

                texX := iconIdx * ICON_SIZE + i;
                texY := elemIdx * 2

                texData[texY * texWidth + texX] = color
            }

            for i in 0..<16 {
                color:u32 = higher & (1 << u32(i)) != 0 ? 0xFFFFFFFF : 0x00000000

                texX := iconIdx * ICON_SIZE + i;
                texY := elemIdx * 2 + 1

                texData[texY * texWidth + texX] = color
            }
        }
    }

    texId := rlgl.LoadTexture(&texData, texWidth, texHeight, cast(i32) rl.PixelFormat.UNCOMPRESSED_R8G8B8A8, 1)

    iconsTexture.id = texId
    iconsTexture.width = texWidth
    iconsTexture.height = texHeight
    iconsTexture.mipmaps = 1
    iconsTexture.format = rl.PixelFormat.UNCOMPRESSED_R8G8B8A8

    // to initialize pool allocators, so we can make some
    // setup before actual work
    mu.begin(ret)
    mu.end(ret)

    return ret
}

muiProcessInput :: proc(ctx: ^mu.Context) {
    // mouse
    posX := rl.GetMouseX()
    posY := rl.GetMouseY()
    mu.input_mouse_move(ctx, posX, posY)

    mouseScroll := rl.GetMouseWheelMove()
    mu.input_scroll(ctx, 0, i32(-SCROLL_SPEED * mouseScroll))

    // keys
    if      rl.IsMouseButtonPressed(.LEFT)  do mu.input_mouse_down(ctx, posX, posY, .LEFT)
    else if rl.IsMouseButtonReleased(.LEFT) do mu.input_mouse_up(ctx, posX, posY, .LEFT)

    if      rl.IsMouseButtonPressed(.RIGHT)  do mu.input_mouse_down(ctx, posX, posY, .RIGHT)
    else if rl.IsMouseButtonReleased(.RIGHT) do mu.input_mouse_up(ctx, posX, posY, .RIGHT)

    if      rl.IsMouseButtonPressed(.MIDDLE)  do mu.input_mouse_down(ctx, posX, posY, .MIDDLE)
    else if rl.IsMouseButtonReleased(.MIDDLE) do mu.input_mouse_up(ctx, posX, posY, .MIDDLE)

    if      rl.IsKeyPressed(.LEFT_SHIFT)  do mu.input_key_down(ctx, .SHIFT)
    else if rl.IsKeyReleased(.LEFT_SHIFT) do mu.input_key_down(ctx, .SHIFT)

    if      rl.IsKeyPressed(.LEFT_CONTROL)  do mu.input_key_down(ctx, .CTRL)
    else if rl.IsKeyReleased(.LEFT_CONTROL) do mu.input_key_down(ctx, .CTRL)

    if      rl.IsKeyPressed(.LEFT_ALT)  do mu.input_key_down(ctx, .ALT)
    else if rl.IsKeyReleased(.LEFT_ALT) do mu.input_key_down(ctx, .ALT)

    if      rl.IsKeyPressed(.BACKSPACE)  do mu.input_key_down(ctx, .BACKSPACE)
    else if rl.IsKeyReleased(.BACKSPACE) do mu.input_key_down(ctx, .BACKSPACE)

    if      rl.IsKeyPressed(.ENTER)  do mu.input_key_down(ctx, .RETURN)
    else if rl.IsKeyReleased(.ENTER) do mu.input_key_down(ctx, .RETURN)

    // text input
    clear(&runesBuffer)

    r := rl.GetCharPressed()
    for r != 0 {
        append(&runesBuffer, r)
        r = rl.GetCharPressed()
    }

    str := utf8.runes_to_string(runesBuffer[:], context.temp_allocator)
    mu.input_text(ctx, str)
}

muiRender :: proc(muCtx: ^mu.Context) {
    rlgl.EnableScissorTest()

    winHeight := rl.GetScreenHeight()

    cmd: ^mu.Command;
    for mu.next_command(muCtx, &cmd) {
        switch c in cmd.variant {
            case ^mu.Command_Rect:
                rect := c.rect
                r := rl.Rectangle{f32(rect.x), f32(rect.y), f32(rect.w), f32(rect.h)}
                rl.DrawRectangleRec(r, transmute(rl.Color)c.color)

            case ^mu.Command_Text:
                f := cast(^rl.Font) c.font
                s := strings.clone_to_cstring(c.str, context.temp_allocator)
                rl.DrawTextEx(f^, s, {f32(c.pos.x), f32(c.pos.y)}, f32(f.baseSize), FONT_SPACING, transmute(rl.Color)c.color)

            case ^mu.Command_Icon:
                x := f32(c.rect.x) + (f32(c.rect.w) - ICON_SIZE) / 2 
                y := f32(c.rect.y) + (f32(c.rect.h) - ICON_SIZE) / 2 

                index := i32(c.id)
                src  := rl.Rectangle{f32(ICON_SIZE * index), 0, ICON_SIZE, ICON_SIZE }
                dest := rl.Rectangle{x, y, ICON_SIZE, ICON_SIZE}

                rl.DrawTexturePro(iconsTexture, src, dest, {0, 0}, 0, transmute(rl.Color)c.color)

            case ^mu.Command_Clip:
                rlgl.DrawRenderBatchActive()

                rect := c.rect
                rlgl.Scissor(rect.x, winHeight - (rect.y + rect.h), rect.w, rect.h)

            case ^mu.Command_Jump: // Ignored
        }
    }

    rlgl.DisableScissorTest()
}
