package game

import rl "vendor:raylib"
import rlgl "vendor:raylib/rlgl"

PostProcess :: struct {
    width, height: i32,

    dest: rl.RenderTexture2D,
    src: rl.RenderTexture2D,
}

PPInit :: proc(width, height: i32) -> PostProcess {
    pp := PostProcess{}
    pp.width = width
    pp.height = height

    pp.dest = rl.LoadRenderTexture(width, height)
    pp.src = rl.LoadRenderTexture(width, height)

    return pp
}


PPBeginDrawing :: proc(pp: PostProcess) {
    rl.BeginTextureMode(pp.dest)
}

PPEndDrawing :: proc(pp: PostProcess) {
    rl.EndTextureMode()
}

PPSwap :: proc(pp: ^PostProcess) {
    pp.dest, pp.src = pp.src, pp.dest
}


PPFinalize :: proc(pp: PostProcess) {
    rl.ClearBackground(rl.BLANK)

    rl.DrawTextureRec(
        pp.dest.texture,
        rl.Rectangle{0, 0, f32(pp.dest.texture.width), -f32(pp.dest.texture.height)},
        rl.Vector2{0, 0},
        rl.WHITE,
    )
}

Blit :: proc {
    BlitNoShader,
    BlitShader
}

BlitNoShader :: proc(src, dest: rl.RenderTexture2D, clear := true) {
    rl.BeginTextureMode(dest)
    if clear {
        rl.ClearBackground(rl.BLANK)
    }

    rl.DrawTexturePro(
        src.texture, 
        {0, 0, f32(src.texture.width), -f32(src.texture.height)},
        {0, 0, f32(dest.texture.width), f32(dest.texture.height)},
         0, 0, rl.WHITE
    )

    rl.EndTextureMode()
}

BlitShader :: proc(src, dest: rl.RenderTexture2D, shader: rl.Shader, clear := true) {
    rl.BeginTextureMode(dest)

    if clear {
        rl.ClearBackground(rl.BLANK)
    }

    rl.BeginShaderMode(shader)
    rl.DrawTexturePro(
        src.texture, 
        {0, 0, f32(src.texture.width), -f32(src.texture.height)},
        {0, 0, f32(dest.texture.width), f32(dest.texture.height)},
         0, 0, rl.WHITE
    )
    rl.EndShaderMode()
    rl.EndTextureMode()
}


/////////////
// Bloom

BloomTresholdShader :: `
#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform vec4 treshold; // [t, -t+tk, 2tk, 1/(4tk + 0.000001)] - t = treshold, k = knee

void main() {
    vec4 color = texture(texture0, fragTexCoord);
    float brightness = dot(color.rgb, vec3(0.2126, 0.7152, 0.0722));

    // float soft = brightness + treshold.y;
    // soft = clamp(soft, 0.0, treshold.z);
    // soft = soft * soft * treshold.w;

    // float contribution = max(soft, brightness - treshold.x) / max(brightness, 0.000001);
    
    float contribution = max(0, brightness - treshold.x) / max(brightness, 0.000001);

    finalColor = color * contribution;
}`

BloomBlurShader :: `
#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform float delta;

vec3 SampleBox (vec2 uv) {
    vec2 texelSize = 1.0 / textureSize(texture0, 0);
    vec4 o = texelSize.xyxy * vec2(-delta, delta).xxyy;
    vec3 s =
        texture(texture0, uv + o.xy).rgb + texture(texture0, uv + o.zy).rgb +
        texture(texture0, uv + o.xw).rgb + texture(texture0, uv + o.zw).rgb;
    return s * 0.25f;
}

void main() {
    finalColor = vec4(SampleBox(fragTexCoord), 1);
}`

BloomBlitShader :: `
#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform sampler2D bloom;
uniform float bloom_intensity;

vec3 Tonemap_ACES(vec3 x)
{
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return (x * (a * x + b)) / (x * (c * x + d) + e);
}

void main() {
    vec4 sceneColor = texture(texture0, fragTexCoord);
    vec4 bloomColor = texture(bloom, fragTexCoord);

    // finalColor = vec4(Tonemap_ACES(sceneColor.rgb + bloomColor.rgb * bloom_intensity), 1);
    finalColor = sceneColor + vec4(Tonemap_ACES(bloomColor.rgb * bloom_intensity), 1);
    // finalColor = sceneColor + bloomColor * bloom_intensity;
}`

