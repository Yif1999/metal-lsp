import Foundation

/// Database of Metal built-in types, functions, and keywords
public struct MetalBuiltins {

    // MARK: - Keywords

    public static let keywords = [
        "kernel", "vertex", "fragment",
        "constant", "device", "threadgroup", "thread",
        "struct", "enum", "typedef",
        "if", "else", "for", "while", "do", "switch", "case", "default",
        "break", "continue", "return",
        "const", "static", "inline",
        "true", "false",
        "using", "namespace",
        "template", "typename"
    ]

    // MARK: - Built-in Types

    public static let types: [CompletionInfo] = [
        // Scalar types
        CompletionInfo(label: "bool", detail: "Boolean type", documentation: "Boolean type (true or false)"),
        CompletionInfo(label: "char", detail: "8-bit signed integer", documentation: "8-bit signed integer type"),
        CompletionInfo(label: "uchar", detail: "8-bit unsigned integer", documentation: "8-bit unsigned integer type"),
        CompletionInfo(label: "short", detail: "16-bit signed integer", documentation: "16-bit signed integer type"),
        CompletionInfo(label: "ushort", detail: "16-bit unsigned integer", documentation: "16-bit unsigned integer type"),
        CompletionInfo(label: "int", detail: "32-bit signed integer", documentation: "32-bit signed integer type"),
        CompletionInfo(label: "uint", detail: "32-bit unsigned integer", documentation: "32-bit unsigned integer type"),
        CompletionInfo(label: "half", detail: "16-bit floating point", documentation: "16-bit floating point type"),
        CompletionInfo(label: "float", detail: "32-bit floating point", documentation: "32-bit floating point type"),

        // Vector types
        CompletionInfo(label: "bool2", detail: "2-component boolean vector"),
        CompletionInfo(label: "bool3", detail: "3-component boolean vector"),
        CompletionInfo(label: "bool4", detail: "4-component boolean vector"),

        CompletionInfo(label: "int2", detail: "2-component signed integer vector"),
        CompletionInfo(label: "int3", detail: "3-component signed integer vector"),
        CompletionInfo(label: "int4", detail: "4-component signed integer vector"),

        CompletionInfo(label: "uint2", detail: "2-component unsigned integer vector"),
        CompletionInfo(label: "uint3", detail: "3-component unsigned integer vector"),
        CompletionInfo(label: "uint4", detail: "4-component unsigned integer vector"),

        CompletionInfo(label: "half2", detail: "2-component half-precision float vector"),
        CompletionInfo(label: "half3", detail: "3-component half-precision float vector"),
        CompletionInfo(label: "half4", detail: "4-component half-precision float vector"),

        CompletionInfo(label: "float2", detail: "2-component float vector"),
        CompletionInfo(label: "float3", detail: "3-component float vector"),
        CompletionInfo(label: "float4", detail: "4-component float vector"),

        // Matrix types
        CompletionInfo(label: "float2x2", detail: "2x2 float matrix"),
        CompletionInfo(label: "float2x3", detail: "2x3 float matrix"),
        CompletionInfo(label: "float2x4", detail: "2x4 float matrix"),
        CompletionInfo(label: "float3x2", detail: "3x2 float matrix"),
        CompletionInfo(label: "float3x3", detail: "3x3 float matrix"),
        CompletionInfo(label: "float3x4", detail: "3x4 float matrix"),
        CompletionInfo(label: "float4x2", detail: "4x2 float matrix"),
        CompletionInfo(label: "float4x3", detail: "4x3 float matrix"),
        CompletionInfo(label: "float4x4", detail: "4x4 float matrix"),

        CompletionInfo(label: "half2x2", detail: "2x2 half-precision matrix"),
        CompletionInfo(label: "half3x3", detail: "3x3 half-precision matrix"),
        CompletionInfo(label: "half4x4", detail: "4x4 half-precision matrix"),

        // Texture types
        CompletionInfo(label: "texture1d", detail: "1D texture", documentation: "1D texture type with template type for pixel data"),
        CompletionInfo(label: "texture1d_array", detail: "1D texture array"),
        CompletionInfo(label: "texture2d", detail: "2D texture", documentation: "2D texture type with template type for pixel data"),
        CompletionInfo(label: "texture2d_array", detail: "2D texture array"),
        CompletionInfo(label: "texture3d", detail: "3D texture"),
        CompletionInfo(label: "texturecube", detail: "Cube texture"),
        CompletionInfo(label: "texturecube_array", detail: "Cube texture array"),
        CompletionInfo(label: "texture2d_ms", detail: "2D multisampled texture"),

        CompletionInfo(label: "depth2d", detail: "2D depth texture"),
        CompletionInfo(label: "depth2d_array", detail: "2D depth texture array"),
        CompletionInfo(label: "depthcube", detail: "Cube depth texture"),
        CompletionInfo(label: "depthcube_array", detail: "Cube depth texture array"),
        CompletionInfo(label: "depth2d_ms", detail: "2D multisampled depth texture"),

        // Sampler type
        CompletionInfo(label: "sampler", detail: "Texture sampler", documentation: "Sampler state for texture sampling operations"),
    ]

