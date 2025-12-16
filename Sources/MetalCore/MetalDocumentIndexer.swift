import Foundation

public struct MetalSourcePosition: Hashable {
  public let line: Int
  public let column: Int

  public init(line: Int, column: Int) {
    self.line = line
    self.column = column
  }
}

public struct MetalSourceRange: Hashable {
  public let start: MetalSourcePosition
  public let end: MetalSourcePosition

  public init(start: MetalSourcePosition, end: MetalSourcePosition) {
    self.start = start
    self.end = end
  }
}

public struct MetalFunctionSignature: Hashable {
  public let name: String
  public let label: String
  public let parameters: [String]

  public init(name: String, label: String, parameters: [String]) {
    self.name = name
    self.label = label
    self.parameters = parameters
  }
}

public struct MetalDocumentSymbolNode: Hashable {
  public let name: String
  public let kind: MetalSymbolFinder.SymbolKind
  public let range: MetalSourceRange
  public let selectionRange: MetalSourceRange
  public let detail: String?
  public let children: [MetalDocumentSymbolNode]

  public init(
    name: String,
    kind: MetalSymbolFinder.SymbolKind,
    range: MetalSourceRange,
    selectionRange: MetalSourceRange,
    detail: String? = nil,
    children: [MetalDocumentSymbolNode] = []
  ) {
    self.name = name
    self.kind = kind
    self.range = range
    self.selectionRange = selectionRange
    self.detail = detail
    self.children = children
  }
}

public struct MetalDocumentIndex: Hashable {
  public let symbols: [MetalDocumentSymbolNode]
  public let functionSignatures: [String: MetalFunctionSignature]

  public init(symbols: [MetalDocumentSymbolNode], functionSignatures: [String: MetalFunctionSignature]) {
    self.symbols = symbols
    self.functionSignatures = functionSignatures
  }
}

public final class MetalDocumentIndexer {
  public init() {}

  public func index(source: String) -> MetalDocumentIndex {
    let masked = SourceMasker.mask(source)

    let maskedChars = Array(masked)
    let sourceChars = Array(source)
    let lineMap = LineMap(chars: maskedChars)

    var symbols: [MetalDocumentSymbolNode] = []
    var functionSignatures: [String: MetalFunctionSignature] = [:]

    var i = 0
    var braceDepth = 0

    while i < maskedChars.count {
      let c = maskedChars[i]

      if c == "{" {
        braceDepth += 1
        i += 1
        continue
      }

      if c == "}" {
        braceDepth = max(0, braceDepth - 1)
        i += 1
        continue
      }

      if braceDepth != 0 {
        i += 1
        continue
      }

      if isIdentifierStart(c) {
        let start = i
        var end = i + 1
        while end < maskedChars.count && isIdentifierContinue(maskedChars[end]) {
          end += 1
        }

        let ident = String(maskedChars[start..<end])

        if ident == "struct" {
          if let parsed = parseStruct(
            from: start,
            maskedChars: maskedChars,
            sourceChars: sourceChars,
            lineMap: lineMap
          ) {
            symbols.append(parsed.symbol)
            i = parsed.endIndex
            continue
          }
        }

        i = end
        continue
      }

      if c == "(" {
        if let parsed = parseFunctionDeclaration(
          openParenIndex: i,
          maskedChars: maskedChars,
          sourceChars: sourceChars,
          lineMap: lineMap
        ) {
          symbols.append(parsed.symbol)
          functionSignatures[parsed.signature.name] = parsed.signature
          i = parsed.endIndex
          continue
        }
      }

      i += 1
    }

    return MetalDocumentIndex(symbols: symbols, functionSignatures: functionSignatures)
  }

  private struct ParsedSymbol {
    let symbol: MetalDocumentSymbolNode
    let endIndex: Int
  }

  private struct ParsedFunction {
    let symbol: MetalDocumentSymbolNode
    let signature: MetalFunctionSignature
    let endIndex: Int
  }

