package game

import rl "vendor:raylib"
import "core:math"
import "core:math/rand"
import ha "handle_array"

SpawnerType :: enum {
    Bullet,
    Stack,

    //
    Circle,
    Spread,
}


AngleType :: union #no_nil {
    AngleTypeParent,
    AngleTypeFixed,
    AngleTypeTargeted,
    AngleTypeRandom
}

AngleTypeParent :: struct {
}

AngleTypeFixed :: struct {
    value: Deg,
}

AngleTypeTargeted :: struct {
}

AngleTypeRandom :: struct {
    min, max: Deg,
}

Spawner :: struct {
    children: []Spawner,

    type: SpawnerType,

    sprite: Image_Asset,

    // position: v2,
    count: int,
    speed: f32,
    acceleration: f32,
    angularSpeed: Deg,

    size: f32,

    angle: AngleType,

    // circle
    radius: f32,

    // Spread
    spredAngle: Deg,

    // Stack
    minSpeed: f32,
    maxSpeed: f32,
}

BulletSizes := #partial [Image_Asset]f32 {
    .Circle_03 = 0.8,
    .Circle_05 = 0.35,
}

GetAngle :: proc(angle: AngleType, position: v2) -> Deg {
    switch v in angle {
    case AngleTypeParent:
        assert(false, "Trying to get angle from AngleTypeParent") // - wer should never get here

    case AngleTypeFixed:
        return v.value

    case AngleTypeTargeted:
        player := ha.GetElement(g.entities, g.playerHandle)
        delta := player.position - position

        rads := math.atan2(delta.y, delta.x)
        return Deg(rads * math.DEG_PER_RAD)

    case AngleTypeRandom:
        return cast(Deg) rand.float32_range(f32(v.min), f32(v.max))
    }

    return 0
}

SpawnEnemyBullet :: proc(pos: v2, sprite: Image_Asset, speed, acc: f32, rot, angSpeed: Deg, size: f32) {
    bullet: Entity
    bullet.flags = {.DrawSprite, .Collision, .BulletMovement, .DestroyOutsideCamera}
    bullet.owner = .Enemy

    bullet.sprite = sprite
    bullet.spriteTint = rl.WHITE

    bullet.position = pos
    bullet.speed = speed
    bullet.acceleration = acc
    bullet.rotation = rot
    bullet.angularSpeed = angSpeed

    bullet.size = size
    bullet.collisionSize = (bullet.size * BulletSizes[sprite]) / 2

    ha.AppendElement(&g.entities, bullet)
}

Spawn :: proc(pos: v2, spawner: Spawner) {
    switch spawner.type {
    case .Bullet: // Spawn at pos, with speed, angle, angular velocity and acceleration
        SpawnEnemyBullet(
            pos,
            spawner.sprite,
            spawner.speed,
            spawner.acceleration,
            GetAngle(spawner.angle, pos),
            spawner.angularSpeed,
            spawner.size
        )

    case .Stack: // Spawn n bullets with stuff as above but
        for i in 0..<spawner.count {

            SpawnEnemyBullet(
                pos,
                spawner.sprite,
                math.lerp(spawner.minSpeed, spawner.maxSpeed, f32(i) / f32(spawner.count)),
                spawner.acceleration,
                GetAngle(spawner.angle, pos),
                spawner.angularSpeed,
                spawner.size
            )
        }

    case .Circle:
        baseAngle := GetAngle(spawner.angle, pos)
        for i in 0..<spawner.count {
            angle := baseAngle + (Deg(i) / Deg(spawner.count)) * 360

            x := math.cos(f32(angle) * math.RAD_PER_DEG) * spawner.radius
            y := math.sin(f32(angle) * math.RAD_PER_DEG) * spawner.radius

            for &child in spawner.children {
                c := child
                if _, ok := c.angle.(AngleTypeParent); ok {
                    c.angle = AngleTypeFixed{ angle }
                }
                
                Spawn(pos + {x, y}, c)
            }
        }

    case .Spread:
        spreadDelta := spawner.spredAngle / Deg(spawner.count - 1)
        baseAngle := GetAngle(spawner.angle, pos)
        for i in 0..<spawner.count {
            angle := baseAngle + Deg(i) * spreadDelta - spawner.spredAngle / 2

            x := math.cos(f32(angle) * math.RAD_PER_DEG) * spawner.radius
            y := math.sin(f32(angle) * math.RAD_PER_DEG) * spawner.radius

            for &child in spawner.children {
                c := child
                if _, ok := c.angle.(AngleTypeParent); ok {
                    c.angle = AngleTypeFixed{ angle }
                }
                
                Spawn(pos + {x, y}, c)
            }
        }
    }
}