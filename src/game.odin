package game

import "core:fmt"
import "core:math/linalg"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import mu "vendor:microui"
import ha "handle_array"

v2  :: [2]f32
iv2 :: [2]int

Rad :: distinct f32
Deg :: distinct f32

PIXEL_WINDOW_HEIGHT :: 20

LEVEL_WIDTH :: f32(5)
LEVEL_HEIGHT :: f32(6)


GameMemory :: struct {
    assetStorage: AssetStorage,
    mui: ^mu.Context,

    camera: rl.Camera,

    entities: ha.HandleArray(Entity, EntityHandle, 1024),

    score: int,

    pp: PostProcess,
    bloom: BloomEffect,

    run: bool,
}

g: ^GameMemory


Update :: proc() {
    if rl.IsKeyPressed(.ESCAPE) {
        g.run = false
    }

    iter := ha.MakeIter(&g.entities)
    for e in ha.Iterate(&iter) {
        UpdateEntity(e)
    }

    iter = ha.MakeIterReverse(&g.entities)
    for e in ha.Iterate(&iter) {
        if e.toDestroy {
            DestroyEntity(e)
        }
    }

    if rl.IsKeyPressed(.R) {
        ResetGame()
    }

    if Panel("text") {
        UILabel("Stuff")
        UILabel("Score:", g.score)
    }

    // if Panel("Debug") {
    //     UISliderLabel("treshold", &g.bloom.treshold, 0, 1)
    //     UISliderLabel("intensity", &g.bloom.intensity, 0, 3)
    //     UISliderIntLabel("iterations", &g.bloom.levels, 0, len(g.bloom.targets))
    //     UISliderLabel("knee", &g.bloom.knee, 0, 1)
    // }
    // test_window(g.mui)

}

Draw :: proc() {
    rl.BeginDrawing()

    PPBeginDrawing(g.pp)
    rl.ClearBackground(rl.DARKGRAY)

    DrawGrid()

    rl.BeginMode3D(g.camera)
        rlgl.DisableBackfaceCulling()

        iter := ha.MakeIter(&g.entities)
        for e in ha.Iterate(&iter) {
            DrawEntity(e)
        }


    // rl.DrawRectangleLinesEx(RectToRLRect(SAFE_ZONE_EXTENDS), 0.01, rl.BLUE)

    rl.EndMode3D()
    PPEndDrawing(g.pp)

    // PP Goes here
    BloomUse(&g.pp, g.bloom)


    PPFinalize(g.pp)

    muiRender(g.mui)
    DrawUI()

    rl.EndDrawing()
}

@(export)
game_update :: proc() {
    muiProcessInput(g.mui)

    uiCtx.input.mousePos = { int(rl.GetMouseX()), int(rl.GetMouseY()) }
    uiCtx.input.mouseDelta = rl.GetMouseDelta()
    uiCtx.input.leftMouseDown = rl.IsMouseButtonDown(.LEFT)
    uiCtx.input.leftMousePressed = rl.IsMouseButtonPressed(.LEFT)
    uiCtx.input.leftMouseReleased = rl.IsMouseButtonReleased(.LEFT)

    UIBegin(int(rl.GetScreenWidth()), int(rl.GetScreenHeight()))
    mu.begin(g.mui)

    Update()

    mu.end(g.mui)
    UIEnd()

    Draw()

    // Everything on tracking allocator is valid until end-of-frame.
    free_all(context.temp_allocator)
}

ResetGame :: proc() {
    ha.Clear(&g.entities)
    g.score = 0
}

@(export)
game_init_window :: proc() {
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
    rl.InitWindow(750, 900, "hiel")
    rl.SetWindowPosition(800, 200)
    rl.SetTargetFPS(500)
    rl.SetExitKey(nil)
}

@(export)
game_init :: proc() {
    g = new(GameMemory)
    g.run = true

    g.pp = PPInit(rl.GetScreenWidth(), rl.GetScreenHeight())
    g.bloom = BloomInit()

    rl.InitAudioDevice()

    InitAssetsMemory(&g.assetStorage)
    LoadAssets(&g.assetStorage)
    g.mui = muiInit()

    g.camera = {
        up = {0, 1, 0},
        position = {0, 4, 1},
        target = {0, 4, 0},
        fovy = 12,
        projection = .ORTHOGRAPHIC
    }

    /////
    ha.Init(&g.entities)

    ////


    InitUI(&uiCtx)
    uiCtx.textStyle.font = GetFont(g.assetStorage, .Goldman_Regular)

    game_hot_reloaded(g)
}

@(export)
game_should_run :: proc() -> bool {
    when ODIN_OS != .JS {
        // Never run this proc in browser. It contains a 16 ms sleep on web!
        if rl.WindowShouldClose() {
            return false
        }
    }

    return g.run
}

@(export)
game_shutdown :: proc() {
    DestroyAssetsMemory(&g.assetStorage)
    free(g.mui)
    free(g)
    delete(uiCtx.transientArena.data)
}

@(export)
game_shutdown_window :: proc() {
    rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
    return g
}

@(export)
game_memory_size :: proc() -> int {
    return size_of(GameMemory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
    g = (^GameMemory)(mem)

    // Here you can also set your own global variables. A good idea is to make
    // your global variables into pointers that point to something inside `g`.
}

@(export)
game_force_reload :: proc() -> bool {
    return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
    return rl.IsKeyPressed(.F6)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
    rl.SetWindowSize(i32(w), i32(h))
}