  private func parseStruct(
    from structKeywordIndex: Int,
    maskedChars: [Character],
    sourceChars: [Character],
    lineMap: LineMap
  ) -> ParsedSymbol? {
    var i = structKeywordIndex + "struct".count
    i = skipWhitespace(maskedChars, from: i)

    guard i < maskedChars.count, isIdentifierStart(maskedChars[i]) else { return nil }

    let nameStart = i
    var nameEnd = i + 1
    while nameEnd < maskedChars.count && isIdentifierContinue(maskedChars[nameEnd]) {
      nameEnd += 1
    }
    let name = String(maskedChars[nameStart..<nameEnd])

    var search = nameEnd
    while search < maskedChars.count && maskedChars[search] != "{" {
      if maskedChars[search] == ";" || maskedChars[search] == "\n" {
        return nil
      }
      search += 1
    }

    guard search < maskedChars.count, maskedChars[search] == "{" else { return nil }

    let openBrace = search
    guard let closeBrace = findMatchingBrace(from: openBrace, maskedChars: maskedChars) else {
      return nil
    }

    var endIndex = closeBrace + 1
    endIndex = skipWhitespace(maskedChars, from: endIndex)
    if endIndex < maskedChars.count, maskedChars[endIndex] == ";" {
      endIndex += 1
    }

    let startPos = lineMap.position(at: structKeywordIndex)
    let endPos = lineMap.position(at: endIndex)

    let selectionStartPos = lineMap.position(at: nameStart)
    let selectionEndPos = lineMap.position(at: nameEnd)

    let children = parseStructFields(
      maskedChars: maskedChars,
      sourceChars: sourceChars,
      bodyStart: openBrace + 1,
      bodyEnd: closeBrace,
      lineMap: lineMap
    )

    let symbol = MetalDocumentSymbolNode(
      name: name,
      kind: .struct,
      range: MetalSourceRange(start: startPos, end: endPos),
      selectionRange: MetalSourceRange(start: selectionStartPos, end: selectionEndPos),
      detail: "struct",
      children: children
    )

    return ParsedSymbol(symbol: symbol, endIndex: endIndex)
  }

  private func parseStructFields(
    maskedChars: [Character],
    sourceChars: [Character],
    bodyStart: Int,
    bodyEnd: Int,
    lineMap: LineMap
  ) -> [MetalDocumentSymbolNode] {
    guard bodyStart < bodyEnd else { return [] }

    let bodyStartLine = lineMap.position(at: bodyStart).line

    let maskedBody = String(maskedChars[bodyStart..<bodyEnd])
    let sourceBody = String(sourceChars[bodyStart..<bodyEnd])

    let maskedLines = maskedBody.split(separator: "\n", omittingEmptySubsequences: false)
    let sourceLines = sourceBody.split(separator: "\n", omittingEmptySubsequences: false)

    var children: [MetalDocumentSymbolNode] = []

    for (lineOffset, maskedLineSub) in maskedLines.enumerated() {
      guard lineOffset < sourceLines.count else { continue }

      let maskedLine = String(maskedLineSub)
      let trimmed = maskedLine.trimmingCharacters(in: .whitespacesAndNewlines)
      if trimmed.isEmpty { continue }
      if trimmed.hasPrefix("#") { continue }
      if trimmed.contains("(") { continue }
      guard trimmed.contains(";") else { continue }

      let statement = trimmed.split(separator: ";", maxSplits: 1, omittingEmptySubsequences: true).first
      guard var statementText = statement.map(String.init) else { continue }

      while let range = statementText.range(of: "[[") {
        guard let endRange = statementText.range(of: "]]", range: range.upperBound..<statementText.endIndex) else {
          break
        }
        statementText.replaceSubrange(range.lowerBound..<endRange.upperBound, with: "")
      }

      if let bracketRange = statementText.range(of: "[") {
        statementText = String(statementText[..<bracketRange.lowerBound])
      }

      let tokens = statementText.split(whereSeparator: { $0 == " " || $0 == "\t" })
      guard let last = tokens.last else { continue }

      let rawName = String(last).trimmingCharacters(in: CharacterSet(charactersIn: "*&"))
      guard !rawName.isEmpty else { continue }
      guard isValidIdentifier(rawName) else { continue }

      let sourceLine = String(sourceLines[lineOffset])
      guard let foundRange = sourceLine.range(of: rawName) else { continue }

      let lineNumber = bodyStartLine + lineOffset
      let column = sourceLine.distance(from: sourceLine.startIndex, to: foundRange.lowerBound)

      let startPos = MetalSourcePosition(line: lineNumber, column: column)
      let endPos = MetalSourcePosition(line: lineNumber, column: column + rawName.count)

      children.append(
        MetalDocumentSymbolNode(
          name: rawName,
          kind: .variable,
          range: MetalSourceRange(start: startPos, end: endPos),
          selectionRange: MetalSourceRange(start: startPos, end: endPos),
          detail: nil,
          children: []
        )
      )
    }

    return children
  }

