import Foundation

/// Parser for Metal Shading Language specification markdown file
public class MetalSpecParser {
  private let specContent: String

  public init(specPath: String) throws {
    self.specContent = try String(contentsOfFile: specPath, encoding: .utf8)
  }

  /// Search for documentation about a specific symbol (function, type, keyword)
  /// Results are cached for performance
  private var documentationCache: [String: SymbolDocumentation?] = [:]

  public func findDocumentation(for symbol: String) -> SymbolDocumentation? {
    // Check cache first
    if let cached = documentationCache[symbol] {
      return cached
    }

    // Try different search strategies
    var result: SymbolDocumentation?

    if let doc = findFunctionDocumentation(for: symbol) {
      result = doc
    } else if let doc = findTypeDocumentation(for: symbol) {
      result = doc
    } else if let doc = findKeywordDocumentation(for: symbol) {
      result = doc
    }

    // Cache the result (even if nil)
    documentationCache[symbol] = result

    return result
  }

  /// Clear the documentation cache
  public func clearCache() {
    documentationCache.removeAll()
  }

  // MARK: - Function Documentation

  private func findFunctionDocumentation(for symbol: String) -> SymbolDocumentation? {
    // Try table-based format first (marker output)
    if let doc = findFunctionInTable(for: symbol) {
      return doc
    }

    // Fall back to plain text format
    return findFunctionInPlainText(for: symbol)
  }

  /// Parse function from markdown table format (marker output)
  /// Tables have format: | T<br>function<br>(...) | Description |
  private func findFunctionInTable(for symbol: String) -> SymbolDocumentation? {
    let lines = specContent.components(separatedBy: .newlines)

    for (index, line) in lines.enumerated() {
      // Check if this is a table row with a function signature
      guard line.hasPrefix("|") else { continue }

      let columns = line.components(separatedBy: "|")
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }

      guard columns.count >= 2 else { continue }

      let signatureColumn = columns[0]
      let descriptionColumn = columns[1]

      // Check if signature contains our symbol
      guard signatureColumn.contains(symbol) else { continue }

      // Clean up signature: remove <br> tags and extra whitespace
      let cleanedSignature = signatureColumn
        .replacingOccurrences(of: "<br>", with: " ")
        .replacingOccurrences(of: "  ", with: " ")
        .trimmingCharacters(in: .whitespaces)

      // Verify it's actually the function we're looking for (not just contains the symbol)
      // Look for pattern: "T symbol(" or "type symbol("
      let hasFunctionPattern = cleanedSignature.contains("\(symbol)(") ||
                               cleanedSignature.hasPrefix("\(symbol)(")

      guard hasFunctionPattern else { continue }

      // Clean up description: remove <br> tags and extra whitespace
      let cleanedDescription = descriptionColumn
        .replacingOccurrences(of: "<br>", with: " ")
        .replacingOccurrences(of: "  ", with: " ")
        .trimmingCharacters(in: .whitespaces)

      // Some descriptions span multiple table rows - look ahead for continuation
      var fullDescription = cleanedDescription
      var offset = 1
      while index + offset < lines.count && offset <= 5 {
        let nextLine = lines[index + offset]

        // Stop if we hit a new table row with a function signature
        if nextLine.hasPrefix("|") {
          let nextCols = nextLine.components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

          if nextCols.count >= 2 && !nextCols[0].isEmpty {
            // This is a new entry
            break
          } else if nextCols.count >= 2 {
            // Empty first column means continuation of description
            let continuation = nextCols[1]
              .replacingOccurrences(of: "<br>", with: " ")
              .replacingOccurrences(of: "  ", with: " ")
              .trimmingCharacters(in: .whitespaces)

            if !continuation.isEmpty {
              fullDescription += " " + continuation
            }
          }
        } else if nextLine.trimmingCharacters(in: .whitespaces).isEmpty {
          break
        }

        offset += 1
      }

      return SymbolDocumentation(
        name: symbol,
        signature: cleanedSignature,
        description: fullDescription,
        kind: .function
      )
    }

