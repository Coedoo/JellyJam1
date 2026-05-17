package game

import "core:fmt"
import "core:math/linalg"
import "core:math"
import "core:math/ease"
import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"
import mu "vendor:microui"
import ha "handle_array"



v2  :: [2]f32
iv2 :: [2]int

Rad :: distinct f32
Deg :: distinct f32

Stage :: enum {
    Menu,
    Game,
    Victory_Anim1,
    Victory_Anim2,
    Victory,
    Defeat,
}

MenuStage :: enum {
    Main,
    Settings,
    Credits,
}

GameMemory :: struct {
    assetStorage: AssetStorage,
    mui: ^mu.Context,

    stage: Stage,
    menuStage: MenuStage,

    camera: rl.Camera,

    entities: ha.HandleArray(Entity, EntityHandle, 5000),

    noDamageTimer: f32,

    helpTimer: f32,
    shieldHandle: EntityHandle,
    helpIdx: int,

    playerHandle: EntityHandle,
    enemyHandle: EntityHandle,

    score: int,

    pp: PostProcess,
    bloom: BloomEffect,

    currentPattern: Pattern,
    patternState: PatternState,

    run: bool,

    masterVolume: f32,
    sfxVolume: f32,
    musicVolume: f32,

    bossParticles: ParticleSystem,
    transitionParticles: ParticleSystem,
    deathParticles: ParticleSystem,

    // Audio
    bgm: rl.Music,
    shootAudio: rl.Sound,
    bossHitAudio: rl.Sound,
    bossDestroyAudio: rl.Sound,
    shieldAudio: rl.Sound,
    playerHitAudio:rl.Sound,

    pause: bool,

    // Debug
    debugDrawCollision: bool,
    debugGodMode: bool,
    debugGodBullet: bool,
}

g: ^GameMemory

PatternHP := [Pattern]int {
    .SimpleAimedAndRandomMovent = 700,
    .ClassicRosette = 1000,

    .CirclesInLine = 1500,
    .Pattern2 = 320,
    .Pattern3 = 320,

    .FourCircles = 1000,

    .MoveAndAimedSpread = 200,

    .StarTrap = 1000,
    .Rain = 2000,
    .Coedo = 3000,

    .END = 0,
}

SHIELD_TIME :: 5
SHIELD_END_TIME :: 1
SHIELD_VFX_TIME :: 2
HELP_COUNT :: 5
GOD_BULLET_DMG :: 100

