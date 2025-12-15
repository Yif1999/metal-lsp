import Foundation

/// Finds symbols (declarations and references) in Metal source code
public class MetalSymbolFinder {
  public init() {}

  /// A symbol declaration found in source code
  public struct SymbolDeclaration {
    public let name: String
    public let line: Int
    public let column: Int
    public let kind: SymbolKind

    public init(name: String, line: Int, column: Int, kind: SymbolKind) {
      self.name = name
      self.line = line
      self.column = column
      self.kind = kind
    }
  }

  /// Types of symbols that can be declared
  public enum SymbolKind {
    case function
    case kernel
    case vertex
    case fragment
    case variable
    case `struct`
    case unknown
  }

  /// Finds all declarations of a symbol in the given source code
  /// - Parameters:
  ///   - name: The symbol name to search for
  ///   - source: The Metal source code
  /// - Returns: Array of symbol declarations found
  public func findDeclarations(name: String, in source: String) -> [SymbolDeclaration] {
    var declarations: [SymbolDeclaration] = []
    let lines = source.components(separatedBy: .newlines)
    let escapedName = NSRegularExpression.escapedPattern(for: name)

    for (lineNum, line) in lines.enumerated() {
      // Skip comments
      let trimmedLine = removeComments(from: line)

      // Function declarations: type name(
      if let regex = try? NSRegularExpression(pattern: "\\b\(escapedName)\\s*\\("),
        let range = regex.firstMatch(
          in: trimmedLine, range: NSRange(location: 0, length: (trimmedLine as NSString).length))?
          .range,
        let swiftRange = Range(range, in: trimmedLine)
      {
        let column = trimmedLine.distance(from: trimmedLine.startIndex, to: swiftRange.lowerBound)

        // Determine function kind
        let kind: SymbolKind
        if trimmedLine.contains("kernel") {
          kind = .kernel
        } else if trimmedLine.contains("vertex") {
          kind = .vertex
        } else if trimmedLine.contains("fragment") {
          kind = .fragment
        } else {
          kind = .function
        }

        declarations.append(
          SymbolDeclaration(
            name: name,
            line: lineNum,
            column: column,
            kind: kind
          ))
      }

      // Struct declarations: struct name {
      if trimmedLine.contains("struct") && trimmedLine.contains(name) {
        if let regex = try? NSRegularExpression(pattern: "\\bstruct\\s+\(escapedName)\\b"),
          let range = regex.firstMatch(
            in: trimmedLine, range: NSRange(location: 0, length: (trimmedLine as NSString).length))?
            .range,
          let swiftRange = Range(range, in: trimmedLine)
        {
          let column = trimmedLine.distance(from: trimmedLine.startIndex, to: swiftRange.lowerBound)
          declarations.append(
            SymbolDeclaration(
              name: name,
              line: lineNum,
              column: column,
              kind: .struct
            ))
        }
      }

      // Variable declarations: type name = or type name;
      if let regex = try? NSRegularExpression(pattern: "\\b\(escapedName)\\s*[=;]"),
        let range = regex.firstMatch(
          in: trimmedLine, range: NSRange(location: 0, length: (trimmedLine as NSString).length))?
          .range,
        let swiftRange = Range(range, in: trimmedLine)
      {
        let column = trimmedLine.distance(from: trimmedLine.startIndex, to: swiftRange.lowerBound)

        // Check if this looks like a declaration (not inside parentheses or brackets)
        let beforeMatch = String(trimmedLine[..<swiftRange.lowerBound])
        let openParens = beforeMatch.filter { $0 == "(" }.count
        let closeParens = beforeMatch.filter { $0 == ")" }.count

        // If balanced parentheses before this point, it's likely a declaration
        if openParens == closeParens {
          declarations.append(
            SymbolDeclaration(
              name: name,
              line: lineNum,
              column: column,
              kind: .variable
            ))
        }
      }
    }

    return declarations
  }

  /// Finds all references to a symbol in the given source code
  /// - Parameters:
  ///   - name: The symbol name to search for
  ///   - source: The Metal source code
  /// - Returns: Array of (line, column) tuples where the symbol is referenced
  public func findReferences(name: String, in source: String) -> [(line: Int, column: Int)] {
    var references: [(line: Int, column: Int)] = []
    let lines = source.components(separatedBy: .newlines)

    for (lineNum, line) in lines.enumerated() {
      // Skip comments
      let trimmedLine = removeComments(from: line)

      // Find all whole-word matches of the symbol
      // Using word boundaries \b
      let escapedName = NSRegularExpression.escapedPattern(for: name)
      guard let regex = try? NSRegularExpression(pattern: "\\b\(escapedName)\\b") else {
        continue
      }

      let nsString = trimmedLine as NSString
      let matches = regex.matches(
        in: trimmedLine, range: NSRange(location: 0, length: nsString.length))

      for match in matches {
        references.append((line: lineNum, column: match.range.location))
      }
    }

    return references
  }

  /// Removes comments from a line of code (both // and /* */ style)
  /// - Parameter line: A line of Metal source code
  /// - Returns: The line with comments removed
  private func removeComments(from line: String) -> String {
    // Handle line comments //
    if let range = line.range(of: "//") {
      return String(line[..<range.lowerBound])
    }

    // For block comments, this is simplified - just remove /* */ blocks
    var result = line
    while let startRange = result.range(of: "/*"),
      let endRange = result.range(of: "*/", range: startRange.upperBound..<result.endIndex)
    {
      result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
    }

    return result
  }
}
