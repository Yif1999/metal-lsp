import Foundation

/// Efficient documentation storage and lookup
public class MetalDocumentation {
  private var documentationMap: [String: DocumentationEntry] = [:]

  /// Initialize with builtin documentation compiled into the binary
  public init() {
    for entry in Self.builtinEntries {
      documentationMap[entry.symbol] = entry
    }
  }

  /// Add a documentation entry
  public func addEntry(_ entry: DocumentationEntry) {
    documentationMap[entry.symbol] = entry
  }

  /// Look up documentation for a symbol
  public func lookup(_ symbol: String) -> DocumentationEntry? {
    return documentationMap[symbol]
  }

  /// Get all documentation entries as completion items
  public func getAllCompletions() -> [CompletionInfo] {
    return documentationMap.values.map { entry in
      CompletionInfo(
        label: entry.symbol,
        detail: entry.signature,
        documentation: entry.description
      )
    }
  }

  /// Export documentation to JSON
  public func exportToJSON() throws -> Data {
    let entries = Array(documentationMap.values).sorted { $0.symbol < $1.symbol }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return try encoder.encode(entries)
  }
}

/// Documentation entry for a Metal symbol
public struct DocumentationEntry: Codable {
  public let symbol: String
  public let signature: String
  public let description: String
  public let kind: String
  public let category: String?

  public init(symbol: String, signature: String, description: String, kind: String, category: String? = nil) {
    self.symbol = symbol
    self.signature = signature
    self.description = description
    self.kind = kind
    self.category = category
  }

  public var markdownDocumentation: String {
    var markdown = "```metal\n\(signature)\n```\n"

    if !description.isEmpty {
      markdown += "\n---\n\n\(description)"
    }

    if let category = category {
      markdown += "\n\n*Category: \(category)*"
    }

    return markdown
  }
}

// MARK: - Completion Info

/// Completion item information
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
