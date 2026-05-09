package game

import "core:fmt"
import "core:math/linalg"

import "core:math"

import rl "vendor:raylib"
import ha "handle_array"

EntityHandle :: distinct ha.Handle

EntityFlag :: enum {
    DrawSprite,
    DrawRect,
    SpriteAnimation,

    Health,
    Collision,

    BulletMovement,

    DestroyOutsideCamera,
}

CollisionType :: enum {
    None,
    AABB,
    Circle,
}

EntityFlags :: distinct bit_set[EntityFlag]

Entity :: struct {
    flags: EntityFlags,
    handle: EntityHandle,

    lifeTime: f32,

    position: v2,
    rotation: Deg,
    size: f32,

    //
    speed: f32,
    acceleration: f32,
    angularSpeed: f32,

    //
    sprite: Image_Asset,
    spriteRot: Deg,

    gif: Gif_Asset,
    frame: int,

    //
    hp: int,
    toDestroy: bool,

    collisionSize: v2,

    shootTimer: f32,

    controller: EntityController,
}

EntityController :: union {
    EntityControllerPlayer,

}

EntityControllerPlayer :: struct {

}

GetCameraBounds :: proc() -> Rect{
    w := rl.GetScreenWidth()
    h := rl.GetScreenHeight()

    height := g.camera.fovy
    width := (f32(w) / f32(h)) * height

    return Rect {
        g.camera.position.x - width / 2,
        g.camera.position.x + width / 2,
        g.camera.position.y + height / 2,
        g.camera.position.y - height / 2,
    }
}

UpdateEntity :: proc(e: ^Entity) {
    frameTime := rl.GetFrameTime()
    e.lifeTime += frameTime


    if .SpriteAnimation in e.flags {
        sheet := GetGif(g.assetStorage, e.gif)
        frames := sheet.rows

        frame := cast(int) math.floor(e.lifeTime / 0.03)
        e.frame = frame % frames
    }

    if .BulletMovement in e.flags {
        e.speed += e.acceleration * frameTime
        e.rotation += Deg(e.angularSpeed * frameTime)

        rads := f32(e.rotation) * math.RAD_PER_DEG
        forward := v2{math.cos(rads), math.sin(rads)}
        e.position += e.speed * forward * frameTime
    }

    if .DestroyOutsideCamera in e.flags {
        cameraBounds := GetCameraBounds()
        bounds := GetEntityBounds(e)
         // wasInsideCamera := e->isInsideCamera

        if( bounds.left  < cameraBounds.left  ||
            bounds.right > cameraBounds.right ||
            bounds.bot   < cameraBounds.bot   ||
            bounds.top   > cameraBounds.top)
        {
            e.toDestroy = true
            fmt.println("destroi")
        }
    }

    switch controller in  e.controller {
    case EntityControllerPlayer:
        UpdatePlayer(e)
    }
}

UpdatePlayer :: proc(e: ^Entity) {
    // movement
    input: v2
    if rl.IsKeyDown(.UP) || rl.IsKeyDown(.W) {
        input.y += 1
    }
    if rl.IsKeyDown(.DOWN) || rl.IsKeyDown(.S) {
        input.y += -1
    }
    if rl.IsKeyDown(.LEFT) || rl.IsKeyDown(.A) {
        input.x += -1
    }
    if rl.IsKeyDown(.RIGHT) || rl.IsKeyDown(.D) {
        input.x += 1
    }

    focus := rl.IsKeyDown(.X)
    speed: f32 = focus ? 4 : 8

    input = linalg.normalize0(input)
    e.position += input * rl.GetFrameTime() * speed

    cameraBounds := GetCameraBounds()
    e.position.x = clamp(e.position.x, cameraBounds.left, cameraBounds.right)
    e.position.x = clamp(e.position.y, cameraBounds.bot, cameraBounds.top)


    // Shooting
    offsets := [?]v2 {
        {0,     0.1},
        {-0.05, 0},
        { 0.05, 0},

        {0.1, 0},

        {-0.1, 0},
    }

    angles := [?]Deg {
        0, 0, 0,
        35,

        -35
    }

    #assert(len(offsets) == len(angles))
    
    e.shootTimer -= rl.GetFrameTime()
    shoot := rl.IsKeyDown(.Z)
    if shoot && e.shootTimer < 0 {
        e.shootTimer = 0.05

        for _, i in offsets {
            bullet, handle := ha.CreateElement(&g.entities)

            bullet.flags = {.DrawSprite, .Collision, .BulletMovement, .DestroyOutsideCamera}
            bullet.sprite = .Trace_07

            bullet.position = e.position + offsets[i]
            bullet.speed = 50

            bullet.rotation = 90 + angles[i]
            bullet.spriteRot = -90

            bullet.size = 1
        }
    }

}

DrawEntity :: proc(e: ^Entity) {
    if .DrawSprite in e.flags {
        tex := GetTexture(g.assetStorage, e.sprite)
        if e.size != 0 {
            DrawSpriteSize(tex, e.position, rl.WHITE, e.size, rotation = e.rotation + e.spriteRot)
        }
        else {
            DrawSprite(tex, e.position, rl.WHITE, rotation = e.rotation + e.spriteRot)
        }
    }

    if .SpriteAnimation in  e.flags {
        anim := GetGif(g.assetStorage, e.gif)
        DrawAnimation(anim, e.position, e.size, i32(e.frame), rotation = e.rotation)
    }


    if .DrawRect in e.flags {
        rl.DrawRectangleV(e.position, e.size, rl.RED)
    }
}

CreatePlayer :: proc() -> EntityHandle {
    player := Entity {
        flags = {
            // .DrawSprite,
            .DrawRect
        },
        // sprite = .Round_Cat,
        size = 1,
        controller = EntityControllerPlayer{}
    }

    return ha.AppendElement(&g.entities, player)
}

DestroyEntity :: proc(entity: ^Entity) {
    ha.FreeSlot(&g.entities, entity.handle)
}

GetEntityBounds :: proc(e: ^Entity) -> Rect {
    ret: Rect = {}

    ret.left  = e.position.x - e.collisionSize.x / 2;
    ret.right = e.position.x + e.collisionSize.x / 2;
    ret.bot   = e.position.y - e.collisionSize.y / 2;
    ret.top   = e.position.y + e.collisionSize.y / 2;

    return ret;
}
