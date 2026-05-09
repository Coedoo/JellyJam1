package game

import rl "vendor:raylib"
import "core:math"
import "core:math/rand"

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
    value: f32,
}

AngleTypeTargeted :: struct {
}

AngleTypeRandom :: struct {
    min, max: f32,
}

Spawner :: struct {
    children: []Spawner,

    type: SpawnerType,

    // position: v2,
    count: int,
    speed: f32,

    angle: AngleType,

    // circle
    radius: f32,

    // Spread
    spredAngle: f32,

    // Stack
    minSpeed: f32,
    maxSpeed: f32,
}

GetAngle :: proc(angle: AngleType) -> f32 {
    switch v in angle {
    case AngleTypeParent:
    case AngleTypeFixed:
        return v.value

    case AngleTypeTargeted:
        // TODO calculate angle to the player

    case AngleTypeRandom:
        return rand.float32_range(v.min, v.max)
    }

    return 0
}

Spawn :: proc(pos: v2, spawner: Spawner) {
    switch spawner.type {
    case .Bullet: // Spawn at pos, with speed, angle, angular velocity and acceleration

    case .Stack: // Spawn n bullets with stuff as above but 

    case .Circle:
        baseAngle := GetAngle(spawner.angle)
        for i in 0..<spawner.count {
            angle := baseAngle + f32(i / spawner.count)
            angle *= math.DEG_PER_RAD

            x := math.cos(angle) * spawner.radius
            y := math.sin(angle) * spawner.radius

            // TODO: Inherit rotation
            for &child in spawner.children {
                Spawn({x, y}, child)
            }
        }

    case .Spread:
    }
}


SpawnCircleOrSomethinIDunno :: proc() {
    spawn := Spawner {
        type = .Circle,
        count = 25,
        angle = AngleTypeFixed { 0 },
        radius = 2,

        children = {
            {
                type = .Bullet,
                speed = .3,
                angle = AngleTypeParent{},
            },
        }
    }

    // timer -= rl.GetFrameTime()
    // if timer < 0 {
    //     count -= 1
    //     if count < 0 {
    //         step += 1
    //     }

    //     timer = 0.2
    //     Spawn({0, 3}, spawn)
    // }
}