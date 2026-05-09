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

    // position: v2,
    count: int,
    speed: f32,
    acceleration: f32,
    angularSpeed: Deg,

    angle: AngleType,

    // circle
    radius: f32,

    // Spread
    spredAngle: Deg,

    // Stack
    minSpeed: f32,
    maxSpeed: f32,
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

Spawn :: proc(pos: v2, spawner: Spawner) {
    switch spawner.type {
    case .Bullet: // Spawn at pos, with speed, angle, angular velocity and acceleration
        bullet, handle := ha.CreateElement(&g.entities)

        bullet.flags = {.DrawSprite, .Collision, .BulletMovement, .DestroyOutsideCamera}
        bullet.sprite = .Circle_05

        bullet.position = pos
        bullet.speed = spawner.speed
        bullet.acceleration = spawner.acceleration
        bullet.angularSpeed = spawner.angularSpeed

        bullet.rotation = GetAngle(spawner.angle, pos)

        bullet.size = .4

    case .Stack: // Spawn n bullets with stuff as above but
        for i in 0..<spawner.count {
            bullet, handle := ha.CreateElement(&g.entities)

            bullet.flags = {.DrawSprite, .Collision, .BulletMovement, .DestroyOutsideCamera}
            bullet.sprite = .Circle_05

            bullet.position = pos
            bullet.speed = math.lerp(spawner.minSpeed, spawner.maxSpeed, f32(i) / f32(spawner.count))

            bullet.rotation = GetAngle(spawner.angle, pos)

            bullet.size = 1
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


SpawnCircleOrSomethinIDunno :: proc() {
    spawn := Spawner {
        type = .Circle,
        count = 12,
        angle = AngleTypeFixed { 0 },
        radius = 0,

        children = {
            {
                type = .Bullet,
                speed = 0,
                acceleration = 0.8,
                // angularSpeed = 30,
                angle = AngleTypeParent{},
            },
        }
    }

    @static timer: f32
    @static step: int

    timer -= rl.GetFrameTime()
    if timer < 0 {
        Spawn({f32(step) *  0.4, 5}, spawn)
        Spawn({f32(step) * -0.4, 5}, spawn)

        step += 1
        timer = .4

        if step > 10 {
            step = 0
            timer = 4
        }
    }
}