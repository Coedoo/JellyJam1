package game

import rl "vendor:raylib"
import ha "handle_array"

import "core:fmt"

import "core:math"
import "core:math/linalg"

import "core:math/ease"
import "core:math/rand"

Pattern :: enum {
    SimpleAimedAndRandomMovent,
    ClassicRosette,

    CirclesInLine,

    Pattern2,
    Pattern3,

    FourCircles,

    MoveAndAimedSpread,

    StarTrap,
}

SubpatternState :: struct {
    timer: f32,
    step: int
}

PatternState :: struct {
    lifeTime: f32,

    state: int,

    timer: f32,
    step: int,

    movementStep: int,
    movementTimer: f32,

    subpatterns: [16]SubpatternState,

    previousPos: v2,
    targetPos: v2,
}

UpdatePattern :: proc(type: Pattern, state: ^PatternState) {
    state.lifeTime += rl.GetFrameTime()
    switch type {
    case .ClassicRosette: ClassicRosette(state)
    case .SimpleAimedAndRandomMovent: SimpleAimedAndRandomMovent(state)

    case .CirclesInLine: CirclesInLine(state)
    case .Pattern2: Patt_Test2(state)
    case .Pattern3: Patt_Test3(state)
    case .FourCircles: FourCircles(state)
    case .MoveAndAimedSpread: MoveAndAimedSpread(state)
    case .StarTrap: StarTrap(state)
    }
}

StartTransition :: proc(state: ^PatternState, particles: bool) {
    state.state = -2
    state.timer = 0
    state.lifeTime = 0

    state.subpatterns = {}

    boss := ha.GetElement(g.entities, g.enemyHandle)
    state.previousPos = boss.position

    if particles {
        SpawnParticles(&g.transitionParticles, 30, boss.position)
        rl.PlaySound(g.bossDestroyAudio)
    }
}

