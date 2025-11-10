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
    "const", "constexpr", "static", "inline",
    "true", "false",
    "using", "namespace",
    "template", "typename",
  ]

  // MARK: - Sampler Constants

  public static let samplerConstants: [CompletionInfo] = [
    // Filter modes
    CompletionInfo(
      label: "filter", detail: "metal::filter",
      documentation: "Namespace for sampler filter modes"),
    CompletionInfo(
      label: "linear", detail: "Sampler filter mode",
      documentation: "Linear filtering - interpolates between texels"),
    CompletionInfo(
      label: "nearest", detail: "Sampler filter mode",
      documentation: "Nearest neighbor filtering - uses closest texel"),

    // Address modes
    CompletionInfo(
      label: "address", detail: "metal::address",
      documentation: "Namespace for sampler address modes"),
    CompletionInfo(
      label: "clamp_to_edge", detail: "Sampler address mode",
      documentation: "Clamp coordinates to edge of texture"),
    CompletionInfo(
      label: "clamp_to_zero", detail: "Sampler address mode",
      documentation: "Clamp coordinates and use border color of 0"),
    CompletionInfo(
      label: "clamp_to_border", detail: "Sampler address mode",
      documentation: "Clamp coordinates and use border color"),
    CompletionInfo(
      label: "repeat", detail: "Sampler address mode",
      documentation: "Repeat texture coordinates"),
    CompletionInfo(
      label: "mirrored_repeat", detail: "Sampler address mode",
      documentation: "Repeat texture coordinates with mirroring"),

    // Coordinate modes
    CompletionInfo(
      label: "coord", detail: "metal::coord",
      documentation: "Namespace for sampler coordinate modes"),
    CompletionInfo(
      label: "normalized", detail: "Sampler coordinate mode",
      documentation: "Coordinates are normalized [0, 1]"),
    CompletionInfo(
      label: "pixel", detail: "Sampler coordinate mode",
      documentation: "Coordinates are in pixel space"),
  ]

  // MARK: - Note
  // Built-in types and functions are now loaded from metal-docs.json
  // See MetalDocumentation.getAllCompletions()

  // MARK: - Attributes

  public static let attributes: [CompletionInfo] = [
    // Function attributes
    CompletionInfo(
      label: "[[kernel]]", detail: "Compute kernel function", insertText: "[[kernel]]"),
    CompletionInfo(
      label: "[[vertex]]", detail: "Vertex shader function", insertText: "[[vertex]]"),
    CompletionInfo(
      label: "[[fragment]]", detail: "Fragment shader function", insertText: "[[fragment]]"),

    // Argument attributes
    CompletionInfo(
      label: "[[buffer(n)]]", detail: "Buffer binding point", insertText: "[[buffer(${1:0})]]"
    ),
    CompletionInfo(
      label: "[[texture(n)]]", detail: "Texture binding point",
      insertText: "[[texture(${1:0})]]"),
    CompletionInfo(
      label: "[[sampler(n)]]", detail: "Sampler binding point",
      insertText: "[[sampler(${1:0})]]"),
    CompletionInfo(label: "[[stage_in]]", detail: "Stage input structure"),

    // Vertex output attributes
    CompletionInfo(label: "[[position]]", detail: "Vertex position output"),
    CompletionInfo(label: "[[point_size]]", detail: "Point size output"),
    CompletionInfo(
      label: "[[color(n)]]", detail: "Color attachment", insertText: "[[color(${1:0})]]"),
    CompletionInfo(
      label: "[[user(name)]]", detail: "User-defined attribute",
      insertText: "[[user(${1:name})]]"),

    // Thread attributes
    CompletionInfo(label: "[[thread_position_in_grid]]", detail: "Global thread position"),
    CompletionInfo(
      label: "[[thread_position_in_threadgroup]]", detail: "Local thread position"),
    CompletionInfo(label: "[[threadgroup_position_in_grid]]", detail: "Threadgroup position"),
    CompletionInfo(
      label: "[[threads_per_threadgroup]]", detail: "Threads per threadgroup size"),
    CompletionInfo(label: "[[threads_per_grid]]", detail: "Total threads in grid"),
    CompletionInfo(
      label: "[[thread_index_in_threadgroup]]", detail: "Linear thread index in threadgroup"),
    CompletionInfo(
      label: "[[thread_index_in_simdgroup]]", detail: "Thread index in SIMD group"),
    CompletionInfo(
      label: "[[simdgroup_index_in_threadgroup]]", detail: "SIMD group index in threadgroup"),

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

  /// Get hardcoded completions (keywords, attributes, snippets, sampler constants)
  /// Built-in types and functions should be loaded from metal-docs.json
  public static func getHardcodedCompletions() -> [CompletionInfo] {
    var completions: [CompletionInfo] = []

    // Add keywords
    completions += keywords.map { CompletionInfo(label: $0, detail: "keyword") }

    // Add sampler constants
    completions += samplerConstants

    // Add attributes
    completions += attributes

    // Add snippets
    completions += snippets

    return completions
  }
}

// CompletionInfo is now defined in MetalDocumentation.swift
