import Foundation
import MetalCore

/// Main LSP server implementation
public class LanguageServer {
  private let transport: MessageTransport
  private let documentManager = DocumentManager()
  private let metalCompiler = MetalCompiler()
  private let symbolFinder = MetalSymbolFinder()
  private let formatter = MetalFormatter()
  private let lexer = MetalLexer()
  private let documentIndexer = MetalDocumentIndexer()
  private let verbose: Bool
  private var documentation: MetalDocumentation?

  private struct CachedDocumentAnalysis {
    let version: Int
    let textHash: UInt64
    let index: MetalDocumentIndex
    let tokens: [MetalToken]
  }

  private struct CachedDiagnostics {
    let cacheKey: UInt64
    let diagnosticsByURI: [String: [Diagnostic]]
  }

  private var analysisCache: [String: CachedDocumentAnalysis] = [:]
  private var diagnosticsCache: [String: CachedDiagnostics] = [:]
  private var builtinCompletionItems: [CompletionItem]?

  private struct CachedWorkspaceFile {
    let modificationTime: TimeInterval
    let size: UInt64
    let source: String
  }

  private var workspaceRootURL: URL?
  private var workspaceFileURLCache: [URL] = []
  private var workspaceFileURLCacheRoot: URL?
  private var workspaceFileCache: [String: CachedWorkspaceFile] = [:]

  private let tokenTypes = [
    "namespace", "type", "class", "enum", "interface", "struct", "typeParameter", "parameter", "variable", "property", "enumMember", "event", "function", "method", "macro", "keyword", "modifier", "comment", "string", "number", "regexp", "operator"
  ]
  private let tokenModifiers = ["declaration", "definition", "readonly", "static", "deprecated", "abstract", "async", "modification", "documentation", "defaultLibrary"]

  private var isInitialized = false
  private var isShuttingDown = false

  public init(verbose: Bool = false, logMessages: Bool = false) {
    self.verbose = verbose
    self.transport = MessageTransport(logMessages: logMessages)

    // Load builtin documentation (compiled into binary)
    self.documentation = MetalDocumentation()
    log("Loaded Metal builtin documentation")
  }

  public func run() throws {
    log("Metal LSP Server starting...")

    while !isShuttingDown {
      guard let messageData = try transport.readMessage() else {
        log("No more messages, exiting")
        break
      }

      try handleMessage(messageData)
    }

    log("Metal LSP Server stopped")
  }

  // MARK: - Message Handling

  private func handleMessage(_ data: Data) throws {
    let decoder = JSONDecoder()

    // Try to decode as request first
    if let request = try? decoder.decode(JSONRPCRequest.self, from: data) {
      try handleRequest(request)
      return
    }

    // Try notification
    if let notification = try? decoder.decode(JSONRPCNotification.self, from: data) {
      try handleNotification(notification)
      return
    }

    // Log what we couldn't decode
    if let jsonString = String(data: data, encoding: .utf8) {
      log("Failed to decode message: \(jsonString)")
    } else {
      log("Failed to decode message (invalid UTF-8)")
    }
  }

  private func handleRequest(_ request: JSONRPCRequest) throws {
    log("Request: \(request.method)")

    do {
      switch request.method {
      case "initialize":
        let params = try request.params?.decode(InitializeParams.self)
        let result = try handleInitialize(params: params)
        try sendResponse(id: request.id, result: result)

      case "shutdown":
        handleShutdown()
        try sendResponse(id: request.id, result: JSONValue.null)

      case "textDocument/completion":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        let params = try request.params?.decode(CompletionParams.self)
        let result = try handleCompletion(params: params)
        try sendResponse(id: request.id, result: result)

      case "textDocument/hover":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        let params = try request.params?.decode(HoverParams.self)
        let result = try handleHover(params: params)
        try sendResponse(id: request.id, result: result)

      case "textDocument/definition":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        let params = try request.params?.decode(DefinitionParams.self)
        let result = try handleDefinition(params: params)
        try sendResponse(id: request.id, result: result)

      case "textDocument/references":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        let params = try request.params?.decode(ReferenceParams.self)
        let result = try handleReferences(params: params)
        try sendResponse(id: request.id, result: result)

      case "textDocument/formatting":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        let params = try request.params?.decode(FormattingParams.self)
        let result = try handleFormatting(params: params)
        try sendResponse(id: request.id, result: result)

      case "textDocument/semanticTokens/full":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        let params = try request.params?.decode(SemanticTokensParams.self)
        let result = try handleSemanticTokens(params: params)
        try sendResponse(id: request.id, result: result)

      case "textDocument/semanticTokens/full/delta":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        // For now, return full tokens (delta not implemented yet)
        // JetBrains may request this but will handle full response
        let params = try request.params?.decode(SemanticTokensParams.self)
        let result = try handleSemanticTokens(params: params)
        try sendResponse(id: request.id, result: result)

      case "textDocument/semanticTokens/range":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        // Range-based semantic tokens - return tokens within the requested range
        let params = try request.params?.decode(SemanticTokensRangeParams.self)
        let result = try handleSemanticTokensRange(params: params)
        try sendResponse(id: request.id, result: result)

      case "workspace/semanticTokens/refresh":
        // Server-initiated refresh notification (no response needed)
        log("Semantic tokens refresh requested by client")
        // Could trigger re-tokenization here if needed
        // For now, just acknowledge with empty response
        try sendResponse(id: request.id, result: JSONValue.null)

      case "textDocument/signatureHelp":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        let params = try request.params?.decode(SignatureHelpParams.self)
        let result = try handleSignatureHelp(params: params)
        try sendResponse(id: request.id, result: result)

      case "textDocument/documentSymbol":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        let params = try request.params?.decode(DocumentSymbolParams.self)
        let result = try handleDocumentSymbols(params: params)
        try sendResponse(id: request.id, result: result)

      case "textDocument/documentHighlight":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        let params = try request.params?.decode(DocumentHighlightParams.self)
        let result = try handleDocumentHighlight(params: params)
        try sendResponse(id: request.id, result: result)

      case "textDocument/documentLink":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        let params = try request.params?.decode(DocumentLinkParams.self)
        let result = try handleDocumentLink(params: params)
        try sendResponse(id: request.id, result: result)

      case "textDocument/foldingRange":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        let params = try request.params?.decode(FoldingRangeParams.self)
        let result = try handleFoldingRange(params: params)
        try sendResponse(id: request.id, result: result)

      case "textDocument/typeDefinition":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        let params = try request.params?.decode(TypeDefinitionParams.self)
        let result = try handleTypeDefinition(params: params)
        try sendResponse(id: request.id, result: result)

      case "textDocument/documentColor":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        let params = try request.params?.decode(DocumentColorParams.self)
        let result = try handleDocumentColor(params: params)
        try sendResponse(id: request.id, result: result)

      case "textDocument/colorPresentation":
        guard isInitialized else {
          try sendError(
            id: request.id, code: .serverNotInitialized,
            message: "Server not initialized")
          return
        }
        let params = try request.params?.decode(ColorPresentationParams.self)
        let result = try handleColorPresentation(params: params)
        try sendResponse(id: request.id, result: result)

      default:
        try sendError(
          id: request.id, code: .methodNotFound,
          message: "Method not found: \(request.method)")
      }
    } catch {
      try sendError(id: request.id, code: .internalError, message: error.localizedDescription)
    }
  }