    return nil
  }

  /// Parse function from plain text format (old format)
  private func findFunctionInPlainText(for symbol: String) -> SymbolDocumentation? {
    let lines = specContent.components(separatedBy: .newlines)

    // Search for function signature patterns
    // Pattern 1: "T symbol(..."
    // Pattern 2: "type symbol(..."
    let patterns = [
      "T \(symbol)\\(",
      "\\w+ \(symbol)\\(",
      "^\\s*\(symbol)\\("
    ]

    for (index, line) in lines.enumerated() {
      for pattern in patterns {
        if let regex = try? NSRegularExpression(pattern: pattern, options: []),
           regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil {

          // Extract signature and description
          let signature = extractSignature(from: line, lines: lines, index: index)
          let description = extractDescription(from: lines, startingAt: index, signature: signature)

          if !signature.isEmpty {
            return SymbolDocumentation(
              name: symbol,
              signature: signature,
              description: description,
              kind: .function
            )
          }
        }
      }
    }

    return nil
  }

  private func extractSignature(from line: String, lines: [String], index: Int) -> String {
    // Clean up the line to extract just the function signature
    var cleaned = line.trimmingCharacters(in: .whitespaces)

    // Remove markdown formatting
    cleaned = cleaned.replacingOccurrences(of: "```", with: "")
    cleaned = cleaned.replacingOccurrences(of: "`", with: "")

    // If line contains description after signature, split it
    let descriptionMarkers = [" Returns ", " Compute ", " Return "]
    for marker in descriptionMarkers {
      if let descIndex = cleaned.range(of: marker),
         descIndex.lowerBound > cleaned.startIndex {
        cleaned = String(cleaned[..<descIndex.lowerBound])
        break
      }
    }

    // Check if signature continues on next line (e.g., multi-line function params)
    // Look for lines that don't start with description markers and continue the signature
    var signature = cleaned
    var offset = 1
    while index + offset < lines.count && offset <= 3 {
      let nextLine = lines[index + offset].trimmingCharacters(in: .whitespaces)

      // Stop at empty lines or description markers
      if nextLine.isEmpty ||
         nextLine.starts(with: "Returns ") ||
         nextLine.starts(with: "Compute ") ||
         nextLine.starts(with: "Return ") ||
         nextLine.starts(with: "```") ||
         nextLine.starts(with: "##") {
        break
      }

      // If it looks like a continuation (starts with lowercase or param), add it
      if nextLine.first?.isLowercase == true ||
         nextLine.contains(")") ||
         nextLine.starts(with: "T ") {
        signature += " " + nextLine.replacingOccurrences(of: "```", with: "")
        offset += 1
      } else {
        break
      }
    }

    return signature.trimmingCharacters(in: .whitespaces)
  }

  private func extractDescription(from lines: [String], startingAt index: Int, signature: String) -> String {
    var description = ""
    let line = lines[index]

    // Check if description is on the same line
    if let descStart = line.range(of: " Returns ") ?? line.range(of: " Compute ") ?? line.range(of: " Return ") {
      description = String(line[descStart.upperBound...])
        .trimmingCharacters(in: .whitespaces)
    }

    // Calculate how many lines the signature took
    let signatureLineCount = signature.components(separatedBy: "\n").count

    // Look at the next few lines for continuation or description
    var foundDescription = !description.isEmpty
    let startOffset = foundDescription ? 1 : signatureLineCount

    for offset in startOffset...15 {
      guard index + offset < lines.count else { break }
      let nextLine = lines[index + offset].trimmingCharacters(in: .whitespaces)

      // Stop at empty lines after finding description
      if nextLine.isEmpty && foundDescription && description.count > 20 {
        break
      }

      // Skip code block markers
      if nextLine == "```" {
        continue
      }

      // Stop at new sections
      if nextLine.starts(with: "##") || nextLine.starts(with: "Table") ||
         nextLine.starts(with: "Built-in") || nextLine.contains("Copyright") {
        break
      }

      // Stop if we encounter another function signature
      let looksLikeFunctionSig = nextLine.contains("(") && nextLine.contains(")") &&
                                  !nextLine.starts(with: "Returns") &&
                                  !description.isEmpty
      if looksLikeFunctionSig {
        // Check if it's truly a new function (has return type or T prefix)
        if nextLine.starts(with: "T ") ||
           nextLine.starts(with: "int ") ||
           nextLine.starts(with: "float ") ||
           nextLine.starts(with: "bool ") {
          break
        }
      }

      // If this line starts with "Returns", "Compute", etc, it's the description
      if !foundDescription {
        if nextLine.starts(with: "Returns ") || nextLine.starts(with: "Compute ") ||
           nextLine.starts(with: "Return ") {
          description = nextLine
          foundDescription = true
          continue
        }
      }

      // Continue description if we already have one
      if foundDescription && !nextLine.isEmpty {
        description += " " + nextLine
      }
    }

    // Clean up the description - stop at first sentence if it gets too long
    let sentences = description.components(separatedBy: ". ")
    if sentences.count > 2 && description.count > 200 {
      description = sentences[0] + "."
    }

    return description.trimmingCharacters(in: .whitespaces)
  }

  // MARK: - Type Documentation

  private func findTypeDocumentation(for symbol: String) -> SymbolDocumentation? {
    let lines = specContent.components(separatedBy: .newlines)

    // Search for type definitions
    // Pattern: "symbol A description..." (for scalar types)
    // Pattern: "symbol<T>" (for template types)
    for (index, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Check if line starts with the symbol followed by space or generic bracket
      if trimmed.hasPrefix(symbol + " ") ||
         trimmed.hasPrefix(symbol + "<") ||
         trimmed.hasPrefix(symbol + "\t") {

        // Extract description from the same line or following lines
        let description = extractTypeDescription(from: lines, startingAt: index)

        if !description.isEmpty {
          return SymbolDocumentation(
            name: symbol,
            signature: symbol,
            description: description,
            kind: .type
          )
        }
      }
    }

    return nil
  }

  private func extractTypeDescription(from lines: [String], startingAt index: Int) -> String {
    let line = lines[index]

    // Try to extract description from the same line
    let components = line.components(separatedBy: " ")
    if components.count > 1 {
      let description = components.dropFirst().joined(separator: " ")
        .trimmingCharacters(in: .whitespaces)

      if !description.isEmpty && !description.starts(with: "[[") {
        return description
      }
    }

    // Look at following lines
    for offset in 1...5 {
      guard index + offset < lines.count else { break }
      let nextLine = lines[index + offset].trimmingCharacters(in: .whitespaces)

      if !nextLine.isEmpty && !nextLine.starts(with: "```") && !nextLine.starts(with: "##") {
        return nextLine
      }
    }

    return ""
  }

  // MARK: - Keyword Documentation

  private func findKeywordDocumentation(for symbol: String) -> SymbolDocumentation? {
    // Search for keyword documentation in specific sections
    let sectionMarkers = [
      "Address Spaces",
      "Function Attributes",
      "Variable Attributes"
    ]

    let lines = specContent.components(separatedBy: .newlines)

    for (index, line) in lines.enumerated() {
      // Check if we're in a relevant section
      let inRelevantSection = sectionMarkers.contains { marker in
        line.contains(marker)
      }

      if inRelevantSection {
        // Search for the keyword in the following lines
        for offset in 0...100 {
          guard index + offset < lines.count else { break }
          let searchLine = lines[index + offset]

          if searchLine.contains(symbol) {
            let description = extractKeywordDescription(from: lines, startingAt: index + offset)
            if !description.isEmpty {
              return SymbolDocumentation(
                name: symbol,
                signature: symbol,
                description: description,
                kind: .keyword
              )
            }
          }
        }
      }
    }

    return nil
  }

  private func extractKeywordDescription(from lines: [String], startingAt index: Int) -> String {
    var description = lines[index].trimmingCharacters(in: .whitespaces)

    // Remove the keyword itself from the beginning
    for offset in 1...5 {
      guard index + offset < lines.count else { break }
      let nextLine = lines[index + offset].trimmingCharacters(in: .whitespaces)

      if nextLine.isEmpty || nextLine.starts(with: "##") {
        break
      }

      description += " " + nextLine
    }

    return description
  }
}

// MARK: - Documentation Model

public struct SymbolDocumentation {
  public let name: String
  public let signature: String
  public let description: String
  public let kind: SymbolKind

  public enum SymbolKind {
    case function
    case type
    case keyword
  }

  public var markdownDocumentation: String {
    var markdown = "```metal\n\(signature)\n```\n"

    if !description.isEmpty {
      markdown += "\n---\n\n\(description)"
    }

    return markdown
  }
}
