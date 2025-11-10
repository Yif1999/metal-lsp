import Foundation
import MetalCore

/// Main LSP server implementation
public class LanguageServer {
    private let transport: MessageTransport
    private let documentManager = DocumentManager()
    private let metalCompiler = MetalCompiler()
    private let verbose: Bool

    private var isInitialized = false
    private var isShuttingDown = false

    public init(verbose: Bool = false, logMessages: Bool = false) {
        self.verbose = verbose
        self.transport = MessageTransport(logMessages: logMessages)
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
                    try sendError(id: request.id, code: .serverNotInitialized, message: "Server not initialized")
                    return
                }
                let params = try request.params?.decode(CompletionParams.self)
                let result = try handleCompletion(params: params)
                try sendResponse(id: request.id, result: result)

            default:
                try sendError(id: request.id, code: .methodNotFound, message: "Method not found: \(request.method)")
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
                change: 1 // Full document sync
            ),
            completionProvider: CompletionOptions(
                triggerCharacters: [".", "[", "(", " "]
            )
        )

        let result = InitializeResult(
            capabilities: capabilities,
            serverInfo: InitializeResult.ServerInfo(
                name: "metal-lsp",
                version: "0.1.0"
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

        // Get all built-in completions
        let builtins = MetalBuiltins.getAllCompletions()

        // Convert to LSP completion items
        let items = builtins.map { builtin -> CompletionItem in
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
                kind = .class // Types
            }

            let insertTextFormat: InsertTextFormat? = builtin.insertText?.contains("$") == true ? .snippet : nil

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
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
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