Update :: proc() {

    rl.UpdateMusicStream(g.bgm)

    if g.stage == .Menu {
        Menu()
        return
    }

    if g.pause {

        style := uiCtx.buttonStyle
        style.fontSize = 50
        style.bgColor     = {0, 0, 0, 0.3}
        style.activeColor = {0, 0.05, 0.5, 0.7}
        style.hotColor    = {0, 0, 0.3, 0.7}
        PushStyle(style)

        // NextNodeStyle(style)
        NextNodePosition({70, f32(rl.GetScreenHeight()) / 2}, origin = {0, 0.5})
        if Panel("PauseMenu", aligment = Aligment{.Middle, .Left}) {
            UILabel("PAUSE")

            UISpacer(10)
            if UISliderLabel("Master volume", &g.masterVolume, 0, 1) {
                rl.SetMasterVolume(g.masterVolume)
            }
            
            if UISliderLabel("Sounds", &g.sfxVolume, 0, 1) {
                UpdateSFXVolumes(g.sfxVolume)
            }

            if UISliderLabel("Music", &g.musicVolume, 0, 1) {
                rl.SetMusicVolume(g.bgm, g.musicVolume)
            }

            UISpacer(30)
            if UIButton("Continue") {
                g.pause = false
            }
        }

        if rl.IsKeyPressed(.ESCAPE) {
            g.pause = false
        }

        PopStyle()
        return
    }


    if g.stage == .Victory {
        if Panel("vic", aligment = Aligment{.Middle, .Middle}) {
            UILabel("Victory.")

            if UIButton("Return to menu") {
                g.stage = .Menu
            }
        }
        return;
    }


    if rl.IsKeyPressed(.ESCAPE) {
        g.pause = true
    }

    frameTime := rl.GetFrameTime()
    g.noDamageTimer -= frameTime

    if rl.IsKeyPressed(.C) {
        if CreateHelp() {
            g.helpTimer = SHIELD_TIME
        }
    }

    if g.helpTimer > 0 {
        g.helpTimer -= frameTime
    }

    if g.stage != .Menu {
        UpdatePattern(g.currentPattern, &g.patternState)
    }

    b := ha.GetElement(g.entities, g.enemyHandle)
    g.bossParticles.position = b.position

    for i in 1..<len(g.entities.elements) {
        e := &g.entities.elements[i]

        e.lifeTime += frameTime

        if .SpriteAnimation in e.flags {
            sheet := GetGif(g.assetStorage, e.gif)
            frames := sheet.rows

            frame := cast(int) math.floor(e.lifeTime / 0.03)
            e.frame = frame % frames
        }

        if .BulletMovement in e.flags {
            e.startMovementTimer -= frameTime
            if e.startMovementTimer < 0 {
                e.speed += e.acceleration * frameTime
                e.rotation += e.angularSpeed * Deg(frameTime)

                rads := f32(e.rotation) * math.RAD_PER_DEG
                forward := v2{math.cos(rads), math.sin(rads)}
                e.position += e.speed * forward * frameTime
            }

            if e.owner == .Player {
                boss, ok := ha.GetElementPtr(&g.entities, g.enemyHandle)
                if ok && rl.CheckCollisionCircles(e.position, e.collisionSize.x, boss.position, boss.collisionSize.x) {
                    e.toDestroy = true

                    // negative states are transition state so we don't want to 
                    // damage boss during those
                    if g.patternState.state >= 0 {
                        boss.hp -= g.debugGodBullet ? GOD_BULLET_DMG : 1

                        rl.PlaySound(g.bossHitAudio)
                        // if rl.IsSoundPlaying(g.bossHitAudio) == false {
                        // }
                    }

                    if boss.hp <= 0 {
                        if IsLastPattern(g.currentPattern) {
                            DestroyAllBullets()
                            DestroyEntityHandle(g.enemyHandle)

                            g.stage = .Victory_Anim1
                        }
                        else {
                            ChangePatternByStep(1)
                            StartTransition(&g.patternState, true)
                        }
                    }
                }
            }

            if e.owner == .Enemy {
                player, ok := ha.GetElementPtr(&g.entities, g.playerHandle)

                if ok && rl.CheckCollisionCircles(e.position, e.collisionSize.x, player.position, player.collisionSize.x) {
                    if player.hp > 0 && g.noDamageTimer <= 0 && g.debugGodMode == false {
                        e.toDestroy = true

                        player.hp -= 1

                        SpawnParticles(&g.deathParticles, 50, player.position)
                        rl.PlaySound(g.playerHitAudio)

                        DestroyAllBullets()
                        ResetPlayer()

                        if player.hp <= 0 {
                            // Game failed
                            DestroyEntityHandle(g.playerHandle)
                            g.stage = .Defeat
                        }
                    }
                }

                shield, okShield := ha.GetElementPtr(&g.entities, g.shieldHandle)
                if okShield && rl.CheckCollisionCircles(e.position, e.collisionSize.x, shield.position, shield.collisionSize.x) {
                    e.toDestroy = true
                }
            }

        }

        if .DestroyOutsideCamera in e.flags {
            cameraBounds := GetCameraBounds()
            bounds := GetEntityBounds(e)
             // wasInsideCamera := e->isInsideCamera

            cameraBounds.top   *= 1.5
            cameraBounds.bot   *= 1.5
            cameraBounds.right *= 1.5
            cameraBounds.left  *= 1.5

            if bounds.right  < cameraBounds.left  ||
               bounds.left > cameraBounds.right   ||
               bounds.top   < cameraBounds.bot    ||
               bounds.bot   > cameraBounds.top
            {
                e.toDestroy = true
            }
        }

        if .DestroyAfterTime in e.flags {
            if e.lifeTime > e.maxLifeTime {
                e.toDestroy = true
            }
        }

        switch controller in  e.controller {
        case EntityControllerPlayer:
            UpdatePlayer(e)
        case EntityControllerShield:
            // fmt.println(e.lifeTime)
            player := ha.GetElement(g.entities, g.playerHandle)
            e.position = player.position

            tim := SHIELD_TIME - g.helpTimer
            p := (tim - (SHIELD_TIME - SHIELD_END_TIME)) / SHIELD_END_TIME
            p = min(1, 1-p)
            p = ease.circular_out(p)

            e.collisionSize = p * 2

        case EntityControllerHelp:
            player := ha.GetElement(g.entities, g.playerHandle)
            e.position = math.lerp(e.position, player.position + controller.offset, 10 * frameTime)

            delta := e.position - player.position
            if linalg.length(delta) > 0.02 {
                e.sheetCell.y = 1 + math.sign(i32(delta.x))
            }
            else {
                e.sheetCell.y = 1
            }

            e.shootTimer -= frameTime
            if rl.IsKeyDown(.Z) {
                if e.shootTimer < 0 {
                    e.shootTimer = 0.05
                    SpawnPlayerBullet(e.position, 0)
                }
            }
        }
    }

    if rl.IsKeyPressed(.R) {
        ResetGame()
    }

    // UI!!!!!!!!!!!!

    // boss hp
    boss, ok := ha.GetElementPtr(&g.entities, g.enemyHandle)
    if ok {
        UISpacer(3)
        hpNode := AddNode("bosshp", {.DrawBackground})
        hpNode.preferredSize[.X] = {.ParentPercent, f32(boss.hp) / f32(PatternHP[g.currentPattern]), 1}
        hpNode.preferredSize[.Y] = {.Fixed, 10, 1}
        hpNode.bgColor = {1, 1, 1, 1}
        hpNode.origin = {0, 0}
    }

    if g.stage == .Game {
        if Panel("text") {
            player := ha.GetElement(g.entities, g.playerHandle)
            UILabel("Lifes: ", i32(player.hp))
            UILabel("Help: ", HELP_COUNT - g.helpIdx)

            UILabel("Entity count: ", len(g.entities.elements))

        }
    }

    if Panel("cheats") {
        UICheckbox("draw collision", &g.debugDrawCollision)
        UICheckbox("god mode", &g.debugGodMode)
        UICheckbox("god bullet", &g.debugGodBullet)
    }

    if g.stage == .Defeat {
        if Panel("def") {
            UILabel("Defeat.")
            UILabel("Make your wish and...")

            if UIButton("Start again") {
                ResetGame()
            }
        }
    }

    // if Panel("patterns", Aligment{.Top, .Left}) {
    //     UILabel("Current:", g.currentPattern)

    //     if LayoutBlock("buttons", .X) {
    //         if UIButton("prev") {
    //             ChangePatternByStep(-1)
    //         }

    //         if UIButton("next") {
    //             ChangePatternByStep(1)
    //         }
    //     }
    // }

    // if Panel("Debug") {
    //     UISliderLabel("treshold", &g.bloom.treshold, 0, 1)
    //     UISliderLabel("intensity", &g.bloom.intensity, 0, 3)
    //     UISliderIntLabel("iterations", &g.bloom.levels, 0, len(g.bloom.targets))
    //     UISliderLabel("knee", &g.bloom.knee, 0, 1)
    // }
    // test_window(g.mui)

    iter := ha.MakeIterReverse(&g.entities)
    for e in ha.Iterate(&iter) {
        if e.toDestroy {
            DestroyEntity(e)
        }
    }
}

