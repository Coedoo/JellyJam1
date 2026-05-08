package game

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import "core:slice"
import "core:unicode"
import "core:unicode/utf8"

// ─────────────────────────────────────────────────────────────────────────────
// Asset kind classification
// ─────────────────────────────────────────────────────────────────────────────

Asset_Kind :: enum {
    Unknown,
    Image,
    Gif,
    Audio,
    Shader,
    Font,
    Model,
}

asset_kind_from_ext :: proc(ext: string) -> Asset_Kind {
    lower := strings.to_lower(ext, context.temp_allocator)
    switch lower {
    case ".png", ".jpg", ".jpeg", ".bmp":
        return .Image

    case ".gif":
        return .Gif

    case ".wav", ".ogg", ".mp3", ".flac":
        return .Audio
    
    case ".glsl":
        return .Shader

    case ".ttf", ".otf":
        return .Font

    case ".obj", ".fbx":
        return .Model
    }
    return .Unknown
}

// ─────────────────────────────────────────────────────────────────────────────
// Asset metadata
// ─────────────────────────────────────────────────────────────────────────────

Asset_Info :: struct {
    rel_path:    string, // forward-slash path relative to scanned root
    file_name:   string, // full filename including extension
    size_bytes:  i64,
    kind:        Asset_Kind,
    enum_name:   string, // valid Odin identifier derived from rel_path
}

// ─────────────────────────────────────────────────────────────────────────────
// Identifier sanitisation
// ─────────────────────────────────────────────────────────────────────────────

// Converts a forward-slash relative path (without extension) into a safe
// PascalCase Odin identifier.
//
//   "textures/player-idle"  ->  "Textures_Player_Idle"
//   "04 jump"               ->  "_04_Jump"
//   "ui/button.normal"      ->  "Ui_Button_Normal"
make_enum_name :: proc(rel_path: string, allocator := context.allocator) -> string {
    no_ext := strings.trim_suffix(rel_path, filepath.ext(rel_path))

    b := strings.builder_make(allocator)
    cap_next := true

    for r, i in no_ext {
        if i == 0 && unicode.is_digit(r) {
            strings.write_rune(&b, '_')
        }

        if r == '/' || r == '\\' || r == '-' || r == ' ' || r == '.' {
            strings.write_rune(&b, '_')
            cap_next = true
        }
        else if unicode.is_letter(r) || unicode.is_digit(r) {
            if cap_next {
                strings.write_rune(&b, unicode.to_upper(r))
                cap_next = false
            }
            else {
                strings.write_rune(&b, r)
            }
        }
        else {
            strings.write_rune(&b, '_')
            cap_next = true
        }
    }

    result := strings.to_string(b)

    if len(result) == 0 {
        return "_unnamed"
    }

    return result
}

// ─────────────────────────────────────────────────────────────────────────────
// Recursive directory walk
// ─────────────────────────────────────────────────────────────────────────────

collect_assets :: proc(root: string, allocator := context.allocator) -> []Asset_Info {
    list := make([dynamic]Asset_Info, 0, 64, allocator)
    walk_dir(root, root, &list, allocator)
    return list[:]
}