BloomBlitShaderHACK :: `
#version 330

in vec2 fragTexCoord;
out vec4 finalColor;

uniform sampler2D texture0;
uniform float bloom_intensity;

void main() {
    vec4 bloomColor = texture(texture0, fragTexCoord);
    finalColor = bloomColor * bloom_intensity;
}`



BloomEffect :: struct {
    tresholdShader: rl.Shader,
    blurShader: rl.Shader,
    blitShader: rl.Shader,

    targets: [dynamic; 8]rl.RenderTexture2D,

    levels: int,
    treshold: f32,
    intensity: f32,
    knee: f32,
}

BloomInit :: proc() -> BloomEffect {
    b := BloomEffect{}

    b.levels = 5
    b.treshold = 0.6
    b.intensity = 1.0
    b.knee = 0.5

    b.tresholdShader = rl.LoadShaderFromMemory(nil, BloomTresholdShader)
    b.blurShader = rl.LoadShaderFromMemory(nil, BloomBlurShader)
    b.blitShader = rl.LoadShaderFromMemory(nil, BloomBlitShader)
    // b.blitShader = rl.LoadShaderFromMemory(nil, BloomBlitShaderHACK)

    w := rl.GetScreenWidth()
    h := rl.GetScreenHeight()


    for i in 0 ..< cap(b.targets) {
        if w <= 2 || h <= 2 {
            break
        }

        tex := rl.LoadRenderTexture(w, h)
        rl.SetTextureFilter(tex.texture, .BILINEAR)
        rl.SetTextureWrap(tex.texture, .CLAMP)

        append(&b.targets, tex)

        w /= 2
        h /= 2
    }

    return b
}

BloomUse :: proc(pp: ^PostProcess, bloom: BloomEffect) {
    PPSwap(pp)

    treshold: [4]f32
    treshold.x = bloom.treshold
    treshold.y = -bloom.treshold + bloom.treshold * bloom.knee
    treshold.z = 2 * bloom.treshold * bloom.knee
    treshold.w = 1 / (4 * bloom.treshold * bloom.knee + 0.000001)

    rl.SetShaderValue(
        bloom.tresholdShader,
        rl.GetShaderLocation(bloom.tresholdShader, "treshold"),
        &treshold,
        .VEC4
    )

    Blit(pp.src, pp.dest, bloom.tresholdShader)

    delta: f32 = 1
    rl.SetShaderValue(
        bloom.blurShader,
        rl.GetShaderLocation(bloom.blurShader, "delta"),
        &delta,
        .FLOAT
    )

    Blit(pp.dest, bloom.targets[0], bloom.blurShader)

    // Downsample step
    i := 0
    for ; i < bloom.levels - 1; i += 1 {
        Blit(bloom.targets[i], bloom.targets[i + 1], bloom.blurShader)
    }

    delta = 0.5
    rl.SetShaderValue(
        bloom.blurShader,
        rl.GetShaderLocation(bloom.blurShader, "delta"),
        &delta,
        .FLOAT
    )

    // Upsample with additive blending
    rl.BeginBlendMode(.ADDITIVE)
    for ; i > 0; i -= 1 {
        Blit(bloom.targets[i], bloom.targets[i - 1], bloom.blurShader, clear = false)
    }
    rl.EndBlendMode()

    // Blit the final bloom texture with the scene texture
    // Cant use the commoon Blit function because setting
    // textures in raylib before using Begin* functions
    // breaks Raylib's batching
    rl.BeginShaderMode(bloom.blitShader)
    rl.BeginTextureMode(pp.dest)

    intensity := bloom.intensity
    rl.SetShaderValue(
        bloom.blitShader,
        rl.GetShaderLocation(bloom.blitShader, "bloom_intensity"),
        &intensity,
        .FLOAT
    )

    rl.SetShaderValueTexture(
        bloom.blitShader,
        rl.GetShaderLocation(bloom.blitShader, "bloom"),
        bloom.targets[0].texture
    )

    rl.DrawTexturePro(
        pp.src.texture,
        {0, 0, f32(pp.src.texture.width), -f32(pp.src.texture.height)},
        {0, 0, f32(pp.dest.texture.width), f32(pp.dest.texture.height)},
         0, 0, rl.WHITE
    )

    rl.EndTextureMode()
    rl.EndShaderMode()
}