  private func parseFunctionDeclaration(
    openParenIndex: Int,
    maskedChars: [Character],
    sourceChars: [Character],
    lineMap: LineMap
  ) -> ParsedFunction? {
    let nameInfo = extractIdentifierBefore(index: openParenIndex, chars: maskedChars)
    guard let nameInfo else { return nil }

    let rawName = nameInfo.name
    if rawName == "if" || rawName == "for" || rawName == "while" || rawName == "switch" {
      return nil
    }

    let precedingChar = previousNonWhitespaceChar(before: nameInfo.startIndex, chars: maskedChars)
    if let precedingChar, ["=", ",", "(", "[", "{", "."].contains(precedingChar) {
      return nil
    }

    let prevWord = extractIdentifierBefore(index: nameInfo.startIndex, chars: maskedChars)?.name
    if let prevWord, ["return", "case", "sizeof"].contains(prevWord) {
      return nil
    }

    guard let closeParen = findMatchingParen(from: openParenIndex, maskedChars: maskedChars) else {
      return nil
    }

    var search = closeParen + 1
    search = skipWhitespace(maskedChars, from: search)

    search = skipAttributeBlocks(maskedChars, from: search)
    search = skipWhitespace(maskedChars, from: search)

    var rangeEnd: Int
    if search < maskedChars.count, maskedChars[search] == "{" {
      guard let closeBrace = findMatchingBrace(from: search, maskedChars: maskedChars) else {
        return nil
      }
      rangeEnd = closeBrace + 1
    } else if let semi = findNextStatementTerminator(from: search, maskedChars: maskedChars) {
      if maskedChars[semi] != ";" {
        return nil
      }
      rangeEnd = semi + 1
    } else {
      return nil
    }

    let lineStart = findLineStart(from: nameInfo.startIndex, chars: maskedChars)

    let signatureRaw = String(sourceChars[lineStart..<(closeParen + 1)])
    let signatureLabel = normalizeWhitespace(signatureRaw)

    let functionKind = inferFunctionKind(signatureLabel)

    let startPos = lineMap.position(at: lineStart)
    let endPos = lineMap.position(at: rangeEnd)

    let selectionStartPos = lineMap.position(at: nameInfo.startIndex)
    let selectionEndPos = lineMap.position(at: nameInfo.endIndex)

    let lspName = normalizeFunctionName(rawName)

    let symbol = MetalDocumentSymbolNode(
      name: lspName,
      kind: functionKind,
      range: MetalSourceRange(start: startPos, end: endPos),
      selectionRange: MetalSourceRange(start: selectionStartPos, end: selectionEndPos),
      detail: signatureLabel,
      children: []
    )

    let params = parseParameters(fromSignature: signatureLabel)
    let signature = MetalFunctionSignature(name: lspName, label: signatureLabel, parameters: params)

    return ParsedFunction(symbol: symbol, signature: signature, endIndex: rangeEnd)
  }

  private func skipAttributeBlocks(_ chars: [Character], from index: Int) -> Int {
    var i = index
    while i + 1 < chars.count, chars[i] == "[", chars[i + 1] == "[" {
      i += 2
      while i + 1 < chars.count {
        if chars[i] == "]", chars[i + 1] == "]" {
          i += 2
          break
        }
        i += 1
      }
      i = skipWhitespace(chars, from: i)
    }
    return i
  }

