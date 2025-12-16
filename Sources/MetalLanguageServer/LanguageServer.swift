import Foundation
import MetalCore

/// Main LSP server implementation
public class LanguageServer {
  private let transport: MessageTransport
  private let documentManager = DocumentManager()
  private let metalCompiler = MetalCompiler()
  private let symbolFinder = MetalSymbolFinder()
  private let formatter = MetalFormatter()
  private let verbose: Bool
  private var documentation: MetalDocumentation?

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

    let capabilities = ServerCapabilities(
      textDocumentSync: TextDocumentSyncOptions(
        openClose: true,
        change: 1  // Full document sync
      ),
      completionProvider: CompletionOptions(
        triggerCharacters: [".", "[", "(", " "]
      )
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

    documentManager.closeDocument(uri: params.textDocument.uri)
  }

  private func handleCompletion(params: CompletionParams?) throws -> JSONValue {
    guard let params = params else {
      return try JSONValue.from(CompletionList(isIncomplete: false, items: []))
    }

    log("Completion requested at \(params.position.line):\(params.position.character)")

    // Combine hardcoded completions (keywords, attributes, snippets) with JSON completions
    var allCompletions = MetalBuiltins.getHardcodedCompletions()

    // Add completions from JSON documentation
    if let documentation = documentation {
      allCompletions += documentation.getAllCompletions()
    }

    // Convert to LSP completion items
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
        kind = .class  // Types
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

    let result = CompletionList(isIncomplete: false, items: items)
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

    // Find declarations of this symbol in the document
    let declarations = symbolFinder.findDeclarations(name: word, in: document.text)

    guard !declarations.isEmpty else {
      log("No declarations found for: \(word)")
      return JSONValue.null
    }

    // Return the first declaration
    let decl = declarations[0]
    let location = Location(
      uri: params.textDocument.uri,
      range: Range(
        start: Position(line: decl.line, character: decl.column),
        end: Position(line: decl.line, character: decl.column + decl.name.count)
      )
    )

    log("Found definition at line \(decl.line), column \(decl.column)")
    return try JSONValue.from(location)
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

    // Find all references to this symbol
    let references = symbolFinder.findReferences(name: word, in: document.text)

    // Include declaration if requested
    var locations: [Location] = []
    if params.context.includeDeclaration {
      let declarations = symbolFinder.findDeclarations(name: word, in: document.text)
      for decl in declarations {
        locations.append(
          Location(
            uri: params.textDocument.uri,
            range: Range(
              start: Position(line: decl.line, character: decl.column),
              end: Position(line: decl.line, character: decl.column + decl.name.count)
            )
          ))
      }
    }

    // Add all references
    for ref in references {
      locations.append(
        Location(
          uri: params.textDocument.uri,
          range: Range(
            start: Position(line: ref.line, character: ref.column),
            end: Position(line: ref.line, character: ref.column + word.count)
          )
        ))
    }

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

  // MARK: - Diagnostics

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

    // Compile with Metal compiler
    let metalDiagnostics = metalCompiler.compile(source: documentText, uri: uri)

    // Convert to LSP diagnostics
    let diagnostics = metalDiagnostics.map { diag -> Diagnostic in
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

      return Diagnostic(
        range: range,
        severity: severity,
        message: diag.message,
        source: "metal-compiler"
      )
    }

    // Publish diagnostics
    let params = PublishDiagnosticsParams(uri: uri, diagnostics: diagnostics)
    try sendNotification(method: "textDocument/publishDiagnostics", params: params)

    log("Published \(diagnostics.count) diagnostics")
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

  private func log(_ message: String) {
    if verbose {
      let log = "[LSP] \(message)\n"
      if let data = log.data(using: .utf8) {
        FileHandle.standardError.write(data)
      }
    }
  }
}
