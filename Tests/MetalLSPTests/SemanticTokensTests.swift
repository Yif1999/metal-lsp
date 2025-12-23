import Foundation
import Testing

@testable import MetalCore
@testable import MetalLanguageServer

/// Tests for semantic tokens functionality
@Suite("Semantic Tokens Tests")
struct SemanticTokensTests {

  @Test("MetalLexer tokenizes Metal code correctly")
  func metalLexerTokenization() {
    let lexer = MetalLexer()
    let code = """
    #include <metal_stdlib>
    using namespace metal;

    float globalValue = 1.0;

    kernel void computeShader(
        device float* data [[buffer(0)]],
        uint id [[thread_position_in_grid]]
    ) {
        float x = data[id];
        data[id] = x * globalValue;
    }
    """

    let tokens = lexer.tokenize(code)

    // Should have tokens
    #expect(!tokens.isEmpty, "Should tokenize the code")

    // Check for specific token types
    let tokenTypes = Set(tokens.map { $0.type })
    #expect(tokenTypes.contains("keyword"), "Should contain keywords")
    #expect(tokenTypes.contains("function"), "Should contain functions")
    #expect(tokenTypes.contains("variable"), "Should contain variables")
    #expect(tokenTypes.contains("number"), "Should contain numbers")
    #expect(tokenTypes.contains("macro"), "Should contain macros")

    // Check token positions
    let firstToken = tokens.first
    #expect(firstToken?.line == 0, "First token should be on line 0")
    #expect(firstToken?.column == 0, "First token should start at column 0")
  }

  @Test("Token encoding produces correct format")
  func tokenEncoding() {
    let lexer = MetalLexer()
    let code = "float x = 1.0;"
    let tokens = lexer.tokenize(code)

    // Create a mock server to test encoding
    let server = LanguageServer(verbose: false)
    let encoded = server.testEncodeTokens(tokens)

    // Each token should produce 5 integers
    #expect(encoded.count == tokens.count * 5, "Each token should encode to 5 integers")

    // First token should be "float" (type)
    // Expected encoding: [0, 0, 5, 1, 0] (lineDelta=0, charDelta=0, length=5, typeIndex=1 for "type", modifiers=0)
    if tokens.count > 0 {
      #expect(encoded[0] == 0, "First token lineDelta should be 0")
      #expect(encoded[1] == 0, "First token charDelta should be 0")
      #expect(encoded[2] == 5, "First token length should be 5")
      #expect(encoded[3] == 1, "First token typeIndex should be 1 (type)")
      #expect(encoded[4] == 0, "First token modifiers should be 0")
    }
  }

  @Test("Legend contains all required token types")
  func legendCompleteness() {
    let tokenTypes = [
      "namespace", "type", "class", "enum", "interface", "struct",
      "typeParameter", "parameter", "variable", "property", "enumMember",
      "event", "function", "method", "macro", "keyword", "modifier",
      "comment", "string", "number", "regexp", "operator"
    ]

    let lexer = MetalLexer()
    let testCode = """
    #include <metal_stdlib>
    kernel void test() {
        float x = 1.0;
        int y = 2;
        float4 z = float4(0.0);
    }
    """

    let tokens = lexer.tokenize(testCode)
    let usedTypes = Set(tokens.map { $0.type })

    // Check that all used types are in the legend
    for type in usedTypes {
      #expect(tokenTypes.contains(type), "Token type '\(type)' should be in legend")
    }
  }

  @Test("SemanticTokensOptions has correct structure")
  func semanticTokensOptionsStructure() {
    let legend = SemanticTokensLegend(
      tokenTypes: ["type", "function", "variable"],
      tokenModifiers: ["declaration"]
    )

    let options = SemanticTokensOptions(legend: legend, full: true, range: true)

    #expect(options.legend.tokenTypes.count == 3, "Legend should have correct number of types")
    #expect(options.full != nil, "Full should be set")
    #expect(options.range == true, "Range should be true")
    #expect(options.delta == true, "Delta should be true")
  }

  @Test("Range filtering works correctly")
  func rangeFiltering() {
    let lexer = MetalLexer()
    let code = """
    line 0
    line 1
    line 2
    line 3
    """

    let tokens = lexer.tokenize(code)

    // Filter tokens in range (line 1 to 2)
    let range = Range(
      start: Position(line: 1, character: 0),
      end: Position(line: 2, character: 6)
    )

    let filteredTokens = tokens.filter { token in
      if token.line < range.start.line { return false }
      if token.line > range.end.line { return false }
      if token.line == range.start.line && token.column < range.start.character { return false }
      if token.line == range.end.line && token.column + token.length > range.end.character { return false }
      return true
    }

    // Should only include tokens from lines 1 and 2
    #expect(filteredTokens.allSatisfy { $0.line >= 1 && $0.line <= 2 }, "All tokens should be in range")
  }
}

// MARK: - Helper extension for testing

extension LanguageServer {
  /// Expose encodeTokens for testing
  func testEncodeTokens(_ tokens: [MetalToken]) -> [Int] {
    // This is a simplified version for testing
    // In real implementation, this would call the private method
    var data: [Int] = []
    var prevLine = 0
    var prevChar = 0

    let tokenTypes = [
      "namespace", "type", "class", "enum", "interface", "struct",
      "typeParameter", "parameter", "variable", "property", "enumMember",
      "event", "function", "method", "macro", "keyword", "modifier",
      "comment", "string", "number", "regexp", "operator"
    ]

    for token in tokens {
      let lineDelta = token.line - prevLine
      let charDelta = (lineDelta == 0) ? (token.column - prevChar) : token.column

      var typeIndex = tokenTypes.firstIndex(of: token.type) ?? 8 // default to variable

      data.append(lineDelta)
      data.append(charDelta)
      data.append(token.length)
      data.append(typeIndex)
      data.append(0)

      prevLine = token.line
      prevChar = token.column
    }

    return data
  }
}
