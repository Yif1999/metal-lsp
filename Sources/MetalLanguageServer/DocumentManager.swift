import Foundation

/// Manages open text documents and their content
class DocumentManager {
    private var documents: [String: Document] = [:]
    private let queue = DispatchQueue(label: "com.metal-lsp.documents")

    /// Open or update a document
    func openDocument(uri: String, text: String, version: Int) {
        queue.sync {
            documents[uri] = Document(uri: uri, text: text, version: version)
        }
    }

    /// Update document content
    func updateDocument(uri: String, changes: [TextDocumentContentChangeEvent], version: Int) {
        queue.sync {
            guard var document = documents[uri] else {
                return
            }

            for change in changes {
                if let range = change.range {
                    // Incremental update
                    document.applyChange(change: change.text, in: range)
                } else {
                    // Full document update
                    document.text = change.text
                }
            }

            document.version = version
            documents[uri] = document
        }
    }

    /// Close a document
    func closeDocument(uri: String) {
        queue.sync {
            _ = documents.removeValue(forKey: uri)
        }
    }

    /// Get document content
    func getDocument(uri: String) -> Document? {
        queue.sync {
            return documents[uri]
        }
    }

    /// Get all document URIs
    func getAllDocuments() -> [String] {
        queue.sync {
            return Array(documents.keys)
        }
    }
}

/// Represents a text document
struct Document {
    let uri: String
    var text: String
    var version: Int
    private(set) var lines: [String]

    init(uri: String, text: String, version: Int) {
        self.uri = uri
        self.text = text
        self.version = version
        self.lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    /// Apply a text change to a specific range
    mutating func applyChange(change: String, in range: Range) {
        let startOffset = offsetAt(position: range.start)
        let endOffset = offsetAt(position: range.end)

        let startIndex = text.index(text.startIndex, offsetBy: startOffset)
        let endIndex = text.index(text.startIndex, offsetBy: endOffset)

        text.replaceSubrange(startIndex..<endIndex, with: change)
        lines = text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
    }

    /// Convert position to character offset
    func offsetAt(position: Position) -> Int {
        var offset = 0
        for (index, line) in lines.enumerated() {
            if index == position.line {
                offset += min(position.character, line.count)
                break
            }
            offset += line.count + 1 // +1 for newline
        }
        return offset
    }

    /// Convert character offset to position
    func positionAt(offset: Int) -> Position {
        var remaining = offset
        for (lineIndex, line) in lines.enumerated() {
            let lineLength = line.count + 1 // +1 for newline
            if remaining <= line.count {
                return Position(line: lineIndex, character: remaining)
            }
            remaining -= lineLength
        }
        // If offset is beyond document, return end position
        let lastLine = max(0, lines.count - 1)
        let lastChar = lines.isEmpty ? 0 : lines[lastLine].count
        return Position(line: lastLine, character: lastChar)
    }

    /// Get line at index
    func line(at index: Int) -> String? {
        guard index >= 0 && index < lines.count else {
            return nil
        }
        return lines[index]
    }

    /// Get text in range
    func text(in range: Range) -> String {
        let startOffset = offsetAt(position: range.start)
        let endOffset = offsetAt(position: range.end)

        let startIndex = text.index(text.startIndex, offsetBy: startOffset)
        let endIndex = text.index(text.startIndex, offsetBy: endOffset)

        return String(text[startIndex..<endIndex])
    }
}
