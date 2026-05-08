package game

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

Rect :: struct {
    left, right, top, bot: f32,
}

RectInt :: struct {
    left, right, top, bot: i32,
}

RectToRLRect :: proc(rect: Rect) -> rl.Rectangle {
    return {rect.left, rect.bot, rect.right - rect.left, rect.top - rect.bot}
}

IsInsideRect :: proc(rect: Rect, pos: v2) -> bool {
    return pos.x >= rect.left && pos.x <= rect.right &&
           pos.y >= rect.bot  && pos.y <= rect.top
}

MouseWorldPos :: proc() -> v2 {
    mousePos := rl.GetMousePosition()

    w := f32(rl.GetScreenWidth())
    h := f32(rl.GetScreenHeight())

    aspect := w / h;
    top    := g.camera.fovy/2.0;
    right  := top*aspect;

    matProj  := rl.MatrixOrtho(-right, right, -top, top, f32(rlgl.GetCullDistanceNear()), f32(rlgl.GetCullDistanceFar()))
    invVPMat := rl.MatrixInvert(matProj * rl.GetCameraMatrix(g.camera))

    mousePos = mousePos / {w, h} * 2 - 1
    mousePos.y = -mousePos.y
    worldPos := invVPMat * [4]f32{ mousePos.x, mousePos.y, 0, 1}

    return worldPos.xy
}