    // MARK: - Math Functions

    public static let mathFunctions: [CompletionInfo] = [
        // Trigonometric
        CompletionInfo(label: "sin", detail: "float sin(float x)", documentation: "Sine function"),
        CompletionInfo(label: "cos", detail: "float cos(float x)", documentation: "Cosine function"),
        CompletionInfo(label: "tan", detail: "float tan(float x)", documentation: "Tangent function"),
        CompletionInfo(label: "asin", detail: "float asin(float x)", documentation: "Arc sine function"),
        CompletionInfo(label: "acos", detail: "float acos(float x)", documentation: "Arc cosine function"),
        CompletionInfo(label: "atan", detail: "float atan(float y_over_x)", documentation: "Arc tangent function"),
        CompletionInfo(label: "atan2", detail: "float atan2(float y, float x)", documentation: "Two-argument arc tangent"),
        CompletionInfo(label: "sinh", detail: "float sinh(float x)", documentation: "Hyperbolic sine"),
        CompletionInfo(label: "cosh", detail: "float cosh(float x)", documentation: "Hyperbolic cosine"),
        CompletionInfo(label: "tanh", detail: "float tanh(float x)", documentation: "Hyperbolic tangent"),

        // Exponential and logarithmic
        CompletionInfo(label: "pow", detail: "float pow(float x, float y)", documentation: "Returns x raised to the power y"),
        CompletionInfo(label: "exp", detail: "float exp(float x)", documentation: "Natural exponentiation"),
        CompletionInfo(label: "exp2", detail: "float exp2(float x)", documentation: "Base-2 exponentiation"),
        CompletionInfo(label: "log", detail: "float log(float x)", documentation: "Natural logarithm"),
        CompletionInfo(label: "log2", detail: "float log2(float x)", documentation: "Base-2 logarithm"),
        CompletionInfo(label: "sqrt", detail: "float sqrt(float x)", documentation: "Square root"),
        CompletionInfo(label: "rsqrt", detail: "float rsqrt(float x)", documentation: "Reciprocal square root"),

        // Common functions
        CompletionInfo(label: "abs", detail: "float abs(float x)", documentation: "Absolute value"),
        CompletionInfo(label: "ceil", detail: "float ceil(float x)", documentation: "Round up to nearest integer"),
        CompletionInfo(label: "floor", detail: "float floor(float x)", documentation: "Round down to nearest integer"),
        CompletionInfo(label: "round", detail: "float round(float x)", documentation: "Round to nearest integer"),
        CompletionInfo(label: "trunc", detail: "float trunc(float x)", documentation: "Truncate to integer"),
        CompletionInfo(label: "fract", detail: "float fract(float x)", documentation: "Fractional part"),
        CompletionInfo(label: "fmod", detail: "float fmod(float x, float y)", documentation: "Floating-point remainder"),
        CompletionInfo(label: "min", detail: "float min(float x, float y)", documentation: "Minimum value"),
        CompletionInfo(label: "max", detail: "float max(float x, float y)", documentation: "Maximum value"),
        CompletionInfo(label: "clamp", detail: "float clamp(float x, float min, float max)", documentation: "Clamp value to range"),
        CompletionInfo(label: "mix", detail: "float mix(float x, float y, float a)", documentation: "Linear interpolation"),
        CompletionInfo(label: "step", detail: "float step(float edge, float x)", documentation: "Step function"),
        CompletionInfo(label: "smoothstep", detail: "float smoothstep(float edge0, float edge1, float x)", documentation: "Smooth step function"),
        CompletionInfo(label: "sign", detail: "float sign(float x)", documentation: "Sign of value (-1, 0, or 1)"),
    ]

    // MARK: - Geometric Functions

    public static let geometricFunctions: [CompletionInfo] = [
        CompletionInfo(label: "dot", detail: "float dot(float2 x, float2 y)", documentation: "Dot product of two vectors"),
        CompletionInfo(label: "cross", detail: "float3 cross(float3 x, float3 y)", documentation: "Cross product of two 3D vectors"),
        CompletionInfo(label: "length", detail: "float length(float2 x)", documentation: "Length of vector"),
        CompletionInfo(label: "distance", detail: "float distance(float2 p0, float2 p1)", documentation: "Distance between two points"),
        CompletionInfo(label: "normalize", detail: "float2 normalize(float2 x)", documentation: "Normalize vector to unit length"),
        CompletionInfo(label: "faceforward", detail: "float2 faceforward(float2 N, float2 I, float2 Nref)", documentation: "Orient vector to face forward"),
        CompletionInfo(label: "reflect", detail: "float2 reflect(float2 I, float2 N)", documentation: "Reflect vector"),
        CompletionInfo(label: "refract", detail: "float2 refract(float2 I, float2 N, float eta)", documentation: "Refract vector"),
    ]

    // MARK: - Texture Functions

