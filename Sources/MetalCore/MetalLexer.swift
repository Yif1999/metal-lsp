import Foundation

public struct MetalToken {
  public let type: String
  public let line: Int
  public let column: Int
  public let length: Int
  
  public init(type: String, line: Int, column: Int, length: Int) {
    self.type = type
    self.line = line
    self.column = column
    self.length = length
  }
}

public class MetalLexer {
  public init() {}
  
  public func tokenize(_ source: String) -> [MetalToken] {
    var tokens: [MetalToken] = []
    let lines = source.components(separatedBy: .newlines)
    
    for (lineIndex, line) in lines.enumerated() {
      tokens.append(contentsOf: tokenizeLine(line, lineIndex: lineIndex))
    }
    return tokens
  }
  
  private func tokenizeLine(_ line: String, lineIndex: Int) -> [MetalToken] {
    var tokens: [MetalToken] = []
    let nsString = line as NSString
    var currentIndex = 0
    var lastTokenWasDot = false
    
    while currentIndex < nsString.length {
      let remainingRange = NSRange(location: currentIndex, length: nsString.length - currentIndex)
      
      // Skip whitespace
      if let match = try? NSRegularExpression(pattern: #"^\s+"#).firstMatch(in: line, range: remainingRange) {
        currentIndex += match.range.length
        // Whitespace resets dot context? Usually yes, unless "foo . bar"
        // But let's assume valid code mostly.
        continue
      }
      
      // Comment //
      if let match = try? NSRegularExpression(pattern: #"^//.*"#).firstMatch(in: line, range: remainingRange) {
        tokens.append(MetalToken(type: "comment", line: lineIndex, column: currentIndex, length: match.range.length))
        currentIndex += match.range.length
        lastTokenWasDot = false
        continue
      }
      
      // String
      if let match = try? NSRegularExpression(pattern: #"^"[^"]*""#).firstMatch(in: line, range: remainingRange) {
        tokens.append(MetalToken(type: "string", line: lineIndex, column: currentIndex, length: match.range.length))
        currentIndex += match.range.length
        lastTokenWasDot = false
        continue
      }
      
      // Preprocessor #
      if let match = try? NSRegularExpression(pattern: #"^#\w+"#).firstMatch(in: line, range: remainingRange) {
         tokens.append(MetalToken(type: "macro", line: lineIndex, column: currentIndex, length: match.range.length))
         currentIndex += match.range.length
         lastTokenWasDot = false
         continue
      }
      
      // Number
      if let match = try? NSRegularExpression(pattern: #"^\b\d+(\.\d+)?f?\b"#).firstMatch(in: line, range: remainingRange) {
        tokens.append(MetalToken(type: "number", line: lineIndex, column: currentIndex, length: match.range.length))
        currentIndex += match.range.length
        lastTokenWasDot = false
        continue
      }
      
      // Identifier
      if let match = try? NSRegularExpression(pattern: #"^[a-zA-Z_]\w*"#).firstMatch(in: line, range: remainingRange) {
        let name = nsString.substring(with: match.range)
        let length = match.range.length
        
        var type = "variable"
        
        if MetalBuiltins.keywords.contains(name) {
          type = "keyword"
        } else if ["float", "int", "void", "bool", "float2", "float3", "float4", "half", "uint", "uint2", "uint3", "uint4", "bool2", "bool3", "bool4", "matrix", "texture2d", "sampler"].contains(name) {
          type = "type"
        } else if lastTokenWasDot {
             // Property or Method
             // Look ahead for (
             let remainingAfter = nsString.substring(from: currentIndex + length)
             if remainingAfter.trimmingCharacters(in: .whitespaces).hasPrefix("(") {
                 type = "method"
             } else {
                 type = "property"
             }
        } else {
             // Function or Variable
             let remainingAfter = nsString.substring(from: currentIndex + length)
             if remainingAfter.trimmingCharacters(in: .whitespaces).hasPrefix("(") {
                 type = "function"
             } else {
                 // Check if it looks like a type (PascalCase often used for structs)
                 if name.first?.isUppercase == true {
                     type = "class" // or struct/type
                 }
             }
        }
        
        tokens.append(MetalToken(type: type, line: lineIndex, column: currentIndex, length: length))
        currentIndex += length
        lastTokenWasDot = false
        continue
      }
      
      // Operator / Punctuation
      let char = nsString.substring(with: NSRange(location: currentIndex, length: 1))
      if char == "." {
          lastTokenWasDot = true
      } else {
          lastTokenWasDot = false
      }
      
      tokens.append(MetalToken(type: "operator", line: lineIndex, column: currentIndex, length: 1))
      currentIndex += 1
    }
    
    return tokens
  }
}
