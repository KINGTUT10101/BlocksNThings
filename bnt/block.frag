// Re-declare g3d's varying variables so the fragment shader knows about them
varying vec4 vertexColor;    // .rgb = unused, .g = face index, .a = baked ambient occlusion (0-1)
varying vec4 worldPosition;
varying vec3 vertexNormal;   // .xy = light map UV sampled at THIS vertex's tile corner (set per-vertex in Lua)

// Updated every tick from Lua
uniform vec3 skylightColor;

// Light map texture for the chunk, updated every time the chunk is remeshed and sent with each render call
extern sampler2D lightMap;

// Ambient occlusion multiplier so it can be adjusted or turned off
extern float aoMulti = 1.0; // TODO: Make it so the strength of this effect can be adjusted
extern bool sideShadingEnabled = true;
extern float minBrightness = 0.0;
extern float brightnessMulti = 1.0;

const vec3 rec709Luma = vec3(0.2126, 0.7152, 0.0722);

vec3 enforceMinBrightness(vec3 color, float minBrightness) {
    float currentBrightness = dot(color, rec709Luma);
    
    // Safe guard against pure black
    currentBrightness = max(currentBrightness, 0.001); 
    
    // Calculate the required scale factor
    float scale = max(1.0, minBrightness / currentBrightness);
    
    return color * scale;
}

vec3 enforceMinLight(vec3 lightColor) {
    float currentBrightness = dot(lightColor, rec709Luma);
    if (currentBrightness >= minBrightness) {
        return lightColor;
    }

    if (currentBrightness <= 0.0) {
        return vec3(minBrightness);
    }

    float lift = minBrightness / currentBrightness;
    return lightColor * lift;
}

vec4 effect(vec4 color, Image tex, vec2 texcoord, vec2 pixcoord) {
    vec4 texcolor = Texel(tex, texcoord);

    if (texcolor.a == 0.0) { discard; }

    float ao = aoMulti * vertexColor.a - aoMulti + 1; // ((1.0 - vertexColor.a) * (1.0 - aoMulti)) + vertexColor.a;

    // Each vertex's UV already sits exactly on a light map texel *boundary* (computed per-vertex
    // in addFace, in Lua). Because lightMap uses "linear" filtering, sampling here makes the GPU
    // blend the light values of the (up to four) tiles that share this corner -- that's our
    // smooth lighting, for free, with no extra texture samples needed.
    vec4 light = texture2D(lightMap, vertexNormal.xy);
    vec3 blockLight = light.rgb;
    float skyExposure = light.a;

    skyExposure = log(1 + skyExposure * (exp(1.0) - 1)); // log -> ln(1 + x*(e-1))
    // skyExposure = ((pow(exp(1.0), skyExposure) - 1) / (exp(1.0) - 1)); // expo -> (e^x - 1)/(e - 1)
    // skyExposure = sqrt(skyExposure); // sqrt -> sqrt(x)
    // skyExposure = pow(skyExposure, 2.0); // quad -> x^2

    float colorMulti = sideShadingEnabled == true ? vertexNormal.z : 1.0;

    vec3 skyContrib = skylightColor * skyExposure;
    vec3 totalLight = max(blockLight, skyContrib);

    // Apply ambient occlusion last so it darkens corners/crevices regardless of light source
    totalLight *= ao;

    totalLight = enforceMinLight(totalLight);
    totalLight *= brightnessMulti;

    vec3 blockColor = vec3(texcolor.rgb * totalLight * colorMulti);

    return vec4 (blockColor, texcolor.a);
}