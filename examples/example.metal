#include <metal_stdlib>
using namespace metal;

// Example vertex shader input structure
struct VertexIn {
    float3 position [[attribute(0)]];
    float3 normal [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

// Example vertex shader output structure
struct VertexOut {
    float4 position [[position]];
    float3 normal;
    float2 texCoord;
};

// Uniforms structure
struct Uniforms {
    float4x4 modelViewProjectionMatrix;
    float4x4 normalMatrix;
};

// Vertex shader
vertex VertexOut vertexShader(
    VertexIn in [[stage_in]],
    constant Uniforms& uniforms [[buffer(1)]]
) {
    VertexOut out;
    out.position = uniforms.modelViewProjectionMatrix * float4(in.position, 1.0);
    out.normal = (uniforms.normalMatrix * float4(in.normal, 0.0)).xyz;
    out.texCoord = in.texCoord;
    return out;
}

// Fragment shader
fragment float4 fragmentShader(
    VertexOut in [[stage_in]],
    texture2d<float> colorTexture [[texture(0)]],
    sampler textureSampler [[sampler(0)]]
) {
    // Sample texture
    float4 color = colorTexture.sample(textureSampler, in.texCoord);

    // Simple lighting
    float3 lightDir = normalize(float3(1.0, 1.0, 1.0));
    float3 normal = normalize(in.normal);
    float diffuse = max(dot(normal, lightDir), 0.0);

    return float4(color.rgb * diffuse, color.a);
}

// Compute kernel example
kernel void computeShader(
    device float* inputData [[buffer(0)]],
    device float* outputData [[buffer(1)]],
    uint id [[thread_position_in_grid]]
) {
    // Simple computation: square each element
    outputData[id] = inputData[id] * inputData[id];
}

// Example of common Metal math functions
float4 mathExample(float4 input) {
    float4 result;
    result.x = sin(input.x);
    result.y = cos(input.y);
    result.z = sqrt(abs(input.z));
    result.w = clamp(input.w, 0.0, 1.0);

    float len = length(input.xyz);
    float3 normalized = normalize(input.xyz);

    return result;
}