    public static let textureFunctions: [CompletionInfo] = [
        CompletionInfo(label: "sample", detail: "float4 sample(sampler s, float2 coord)", documentation: "Sample texture with sampler"),
        CompletionInfo(label: "read", detail: "float4 read(uint2 coord)", documentation: "Read texel at coordinates"),
        CompletionInfo(label: "write", detail: "void write(float4 color, uint2 coord)", documentation: "Write color to texture at coordinates"),
        CompletionInfo(label: "get_width", detail: "uint get_width()", documentation: "Get texture width"),
        CompletionInfo(label: "get_height", detail: "uint get_height()", documentation: "Get texture height"),
        CompletionInfo(label: "get_depth", detail: "uint get_depth()", documentation: "Get texture depth"),
    ]

    // MARK: - Attributes

    public static let attributes: [CompletionInfo] = [
        // Function attributes
        CompletionInfo(label: "[[kernel]]", detail: "Compute kernel function", insertText: "[[kernel]]"),
        CompletionInfo(label: "[[vertex]]", detail: "Vertex shader function", insertText: "[[vertex]]"),
        CompletionInfo(label: "[[fragment]]", detail: "Fragment shader function", insertText: "[[fragment]]"),

        // Argument attributes
        CompletionInfo(label: "[[buffer(n)]]", detail: "Buffer binding point", insertText: "[[buffer(${1:0})]]"),
        CompletionInfo(label: "[[texture(n)]]", detail: "Texture binding point", insertText: "[[texture(${1:0})]]"),
        CompletionInfo(label: "[[sampler(n)]]", detail: "Sampler binding point", insertText: "[[sampler(${1:0})]]"),
        CompletionInfo(label: "[[stage_in]]", detail: "Stage input structure"),

        // Vertex output attributes
        CompletionInfo(label: "[[position]]", detail: "Vertex position output"),
        CompletionInfo(label: "[[point_size]]", detail: "Point size output"),
        CompletionInfo(label: "[[color(n)]]", detail: "Color attachment", insertText: "[[color(${1:0})]]"),
        CompletionInfo(label: "[[user(name)]]", detail: "User-defined attribute", insertText: "[[user(${1:name})]]"),

        // Thread attributes
        CompletionInfo(label: "[[thread_position_in_grid]]", detail: "Global thread position"),
        CompletionInfo(label: "[[thread_position_in_threadgroup]]", detail: "Local thread position"),
        CompletionInfo(label: "[[threadgroup_position_in_grid]]", detail: "Threadgroup position"),
        CompletionInfo(label: "[[threads_per_threadgroup]]", detail: "Threads per threadgroup size"),
        CompletionInfo(label: "[[threads_per_grid]]", detail: "Total threads in grid"),
        CompletionInfo(label: "[[thread_index_in_threadgroup]]", detail: "Linear thread index in threadgroup"),
        CompletionInfo(label: "[[thread_index_in_simdgroup]]", detail: "Thread index in SIMD group"),
        CompletionInfo(label: "[[simdgroup_index_in_threadgroup]]", detail: "SIMD group index in threadgroup"),

        // Vertex input attributes
        CompletionInfo(label: "[[vertex_id]]", detail: "Vertex ID"),
        CompletionInfo(label: "[[instance_id]]", detail: "Instance ID"),
        CompletionInfo(label: "[[base_vertex]]", detail: "Base vertex value"),
        CompletionInfo(label: "[[base_instance]]", detail: "Base instance value"),
    ]

    // MARK: - Snippets

    public static let snippets: [CompletionInfo] = [
        CompletionInfo(
            label: "kernel_function",
            detail: "Compute kernel template",
            insertText: """
            kernel void ${1:computeShader}(
                device float* ${2:data} [[buffer(0)]],
                uint id [[thread_position_in_grid]]
            ) {
                $0
            }
            """
        ),
        CompletionInfo(
            label: "vertex_function",
            detail: "Vertex shader template",
            insertText: """
            vertex float4 ${1:vertexShader}(
                uint vertexID [[vertex_id]]
            ) {
                $0
                return float4(0.0);
            }
            """
        ),
        CompletionInfo(
            label: "fragment_function",
            detail: "Fragment shader template",
            insertText: """
            fragment float4 ${1:fragmentShader}(
                float4 position [[position]]
            ) {
                $0
                return float4(1.0);
            }
            """
        ),
    ]

    // MARK: - Access

    public static func getAllCompletions() -> [CompletionInfo] {
        var completions: [CompletionInfo] = []

        // Add keywords
        completions += keywords.map { CompletionInfo(label: $0, detail: "keyword") }

        // Add types
        completions += types

        // Add functions
        completions += mathFunctions
        completions += geometricFunctions
        completions += textureFunctions

        // Add attributes
        completions += attributes

        // Add snippets
        completions += snippets

        return completions
    }
}

// MARK: - Completion Info

public struct CompletionInfo {
    public let label: String
    public let detail: String?
    public let documentation: String?
    public let insertText: String?

    public init(
        label: String,
        detail: String? = nil,
        documentation: String? = nil,
        insertText: String? = nil
    ) {
        self.label = label
        self.detail = detail
        self.documentation = documentation
        self.insertText = insertText
    }
}
