package game

import "core:mem"
import "core:fmt"
import "core:strings"

import rl "vendor:raylib"

ASSETS_MEMORY :: 4 * mem.Megabyte

AssetStorage :: struct {
    arena: mem.Arena,
    allocator: mem.Allocator,

    textures: []TextureEntry,
    fonts: []FontEntry,
    // models: []ModelEntry,
    shaders: []ShaderEntry,
    gifs: []GifEntry,
    sounds: []SoundEntry,

}

AssetEntry :: struct($T, $S: typeid) {
    name: T,
    asset: S,
}

TextureEntry :: distinct AssetEntry(Image_Asset, rl.Texture2D)
SoundEntry   :: distinct AssetEntry(Audio_Asset, rl.Sound)
FontEntry    :: distinct AssetEntry(Font_Asset, rl.Font)
// ModelEntry   :: distinct AssetEntry(Model_Asset, rl.Model)
ShaderEntry   :: distinct AssetEntry(Shader_Asset, rl.Shader)

GifEntry :: struct {
    name: Gif_Asset,
    asset: SpriteSheet,
}

InitAssetsMemory :: proc(storage: ^AssetStorage) {
    memory := make([]byte, ASSETS_MEMORY)

    mem.arena_init(&storage.arena, memory)
    storage.allocator = mem.arena_allocator(&storage.arena)
}

DestroyAssetsMemory :: proc(storage: ^AssetStorage) {
    free_all(storage.allocator)
    delete(storage.arena.data)
}

LoadAssets :: proc(storage: ^AssetStorage) {
    // LOAD TEXTURES
    textures := make([dynamic]TextureEntry, 0, len(Image_Asset), storage.allocator)
    for &info, name in Image_Assets {
        entry := TextureEntry {
            name = name,
            asset = rl.LoadTexture(info.path),
        }

        append(&textures, entry)
    }

    // LOAD GIFS
    gifs := make([dynamic]GifEntry, 0, len(Gif_Asset), storage.allocator)
    for &info, name in Gif_Assets {
        frames: i32
        image := rl.LoadImageAnim(info.path, &frames)

        entry := GifEntry {
            name = name
        }

        entry.asset.frameSize.x = image.width
        entry.asset.frameSize.y = image.height

        entry.asset.columns = 1
        entry.asset.rows = int(frames)

        image.height *= frames
        entry.asset.texture = rl.LoadTextureFromImage(image)

        rl.UnloadImage(image)

        append(&gifs, entry)
    }

    // LOAD FONTS
    fonts := make([dynamic]FontEntry, 0, len(Font_Asset), storage.allocator)
    for &info, name in Font_Assets {
        entry := FontEntry {
            name = name,
            asset = rl.LoadFontEx(info.path, 80, nil, 0),
        }

        append(&fonts, entry)
    }

    // LOAD SHADERS
    b := strings.builder_make(context.allocator)
    defer strings.builder_destroy(&b)

    shaders := make([dynamic]ShaderEntry, 0, len(Shader_Asset), storage.allocator)
    for &info, name in Shader_Assets {
        // Prepare file
        source, success := read_entire_file(cast(string) info.path, context.temp_allocator)
        if success == false {
            fmt.eprintln("Error while loading asset file:", info.path)
        }

        // Build vertex shader source
        strings.builder_reset(&b)
        when ODIN_OS == .JS {
            strings.write_string(&b, "#version 300 es\n")
            strings.write_string(&b, "precision mediump float;\n\n")
        }
        else {
            strings.write_string(&b, "#version 430\n\n")
        }

        strings.write_string(&b, "#define VERTEX\n\n")
        strings.write_bytes(&b, source)

        vertexSource := strings.clone_to_cstring(strings.to_string(b), context.temp_allocator)

        // Build fragment shader source
        strings.builder_reset(&b)
        when ODIN_OS == .JS {
            strings.write_string(&b, "#version 300 es\n")
            strings.write_string(&b, "precision mediump float;\n\n")
        }
        else {
            strings.write_string(&b, "#version 430\n\n")
        }

        strings.write_string(&b, "#define FRAGMENT\n")
        strings.write_bytes(&b, source)

        // Compile
        fragmentSource := strings.clone_to_cstring(strings.to_string(b), context.temp_allocator)
        shader := rl.LoadShaderFromMemory(vertexSource, fragmentSource)

        // fmt.print(vertexSource)
        // fmt.print(fragmentSource)

        entry := ShaderEntry {
            name = name,
            asset = shader,
        }

        append(&shaders, entry)
    }

    // load sounds and music
    sounds := make([dynamic]SoundEntry, 0, len(Audio_Assets), storage.allocator)
    for &info, name in Audio_Assets {
        entry := SoundEntry {
            name = name,
            asset = rl.LoadSound(info.path),
        }

        append(&sounds, entry)
    }


    storage.textures = textures[:]
    storage.fonts    = fonts[:]
    storage.shaders  = shaders[:]
    storage.gifs     = gifs[:]
    storage.sounds   = sounds[:]
}

GetTexture :: proc(storage: AssetStorage, name: Image_Asset) -> rl.Texture {
    for &t in storage.textures {
        if t.name == name {
            return t.asset
        }
    }

    return {}
}

GetFont :: proc(storage: AssetStorage, name: Font_Asset) -> rl.Font {
    for &t in storage.fonts {
        if t.name == name {
            return t.asset
        }
    }

    return {}
}


GetShader :: proc(storage: AssetStorage, name: Shader_Asset) -> rl.Shader {
    for &t in storage.shaders {
        if t.name == name {
            return t.asset
        }
    }

    return {}
}

GetGif :: proc(storage: AssetStorage, name: Gif_Asset) -> SpriteSheet {
    for &t in storage.gifs {
        if t.name == name {
            return t.asset
        }
    }

    return {}
}


GetSound :: proc(storage: AssetStorage, name: Audio_Asset) -> rl.Sound {
    for &t in storage.sounds {
        if t.name == name {
            return t.asset
        }
    }

    return {}
}