walk_dir :: proc(
    root:     string,
    dir:      string,
    out:      ^[dynamic]Asset_Info,
    allocator := context.allocator,
) {
    handle, open_err := os.open(dir)
    if open_err != nil {
        fmt.eprintfln("WARNING: cannot open '%s': %v", dir, open_err)
        return
    }
    defer os.close(handle)

    infos, read_err := os.read_dir(handle, -1, context.temp_allocator)
    if read_err != nil {
        fmt.eprintfln("WARNING: cannot read '%s': %v", dir, read_err)
        return
    }

    // Deterministic order: sort by name
    slice.sort_by(infos, proc(a, b: os.File_Info) -> bool {
        return a.name < b.name
    })

    for info in infos {
        if info.type == .Directory {
            walk_dir(root, info.fullpath, out, allocator)
            continue
        }

        // Build a forward-slash relative path
        rel, rel_ok := filepath.rel(root, info.fullpath, context.temp_allocator)
        if rel_ok != {} {
            rel = info.fullpath
        }
        rel_fwd, fwd_ok := filepath.replace_path_separators(rel, '/', context.temp_allocator)

        ext := filepath.ext(info.name)

        append(out, Asset_Info{
            rel_path   = strings.clone(rel_fwd,       allocator),
            file_name  = strings.clone(info.name,     allocator),
            size_bytes = info.size,
            kind       = asset_kind_from_ext(ext),
            enum_name  = make_enum_name(rel_fwd, allocator),
        })
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Code generation
// ─────────────────────────────────────────────────────────────────────────────

group_by_kind :: proc(assets: []Asset_Info, allocator := context.allocator) -> (ret: [Asset_Kind][]Asset_Info) {
    for kind in Asset_Kind {
        subset := make([dynamic]Asset_Info, 0, 16, allocator)

        for a in assets {
            if a.kind == kind do append(&subset, a)
        }

        ret[kind] = subset[:]
    }

    return 
}

generate :: proc(assets: []Asset_Info, assetsDir: string, pkg_name: string, out_path: string) -> bool {
    b := strings.builder_make(context.temp_allocator)

    fmt.sbprintln(&b, "// AUTO-GENERATED by asset_preprocessor -- do not edit by hand.")
    fmt.sbprintfln(&b, "package %s", pkg_name)
    fmt.sbprintln(&b, "")

    // ── Metadata structs ──────────────────────────────────────────────────────
    fmt.sbprintln(&b, "// ─── Asset metadata structs ─────────────────────────────────────────────")
    fmt.sbprintln(&b, "")

    fmt.sbprintfln(&b, "Asset_Info :: struct {{")
    fmt.sbprintln(&b,  "\tpath:       cstring, // forward-slash path relative to the assets root")
    fmt.sbprintln(&b,  "\tfile_name:  string, // full filename including extension")
    fmt.sbprintln(&b,  "\tsize_bytes: i64,")
    fmt.sbprintln(&b,  "}")
    fmt.sbprintln(&b, "")
    

    groups := group_by_kind(assets, context.temp_allocator)

    // ── Enums (one per kind) ──────────────────────────────────────────────────
    fmt.sbprintln(&b, "// ─── Per-kind asset enums ───────────────────────────────────────────────")
    fmt.sbprintln(&b, "")
    for g, kind in groups {
        ks := fmt.tprint(kind)
        fmt.sbprintfln(&b, "%v_Asset :: enum {{", ks)
        for a in g {
            fmt.sbprintfln(&b, "\t%v,", a.enum_name)
        }
        fmt.sbprintln(&b, "}")
        fmt.sbprintln(&b, "")
    }

    // ── Global arrays indexed by the matching enum ────────────────────────────
    fmt.sbprintln(&b, "// ─── Global metadata arrays (indexed by the matching enum) ──────────────")
    fmt.sbprintln(&b, "")
    for g, kind in groups {
        ks := fmt.tprint(kind)
        fmt.sbprintfln(&b, "%v_Assets := [%v_Asset]Asset_Info{{", ks, ks)
        for a in g {
            fmt.sbprintfln(&b, "\t.%v = {{", a.enum_name)
            fmt.sbprintfln(&b, "\t\tpath       = \"%v/%v\",", assetsDir, a.rel_path)
            fmt.sbprintfln(&b, "\t\tfile_name  = \"%v\",", a.file_name)
            fmt.sbprintfln(&b, "\t\tsize_bytes = %v,", a.size_bytes)
            fmt.sbprintln(&b, "\t},")
        }
        fmt.sbprintln(&b, "}")
        fmt.sbprintln(&b, "")
    }

    if os.write_entire_file(out_path, strings.to_string(b)) != os.ERROR_NONE {
        fmt.eprintfln("ERROR: failed to write '%v'", out_path)
        return false
    }
    return true
}

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

print_usage :: proc() {
    fmt.println("Usage:  asset_preprocessor <assets_dir> <output_file> [package_name]")
    fmt.println("")
    fmt.println("  assets_dir    Directory to scan recursively.")
    fmt.println("  output_file   Path of the .odin file to generate.")
    fmt.println("  package_name  Odin package name to emit (default: assets).")
    fmt.println("")
    fmt.println("Example:")
    fmt.println("  asset_preprocessor ./assets src/generated_assets.odin assets")
}

main :: proc() {
    args := os.args // args[0] is the executable

    if len(args) < 3 {
        print_usage()
        os.exit(1)
    }

    assets_dir  := args[1]
    output_file := args[2]
    pkg_name    := len(args) >= 4 ? args[3] : "assets"

    // Validate the input directory
    dir_info, stat_err := os.stat(assets_dir, context.temp_allocator)
    if stat_err != nil {
        fmt.eprintfln("ERROR: cannot access '%v': %v", assets_dir, stat_err)
        os.exit(1)
    }
    if dir_info.type != .Directory {
        fmt.eprintfln("ERROR: '%v' is not a directory", assets_dir)
        os.exit(1)
    }

    fmt.printfln("Scanning '%v'...", assets_dir)

    assets := collect_assets(assets_dir)

    if len(assets) == 0 {
        fmt.println("WARNING: no files found; generating an empty asset registry.")
    } else {
        fmt.printfln("Found %v file(s):", len(assets))
        for kind in Asset_Kind {
            n := 0
            for a in assets {
                if a.kind == kind do n += 1
            }
            if n > 0 {
                fmt.printfln("  %-10v  %v", fmt.tprint(kind), n)
            }
        }
    }

    if !generate(assets, assets_dir, pkg_name, output_file) {
        os.exit(1)
    }

    fmt.printfln("Generated '%v'  (package %v).", output_file, pkg_name)
}