  private func handleNotification(_ notification: JSONRPCNotification) throws {
    log("Notification: \(notification.method)")

    switch notification.method {
    case "initialized":
      handleInitialized()

    case "exit":
      handleExit()

    case "textDocument/didOpen":
      guard isInitialized else { return }
      let params = try notification.params?.decode(DidOpenTextDocumentParams.self)
      try handleDidOpen(params: params)

    case "textDocument/didChange":
      guard isInitialized else { return }
      let params = try notification.params?.decode(DidChangeTextDocumentParams.self)
      try handleDidChange(params: params)

    case "textDocument/didSave":
      guard isInitialized else { return }
      let params = try notification.params?.decode(DidSaveTextDocumentParams.self)
      try handleDidSave(params: params)

    case "textDocument/didClose":
      guard isInitialized else { return }
      let params = try notification.params?.decode(DidCloseTextDocumentParams.self)
      try handleDidClose(params: params)

    default:
      log("Unknown notification: \(notification.method)")
    }
  }

  // MARK: - LSP Handlers

  private func handleInitialize(params: InitializeParams?) throws -> JSONValue {
    log("Initializing server...")

    workspaceRootURL = resolveWorkspaceRootURL(from: params)
    workspaceFileURLCache = []
    workspaceFileURLCacheRoot = workspaceRootURL

    let capabilities = ServerCapabilities(
      textDocumentSync: TextDocumentSyncOptions(
        openClose: true,
        change: 2
      ),
      completionProvider: CompletionOptions(
        triggerCharacters: [".", "[", "(", " ", ","]
      ),
      signatureHelpProvider: SignatureHelpOptions(triggerCharacters: ["(", ","]),
      semanticTokensProvider: SemanticTokensOptions(
        legend: SemanticTokensLegend(tokenTypes: tokenTypes, tokenModifiers: tokenModifiers),
        full: true,
        range: true
      ),
      documentHighlightProvider: true,
      documentLinkProvider: DocumentLinkOptions(resolveProvider: false),
      foldingRangeProvider: true,
      typeDefinitionProvider: true,
      colorProvider: true
    )

    let result = InitializeResult(
      capabilities: capabilities,
      serverInfo: InitializeResult.ServerInfo(
        name: "metal-lsp",
        version: Version.current
      )
    )

    return try JSONValue.from(result)
  }

  private func handleInitialized() {
    isInitialized = true
    log("Server initialized")
  }

  private func handleShutdown() {
    log("Shutting down...")
    isShuttingDown = true
  }

  private func handleExit() {
    log("Exiting...")
    exit(0)
  }

  private func handleDidOpen(params: DidOpenTextDocumentParams?) throws {
    guard let params = params else { return }

    log("Document opened: \(params.textDocument.uri)")

    documentManager.openDocument(
      uri: params.textDocument.uri,
      text: params.textDocument.text,
      version: params.textDocument.version
    )

    // Validate document
    try validateDocument(uri: params.textDocument.uri)
  }

  private func handleDidChange(params: DidChangeTextDocumentParams?) throws {
    guard let params = params else { return }

    log("Document changed: \(params.textDocument.uri)")

    documentManager.updateDocument(
      uri: params.textDocument.uri,
      changes: params.contentChanges,
      version: params.textDocument.version
    )

    analysisCache.removeValue(forKey: params.textDocument.uri)
  }

  private func handleDidSave(params: DidSaveTextDocumentParams?) throws {
    guard let params = params else { return }

    log("Document saved: \(params.textDocument.uri)")

    // Validate on save
    try validateDocument(uri: params.textDocument.uri)
  }

  private func handleDidClose(params: DidCloseTextDocumentParams?) throws {
    guard let params = params else { return }

    log("Document closed: \(params.textDocument.uri)")

    analysisCache.removeValue(forKey: params.textDocument.uri)
    diagnosticsCache.removeValue(forKey: params.textDocument.uri)
    documentManager.closeDocument(uri: params.textDocument.uri)
  }

  private func handleCompletion(params: CompletionParams?) throws -> JSONValue {
    guard let params = params else {
      return try JSONValue.from(CompletionList(isIncomplete: false, items: []))
    }

    log("Completion requested at \(params.position.line):\(params.position.character)")

    let document = documentManager.getDocument(uri: params.textDocument.uri)

    let filterContext: CompletionFilterContext
    if let document {
      filterContext = completionFilterContext(in: document, at: params.position)
    } else {
      filterContext = CompletionFilterContext(prefix: nil, restrictToAttributes: false)
    }

    var items: [CompletionItem] = []

    if let document, let analysis = getAnalysis(for: params.textDocument.uri, document: document) {
      items += completionItems(from: analysis.index)
    }

    items += getBuiltinCompletionItems()

    if filterContext.restrictToAttributes {
      items = items.filter { $0.label.hasPrefix("[[") }
    }

    if let prefix = filterContext.prefix, !prefix.isEmpty {
      let lowered = prefix.lowercased()
      items = items.filter { $0.label.lowercased().hasPrefix(lowered) }
    }

    var deduped: [CompletionItem] = []
    deduped.reserveCapacity(items.count)
    var seen = Set<String>()

    for item in items {
      if seen.contains(item.label) {
        continue
      }
      seen.insert(item.label)
      deduped.append(item)
    }

    let result = CompletionList(isIncomplete: false, items: deduped)
    return try JSONValue.from(result)
  }

  private func handleHover(params: HoverParams?) throws -> JSONValue {
    guard let params = params else {
      return JSONValue.null
    }

    log("Hover requested at \(params.position.line):\(params.position.character)")

    // Get document text
    guard let document = documentManager.getDocument(uri: params.textDocument.uri) else {
      log("Document not found: \(params.textDocument.uri)")
      return JSONValue.null
    }

    // Extract word at position
    guard let word = extractWordAtPosition(text: document.text, position: params.position) else {
      log("No word found at position")
      return JSONValue.null
    }

    log("Hovering over word: \(word)")

    // Try to find documentation from the JSON documentation first
    if let documentation = documentation,
      let entry = documentation.lookup(word)
    {
      log("Found JSON documentation for: \(word)")

      let hover = Hover(
        contents: MarkupContent(kind: .markdown, value: entry.markdownDocumentation)
      )

      return try JSONValue.from(hover)
    }

    // Fallback to hardcoded completions (keywords, attributes, etc.)
    let builtins = MetalBuiltins.getHardcodedCompletions()
    guard let builtin = builtins.first(where: { $0.label == word }) else {
      log("No documentation found for word: \(word)")
      return JSONValue.null
    }

    // Format hover content from builtins
    var markdown = ""

    if let detail = builtin.detail {
      markdown += "```metal\n\(detail)\n```\n"
    } else {
      markdown += "```metal\n\(builtin.label)\n```\n"
    }

    if let documentation = builtin.documentation {
      markdown += "\n---\n\n\(documentation)"
    }

    let hover = Hover(
      contents: MarkupContent(kind: .markdown, value: markdown)
    )

    return try JSONValue.from(hover)
  }

  private func handleDefinition(params: DefinitionParams?) throws -> JSONValue {
    guard let params = params else {
      return JSONValue.null
    }

    log("Definition requested at \(params.position.line):\(params.position.character)")

    guard let document = documentManager.getDocument(uri: params.textDocument.uri) else {
      log("Document not found: \(params.textDocument.uri)")
      return JSONValue.null
    }

    guard let word = extractWordAtPosition(text: document.text, position: params.position) else {
      log("No word found at position")
      return JSONValue.null
    }

    log("Looking for definition of: \(word)")

    if let includeLocation = resolveIncludeLocation(in: document, at: params.position) {
      return try JSONValue.from(includeLocation)
    }

    if let location = findBestDefinitionLocation(name: word, primaryURI: params.textDocument.uri, primarySource: document.text) {
      return try JSONValue.from(location)
    }

    log("No declarations found for: \(word)")
    return JSONValue.null
  }

