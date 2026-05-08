package game

import "core:fmt"
import "core:math/linalg"

import "core:math"

import rl "vendor:raylib"
import ha "handle_array"

EntityHandle :: distinct ha.Handle

EntityFlag :: enum {
    DrawSprite,
    SpriteAnimation,
}

EntityFlags :: distinct bit_set[EntityFlag]

Entity :: struct {
    flags: EntityFlags,
    handle: EntityHandle,

    level: int,

    lifeTime: f32,

    position: v2,
    rotation: Deg,
    size: f32,

    texture: Image_Asset,

    gif: Gif_Asset,
    frame: int,

    toDestroy: bool,
    controller: EntityController,
}

EntityController :: union {
    EntityControllerPlayer,

}

EntityControllerPlayer :: struct {

}

UpdateEntity :: proc(e: ^Entity) {
    e.lifeTime += rl.GetFrameTime()

    if .SpriteAnimation in e.flags {
        sheet := GetGif(g.assetStorage, e.gif)
        frames := sheet.rows

        frame := cast(int) math.floor(e.lifeTime / 0.03)
        e.frame = frame % frames
    }

    switch controller in  e.controller {
    case EntityControllerPlayer:
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

        input = linalg.normalize0(input)
        e.position += input * rl.GetFrameTime() * 5
    }
}

DrawEntity :: proc(e: ^Entity) {
    if .DrawSprite in e.flags {
        tex := GetTexture(g.assetStorage, e.texture)
        DrawSprite(tex, e.position, rl.WHITE, rotation = e.rotation)
    }

    if .SpriteAnimation in  e.flags {
        anim := GetGif(g.assetStorage, e.gif)
        DrawAnimation(anim, e.position, e.size, i32(e.frame), rotation = e.rotation)
    }
}

CreatePlayer :: proc() -> EntityHandle {
    player := Entity {
        flags = {
            .DrawSprite,
        },
        // texture = .Round_Cat,
        controller = EntityControllerPlayer{}
    }

    return ha.AppendElement(&g.entities, player)
}

DestroyEntity :: proc(entity: ^Entity) {
    ha.FreeSlot(&g.entities, entity.handle)
}
