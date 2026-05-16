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

    DrawSpriteSheet,

    DrawCircle,

    Health,
    Collision,

    BulletMovement,

    DestroyOutsideCamera,

    DrawCollisionCircle,

    DestroyAfterTime,
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

    animCheckpointTime: f32,
    lifeTime: f32,
    maxLifeTime: f32,

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

    sheetCell: [2]i32,
    spriteSheet: SpriteSheet,

    gif: Gif_Asset,
    frame: int,

    spriteTint: rl.Color,
    color: rl.Color,

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
    EntityControllerShield,
    EntityControllerHelp,
}

EntityControllerPlayer :: struct {
}

EntityControllerShield :: struct {
}

EntityControllerHelp :: struct {
    offset: v2,
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

MovePlayerToPoint :: proc(e: ^Entity, target: v2, speed: f32) -> bool {
    epsilon : f32 = 0.05
    direction := target - e.position;
    direction = linalg.normalize0(direction)
    e.position += direction * rl.GetFrameTime() * f32(speed)
    return linalg.vector_length2(e.position - target) <= epsilon
}

UpdatePlayer :: proc(e: ^Entity) {
    if g.stage == .Victory {
        return
    }

    cameraBounds := GetCameraBounds()

    if g.stage == .Victory_Anim1 {
        target := v2{0, f32(cameraBounds.top + cameraBounds.bot) / 2}
        distance := linalg.vector_length2(e.position - target)
        speed : f32 = clamp(distance, 0.5, 3)
        arrived := MovePlayerToPoint(e, target, speed)

        if (arrived) {
            e.animCheckpointTime = e.lifeTime
            g.stage = .Victory_Anim2
        }
        return
    }
    if g.stage == .Victory_Anim2 {
        speed : f32 = clamp(math.pow_f32(1 + (e.lifeTime - e.animCheckpointTime)/0.8, 5), 0, 50)
        arrived := MovePlayerToPoint(e, v2{0.0, f32(cameraBounds.top)}, speed)
        if (arrived) {
            g.stage = .Victory
            e.toDestroy = true
        }
        return
    }

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
    speed: f32 = focus ? 3 : 7

    input = linalg.normalize0(input)
    e.position += input * rl.GetFrameTime() * speed

    e.position.x = clamp(e.position.x, cameraBounds.left, cameraBounds.right)
    e.position.y = clamp(e.position.y, cameraBounds.bot, cameraBounds.top)

    e.sheetCell.y = 1 + i32(input.x)

    if focus {
        e.flags += {.DrawCollisionCircle}
    }
    else {
        e.flags -= {.DrawCollisionCircle}
    }

    // Shooting
    offsets := [?]v2 {
        {-0.05, 0.1},
        { 0.05, 0.1},
        {-0.2, 0},
        { 0.2, 0},

        {-0.4, -0.4},
        {-0.3, -0.3},

        {0.4, -0.4},
        {0.3, -0.3},
    }

    angles := [?]Deg {
        0, 0, 0, 0, // front
        20, 20, // left
        -20, -20, // right
    }

    offsetsFocused := [?]v2 {
        {-0.05, 0.1},
        { 0.05, 0.1},
        {-0.05, 0},
        { 0.05, 0},

        {-0.4, -0.4},
        {-0.3, -0.3},

        {0.4, -0.4},
        {0.3, -0.3},
    }

    anglesFocused := [?]Deg {
        0, 0, 0, 0,
        5, 0,
        -5, 0
    }

    e.shootTimer -= rl.GetFrameTime()
    shoot := rl.IsKeyDown(.Z)
    if shoot && e.shootTimer < 0 {
        e.shootTimer = 0.05

        rl.PlaySound(g.shootAudio)

        off := focus ? offsetsFocused : offsets
        ang := focus ? anglesFocused : angles

        for _, i in offsets {
            SpawnPlayerBullet(e.position + off[i], ang[i])
        }
    }

}

SpawnPlayerBullet :: proc(pos: v2, angle: Deg) {
    bullet, handle := ha.CreateElement(&g.entities)

    bullet.flags = {.DrawSprite, .Collision, .BulletMovement, .DestroyOutsideCamera}
    bullet.sprite = .Trace_07
    bullet.spriteTint = rl.WHITE

    bullet.owner = .Player

    bullet.position = pos
    bullet.speed = 50

    bullet.rotation = 90 + angle
    bullet.spriteRot = -90

    bullet.size = 1
}

DrawEntity :: proc(e: ^Entity) {
    if .DrawSprite in e.flags {
        tex := GetTexture(g.assetStorage, e.sprite)
        if e.size != 0 {
            DrawSpriteSize(tex, e.position, e.spriteTint, e.size, rotation = e.rotation + e.spriteRot)
        }
        else {
            DrawSprite(tex, e.position, e.spriteTint, rotation = e.rotation + e.spriteRot)
        }
    }

    if .DrawSpriteSheet in e.flags {
        DrawSpriteSheetCell(
            e.spriteSheet,
            e.sheetCell,
            e.position,
            e.spriteTint,
            e.size,
            e.rotation + e.spriteRot)
    }

    if .SpriteAnimation in  e.flags {
        anim := GetGif(g.assetStorage, e.gif)
        DrawAnimation(anim, e.position, e.size, i32(e.frame), rotation = e.rotation)
    }

    if .DrawCircle in e.flags {
        rl.DrawCircleV(e.position, e.collisionSize.x, {255, 255, 0, 100})
    }

    if .DrawCollisionCircle in e.flags {
            rl.DrawCircleV(e.position, e.collisionSize.x, e.color)
    }
}

CreatePlayer :: proc() -> EntityHandle {
    player := Entity {
        flags = {
            // .DrawSprite,
            .DrawRect,
            .Collision,
            .DrawSpriteSheet,
        },
        sprite = .Ship,
        spriteTint = rl.WHITE,

        sheetCell = {0, 1},
        spriteSheet =  {
            texture = GetTexture(g.assetStorage, .Ship),
            frameSize = {48, 48},
            columns = 4,
            rows = 3,
        },

        hp = 3,
        size = 1.5,
        collisionSize = 0.04,
        controller = EntityControllerPlayer{},
        color = rl.RED
    }

    return ha.AppendElement(&g.entities, player)
}

DestroyEntity :: proc(entity: ^Entity) {
    ha.FreeSlot(&g.entities, entity.handle)
}

DestroyEntityHandle :: proc(handle: EntityHandle) {
    ha.FreeSlot(&g.entities, handle)
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


HelpType :: enum {
    Purple,
    Yellow,
    Red,
    Blue
}

HelpColor := [HelpType]rl.Color {
    .Purple = {20, 0, 140, 127},
    .Yellow = {200, 200, 200, 127},
    .Red = {200, 0, 20, 127},
    .Blue = {10, 190, 220, 127},
}

HelpOffset := [HelpType]v2 {
    .Purple = {-0.8, -1},
    .Yellow = {0.8, -1},
    .Red = {0, -2},
    .Blue = {},
}

CreateHelp :: proc() -> bool {
    if g.helpTimer > 0 || g.helpCount <= 0 {
        return false
    }

    type := cast(HelpType) g.helpIdx
    g.helpIdx += 1

    shield := Entity {
        flags = {
            .Collision, .DrawCollisionCircle, .DestroyAfterTime
        },
        maxLifeTime = SHIELD_TIME,
        size = 4,
        collisionSize = 2,
        controller = EntityControllerShield{},
        color = HelpColor[type]
    }

    g.shieldHandle = ha.AppendElement(&g.entities, shield)

    help := Entity {
        flags = {
            // .DrawSprite,
            .DrawSpriteSheet,
            .DrawRect,
            .DestroyAfterTime,
        },
        maxLifeTime = SHIELD_TIME,
        sprite = .Ship,

        sheetCell = {1, 1},
        spriteSheet =  {
            texture = GetTexture(g.assetStorage, .Ship),
            frameSize = {48, 48},
            columns = 4,
            rows = 3,
        },

        spriteTint = rl.WHITE,
        size = 1,
        controller = EntityControllerHelp{ HelpOffset[type] },
        color = rl.RED
    }

    ha.AppendElement(&g.entities, help)

    return true
}