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
    guard !name.isEmpty else { return [] }

    var declarations: [SymbolDeclaration] = []
    let maskedSource = MetalSourceMasker.mask(source)
    let lines = maskedSource.components(separatedBy: .newlines)

    let escapedName = NSRegularExpression.escapedPattern(for: name)

    let functionRegex = try? NSRegularExpression(pattern: "\\b\(escapedName)\\s*\\(")
    let variableRegex = try? NSRegularExpression(pattern: "\\b\(escapedName)\\s*[=;]")
    let structRegex = try? NSRegularExpression(pattern: "\\bstruct\\s+\(escapedName)\\b")

    for (lineNum, line) in lines.enumerated() {
      let nsLine = line as NSString
      let range = NSRange(location: 0, length: nsLine.length)

      if let match = functionRegex?.firstMatch(in: line, range: range) {
        let kind: SymbolKind
        if line.contains("kernel") {
          kind = .kernel
        } else if line.contains("vertex") {
          kind = .vertex
        } else if line.contains("fragment") {
          kind = .fragment
        } else {
          kind = .function
        }

        declarations.append(
          SymbolDeclaration(
            name: name,
            line: lineNum,
            column: match.range.location,
            kind: kind
          )
        )
      }

      if let match = structRegex?.firstMatch(in: line, range: range) {
        let structText = nsLine.substring(with: match.range)
        if let nameRange = structText.range(of: name) {
          let offset = structText.distance(from: structText.startIndex, to: nameRange.lowerBound)
          declarations.append(
            SymbolDeclaration(
              name: name,
              line: lineNum,
              column: match.range.location + offset,
              kind: .struct
            )
          )
        }
      }

      if let match = variableRegex?.firstMatch(in: line, range: range) {
        let before = nsLine.substring(to: match.range.location)
        let openParens = before.filter { $0 == "(" }.count
        let closeParens = before.filter { $0 == ")" }.count

        if openParens == closeParens {
          declarations.append(
            SymbolDeclaration(
              name: name,
              line: lineNum,
              column: match.range.location,
              kind: .variable
            )
          )
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
    guard !name.isEmpty else { return [] }

    var references: [(line: Int, column: Int)] = []
    let maskedSource = MetalSourceMasker.mask(source)
    let lines = maskedSource.components(separatedBy: .newlines)

    let escapedName = NSRegularExpression.escapedPattern(for: name)
    guard let regex = try? NSRegularExpression(pattern: "\\b\(escapedName)\\b") else {
      return []
    }

    for (lineNum, line) in lines.enumerated() {
      let nsLine = line as NSString
      let matches = regex.matches(in: line, range: NSRange(location: 0, length: nsLine.length))
      for match in matches {
        references.append((line: lineNum, column: match.range.location))
      }
    }

    return references
  }
}