  private func inferFunctionKind(_ signature: String) -> MetalSymbolFinder.SymbolKind {
    let trimmed = signature.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.hasPrefix("kernel ") { return .kernel }
    if trimmed.hasPrefix("vertex ") { return .vertex }
    if trimmed.hasPrefix("fragment ") { return .fragment }
    return .function
  }

  private func normalizeFunctionName(_ raw: String) -> String {
    if raw.contains("::") {
      return raw.split(separator: ":").last.map(String.init) ?? raw
    }
    return raw
  }

  private func parseParameters(fromSignature signature: String) -> [String] {
    guard let open = signature.firstIndex(of: "("), let close = signature.lastIndex(of: ")"), open < close else {
      return []
    }

    let inside = signature[signature.index(after: open)..<close]
    var params: [String] = []
    var current = ""

    var parenDepth = 0
    var angleDepth = 0
    var bracketDepth = 0

    for ch in inside {
      if ch == "," && parenDepth == 0 && angleDepth == 0 && bracketDepth == 0 {
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
          params.append(trimmed)
        }
        current = ""
        continue
      }

      if ch == "(" { parenDepth += 1 }
      if ch == ")" { parenDepth = max(0, parenDepth - 1) }
      if ch == "<" { angleDepth += 1 }
      if ch == ">" { angleDepth = max(0, angleDepth - 1) }
      if ch == "[" { bracketDepth += 1 }
      if ch == "]" { bracketDepth = max(0, bracketDepth - 1) }

      current.append(ch)
    }

    let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
    if !trimmed.isEmpty {
      params.append(trimmed)
    }