  private func handleReferences(params: ReferenceParams?) throws -> JSONValue {
    guard let params = params else {
      return try JSONValue.from(ReferenceResult())
    }

    log("References requested at \(params.position.line):\(params.position.character)")

    guard let document = documentManager.getDocument(uri: params.textDocument.uri) else {
      log("Document not found: \(params.textDocument.uri)")
      return try JSONValue.from(ReferenceResult())
    }

    guard let word = extractWordAtPosition(text: document.text, position: params.position) else {
      log("No word found at position")
      return try JSONValue.from(ReferenceResult())
    }

    log("Finding references to: \(word)")

    let locations = findReferencesInWorkspace(
      name: word,
      includeDeclaration: params.context.includeDeclaration,
      primaryURI: params.textDocument.uri,
      primarySource: document.text
    )

    log("Found \(locations.count) references")
    return try JSONValue.from(locations)
  }

  private func handleFormatting(params: FormattingParams?) throws -> JSONValue {
    guard let params = params else {
      return try JSONValue.from(FormattingResult())
    }

    log("Formatting requested for \(params.textDocument.uri)")

    guard let document = documentManager.getDocument(uri: params.textDocument.uri) else {
      log("Document not found: \(params.textDocument.uri)")
      return try JSONValue.from(FormattingResult())
    }

    let originalText = document.text
    let formattedText = formatter.format(
      source: originalText,
      tabSize: params.options.tabSize,
      insertSpaces: params.options.insertSpaces
    )

    // If formatting succeeded and produced different output, return a single edit
    if formattedText != originalText {
      let lines = originalText.components(separatedBy: .newlines)
      let endLine = lines.count - 1
      let lastLine = lines.isEmpty ? "" : lines[endLine]

      let edit = TextEdit(
        range: Range(
          start: Position(line: 0, character: 0),
          end: Position(line: endLine, character: lastLine.count)
        ),
        newText: formattedText
      )

      log("Formatting produced changes")
      return try JSONValue.from([edit])
    }

    log("No formatting changes needed")
    return try JSONValue.from(FormattingResult())
  }

  private func handleSemanticTokens(params: SemanticTokensParams?) throws -> JSONValue {
    guard let params = params else {
      return try JSONValue.from(SemanticTokens(data: []))
    }

    log("Semantic tokens requested for \(params.textDocument.uri)")

    guard let document = documentManager.getDocument(uri: params.textDocument.uri) else {
      return try JSONValue.from(SemanticTokens(data: []))
    }

    let tokens = lexer.tokenize(document.text)

    // Debug: Log first few tokens
    if verbose && !tokens.isEmpty {
      let preview = tokens.prefix(10).map { "\($0.type)@[\($0.line):\($0.column)]" }.joined(separator: ", ")
      log("Token preview: \(preview)")
    }

    let encodedData = encodeTokens(tokens)

    log("Returning \(encodedData.count / 5) tokens, data length: \(encodedData.count)")

    return try JSONValue.from(SemanticTokens(data: encodedData))
  }

  private func handleSemanticTokensRange(params: SemanticTokensRangeParams?) throws -> JSONValue {
    guard let params = params else {
      return try JSONValue.from(SemanticTokens(data: []))
    }

    log("Semantic tokens range requested for \(params.textDocument.uri) at \(params.range)")

    guard let document = documentManager.getDocument(uri: params.textDocument.uri) else {
      return try JSONValue.from(SemanticTokens(data: []))
    }

    let allTokens = lexer.tokenize(document.text)

    // Filter tokens within the requested range
    let filteredTokens = allTokens.filter { token in
      // Check if token overlaps with the requested range
      if token.line < params.range.start.line {
        return false
      }
      if token.line > params.range.end.line {
        return false
      }
      if token.line == params.range.start.line && token.column < params.range.start.character {
        return false
      }
      if token.line == params.range.end.line && token.column + token.length > params.range.end.character {
        return false
      }
      return true
    }

    let encodedData = encodeTokens(filteredTokens)

    log("Returning \(filteredTokens.count) tokens in range, data length: \(encodedData.count)")

    return try JSONValue.from(SemanticTokens(data: encodedData))
  }

  private func handleSignatureHelp(params: SignatureHelpParams?) throws -> JSONValue {
    guard let params = params else {
      return try JSONValue.from(SignatureHelp(signatures: [], activeSignature: nil, activeParameter: nil))
    }

    log("Signature help requested at \(params.position.line):\(params.position.character)")

    guard let document = documentManager.getDocument(uri: params.textDocument.uri) else {
      return try JSONValue.from(SignatureHelp(signatures: [], activeSignature: nil, activeParameter: nil))
    }

    guard let analysis = getAnalysis(for: params.textDocument.uri, document: document) else {
      return try JSONValue.from(SignatureHelp(signatures: [], activeSignature: nil, activeParameter: nil))
    }

    if isPositionInNonCodeToken(position: params.position, tokens: analysis.tokens) {
      return try JSONValue.from(SignatureHelp(signatures: [], activeSignature: nil, activeParameter: nil))
    }

    guard let call = extractCallContext(in: document, at: params.position) else {
      return try JSONValue.from(SignatureHelp(signatures: [], activeSignature: nil, activeParameter: nil))
    }

    let functionName = call.functionName

    let signature: MetalFunctionSignature?
    if let documentation = documentation, let entry = documentation.lookup(functionName) {
      signature = MetalFunctionSignature(
        name: entry.symbol,
        label: entry.signature,
        parameters: parseParameters(fromSignatureLabel: entry.signature)
      )
    } else {
      signature = analysis.index.functionSignatures[functionName]
    }

    guard let signature else {
      return try JSONValue.from(SignatureHelp(signatures: [], activeSignature: nil, activeParameter: nil))
    }

    let signatureInformation = SignatureInformation(
      label: signature.label,
      documentation: nil,
      parameters: signature.parameters.map { ParameterInformation(label: $0) }
    )

    let help = SignatureHelp(
      signatures: [signatureInformation],
      activeSignature: 0,
      activeParameter: call.activeParameter
    )

    return try JSONValue.from(help)
  }

  private func handleDocumentSymbols(params: DocumentSymbolParams?) throws -> JSONValue {
    guard let params = params else {
      return try JSONValue.from(DocumentSymbolResult())
    }

    log("Document symbols requested for \(params.textDocument.uri)")

    guard let document = documentManager.getDocument(uri: params.textDocument.uri) else {
      return try JSONValue.from(DocumentSymbolResult())
    }

    guard let analysis = getAnalysis(for: params.textDocument.uri, document: document) else {
      return try JSONValue.from(DocumentSymbolResult())
    }

    let symbols = analysis.index.symbols.map { documentSymbol(from: $0) }
    return try JSONValue.from(symbols)
  }