Menu :: proc() {
    style := uiCtx.textStyle
    style.fontSize = 130
    style.textColor = {0, 0.5, 1, 1}

    // NextNodeStyle(style)
    // NextNodePosition({60, 100}, origin = {0, 0.5})
    // UILabel("TITTLE TBD")

    style = uiCtx.panelStyle
    style.bgColor = {0, 0, 0, 0.7}

    NextNodeStyle(style)
    NextNodePosition({70, f32(rl.GetScreenHeight()) / 2}, origin = {0, 0.5})
    if Panel("Menu", aligment = Aligment{.Middle, .Left}) {

        style = uiCtx.buttonStyle
        style.fontSize = 50
        style.bgColor     = {0, 0, 0, 0.3}
        style.activeColor = {0, 0.05, 0.5, 0.7}
        style.hotColor    = {0, 0, 0.3, 0.7}
        PushStyle(style)

        switch g.menuStage {
        case .Main:

            if UIButton("Play") {
                // g.menuStage = .LevelSelect
                StartGame()
            }
            if UIButton("Settings") do g.menuStage = .Settings
            if UIButton("Credits")  do g.menuStage = .Credits

            UISpacer(20)
            if UIButton("Quit") {}


        case .Settings:
            if UISliderLabel("Master volume", &g.masterVolume, 0, 1) {
                rl.SetMasterVolume(g.masterVolume)
            }
            
            if UISliderLabel("Sounds", &g.sfxVolume, 0, 1) {
                UpdateSFXVolumes(g.sfxVolume)
            }

            if UISliderLabel("Music", &g.musicVolume, 0, 1) {
                rl.SetMusicVolume(g.bgm, g.musicVolume)
            }

            UISpacer(20)
            if UIButton("Back") do g.menuStage = .Main

        case .Credits:
            UISpacer(20)
            UILabel("Programing:")
            UILabel("\tCoedo")
            UILabel("\tSheepiro")
            UISpacer(5)
            UILabel("Art:")
            UILabel("\tTheSecondAce")
            UILabel("\tSheepiro##lskjdf")
            UISpacer(5)
            UILabel("Music:")
            UILabel("\tLuca Chuba")

            if UIButton("Back") do g.menuStage = .Main
        }
        PopStyle()

        if g.menuStage == .Main {
            NextNodePosition({530, 400})
            if Panel("controls", aligment = Aligment{.Middle, .Left}) {
                UILabel("Controls")
                UILabel("Arrows - move")
                UILabel("Z - Fire")
                UILabel("X - Focus")
                UILabel("C - Shield")
            }
        }
    }
}

