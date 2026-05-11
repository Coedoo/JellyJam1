package game

import "core:fmt"
import "core:math/linalg"

import "core:math"

import rl "vendor:raylib"
import ha "handle_array"

import "core:math/ease"

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

// CollisionType :: enum {
//     None,
//     AABB,
//     Circle,
// }

Owner :: enum {
    None,
    Player,
    Enemy,
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
    angularSpeed: Deg,

    //
    sprite: Image_Asset,
    spriteRot: Deg,

    gif: Gif_Asset,
    frame: int,

    //
    hp: int,
    toDestroy: bool,

    owner: Owner,

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

ResetPlayer :: proc() {
    player, ok := ha.GetElementPtr(&g.entities, g.playerHandle)
    if ok {
        player.lifeTime = 0

        g.noDamageTimer = 3
    }
}

UpdatePlayer :: proc(e: ^Entity) {
    cameraBounds := GetCameraBounds()

    // Spawn animation
    animTime : f32 = 0.8
    if(e.lifeTime < animTime) {
        p := ease.sine_out(e.lifeTime / animTime)
        e.position = linalg.lerp(v2{0, cameraBounds.bot}, v2{0, -1}, p)
        return
    }

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

    e.position.x = clamp(e.position.x, cameraBounds.left, cameraBounds.right)
    e.position.y = clamp(e.position.y, cameraBounds.bot, cameraBounds.top)


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

    offsetsFocused := [?]v2 {
        {0,     0.1},
        {-0.05, 0},
        { 0.05, 0},

        {0.08, 0},

        {-0.08, 0},
    }

    anglesFocused := [?]Deg {
        0, 0, 0,
        0,

        0
    }

    #assert(len(offsets) == len(angles))

    e.shootTimer -= rl.GetFrameTime()
    shoot := rl.IsKeyDown(.Z)
    if shoot && e.shootTimer < 0 {
        e.shootTimer = 0.05

        off := focus ? offsetsFocused : offsets
        ang := focus ? anglesFocused : angles

        for _, i in offsets {
            bullet, handle := ha.CreateElement(&g.entities)

            bullet.flags = {.DrawSprite, .Collision, .BulletMovement, .DestroyOutsideCamera}
            bullet.sprite = .Trace_07

            bullet.owner = .Player

            bullet.position = e.position + off[i]
            bullet.speed = 50

            bullet.rotation = 90 + ang[i]
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

    if e.handle == g.playerHandle {
        size :: v2{.5, .8}
        tint := rl.RED
        if e.handle == g.playerHandle && g.noDamageTimer > 0 {
            tint = rl.ColorLerp(tint, {100, 100, 100, 255}, math.sin(g.noDamageTimer * 5) * 2 + 1)
        }
        rl.DrawRectangleV(e.position - size / 2, size, tint)
    }


    // if .DrawRect in e.flags {
    //     tint := rl.RED
    //     if e.handle == g.playerHandle && g.noDamageTimer > 0 {
    //         tint = rl.ColorLerp(tint, {100, 100, 100, 255}, math.sin(g.noDamageTimer * 5) * 2 + 1)
    //     }

    //     rl.DrawRectangleV(e.position - e.size / 2, e.size, tint)
    // }
}

CreatePlayer :: proc() -> EntityHandle {
    player := Entity {
        flags = {
            // .DrawSprite,
            .DrawRect
        },
        // sprite = .Round_Cat,
        size = 1,
        controller = EntityControllerPlayer{},
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

DestroyAllBullets :: proc() {
    iter := ha.MakeIterReverse(&g.entities)
    for e in ha.Iterate(&iter) {
        if .BulletMovement in e.flags {
            DestroyEntity(e)
        }
    }
}


CreateEnemy :: proc() -> EntityHandle {
    enemy := Entity {
        flags = {
            .DrawRect, .Collision
        },
        size = 2,
        collisionSize = 0.8,
        position  = {0, 7},

        hp = PatternHP[g.currentPattern],
    }

    return ha.AppendElement(&g.entities, enemy)
}