  private func handleDocumentHighlight(params: DocumentHighlightParams?) throws -> JSONValue {
    guard let params = params else {
      return try JSONValue.from(DocumentHighlightResult())
    }

    log("Document highlight requested at \(params.position.line):\(params.position.character)")

    guard let document = documentManager.getDocument(uri: params.textDocument.uri) else {
      return try JSONValue.from(DocumentHighlightResult())
    }

    guard let word = extractWordAtPosition(text: document.text, position: params.position) else {
      return try JSONValue.from(DocumentHighlightResult())
    }

    log("Highlighting occurrences of: \(word)")

    // Find all occurrences in current document
    var highlights: [DocumentHighlight] = []
    let lines = document.text.components(separatedBy: .newlines)

    for (lineIndex, line) in lines.enumerated() {
      var searchRange = line.startIndex..<line.endIndex
      while let range = line.range(of: word, options: [], range: searchRange) {
        let column = line.distance(from: line.startIndex, to: range.lowerBound)

        // Verify word boundaries
        let beforeIndex = range.lowerBound
        let afterIndex = range.upperBound

        let beforeChar = beforeIndex > line.startIndex ? line[line.index(before: beforeIndex)] : nil
        let afterChar = afterIndex < line.endIndex ? line[afterIndex] : nil

        let wordChars = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        let isWordBoundary =
          (beforeChar == nil || String(beforeChar!).rangeOfCharacter(from: wordChars) == nil) &&
          (afterChar == nil || String(afterChar!).rangeOfCharacter(from: wordChars) == nil)

        if isWordBoundary {
          highlights.append(
            DocumentHighlight(
              range: Range(
                start: Position(line: lineIndex, character: column),
                end: Position(line: lineIndex, character: column + word.count)
              ),
              kind: .read
            )
          )
        }

        searchRange = range.upperBound..<line.endIndex
      }
    }

    return try JSONValue.from(highlights)
  }

  private func handleDocumentLink(params: DocumentLinkParams?) throws -> JSONValue {
    guard let params = params else {
      return try JSONValue.from(DocumentLinkResult())
    }

    log("Document links requested for \(params.textDocument.uri)")

    guard let document = documentManager.getDocument(uri: params.textDocument.uri) else {
      return try JSONValue.from(DocumentLinkResult())
    }

    guard let fileURL = URL(string: document.uri), fileURL.isFileURL else {
      return try JSONValue.from(DocumentLinkResult())
    }

    var links: [DocumentLink] = []
    let lines = document.text.components(separatedBy: .newlines)
    let baseDir = fileURL.deletingLastPathComponent()

    for (lineIndex, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Match #include "path" or #include <path>
      if trimmed.hasPrefix("#include") {
        if let startQuote = trimmed.firstIndex(of: "\""),
           let endQuote = trimmed[trimmed.index(after: startQuote)...].firstIndex(of: "\"") {

          let startColumn = trimmed.distance(from: trimmed.startIndex, to: startQuote)
          let endColumn = trimmed.distance(from: trimmed.startIndex, to: endQuote)
          let includePath = String(trimmed[trimmed.index(after: startQuote)..<endQuote])

          // Resolve relative path
          let resolvedURL = baseDir.appendingPathComponent(includePath)
          let targetURI = resolvedURL.absoluteString

          // Check if file exists
          let fileExists = FileManager.default.fileExists(atPath: resolvedURL.path)

          if fileExists {
            links.append(
              DocumentLink(
                range: Range(
                  start: Position(line: lineIndex, character: startColumn),
                  end: Position(line: lineIndex, character: endColumn + 1)
                ),
                target: targetURI,
                tooltip: "Open \(includePath)"
              )
            )
          }
        } else if let startAngle = trimmed.firstIndex(of: "<"),
                  let endAngle = trimmed[trimmed.index(after: startAngle)...].firstIndex(of: ">") {

          let startColumn = trimmed.distance(from: trimmed.startIndex, to: startAngle)
          let endColumn = trimmed.distance(from: trimmed.startIndex, to: endAngle)
          let includePath = String(trimmed[trimmed.index(after: startAngle)..<endAngle])

          // System includes - still provide link but no target
          links.append(
            DocumentLink(
              range: Range(
                start: Position(line: lineIndex, character: startColumn),
                end: Position(line: lineIndex, character: endColumn + 1)
              ),
              target: nil,
              tooltip: "System include: \(includePath)"
            )
          )
        }
      }
    }

    return try JSONValue.from(links)
  }

  private func handleFoldingRange(params: FoldingRangeParams?) throws -> JSONValue {
    guard let params = params else {
      return try JSONValue.from(FoldingRangeResult())
    }

    log("Folding range requested for \(params.textDocument.uri)")

    guard let document = documentManager.getDocument(uri: params.textDocument.uri) else {
      return try JSONValue.from(FoldingRangeResult())
    }

    guard let analysis = getAnalysis(for: params.textDocument.uri, document: document) else {
      return try JSONValue.from(FoldingRangeResult())
    }

    var ranges: [FoldingRange] = []

    // Create folding ranges from document symbols
    for symbol in analysis.index.symbols {
      let range = symbol.range

      // Function/struct body folding
      if symbol.kind == .kernel || symbol.kind == .vertex || symbol.kind == .fragment ||
         symbol.kind == .function || symbol.kind == .struct {

        // Find the opening brace
        let startLine = range.start.line
        let endLine = range.end.line

        if endLine > startLine {
          ranges.append(
            FoldingRange(
              startLine: startLine,
              endLine: endLine,
              kind: .region
            )
          )
        }
      }
    }

    // Add folding for #include blocks
    let lines = document.text.components(separatedBy: .newlines)
    for (lineIndex, line) in lines.enumerated() {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if trimmed.hasPrefix("#include") {
        // Check if there are multiple includes in a block
        if lineIndex + 1 < lines.count {
          var lastInclude = lineIndex
          for nextLine in (lineIndex + 1)..<lines.count {
            let nextTrimmed = lines[nextLine].trimmingCharacters(in: .whitespaces)
            if nextTrimmed.hasPrefix("#include") {
              lastInclude = nextLine
            } else if !nextTrimmed.isEmpty {
              break
            }
          }

          if lastInclude > lineIndex {
            ranges.append(
              FoldingRange(
                startLine: lineIndex,
                endLine: lastInclude,
                kind: .imports
              )
            )
          }
        }
      }
    }

    // Add folding for comments
    var inComment = false
    var commentStart = 0

    for (lineIndex, line) in lines.enumerated() {
      if line.contains("/*") && !inComment {
        inComment = true
        commentStart = lineIndex
      }

      if line.contains("*/") && inComment {
        ranges.append(
          FoldingRange(
            startLine: commentStart,
            endLine: lineIndex,
            kind: .comment
          )
        )
        inComment = false
      }
    }

    return try JSONValue.from(ranges)
  }

  private func handleTypeDefinition(params: TypeDefinitionParams?) throws -> JSONValue {
    guard let params = params else {
      return JSONValue.null
    }

    log("Type definition requested at \(params.position.line):\(params.position.character)")

    guard let document = documentManager.getDocument(uri: params.textDocument.uri) else {
      return JSONValue.null
    }

    guard let word = extractWordAtPosition(text: document.text, position: params.position) else {
      return JSONValue.null
    }

    log("Looking for type definition of: \(word)")

    // Find struct declarations
    if let location = findStructDefinition(name: word, primaryURI: params.textDocument.uri, primarySource: document.text) {
      return try JSONValue.from(location)
    }

    return JSONValue.null
  }

  private func findStructDefinition(name: String, primaryURI: String, primarySource: String) -> Location? {
    // Check primary document first
    let primaryDeclarations = symbolFinder.findDeclarations(name: name, in: primarySource)
    let structDecl = primaryDeclarations.first { $0.kind == .struct }

    if let decl = structDecl {
      return Location(
        uri: primaryURI,
        range: Range(
          start: Position(line: decl.line, character: decl.column),
          end: Position(line: decl.line, character: decl.column + decl.name.count)
        )
      )
    }

    // Search workspace
    for uri in workspaceCandidateURIs() {
      if uri == primaryURI { continue }

      guard let source = loadWorkspaceSource(uri: uri) else { continue }

      let declarations = symbolFinder.findDeclarations(name: name, in: source)
      let workspaceStructDecl = declarations.first { $0.kind == .struct }

      if let decl = workspaceStructDecl {
        return Location(
          uri: uri,
          range: Range(
            start: Position(line: decl.line, character: decl.column),
            end: Position(line: decl.line, character: decl.column + decl.name.count)
          )
        )
      }
    }

    return nil
  }