StartGame :: proc() {
    g.stage = .Game

    g.playerHandle = CreatePlayer()
    g.enemyHandle = CreateEnemy()

    g.patternState = {}

    StartTransition(&g.patternState, false)
    g.patternState.state = -3
    g.currentPattern = nil
    // g.currentPattern = .Rain

    // g.debugGodMode = true

    boss, ok := ha.GetElementPtr(&g.entities, g.enemyHandle)
    boss.hp = PatternHP[g.currentPattern]
    g.helpIdx =  0

    rl.PlayMusicStream(g.bgm)

    ResetPlayer()
}


ChangePatternByStep :: proc(step: int) {
    i := (cast(int) g.currentPattern) + step
    i = i %% len(Pattern)

    g.currentPattern = cast(Pattern) i

    boss, ok := ha.GetElementPtr(&g.entities, g.enemyHandle)
    boss.hp = PatternHP[g.currentPattern]

    g.patternState = {}
    DestroyAllBullets()
}

IsLastPattern :: proc(patt: Pattern) -> bool {
    next := Pattern(cast(int) patt + 1)
    return next == .END
}

Draw :: proc() {
    rl.BeginDrawing()

    PPBeginDrawing(g.pp)
    rl.ClearBackground({0, 5, 10, 255})

    rl.BeginMode3D(g.camera)

        rlgl.DisableBackfaceCulling()
        rlgl.DisableDepthTest()

        DrawSpriteSize(GetTexture(g.assetStorage, .Background), {0, 3}, rl.WHITE, g.camera.fovy + 1)

        // DrawGrid()

        if g.stage != .Menu {
            if ha.IsHandleValid(g.entities, g.enemyHandle) {
                UpdateParticleSystem(&g.bossParticles, rl.GetFrameTime())
            }

            DrawParticleSystem(&g.bossParticles)
            UpdateAndDrawParticleSystem(&g.transitionParticles)
            UpdateAndDrawParticleSystem(&g.deathParticles)
        }
        
        iter := ha.MakeIter(&g.entities)
        for e in ha.Iterate(&iter) {
            DrawEntity(e)
        }

        iter = ha.MakeIter(&g.entities)
        for e in ha.Iterate(&iter) {
            if g.debugDrawCollision {
                if .Collision in e.flags {
                    rl.DrawCircleLinesV(e.position, e.collisionSize.x, rl.BLUE)
                }
            }
        }

    rl.EndMode3D()
    PPEndDrawing(g.pp)

    // PP Goes here
    BloomUse(&g.pp, g.bloom)

    PPFinalize(g.pp)

    if g.helpTimer > 0 {
        rl.BeginMode3D(g.camera)

        p := math.remap(SHIELD_TIME - g.helpTimer, 0, SHIELD_TIME, 0, SHIELD_VFX_TIME)
        alpha := u8(clamp(math.sin(p * math.PI) * 1.5, 0, 1) * 190)
        color := rl.Color{255, 255, 255, alpha}

        currentHelpSprite := HelpSprites[cast(HelpType) (g.helpIdx - 1)]
        move := ease.sine_in_out(p) * 3
        size :=  g.camera.fovy + ease.exponential_in(p) * 2

        DrawSpriteSize(
            GetTexture(g.assetStorage, currentHelpSprite.assetName),
            {3, move},
            color,
            size,
            0,
            currentHelpSprite.origin)

        rl.EndMode3D()
    }

    muiRender(g.mui)
    DrawUI()

    rl.EndDrawing()
}