    return params
  }

  private func normalizeWhitespace(_ input: String) -> String {
    var result = ""
    result.reserveCapacity(input.count)

    var wasWhitespace = false
    for ch in input {
      if ch == "\n" || ch == "\t" || ch == "\r" || ch == " " {
        if !wasWhitespace {
          result.append(" ")
          wasWhitespace = true
        }
      } else {
        result.append(ch)
        wasWhitespace = false
      }
    }

    return result.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func findNextStatementTerminator(from index: Int, maskedChars: [Character]) -> Int? {
    var i = index
    while i < maskedChars.count {
      let c = maskedChars[i]
      if c == ";" || c == "{" || c == "\n" {
        return i
      }
      i += 1
    }
    return nil
  }

  private func findLineStart(from index: Int, chars: [Character]) -> Int {
    var i = index
    while i > 0 {
      if chars[i - 1] == "\n" {
        return i
      }
      i -= 1
    }
    return 0
  }

  private func skipWhitespace(_ chars: [Character], from index: Int) -> Int {
    var i = index
    while i < chars.count {
      let c = chars[i]
      if c != " " && c != "\t" && c != "\n" && c != "\r" {
        break
      }
      i += 1
    }
    return i
  }

  private func extractIdentifierBefore(index: Int, chars: [Character]) -> (name: String, startIndex: Int, endIndex: Int)? {
    var i = index - 1
    while i >= 0 {
      let c = chars[i]
      if c == " " || c == "\t" || c == "\n" || c == "\r" {
        i -= 1
        continue
      }
      break
    }
    if i < 0 { return nil }

    guard isIdentifierContinue(chars[i]) else { return nil }

    let end = i + 1
    var start = i
    while start > 0 && isIdentifierContinue(chars[start - 1]) {
      start -= 1
    }

    let name = String(chars[start..<end])
    return (name: name, startIndex: start, endIndex: end)
  }

  private func previousNonWhitespaceChar(before index: Int, chars: [Character]) -> Character? {
    var i = index - 1
    while i >= 0 {
      let c = chars[i]
      if c == " " || c == "\t" || c == "\n" || c == "\r" {
        i -= 1
        continue
      }
      return c
    }
    return nil
  }

  private func findMatchingParen(from openParen: Int, maskedChars: [Character]) -> Int? {
    var depth = 0
    var i = openParen
    while i < maskedChars.count {
      let c = maskedChars[i]
      if c == "(" { depth += 1 }
      if c == ")" {
        depth -= 1
        if depth == 0 {
          return i
        }
      }
      i += 1
    }
    return nil
  }

  private func findMatchingBrace(from openBrace: Int, maskedChars: [Character]) -> Int? {
    var depth = 0
    var i = openBrace
    while i < maskedChars.count {
      let c = maskedChars[i]
      if c == "{" { depth += 1 }
      if c == "}" {
        depth -= 1
        if depth == 0 {
          return i
        }
      }
      i += 1
    }
    return nil
  }

  private func isIdentifierStart(_ c: Character) -> Bool {
    guard let scalar = c.unicodeScalars.first else { return false }
    return CharacterSet.letters.contains(scalar) || c == "_"
  }

  private func isIdentifierContinue(_ c: Character) -> Bool {
    guard let scalar = c.unicodeScalars.first else { return false }
    return CharacterSet.alphanumerics.contains(scalar) || c == "_" || c == ":"
  }

  private func isValidIdentifier(_ name: String) -> Bool {
    guard let first = name.first, isIdentifierStart(first) else { return false }
    return name.allSatisfy { isIdentifierContinue($0) }
  }

  private struct LineMap {
    private let lineStarts: [Int]
    private let textLength: Int

    init(chars: [Character]) {
      self.textLength = chars.count

      var starts: [Int] = [0]
      starts.reserveCapacity(256)

      for (i, c) in chars.enumerated() {
        if c == "\n" {
          starts.append(i + 1)
        }
      }

      self.lineStarts = starts
    }

    func position(at index: Int) -> MetalSourcePosition {
      let clamped = max(0, min(index, textLength))

      var low = 0
      var high = lineStarts.count - 1
      while low <= high {
        let mid = (low + high) / 2
        let value = lineStarts[mid]
        if value == clamped {
          return MetalSourcePosition(line: mid, column: 0)
        }
        if value < clamped {
          low = mid + 1
        } else {
          high = mid - 1
        }
      }

      let line = max(0, min(high, lineStarts.count - 1))
      let column = clamped - lineStarts[line]
      return MetalSourcePosition(line: line, column: column)
    }
  }

  private enum SourceMasker {
    static func mask(_ source: String) -> String {
      let chars = Array(source)
      var result = Array(repeating: Character(" "), count: chars.count)

      enum State {
        case code
        case lineComment
        case blockComment
        case string
      }

      var state: State = .code
      var i = 0
      while i < chars.count {
        let c = chars[i]
        let next = (i + 1 < chars.count) ? chars[i + 1] : nil

        switch state {
        case .code:
          if c == "/", next == "/" {
            result[i] = " "
            result[i + 1] = " "
            state = .lineComment
            i += 2
            continue
          }
          if c == "/", next == "*" {
            result[i] = " "
            result[i + 1] = " "
            state = .blockComment
            i += 2
            continue
          }
          if c == "\"" {
            result[i] = "\""
            state = .string
            i += 1
            continue
          }

          result[i] = c
          i += 1

        case .lineComment:
          if c == "\n" {
            result[i] = "\n"
            state = .code
          } else {
            result[i] = " "
          }
          i += 1

        case .blockComment:
          if c == "\n" {
            result[i] = "\n"
            i += 1
            continue
          }
          if c == "*", next == "/" {
            result[i] = " "
            result[i + 1] = " "
            state = .code
            i += 2
            continue
          }

          result[i] = " "
          i += 1

        case .string:
          if c == "\\", next != nil {
            result[i] = " "
            if chars.indices.contains(i + 1) {
              result[i + 1] = " "
            }
            i += 2
            continue
          }

          if c == "\"" {
            result[i] = "\""
            state = .code
            i += 1
            continue
          }

          if c == "\n" {
            result[i] = "\n"
            state = .code
            i += 1
            continue
          }

          result[i] = " "
          i += 1
        }
      }

      return String(result)
    }
  }
}