  // MARK: - Document Color Handlers

  private func handleDocumentColor(params: DocumentColorParams?) throws -> JSONValue {
    guard let params = params else {
      return try JSONValue.from(DocumentColorResult())
    }

    log("Document color requested for \(params.textDocument.uri)")

    guard let document = documentManager.getDocument(uri: params.textDocument.uri) else {
      return try JSONValue.from(DocumentColorResult())
    }

    let colors = findColors(in: document.text)
    return try JSONValue.from(colors)
  }

  private func handleColorPresentation(params: ColorPresentationParams?) throws -> JSONValue {
    guard let params = params else {
      return try JSONValue.from(ColorPresentationResult())
    }

    log("Color presentation requested")

    // Generate label from color
    let color = params.color
    let label = String(format: "rgba(%.0f, %.0f, %.0f, %.2f)",
      color.red * 255, color.green * 255, color.blue * 255, color.alpha)

    let presentation = ColorPresentation(label: label)
    return try JSONValue.from([presentation])
  }

  private func findColors(in text: String) -> [ColorInformation] {
    var colors: [ColorInformation] = []
    let lines = text.components(separatedBy: .newlines)

    for (lineIndex, line) in lines.enumerated() {
      // Pattern 1: float4(r, g, b, a) or float3(r, g, b)
      // Pattern 2: float4 { r, g, b, a }
      // Pattern 3: hex colors (0xRRGGBB or 0xRRGGBBAA)
      // Pattern 4: rgba(r, g, b, a) or rgb(r, g, b)

      colors.append(contentsOf: findFloat4Colors(line: line, lineIndex: lineIndex))
      colors.append(contentsOf: findFloat3Colors(line: line, lineIndex: lineIndex))
      colors.append(contentsOf: findHexColors(line: line, lineIndex: lineIndex))
      colors.append(contentsOf: findRgbaColors(line: line, lineIndex: lineIndex))
    }

    return colors
  }

  private func findFloat4Colors(line: String, lineIndex: Int) -> [ColorInformation] {
    // Match: float4(r, g, b, a) or float4 { r, g, b, a }
    var colors: [ColorInformation] = []

    // Pattern: float4(0.5, 0.5, 0.5, 1.0)
    let float4Pattern = #/float4\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)/#

    for match in line.matches(of: float4Pattern) {
      let r = Double(match.output.1) ?? 0
      let g = Double(match.output.2) ?? 0
      let b = Double(match.output.3) ?? 0
      let a = Double(match.output.4) ?? 1

      let startCol = line.distance(from: line.startIndex, to: match.range.lowerBound)
      let endCol = line.distance(from: line.startIndex, to: match.range.upperBound)

      colors.append(
        ColorInformation(
          range: Range(
            start: Position(line: lineIndex, character: startCol),
            end: Position(line: lineIndex, character: endCol)
          ),
          color: Color(red: r, green: g, blue: b, alpha: a)
        )
      )
    }

    // Pattern: float4 { 0.5, 0.5, 0.5, 1.0 }
    let float4BracePattern = #/float4\s*\{\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\}/#

    for match in line.matches(of: float4BracePattern) {
      let r = Double(match.output.1) ?? 0
      let g = Double(match.output.2) ?? 0
      let b = Double(match.output.3) ?? 0
      let a = Double(match.output.4) ?? 1

      let startCol = line.distance(from: line.startIndex, to: match.range.lowerBound)
      let endCol = line.distance(from: line.startIndex, to: match.range.upperBound)

      colors.append(
        ColorInformation(
          range: Range(
            start: Position(line: lineIndex, character: startCol),
            end: Position(line: lineIndex, character: endCol)
          ),
          color: Color(red: r, green: g, blue: b, alpha: a)
        )
      )
    }

    return colors
  }

  private func findFloat3Colors(line: String, lineIndex: Int) -> [ColorInformation] {
    // Match: float3(r, g, b) or float3 { r, g, b }
    var colors: [ColorInformation] = []

    // Pattern: float3(0.5, 0.5, 0.5)
    let float3Pattern = #/float3\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)/#

    for match in line.matches(of: float3Pattern) {
      let r = Double(match.output.1) ?? 0
      let g = Double(match.output.2) ?? 0
      let b = Double(match.output.3) ?? 0

      let startCol = line.distance(from: line.startIndex, to: match.range.lowerBound)
      let endCol = line.distance(from: line.startIndex, to: match.range.upperBound)

      colors.append(
        ColorInformation(
          range: Range(
            start: Position(line: lineIndex, character: startCol),
            end: Position(line: lineIndex, character: endCol)
          ),
          color: Color(red: r, green: g, blue: b, alpha: 1.0)
        )
      )
    }

    // Pattern: float3 { 0.5, 0.5, 0.5 }
    let float3BracePattern = #/float3\s*\{\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\}/#

    for match in line.matches(of: float3BracePattern) {
      let r = Double(match.output.1) ?? 0
      let g = Double(match.output.2) ?? 0
      let b = Double(match.output.3) ?? 0

      let startCol = line.distance(from: line.startIndex, to: match.range.lowerBound)
      let endCol = line.distance(from: line.startIndex, to: match.range.upperBound)

      colors.append(
        ColorInformation(
          range: Range(
            start: Position(line: lineIndex, character: startCol),
            end: Position(line: lineIndex, character: endCol)
          ),
          color: Color(red: r, green: g, blue: b, alpha: 1.0)
        )
      )
    }

    return colors
  }

  private func findHexColors(line: String, lineIndex: Int) -> [ColorInformation] {
    // Match: 0xRRGGBB or 0xRRGGBBAA
    var colors: [ColorInformation] = []

    let hexPattern = #/0x([0-9a-fA-F]{6})([0-9a-fA-F]{2})?/#

    for match in line.matches(of: hexPattern) {
      let hexRGB = String(match.output.1)
      let hexAlpha = match.output.2.map(String.init) ?? "FF"

      // Parse RGB
      let r = Double(Int(hexRGB.prefix(2), radix: 16)!) / 255.0
      let g = Double(Int(hexRGB.dropFirst(2).prefix(2), radix: 16)!) / 255.0
      let b = Double(Int(hexRGB.suffix(2), radix: 16)!) / 255.0
      let a = Double(Int(hexAlpha, radix: 16)!) / 255.0

      let startCol = line.distance(from: line.startIndex, to: match.range.lowerBound)
      let endCol = line.distance(from: line.startIndex, to: match.range.upperBound)

      colors.append(
        ColorInformation(
          range: Range(
            start: Position(line: lineIndex, character: startCol),
            end: Position(line: lineIndex, character: endCol)
          ),
          color: Color(red: r, green: g, blue: b, alpha: a)
        )
      )
    }

    return colors
  }