PatternTransition :: proc(state: ^PatternState, pos: v2) -> bool {
    switch state.state {

    case -3:
        state.timer += rl.GetFrameTime()
        p := state.timer / 3

        g.bossParticles.emitRate = ease.quadratic_in(p) * 30
        fmt.println(g.bossParticles.emitRate)
        if state.timer > 3 {
            g.bossParticles.emitRate = 40
            state.state = -1
            state.timer = 0

            boss := ha.GetElement(g.entities, g.enemyHandle)
            state.previousPos = boss.position
        }

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

CirclesInLine :: proc(state: ^PatternState) {
    start :: v2{0, 6}

    if PatternTransition(state, start) {
        return
    }

    spawn := Spawner {
        type = .Circle,
        count = 18,
        angle = AngleTypeFixed {},
        radius = 0,

        children = {
            {
                type = .Bullet,
                sprite = .Circle_05,
                speed = 2,
                acceleration = 1,
                angle = AngleTypeParent{},

                size = 0.6,
            },
        }
    }

    @static angle: f32

    state.timer -= rl.GetFrameTime()
    switch state.state {
    case 0:
        state.timer = 1
        state.state = 1

    case 1:
        if state.timer < 0 {
            dir := v2{math.cos(angle), math.sin(angle)}

            Spawn(start + dir * f32(state.step) *  0.8, spawn)
            Spawn(start + dir * f32(state.step) * -0.8, spawn)

            state.step += 1
            state.timer = .4

            if state.step > 8 {
                state.step = 0
                state.state = 2
                state.timer = 3.5

                angle = rand.float32_range(-30, 30) * math.RAD_PER_DEG
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
    if PatternTransition(state, {0, 5.5}) {
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
                sprite = .Circle_05,
                minSpeed = 2,
                maxSpeed = 3,
                acceleration = 0.3,
                count = 4,
                angle = AngleTypeParent{},
                size = 0.4,
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
    if PatternTransition(state, {0, 6}) {
        return
    }

    spawn := Spawner {
        type = .Circle,
        count = 25,
        angle = AngleTypeFixed {},

        children = {
            {
                type = .Stack,
                sprite = .Circle_05,
                minSpeed = 2,
                maxSpeed = 2.4,

                count = 4,
                angularSpeed = state.step % 2 == 1 ? -20 : 20,
                angle = AngleTypeParent{},
                size = 0.4,
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

SimpleAimedAndRandomMovent :: proc(state: ^PatternState) {
    start :: v2 {0, 8}

    if PatternTransition(state, start) {
        return
    }

    boss, ok := ha.GetElementPtr(&g.entities, g.enemyHandle)
    if ok == false {
        return
    }

    moveTime :: 3

    boxMin :: v2{-4, 6}
    boxMax :: v2{4, 9}


    stacksSpawner := Spawner {
        type = .Stack,
        minSpeed = 4,
        maxSpeed = 5.5,
        sprite = .Circle_05,
        // acceleration = 0.3,
        count = 4,
        angle = AngleTypeTargeted{},
        size = 0.7,
    }

    circleSpawn := Spawner {
        type = .Circle,
        count = 28,
        // angle = AngleTypeFixed { Deg(spawnAngle) },
        angle = AngleTypeTargeted{},

        children = {
            {
                type = .Bullet,
                // minSpeed = 2,
                // maxSpeed = 2.4,

                sprite = .Circle_05,
                speed = 4,

                // count = 4,
                // angularSpeed = Deg(angularSpeed),
                angle = AngleTypeParent{},
                size = 0.8,
            },
        }
    }

    if state.movementTimer <= 0 {
        state.previousPos = boss.position

        x := rand.float32_range(boxMin.x, boxMax.x)
        y := rand.float32_range(boxMin.y, boxMax.y)
        state.targetPos = {x, y}

        state.movementTimer = moveTime

        Spawn(boss.position, circleSpawn)
    }

    state.movementTimer -= rl.GetFrameTime()
    p := ease.quadratic_out(1 - state.movementTimer / moveTime)
    boss.position = linalg.lerp(state.previousPos, state.targetPos, p)

    shotsCount :: 2
    interval :: f32(moveTime) / (shotsCount + 1)

    state.timer += rl.GetFrameTime()
    if state.timer >= interval {
        state.timer = 0
        state.step += 1

        if state.step != shotsCount + 1 {
            Spawn(boss.position, stacksSpawner)
        }
        else {
            state.step = 0
        }
    }
}

ClassicRosette :: proc(state: ^PatternState) {
    start :: v2 {0, 8}

    if PatternTransition(state, start) {
        return
    }

    angularSpeed : f32 = state.step % 2 == 1 ? -20 : 20

    spawnAngle := state.lifeTime * angularSpeed

    circleSpawn := Spawner {
        type = .Circle,
        count = 28,
        angle = AngleTypeFixed { Deg(spawnAngle) },
        // angle = AngleTypeFixed { Deg(0) },

        children = {
            {
                type = .Bullet,
                // minSpeed = 2,
                // maxSpeed = 2.4,

                sprite = .Circle_05,
                speed = 3,

                // count = 4,
                angularSpeed = Deg(angularSpeed),
                angle = AngleTypeParent{},
                size = 0.7,
            },
        }
    }

    stacksSpawner := Spawner {
        type = .Spread,
        count = 3,
        angle = AngleTypeTargeted {},
        spredAngle = 25,

        children = {
            {
                type = .Stack,
                sprite = .Circle_03,
                minSpeed = 2,
                maxSpeed = 3,
                // acceleration = 0.3,
                count = 3,
                angle = AngleTypeParent{},
                size = 0.5,
            },
        }
    }

    state.timer -= rl.GetFrameTime()
    state.subpatterns[0].timer += rl.GetFrameTime()

    switch state.state {
    case 0:
        if state.timer < 0 {
            state.timer = 0.4

            Spawn(start, circleSpawn)

            state.step += 1
        }

        if state.subpatterns[0].timer > 4 {
            state.subpatterns[0].timer = 0
            // Spawn(start, stacksSpawner)
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
                sprite = .Circle_05,
                minSpeed = 2,
                maxSpeed = 3,
                acceleration = 0.3,
                count = 4,
                angle = AngleTypeParent{},
                size = 0.4,
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

// It's pretty easy, the pattern is very predictable
FourCircles :: proc(state: ^PatternState) {
    start :: v2{0, 7}

    if PatternTransition(state, start) {
        return
    }

    spawnPoints := 
    [][]v2{ 
        []v2{{-5.5, 4}, {5.5, 4}},
        []v2{{-4, 6}, {4, 6}},
    }


    circleSpawn := Spawner {
        type = .Circle,
        count = 28,
        // angle = AngleTypeFixed { Deg(state.step * 10) },

        children = {
            {
                type = .Bullet,

                sprite = .Circle_05,
                speed = 2,

                angle = AngleTypeParent{},
                size = 0.7,
            },
        }
    }

    state.timer -= rl.GetFrameTime()
    switch state.state {
    case 0:
        if state.timer < 0 {
            state.timer = 0.6

            rowIdx := state.step % len(spawnPoints)

            for p, i in spawnPoints[rowIdx] {
                dir := i % 2 == 0 ? -1 : 1
                angleStep := state.step % 2 == 0 ? 10 : 18
                circleSpawn.angle = AngleTypeFixed{Deg(state.step * angleStep * dir)}
                Spawn(p, circleSpawn)
            }

            state.step += 1
        }
    }
}

StarTrap :: proc(state: ^PatternState) {
    if PatternTransition(state, {0, 6}) {
        return
    }
 
    starStack := Spawner {
        type = .Circle,
        count = 5,
        radius = 7.5,
        angle = AngleTypeFixed { Deg(state.step * 15) },

        children = {
            {
                type = .Circle,
                count = 5,
                angle = AngleTypeParent{},
                children = {
                    {
                        type = .Stack,
                        sprite = .Circle_05,
                        minSpeed = 1,
                        maxSpeed = 4,
                        // acceleration = 0.3,
                        count = 18,
                        angle = AngleTypeParent{},
                        size = 0.4,
                    },
                }
            },
        }
    }

    targeted := Spawner {
        type = .Circle,
        count = 5,
        radius = 0,
        angle = AngleTypeFixed { Deg(state.subpatterns[0].step * 20) },
        children = {
            {
                type = .Stack,
                sprite = .Circle_03,
                minSpeed = 2,
                maxSpeed = 7,
                // acceleration = 0.3,
                // angularSpeed = 10,
                count = 5,
                angle = AngleTypeParent{},
                size = 0.4,
            },
        }
    }

    state.timer -= rl.GetFrameTime()
    state.subpatterns[0].timer += rl.GetFrameTime()

    switch state.state {
    case 0:
        if state.timer < 0 {
            state.timer = 0.7
            Spawn({0, 5.5}, starStack)

            state.step += 1
        }

        if state.subpatterns[0].timer >= 0.8 {
            state.subpatterns[0].timer = 0
            state.subpatterns[0].step += 1

            Spawn({0, 5.5}, targeted)
        }
    }
}
