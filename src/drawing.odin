package game

import rl "vendor:raylib"
import b2 "vendor:box2d"
import rlgl "vendor:raylib/rlgl"
import "core:fmt"

import "core:math"

PIXELS_PER_UNIT :: 32

DrawSprite :: proc(tex: rl.Texture, pos: v2, color: rl.Color, rotation: Deg = 0, origin := v2{0.5, 0.5}) {
    size := f32(tex.width)  / PIXELS_PER_UNIT
    DrawSpriteSize(tex, pos, color, size, rotation, origin)
}

DrawSpriteSize :: proc(tex: rl.Texture, pos: v2, color: rl.Color, size: f32, rotation: Deg = 0, origin := v2{0.5, 0.5}) {
    sizeX := size
    sizeY := size * f32(tex.height) / f32(tex.width)

    left  := -sizeX * origin.x
    bot   := -sizeY * origin.y
    right := +sizeX * (1 - origin.x)
    top   := +sizeY * (1 - origin.y)

    rotRad := f32(rotation * math.RAD_PER_DEG)
    rotMat :=  matrix[2, 2] f32 {math.cos(rotRad), -math.sin(rotRad),
                                 math.sin(rotRad),  math.cos(rotRad)}

    a := rotMat * v2{left,  bot} + pos
    b := rotMat * v2{right, bot} + pos
    c := rotMat * v2{right, top} + pos
    d := rotMat * v2{left,  top} + pos

    rlgl.SetTexture(tex.id);
    rlgl.Begin(rlgl.QUADS);

        rlgl.Normal3f(0.0, 0.0, 1.0);
        rlgl.Color4ub(color.r, color.g, color.b, color.a);

        rlgl.TexCoord2f(1, 1)
        rlgl.Vertex2f(a.x, a.y)
        rlgl.TexCoord2f(0, 1)
        rlgl.Vertex2f(b.x, b.y)
        rlgl.TexCoord2f(0, 0)
        rlgl.Vertex2f(c.x, c.y)
        rlgl.TexCoord2f(1, 0)
        rlgl.Vertex2f(d.x, d.y)

    rlgl.End();
    rlgl.SetTexture(0);
}

SpriteSheet :: struct {
    texture: rl.Texture,

    frameSize: [2]i32,

    columns: int,
    rows: int,
}

DrawAnimation :: proc(sheet: SpriteSheet, pos: v2, size: f32, frame: i32, color := rl.WHITE, rotation: Deg = 0, origin := v2{0.5, 0.5}) {
    sizeX := size
    sizeY := size * f32(sheet.frameSize.x) / f32(sheet.frameSize.y)

    left  := -sizeX * origin.x
    bot   := -sizeY * origin.y
    right := +sizeX * (1 - origin.x)
    top   := +sizeY * (1 - origin.y)

    rotRad := f32(rotation * math.RAD_PER_DEG)
    rotMat :=  matrix[2, 2] f32 {math.cos(rotRad), -math.sin(rotRad),
                                 math.sin(rotRad),  math.cos(rotRad)}

    a := rotMat * v2{left,  bot} + pos
    b := rotMat * v2{right, bot} + pos
    c := rotMat * v2{right, top} + pos
    d := rotMat * v2{left,  top} + pos

    frames := sheet.columns * sheet.rows
    frame := int(frame) % frames

    frameMinX := f32(frame % sheet.columns) / f32(sheet.columns)
    frameMaxX := f32(frame % sheet.columns + 1) / f32(sheet.columns)

    // For Y axis we reverse the Y direction because raylib textures are upside down
    frame = frames - frame

    frameMinY := f32(frame / sheet.columns) / f32(sheet.rows)
    frameMaxY := f32(frame / sheet.columns + 1) / f32(sheet.rows)

    rlgl.SetTexture(sheet.texture.id);
    rlgl.Begin(rlgl.QUADS);

        rlgl.Normal3f(0.0, 0.0, 1.0);
        rlgl.Color4ub(color.r, color.g, color.b, color.a);

        rlgl.TexCoord2f(frameMaxX, frameMaxY)
        rlgl.Vertex2f(a.x, a.y)
        rlgl.TexCoord2f(frameMinX, frameMaxY)
        rlgl.Vertex2f(b.x, b.y)
        rlgl.TexCoord2f(frameMinX, frameMinY)
        rlgl.Vertex2f(c.x, c.y)
        rlgl.TexCoord2f(frameMaxX, frameMinY)
        rlgl.Vertex2f(d.x, d.y)

    rlgl.End();
    rlgl.SetTexture(0);
}



DrawGrid :: proc() {
    w := f32(rl.GetScreenWidth())
    h := f32(rl.GetScreenHeight())

    aspect := w / h;
    top := g.camera.fovy/2.0;
    right := top*aspect;

    matProj := rl.MatrixOrtho(-right, right, -top, top, f32(rlgl.GetCullDistanceNear()), f32(rlgl.GetCullDistanceFar()))
    invVPMat := rl.MatrixInvert(matProj * rl.GetCameraMatrix(g.camera))

    gridShader := GetShader(g.assetStorage, .Grid)
    loc := rl.GetShaderLocation(gridShader, "invVPMat")
    rl.SetShaderValueMatrix(gridShader, loc, invVPMat);

    rl.BeginShaderMode(gridShader)
    rlgl.Begin(rlgl.QUADS)
        rlgl.Vertex2f(-1, -1)
        rlgl.Vertex2f( 1, -1)
        rlgl.Vertex2f( 1,  1)
        rlgl.Vertex2f(-1,  1)
    rlgl.End()
    rl.EndShaderMode()
}