  private func findRgbaColors(line: String, lineIndex: Int) -> [ColorInformation] {
    // Match: rgba(r, g, b, a) or rgb(r, g, b)
    var colors: [ColorInformation] = []

    // rgba pattern
    let rgbaPattern = #/rgba\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)/#

    for match in line.matches(of: rgbaPattern) {
      let r = (Double(match.output.1) ?? 0) / 255.0
      let g = (Double(match.output.2) ?? 0) / 255.0
      let b = (Double(match.output.3) ?? 0) / 255.0
      let a = Double(match.output.4) ?? 1

      let startCol = line.distance(from: line.startIndex, to: match.range.lowerBound)
      let endCol = line.distance(from: line.startIndex, to: match.range.upperBound)

      colors.append(
        ColorInformation(
          range: Range(
            start: Position(line: lineIndex, character: startCol),
            end: Position(line: lineIndex, character: endCol)
          ),
          color: Color(red: r, green: g, blue: b, alpha: a)
        )
      )
    }

    // rgb pattern
    let rgbPattern = #/rgb\s*\(\s*([0-9.]+)\s*,\s*([0-9.]+)\s*,\s*([0-9.]+)\s*\)/#

    for match in line.matches(of: rgbPattern) {
      let r = (Double(match.output.1) ?? 0) / 255.0
      let g = (Double(match.output.2) ?? 0) / 255.0
      let b = (Double(match.output.3) ?? 0) / 255.0

      let startCol = line.distance(from: line.startIndex, to: match.range.lowerBound)
      let endCol = line.distance(from: line.startIndex, to: match.range.upperBound)

      colors.append(
        ColorInformation(
          range: Range(
            start: Position(line: lineIndex, character: startCol),
            end: Position(line: lineIndex, character: endCol)
          ),
          color: Color(red: r, green: g, blue: b, alpha: 1.0)
        )
      )
    }

    return colors
  }

  private func encodeTokens(_ tokens: [MetalToken]) -> [Int] {
    var data: [Int] = []
    var prevLine = 0
    var prevChar = 0

    for token in tokens {
      let lineDelta = token.line - prevLine
      let charDelta = (lineDelta == 0) ? (token.column - prevChar) : token.column

      // Find index in legend
      // If not found, fallback to variable
      let tokenType = token.type
      var typeIndex = tokenTypes.firstIndex(of: tokenType)

      if typeIndex == nil {
        if tokenType == "class" {
          typeIndex = tokenTypes.firstIndex(of: "class")
        } else {
          typeIndex = tokenTypes.firstIndex(of: "variable")
        }
      }

      guard let finalTypeIndex = typeIndex else { continue }

      data.append(lineDelta)
      data.append(charDelta)
      data.append(token.length)
      data.append(finalTypeIndex)
      data.append(0)  // Modifiers

      prevLine = token.line
      prevChar = token.column
    }
    return data
  }

  // MARK: - Helper Methods

