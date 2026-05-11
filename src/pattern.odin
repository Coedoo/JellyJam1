package game

import rl "vendor:raylib"
import ha "handle_array"

import "core:fmt"

import "core:math/linalg"

import "core:math/ease"

Pattern :: enum {
    Pattern1,
    Pattern2,
    Pattern3,

    MoveAndAimedSpread,
}

PatternState :: struct {
    state: int,

    timer: f32,
    step: int,

    movementStep: int,
    movementTimer: f32,

    previousPos: v2
}

UpdatePattern :: proc(type: Pattern, state: ^PatternState) {
    switch type {
    case .Pattern1: Patt_Test1(state)
    case .Pattern2: Patt_Test2(state)
    case .Pattern3: Patt_Test3(state)
    case .MoveAndAimedSpread: MoveAndAimedSpread(state)
    }
}

StartTransition :: proc(state: ^PatternState) {
    state.state = -2
    state.timer = 0

    boss := ha.GetElement(g.entities, g.enemyHandle)
    state.previousPos = boss.position

    SpawnParticles(&g.transitionParticles, 30, boss.position)
}

PatternTransition :: proc(state: ^PatternState, pos: v2) -> bool {
    switch state.state {

    case -2:
        state.timer += rl.GetFrameTime()
        if state.timer > 0.5 {
            state.timer = 0
            state.state = -1
        }

    case -1:
        time :: 1

        state.timer += rl.GetFrameTime()

        p := ease.quartic_out(state.timer / time)
        boss, _ := ha.GetElementPtr(&g.entities, g.enemyHandle)

        boss.position = linalg.lerp(state.previousPos, pos, p)

        if state.timer > time {
            state^ = {}
        }
    }

    return state.state < 0
}

//////////////////

Patt_Test1 :: proc(state: ^PatternState) {
    if PatternTransition(state, {0, 8}) {
        return
    }

    spawn := Spawner {
        type = .Circle,
        count = 12,
        angle = AngleTypeFixed {},
        radius = 0,

        children = {
            {
                type = .Bullet,
                speed = -2,
                acceleration = 1,
                angle = AngleTypeParent{},
            },
        }
    }

    state.timer -= rl.GetFrameTime()
    switch state.state {
    case 0:
        state.timer = 1
        state.state = 1

    case 1:
        if state.timer < 0 {
            Spawn({f32(state.step) *  0.4, 5}, spawn)
            Spawn({f32(state.step) * -0.4, 5}, spawn)

            state.step += 1
            state.timer = .4

            if state.step > 10 {
                state.step = 0
                state.state = 2
                state.timer = 4
            }
        }
    case 2:
        if state.timer < 0 {
            state.timer = 0
            state.state = 1
        }
    }
}

Patt_Test2 :: proc(state: ^PatternState) {
    if PatternTransition(state, {0, 8}) {
        return
    }
    

    spawn := Spawner {
        type = .Spread,
        count = 4,
        angle = AngleTypeTargeted {},
        spredAngle = 20,

        children = {
            {
                type = .Stack,
                minSpeed = 2,
                maxSpeed = 3,
                acceleration = 0.3,
                count = 4,
                angle = AngleTypeParent{},
            },
        }
    }

    pos := [?]v2{{2, 6}, {-2, 6}, {3, 5}, {-3, 5}}

    state.timer -= rl.GetFrameTime()
    switch state.state {
    case 0:
        if state.timer < 0 {
            for p in pos {
                Spawn(p, spawn)
            }

            state.timer = 0.3
            state.step += 1

            if state.step == 3 {
                state.timer = 2
                state.step = 0
            }
        }
    }
}

Patt_Test3 :: proc(state: ^PatternState) {
    if PatternTransition(state, {0, 8}) {
        return
    }

    spawn := Spawner {
        type = .Circle,
        count = 25,
        angle = AngleTypeFixed {},

        children = {
            {
                type = .Stack,
                minSpeed = 2,
                maxSpeed = 2.4,

                count = 4,
                angularSpeed = state.step % 2 == 1 ? -20 : 20,
                angle = AngleTypeParent{},
            },
        }
    }


    state.timer -= rl.GetFrameTime()
    switch state.state {
    case 0:
        if state.timer < 0 {
            state.timer = 0.5

            Spawn({0, 6}, spawn)
            
            state.step += 1
        }
    }
}

MoveAndAimedSpread :: proc(state: ^PatternState) {
    moveTime :: 2.5

    boss, ok := ha.GetElementPtr(&g.entities, g.enemyHandle)
    if ok == false {
        return
    }

    start := v2{-5, 7}
    end := v2{5, 7}

    if PatternTransition(state, start) {
        return
    }

    if state.movementStep % 2 == 1 {
        start, end = end, start
    }

    state.movementTimer += rl.GetFrameTime()

    p := ease.exponential_in_out(state.movementTimer / moveTime)
    boss.position = linalg.lerp(start, end, p)

    if p >= 1 {
        state.movementTimer = 0
        state.movementStep += 1
    }

    spawn := Spawner {
        type = .Spread,
        count = 3,
        angle = AngleTypeTargeted {},
        spredAngle = 25,

        children = {
            {
                type = .Stack,
                minSpeed = 2,
                maxSpeed = 3,
                acceleration = 0.3,
                count = 4,
                angle = AngleTypeParent{},
            },
        }
    }

    shotsNumber :: 8

    state.timer -= rl.GetFrameTime()
    if state.timer < 0 {
        state.timer = moveTime / (shotsNumber - 1)
        Spawn(boss.position, spawn)
    }
}

