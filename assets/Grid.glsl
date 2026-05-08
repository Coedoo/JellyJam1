#if defined(VERTEX)

in vec3 vertexPosition;

uniform mat4 invVPMat;
uniform vec2 resolution;

out vec4 worldPos;

void main() {
    gl_Position = vec4(vertexPosition.x, vertexPosition.y, vertexPosition.z, 1);
    // vec2 vertPos = vertexPosition.xy * resolution;
    worldPos = invVPMat * vec4(vertexPosition.x, vertexPosition.y, vertexPosition.z, 1.0);

    // worldPos.xyz /= worldPos.w;

    // worldPos.xy /= resolution;
}

#elif defined(FRAGMENT)

in vec4 worldPos;

out vec4 FragColor;

void main() {
    const float lineSize = 1.0;

    vec2 deriv = fwidth(worldPos.xy);
    vec2 grid = abs(fract(worldPos.xy - 0.5) - 0.5) / deriv;
    float l = min(grid.x, grid.y);

    // float4 col = float4(0.1, 0.1, 0.1, step(l, lineSize));
    vec4 col = vec4(0.1, 0.1, 0.1, 1.0 - min(l, 1.0));

    deriv.x = min(deriv.x, 1.0);
    deriv.y = min(deriv.y, 1.0);

    if(worldPos.x > -deriv.x && worldPos.x < deriv.x) {
        col.x = 1.0;
    }
    if(worldPos.y > -deriv.y && worldPos.y < deriv.y) {
        col.y = 1.0;
    }

    FragColor = col;
}

#endif