  private func extractWordAtPosition(text: String, position: Position) -> String? {
    let lines = text.components(separatedBy: .newlines)
    guard position.line < lines.count else { return nil }

    let line = lines[position.line]
    let characters = Array(line)
    guard position.character < characters.count else { return nil }

    // Find word boundaries
    let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))

    var start = position.character
    var end = position.character

    // Expand backward
    while start > 0 {
      let char = characters[start - 1]
      if String(char).rangeOfCharacter(from: wordCharacters) == nil {
        break
      }
      start -= 1
    }

    // Expand forward
    while end < characters.count {
      let char = characters[end]
      if String(char).rangeOfCharacter(from: wordCharacters) == nil {
        break
      }
      end += 1
    }

    guard start < end else { return nil }

    let wordChars = characters[start..<end]
    return String(wordChars)
  }

  private struct CompletionFilterContext {
    let prefix: String?
    let restrictToAttributes: Bool
  }

  private struct CallContext {
    let functionName: String
    let activeParameter: Int
  }

  private func stableHash(_ text: String) -> UInt64 {
    var hash: UInt64 = 14695981039346656037
    for byte in text.utf8 {
      hash ^= UInt64(byte)
      hash &*= 1099511628211
    }
    return hash
  }

  private func resolveWorkspaceRootURL(from params: InitializeParams?) -> URL? {
    if let folders = params?.workspaceFolders {
      for folder in folders {
        if let url = URL(string: folder.uri), url.isFileURL {
          return url
        }
      }
    }

    if let rootUri = params?.rootUri, let url = URL(string: rootUri), url.isFileURL {
      return url
    }

    if let rootPath = params?.rootPath {
      return URL(fileURLWithPath: rootPath, isDirectory: true)
    }

    return nil
  }

  private func workspaceCandidateURIs() -> [String] {
    var uris = Set(documentManager.getAllDocuments())

    for url in workspaceCandidateFileURLs() {
      uris.insert(url.absoluteString)
    }

    return uris.sorted()
  }

  private func workspaceCandidateFileURLs() -> [URL] {
    guard let root = workspaceRootURL, root.isFileURL else { return [] }

    if workspaceFileURLCacheRoot == root, !workspaceFileURLCache.isEmpty {
      return workspaceFileURLCache
    }

    guard FileManager.default.fileExists(atPath: root.path) else {
      workspaceFileURLCache = []
      workspaceFileURLCacheRoot = root
      return []
    }

    let excludedDirectories: Set<String> = [
      ".git", ".build", ".swiftpm", "DerivedData", "build", ".vscode", ".idea"
    ]

    let allowedExtensions: Set<String> = [
      "metal", "h", "hpp", "hh", "inc", "metalh"
    ]

    var files: [URL] = []

    let keys: [URLResourceKey] = [.isDirectoryKey, .nameKey]
    let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: keys,
      options: [.skipsHiddenFiles]
    )

    while let url = enumerator?.nextObject() as? URL {
      guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
        continue
      }

      if values.isDirectory == true {
        if let name = values.name, excludedDirectories.contains(name) {
          enumerator?.skipDescendants()
        }
        continue
      }

      let ext = url.pathExtension.lowercased()
      if allowedExtensions.contains(ext) {
        files.append(url)
      }
    }

    files.sort { $0.path < $1.path }

    workspaceFileURLCache = files
    workspaceFileURLCacheRoot = root

    return files
  }

  private func loadWorkspaceSource(uri: String, preferredSource: String? = nil) -> String? {
    if let preferredSource {
      return preferredSource
    }

    if let document = documentManager.getDocument(uri: uri) {
      return document.text
    }

    guard let url = URL(string: uri), url.isFileURL else {
      return nil
    }

    let filePath = url.path
    guard let attributes = try? FileManager.default.attributesOfItem(atPath: filePath) else {
      return nil
    }

    let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0

    if let cached = workspaceFileCache[uri], cached.modificationTime == mtime, cached.size == size {
      return cached.source
    }

    guard let source = try? String(contentsOf: url, encoding: .utf8) else {
      return nil
    }

    workspaceFileCache[uri] = CachedWorkspaceFile(modificationTime: mtime, size: size, source: source)

    if workspaceFileCache.count > 128 {
      workspaceFileCache.removeAll(keepingCapacity: true)
    }

    return source
  }

  private func resolveIncludeLocation(in document: Document, at position: Position) -> Location? {
    guard let fileURL = URL(string: document.uri), fileURL.isFileURL else {
      return nil
    }

    guard let lineText = document.line(at: position.line) else {
      return nil
    }

    let trimmed = lineText.trimmingCharacters(in: .whitespaces)
    guard trimmed.hasPrefix("#include") else {
      return nil
    }

    let cursor = min(position.character, lineText.count)

    if let startQuote = lineText.firstIndex(of: "\""),
      let endQuote = lineText[lineText.index(after: startQuote)...].firstIndex(of: "\""),
      startQuote < endQuote
    {
      let startColumn = lineText.distance(from: lineText.startIndex, to: startQuote)
      let endColumn = lineText.distance(from: lineText.startIndex, to: endQuote)

      guard cursor > startColumn, cursor < endColumn else {
        return nil
      }

      let path = String(lineText[lineText.index(after: startQuote)..<endQuote])
      let resolved = fileURL.deletingLastPathComponent().appendingPathComponent(path)

      guard FileManager.default.fileExists(atPath: resolved.path) else {
        return nil
      }

      return Location(
        uri: resolved.absoluteString,
        range: Range(
          start: Position(line: 0, character: 0),
          end: Position(line: 0, character: 0)
        )
      )
    }

    return nil
  }

  private func findBestDefinitionLocation(name: String, primaryURI: String, primarySource: String) -> Location? {
    let primaryDeclarations = symbolFinder.findDeclarations(name: name, in: primarySource)

    if let best = bestDeclaration(from: primaryDeclarations) {
      return Location(
        uri: primaryURI,
        range: Range(
          start: Position(line: best.line, character: best.column),
          end: Position(line: best.line, character: best.column + best.name.count)
        )
      )
    }

    for uri in workspaceCandidateURIs() {
      if uri == primaryURI {
        continue
      }

      guard let source = loadWorkspaceSource(uri: uri) else {
        continue
      }

      let declarations = symbolFinder.findDeclarations(name: name, in: source)
      if let best = bestDeclaration(from: declarations) {
        return Location(
          uri: uri,
          range: Range(
            start: Position(line: best.line, character: best.column),
            end: Position(line: best.line, character: best.column + best.name.count)
          )
        )
      }
    }

    return nil
  }

  private func bestDeclaration(from declarations: [MetalSymbolFinder.SymbolDeclaration]) -> MetalSymbolFinder.SymbolDeclaration? {
    guard !declarations.isEmpty else { return nil }

    func rank(_ kind: MetalSymbolFinder.SymbolKind) -> Int {
      switch kind {
      case .kernel, .vertex, .fragment, .function:
        return 0
      case .struct:
        return 1
      case .variable:
        return 2
      case .unknown:
        return 3
      }
    }

    return declarations.sorted {
      let lhsRank = rank($0.kind)
      let rhsRank = rank($1.kind)
      if lhsRank != rhsRank {
        return lhsRank < rhsRank
      }
      if $0.line != $1.line {
        return $0.line < $1.line
      }
      return $0.column < $1.column
    }.first
  }

  private func findReferencesInWorkspace(
    name: String,
    includeDeclaration: Bool,
    primaryURI: String,
    primarySource: String
  ) -> [Location] {
    struct ReferenceKey: Hashable {
      let uri: String
      let line: Int
      let column: Int
    }

    var locations: [Location] = []
    var seen = Set<ReferenceKey>()

    func addLocation(uri: String, line: Int, column: Int, length: Int) {
      let key = ReferenceKey(uri: uri, line: line, column: column)
      if seen.contains(key) {
        return
      }
      seen.insert(key)
      locations.append(
        Location(
          uri: uri,
          range: Range(
            start: Position(line: line, character: column),
            end: Position(line: line, character: column + length)
          )
        )
      )
    }

    let searchURIs = workspaceCandidateURIs()

    for uri in searchURIs {
      let source = loadWorkspaceSource(uri: uri, preferredSource: uri == primaryURI ? primarySource : nil)
      guard let source else { continue }

      if includeDeclaration {
        let declarations = symbolFinder.findDeclarations(name: name, in: source)
        for decl in declarations {
          addLocation(uri: uri, line: decl.line, column: decl.column, length: decl.name.count)
        }
      }

      let references = symbolFinder.findReferences(name: name, in: source)
      for ref in references {
        addLocation(uri: uri, line: ref.line, column: ref.column, length: name.count)
      }
    }

    return locations
  }

  private func getAnalysis(for uri: String, document: Document) -> CachedDocumentAnalysis? {
    let textHash = stableHash(document.text)
    if let cached = analysisCache[uri], cached.version == document.version, cached.textHash == textHash {
      return cached
    }

    let index = documentIndexer.index(source: document.text)
    let tokens = lexer.tokenize(document.text)

    let analysis = CachedDocumentAnalysis(
      version: document.version,
      textHash: textHash,
      index: index,
      tokens: tokens
    )

    analysisCache[uri] = analysis
    return analysis
  }

  private func getBuiltinCompletionItems() -> [CompletionItem] {
    if let cached = builtinCompletionItems {
      return cached
    }

    var allCompletions = MetalBuiltins.getHardcodedCompletions()
    if let documentation = documentation {
      allCompletions += documentation.getAllCompletions()
    }

    let items = allCompletions.map { builtin -> CompletionItem in
      let kind: CompletionItemKind
      if builtin.label.starts(with: "[[") {
        kind = .property
      } else if builtin.insertText?.contains("$") == true {
        kind = .snippet
      } else if builtin.detail?.contains("(") == true {
        kind = .function
      } else if MetalBuiltins.keywords.contains(builtin.label) {
        kind = .keyword
      } else {
        kind = .class
      }

      let insertTextFormat: InsertTextFormat? =
        builtin.insertText?.contains("$") == true ? .snippet : nil

      return CompletionItem(
        label: builtin.label,
        kind: kind,
        detail: builtin.detail,
        documentation: builtin.documentation,
        insertText: builtin.insertText,
        insertTextFormat: insertTextFormat
      )
    }

    builtinCompletionItems = items
    return items
  }

  private func completionItems(from index: MetalDocumentIndex) -> [CompletionItem] {
    var items: [CompletionItem] = []
    items.reserveCapacity(index.symbols.count)

    for symbol in index.symbols {
      let kind: CompletionItemKind
      switch symbol.kind {
      case .kernel, .vertex, .fragment, .function:
        kind = .function
      case .struct:
        kind = .`struct`
      case .variable:
        kind = .variable
      case .unknown:
        kind = .text
      }

      items.append(
        CompletionItem(
          label: symbol.name,
          kind: kind,
          detail: symbol.detail
        )
      )
    }

    return items
  }

  private func completionFilterContext(in document: Document, at position: Position) -> CompletionFilterContext {
    guard let lineText = document.line(at: position.line) else {
      return CompletionFilterContext(prefix: nil, restrictToAttributes: false)
    }

    let cursor = min(position.character, lineText.count)
    let beforeCursor = String(lineText.prefix(cursor))

    if let lastOpen = beforeCursor.range(of: "[[", options: .backwards) {
      let lastClose = beforeCursor.range(of: "]]", options: .backwards)
      if lastClose == nil || lastClose!.upperBound < lastOpen.lowerBound {
        let prefix = String(beforeCursor[lastOpen.lowerBound..<beforeCursor.endIndex])
        return CompletionFilterContext(prefix: prefix, restrictToAttributes: true)
      }
    }

    let chars = Array(beforeCursor)
    var start = chars.count
    let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
    while start > 0 {
      let char = chars[start - 1]
      if String(char).rangeOfCharacter(from: wordCharacters) == nil {
        break
      }
      start -= 1
    }

    let prefix = String(chars[start..<chars.count])
    return CompletionFilterContext(prefix: prefix.isEmpty ? nil : prefix, restrictToAttributes: false)
  }

  private func isPositionInNonCodeToken(position: Position, tokens: [MetalToken]) -> Bool {
    for token in tokens {
      if token.line != position.line {
        continue
      }
      guard token.type == "comment" || token.type == "string" else {
        continue
      }
      if position.character >= token.column && position.character < token.column + token.length {
        return true
      }
    }
    return false
  }

  private func extractCallContext(in document: Document, at position: Position) -> CallContext? {
    let cursorOffset = document.offsetAt(position: position)
    let chars = Array(document.text)

    guard cursorOffset <= chars.count else { return nil }

    var parenDepth = 0
    var openParenIndex: Int?

    var i = min(cursorOffset - 1, chars.count - 1)
    while i >= 0 {
      let c = chars[i]

      if c == ")" {
        parenDepth += 1
      } else if c == "(" {
        if parenDepth == 0 {
          openParenIndex = i
          break
        }
        parenDepth -= 1
      } else if parenDepth == 0 {
        if c == ";" || c == "{" || c == "}" {
          break
        }
      }

      i -= 1
    }

    guard let open = openParenIndex else { return nil }

    var j = open - 1
    while j >= 0 {
      let c = chars[j]
      if c == " " || c == "\t" || c == "\n" || c == "\r" {
        j -= 1
        continue
      }
      break
    }

    guard j >= 0 else { return nil }

    let wordCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_:"))
    var nameStart = j
    while nameStart >= 0 {
      let c = chars[nameStart]
      if String(c).rangeOfCharacter(from: wordCharacters) == nil {
        break
      }
      nameStart -= 1
    }
    nameStart += 1

    guard nameStart <= j else { return nil }

    let rawName = String(chars[nameStart..<(j + 1)])
    let functionName = rawName.split(separator: ":").last.map(String.init) ?? rawName

    var activeParameter = 0
    var depth = 0
    if open + 1 < cursorOffset {
      for k in (open + 1)..<min(cursorOffset, chars.count) {
        let c = chars[k]
        if c == "(" {
          depth += 1
        } else if c == ")" {
          depth = max(0, depth - 1)
        } else if c == "," && depth == 0 {
          activeParameter += 1
        }
      }
    }

    return CallContext(functionName: functionName, activeParameter: activeParameter)
  }

  private func parseParameters(fromSignatureLabel signature: String) -> [String] {
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

  private func documentSymbol(from node: MetalDocumentSymbolNode) -> DocumentSymbol {
    return documentSymbol(from: node, isChild: false)
  }

  private func documentSymbol(from node: MetalDocumentSymbolNode, isChild: Bool) -> DocumentSymbol {
    let children = node.children.isEmpty ? nil : node.children.map { documentSymbol(from: $0, isChild: true) }

    return DocumentSymbol(
      name: node.name,
      detail: node.detail,
      kind: lspSymbolKind(from: node.kind, isChild: isChild),
      range: lspRange(from: node.range),
      selectionRange: lspRange(from: node.selectionRange),
      children: children
    )
  }

  private func lspRange(from range: MetalSourceRange) -> Range {
    return Range(
      start: Position(line: range.start.line, character: range.start.column),
      end: Position(line: range.end.line, character: range.end.column)
    )
  }

  private func lspSymbolKind(from kind: MetalSymbolFinder.SymbolKind, isChild: Bool) -> SymbolKind {
    switch kind {
    case .kernel, .vertex, .fragment, .function:
      return .function
    case .struct:
      return .`struct`
    case .variable:
      return isChild ? .field : .variable
    case .unknown:
      return .variable
    }
  }

  // MARK: - Diagnostics

  private func diagnosticsCacheKey(uri: String, source: String) -> UInt64 {
    let sourceHash = stableHash(source)
    let includeHash = includeFingerprintHash(uri: uri, source: source)

    var hash = sourceHash
    hash ^= includeHash &* 31
    return hash
  }

  private func includeFingerprintHash(uri: String, source: String) -> UInt64 {
    guard let fileURL = URL(string: uri), fileURL.isFileURL else {
      return 0
    }

    let baseDir = fileURL.deletingLastPathComponent()
    let fileManager = FileManager.default

    var fingerprint = ""

    for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard trimmed.hasPrefix("#include") else { continue }

      guard let startQuote = trimmed.firstIndex(of: "\"") else { continue }
      let afterStart = trimmed.index(after: startQuote)
      guard let endQuote = trimmed[afterStart...].firstIndex(of: "\"") else { continue }

      let includePath = String(trimmed[afterStart..<endQuote])
      let resolvedURL = baseDir.appendingPathComponent(includePath)

      fingerprint += includePath

      if let attributes = try? fileManager.attributesOfItem(atPath: resolvedURL.path) {
        let mtime = (attributes[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        let size = (attributes[.size] as? NSNumber)?.uint64Value ?? 0
        fingerprint += "|\(mtime)|\(size)\n"
      } else {
        fingerprint += "|missing\n"
      }
    }

    return stableHash(fingerprint)
  }

  private func validateDocument(uri: String) throws {
    // Get document text from manager or read from disk
    let documentText: String
    if let document = documentManager.getDocument(uri: uri) {
      documentText = document.text
    } else {
      // Fallback: read from disk
      guard let url = URL(string: uri),
        url.isFileURL,
        let text = try? String(contentsOf: url, encoding: .utf8)
      else {
        log("Cannot validate document: not in manager and cannot read from disk: \(uri)")
        return
      }
      documentText = text
    }

    log("Validating document: \(uri)")

    let cacheKey = diagnosticsCacheKey(uri: uri, source: documentText)
    if let cached = diagnosticsCache[uri], cached.cacheKey == cacheKey {
      for (fileURI, diagnostics) in cached.diagnosticsByURI {
        let params = PublishDiagnosticsParams(uri: fileURI, diagnostics: diagnostics)
        try sendNotification(method: "textDocument/publishDiagnostics", params: params)
      }

      log("Published cached diagnostics for \(cached.diagnosticsByURI.count) files")
      return
    }

    // Compile with Metal compiler
    let metalDiagnostics = metalCompiler.compile(source: documentText, uri: uri)

    // Group diagnostics by URI
    var diagnosticsByURI: [String: [Diagnostic]] = [:]

    // Initialize with empty list for the main document so we clear it if no errors
    diagnosticsByURI[uri] = []

    for diag in metalDiagnostics {
      let diagURI = diag.fileURI ?? uri

      let severity: DiagnosticSeverity
      switch diag.severity {
      case .error:
        severity = .error
      case .warning:
        severity = .warning
      case .information:
        severity = .information
      case .hint:
        severity = .hint
      }

      let position = Position(line: diag.line, character: diag.column)
      let range = Range(start: position, end: position)

      let diagnostic = Diagnostic(
        range: range,
        severity: severity,
        message: diag.message,
        source: "metal-compiler"
      )

      if diagnosticsByURI[diagURI] == nil {
        diagnosticsByURI[diagURI] = []
      }
      diagnosticsByURI[diagURI]?.append(diagnostic)
    }

    diagnosticsCache[uri] = CachedDiagnostics(cacheKey: cacheKey, diagnosticsByURI: diagnosticsByURI)

    // Publish diagnostics for each URI
    for (fileURI, diagnostics) in diagnosticsByURI {
      let params = PublishDiagnosticsParams(uri: fileURI, diagnostics: diagnostics)
      try sendNotification(method: "textDocument/publishDiagnostics", params: params)
    }

    log("Published diagnostics for \(diagnosticsByURI.count) files")
  }

  // MARK: - Response Helpers

  private func sendResponse(id: RequestID, result: JSONValue) throws {
    let response = JSONRPCResponse(id: id, result: result)
    try transport.writeJSON(response)
  }

  private func sendError(id: RequestID, code: ErrorCode, message: String) throws {
    let error = ResponseError(code: code, message: message)
    let response = JSONRPCResponse(id: id, error: error)
    try transport.writeJSON(response)
  }

  private func sendNotification<T: Encodable>(method: String, params: T) throws {
    let paramsJSON = try JSONValue.from(params)
    let notification = JSONRPCNotification(method: method, params: paramsJSON)
    try transport.writeJSON(notification)
  }

  private func sendProgressNotification(token: String, kind: String? = nil, title: String? = nil, percentage: Int? = nil, message: String? = nil) throws {
    let value = ProgressValue(kind: kind, title: title, percentage: percentage, message: message)
    let params = ProgressParams(token: token, value: value)
    try sendNotification(method: "$/progress", params: params)
  }

  private func log(_ message: String) {
    if verbose {
      let log = "[LSP] \(message)\n"
      if let data = log.data(using: .utf8) {
        FileHandle.standardError.write(data)
      }
    }
  }
}