@(export)
game_update :: proc() {
    muiProcessInput(g.mui)

    uiCtx.input.mousePos = { int(rl.GetMouseX()), int(rl.GetMouseY()) }
    uiCtx.input.mouseDelta = rl.GetMouseDelta()
    uiCtx.input.leftMouseDown = rl.IsMouseButtonDown(.LEFT)
    uiCtx.input.leftMousePressed = rl.IsMouseButtonPressed(.LEFT)
    uiCtx.input.leftMouseReleased = rl.IsMouseButtonReleased(.LEFT)

    UIBegin(int(rl.GetScreenWidth()), int(rl.GetScreenHeight()))
    mu.begin(g.mui)

    Update()

    mu.end(g.mui)
    UIEnd()

    Draw()

    // Everything on tracking allocator is valid until end-of-frame.
    free_all(context.temp_allocator)
}

ResetGame :: proc() {
    ha.Clear(&g.entities)
    ClearParticles(&g.bossParticles)
    StartGame()
}

@(export)
game_init_window :: proc() 
{
    rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
    rl.InitWindow(750, 900, "hiel")
    rl.SetWindowPosition(800, 200)
    rl.SetTargetFPS(500)
    rl.SetExitKey(nil)
}


UpdateSFXVolumes :: proc(volume: f32) {
    rl.SetSoundVolume(g.shootAudio,       volume * 0.4)
    rl.SetSoundVolume(g.shieldAudio,      volume * 0.5)
    rl.SetSoundVolume(g.playerHitAudio,   volume * 0.9)
    rl.SetSoundVolume(g.bossHitAudio,     volume * 1)
    rl.SetSoundVolume(g.bossDestroyAudio, volume * 1)
}

@(export)
game_init :: proc() {
    g = new(GameMemory)
    g.run = true

    g.pp = PPInit(rl.GetScreenWidth(), rl.GetScreenHeight())
    g.bloom = BloomInit()

    rl.InitAudioDevice()

    InitAssetsMemory(&g.assetStorage)
    LoadAssets(&g.assetStorage)
    g.mui = muiInit()

    g.camera = {
        up = {0, 1, 0},
        position = {0, 4, 1},
        target = {0, 4, 0},
        fovy = 15,
        projection = .ORTHOGRAPHIC
    }

    /////
    ha.Init(&g.entities)

    ////


    InitUI(&uiCtx, GetFont(g.assetStorage, .Goldman_Regular))
    // uiCtx.textStyle.font = GetFont(g.assetStorage, .Goldman_Regular)


    game_hot_reloaded(g)

    // g.debugDrawCollision = true
    // g.debugGodMode = true

    ////////////////

    g.bgm = rl.LoadMusicStream(Audio_Assets[.Bgm].path)
    g.bgm.looping = true

    g.shootAudio = rl.LoadSound(Audio_Assets[.Fire].path)
    g.shieldAudio = rl.LoadSound(Audio_Assets[.Shield].path)
    g.playerHitAudio = rl.LoadSound(Audio_Assets[.PlayerHit].path)
    g.bossHitAudio = rl.LoadSound(Audio_Assets[.BossHit].path)
    g.bossDestroyAudio = rl.LoadSound(Audio_Assets[.BossDestroy].path)

    UpdateSFXVolumes(1)

    ////////////////

    g.bossParticles = DefaultParticleSystem
    g.bossParticles.texture = GetTexture(g.assetStorage, .Scorch_01)
    g.bossParticles.emitRate = 40
    g.bossParticles.startSize = RandomFloat{2, 4}
    g.bossParticles.startRotation = RandomFloat{0, 360}
    g.bossParticles.startRotationSpeed = RandomFloat{-20, 20}
    g.bossParticles.lifetime = RandomFloat{0.6, 1}
    g.bossParticles.color = ColorOverLifetime{{1, 1, 1, 1}, {1, 1, 1, 0}, .Exponential_Out}

    InitParticleSystem(&g.bossParticles)

    g.transitionParticles = DefaultParticleSystem
    g.transitionParticles.texture = GetTexture(g.assetStorage, .Maple)
    g.transitionParticles.emitRate = 0
    g.transitionParticles.startSpeed = RandomFloat{1, 8}
    g.transitionParticles.startSize = RandomFloat{.5, 2}
    g.transitionParticles.startRotation = RandomFloat{0, 360}
    g.transitionParticles.startRotationSpeed = RandomFloat{-20, 20}
    g.transitionParticles.lifetime = RandomFloat{1, 1.5}
    g.transitionParticles.color = ColorOverLifetime{{1, 1, 1, 1}, {1, 1, 1, 0}, .Exponential_Out}

    InitParticleSystem(&g.transitionParticles)

    g.deathParticles = DefaultParticleSystem
    g.deathParticles.texture = GetTexture(g.assetStorage, .Star_08)
    g.deathParticles.emitRate = 0
    g.deathParticles.startSpeed = RandomFloat{1, 8}
    g.deathParticles.startSize = RandomFloat{.5, 2}
    g.deathParticles.startRotation = RandomFloat{0, 360}
    g.deathParticles.startRotationSpeed = RandomFloat{-20, 20}
    g.deathParticles.lifetime = RandomFloat{1, 1.5}
    g.deathParticles.color = ColorOverLifetime{{1, 1, 1, 1}, {1, 1, 1, 0}, .Exponential_Out}

    InitParticleSystem(&g.transitionParticles)


    rl.SetTextureFilter(GetTexture(g.assetStorage, .Background), .POINT)


    for &s in HelpSprites {
        rl.SetTextureFilter(GetTexture(g.assetStorage, s.assetName), .BILINEAR)
    }

    g.sfxVolume = 1
    g.musicVolume = 1
    g.masterVolume = 1

    // SpawnParticles(&g.transitionParticles, 30)

    // StartGame()
}

@(export)
game_should_run :: proc() -> bool {
    when ODIN_OS != .JS {
        // Never run this proc in browser. It contains a 16 ms sleep on web!
        if rl.WindowShouldClose() {
            return false
        }
    }

    return g.run
}

@(export)
game_shutdown :: proc() {
    DestroyAssetsMemory(&g.assetStorage)
    free(g.mui)
    DestroyParticlesystem(&g.bossParticles)
    free(g)
    delete(uiCtx.transientArena.data)
}

@(export)
game_shutdown_window :: proc() {
    rl.CloseWindow()
}

@(export)
game_memory :: proc() -> rawptr {
    return g
}

@(export)
game_memory_size :: proc() -> int {
    return size_of(GameMemory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
    g = (^GameMemory)(mem)

    // Here you can also set your own global variables. A good idea is to make
    // your global variables into pointers that point to something inside `g`.
}

@(export)
game_force_reload :: proc() -> bool {
    return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
    return rl.IsKeyPressed(.F6)
}

// In a web build, this is called when browser changes size. Remove the
// `rl.SetWindowSize` call if you don't want a resizable game.
game_parent_window_size_changed :: proc(w, h: int) {
    rl.SetWindowSize(i32(w), i32(h))
}
