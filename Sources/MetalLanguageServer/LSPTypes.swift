import Foundation

// MARK: - Basic LSP Types

struct Position: Codable, Equatable, Hashable {
  let line: Int
  let character: Int
}

struct Range: Codable, Equatable {
  let start: Position
  let end: Position
}

struct Location: Codable, Equatable {
  let uri: String
  let range: Range
}

struct TextDocumentIdentifier: Codable {
  let uri: String
}

struct VersionedTextDocumentIdentifier: Codable {
  let uri: String
  let version: Int
}

struct TextDocumentItem: Codable {
  let uri: String
  let languageId: String
  let version: Int
  let text: String
}

struct TextDocumentContentChangeEvent: Codable {
  let range: Range?
  let rangeLength: Int?
  let text: String
}

struct TextDocumentPositionParams: Codable {
  let textDocument: TextDocumentIdentifier
  let position: Position
}

// MARK: - Diagnostic Types

enum DiagnosticSeverity: Int, Codable {
  case error = 1
  case warning = 2
  case information = 3
  case hint = 4
}

struct Diagnostic: Codable {
  let range: Range
  let severity: DiagnosticSeverity?
  let code: String?
  let source: String?
  let message: String
  let relatedInformation: [DiagnosticRelatedInformation]?

  init(range: Range, severity: DiagnosticSeverity, message: String, source: String = "metal-lsp") {
    self.range = range
    self.severity = severity
    self.message = message
    self.source = source
    self.code = nil
    self.relatedInformation = nil
  }
}

struct DiagnosticRelatedInformation: Codable {
  let location: Location
  let message: String
}

struct PublishDiagnosticsParams: Codable {
  let uri: String
  let diagnostics: [Diagnostic]
}

// MARK: - Completion Types

enum CompletionItemKind: Int, Codable {
  case text = 1
  case method = 2
  case function = 3
  case constructor = 4
  case field = 5
  case variable = 6
  case `class` = 7
  case interface = 8
  case module = 9
  case property = 10
  case unit = 11
  case value = 12
  case `enum` = 13
  case keyword = 14
  case snippet = 15
  case color = 16
  case file = 17
  case reference = 18
  case folder = 19
  case enumMember = 20
  case constant = 21
  case `struct` = 22
  case event = 23
  case `operator` = 24
  case typeParameter = 25
}

enum InsertTextFormat: Int, Codable {
  case plainText = 1
  case snippet = 2
}

struct CompletionItem: Codable {
  let label: String
  let kind: CompletionItemKind?
  let detail: String?
  let documentation: String?
  let insertText: String?
  let insertTextFormat: InsertTextFormat?
  let sortText: String?
  let filterText: String?

  init(
    label: String,
    kind: CompletionItemKind,
    detail: String? = nil,
    documentation: String? = nil,
    insertText: String? = nil,
    insertTextFormat: InsertTextFormat? = nil
  ) {
    self.label = label
    self.kind = kind
    self.detail = detail
    self.documentation = documentation
    self.insertText = insertText
    self.insertTextFormat = insertTextFormat
    self.sortText = nil
    self.filterText = nil
  }
}

struct CompletionList: Codable {
  let isIncomplete: Bool
  let items: [CompletionItem]
}

struct CompletionParams: Codable {
  let textDocument: TextDocumentIdentifier
  let position: Position
  let context: CompletionContext?
}

struct CompletionContext: Codable {
  let triggerKind: Int
  let triggerCharacter: String?
}

// MARK: - Hover Types

enum MarkupKind: String, Codable {
  case plaintext
  case markdown
}

struct MarkupContent: Codable {
  let kind: MarkupKind
  let value: String

  init(kind: MarkupKind = .markdown, value: String) {
    self.kind = kind
    self.value = value
  }
}

struct Hover: Codable {
  let contents: MarkupContent
  let range: Range?

  init(contents: MarkupContent, range: Range? = nil) {
    self.contents = contents
    self.range = range
  }
}

typealias HoverParams = TextDocumentPositionParams

// MARK: - Definition Types

typealias DefinitionParams = TextDocumentPositionParams

typealias LocationResult = Location

// MARK: - References Types

struct ReferenceParams: Codable {
  let textDocument: TextDocumentIdentifier
  let position: Position
  let context: ReferenceContext
}

struct ReferenceContext: Codable {
  let includeDeclaration: Bool
}

typealias ReferenceResult = [Location]

// MARK: - Formatting Types

struct FormattingParams: Codable {
  let textDocument: TextDocumentIdentifier
  let options: FormattingOptions
}

struct FormattingOptions: Codable {
  let tabSize: Int
  let insertSpaces: Bool
  let trimTrailingWhitespace: Bool?
  let insertFinalNewline: Bool?
  let trimFinalNewlines: Bool?
}

struct TextEdit: Codable {
  let range: Range
  let newText: String
}

typealias FormattingResult = [TextEdit]

// MARK: - Signature Help Types

struct SignatureHelpOptions: Codable {
  let triggerCharacters: [String]?
  let retriggerCharacters: [String]?

  init(triggerCharacters: [String]) {
    self.triggerCharacters = triggerCharacters
    self.retriggerCharacters = triggerCharacters
  }
}

struct SignatureHelpParams: Codable {
  let textDocument: TextDocumentIdentifier
  let position: Position
  let context: SignatureHelpContext?
}

struct SignatureHelpContext: Codable {
  let triggerKind: Int
  let triggerCharacter: String?
}

struct SignatureHelp: Codable {
  let signatures: [SignatureInformation]
  let activeSignature: Int?
  let activeParameter: Int?
}

struct SignatureInformation: Codable {
  let label: String
  let documentation: String?
  let parameters: [ParameterInformation]?
}

struct ParameterInformation: Codable {
  let label: String
}

// MARK: - Document Symbols Types

enum SymbolKind: Int, Codable {
  case file = 1
  case module = 2
  case namespace = 3
  case package = 4
  case `class` = 5
  case method = 6
  case property = 7
  case field = 8
  case constructor = 9
  case `enum` = 10
  case interface = 11
  case function = 12
  case variable = 13
  case constant = 14
  case string = 15
  case number = 16
  case boolean = 17
  case array = 18
  case object = 19
  case key = 20
  case null = 21
  case enumMember = 22
  case `struct` = 23
  case event = 24
  case `operator` = 25
  case typeParameter = 26
}

struct DocumentSymbol: Codable {
  let name: String
  let detail: String?
  let kind: SymbolKind
  let range: Range
  let selectionRange: Range
  let children: [DocumentSymbol]?
}

struct DocumentSymbolParams: Codable {
  let textDocument: TextDocumentIdentifier
}

typealias DocumentSymbolResult = [DocumentSymbol]

// MARK: - Initialize Types

struct InitializeParams: Codable {
  let processId: Int?
  let rootPath: String?
  let rootUri: String?
  let capabilities: ClientCapabilities
  let trace: String?
  let workspaceFolders: [WorkspaceFolder]?
}

struct ClientCapabilities: Codable {
  let workspace: WorkspaceClientCapabilities?
  let textDocument: TextDocumentClientCapabilities?
}

struct WorkspaceClientCapabilities: Codable {
  // We can expand this as needed
}

struct TextDocumentClientCapabilities: Codable {
  let completion: CompletionClientCapabilities?
  let synchronization: TextDocumentSyncClientCapabilities?
}

struct CompletionClientCapabilities: Codable {
  let snippetSupport: Bool?
}

struct TextDocumentSyncClientCapabilities: Codable {
  let dynamicRegistration: Bool?
}

struct WorkspaceFolder: Codable {
  let uri: String
  let name: String
}

struct ServerCapabilities: Codable {
  let textDocumentSync: TextDocumentSyncOptions?
  let completionProvider: CompletionOptions?
  let hoverProvider: Bool?
  let definitionProvider: Bool?
  let referencesProvider: Bool?
  let documentFormattingProvider: Bool?
  let documentSymbolProvider: Bool?
  let signatureHelpProvider: SignatureHelpOptions?
  let semanticTokensProvider: SemanticTokensOptions?

  init(
    textDocumentSync: TextDocumentSyncOptions,
    completionProvider: CompletionOptions,
    hoverProvider: Bool = true,
    definitionProvider: Bool = true,
    referencesProvider: Bool = true,
    documentFormattingProvider: Bool = true,
    documentSymbolProvider: Bool = true,
    signatureHelpProvider: SignatureHelpOptions? = nil,
    semanticTokensProvider: SemanticTokensOptions? = nil
  ) {
    self.textDocumentSync = textDocumentSync
    self.completionProvider = completionProvider
    self.hoverProvider = hoverProvider
    self.definitionProvider = definitionProvider
    self.referencesProvider = referencesProvider
    self.documentFormattingProvider = documentFormattingProvider
    self.documentSymbolProvider = documentSymbolProvider
    self.signatureHelpProvider = signatureHelpProvider
    self.semanticTokensProvider = semanticTokensProvider
  }
}

struct SemanticTokensOptions: Codable {
  let legend: SemanticTokensLegend
  let full: SemanticTokensFullOptions?
  let range: Bool?
  let delta: Bool?  // Top-level delta support for some clients

  init(legend: SemanticTokensLegend, full: Bool = true, range: Bool? = nil) {
    self.legend = legend
    self.full = full ? SemanticTokensFullOptions(delta: true) : nil
    self.range = range
    self.delta = true
  }
}

struct SemanticTokensFullOptions: Codable {
  let delta: Bool?  // Support delta updates

  init(delta: Bool? = nil) {
    self.delta = delta
  }
}

struct SemanticTokensLegend: Codable {
  let tokenTypes: [String]
  let tokenModifiers: [String]
}

struct SemanticTokensParams: Codable {
  let textDocument: TextDocumentIdentifier
}

struct SemanticTokensRangeParams: Codable {
  let textDocument: TextDocumentIdentifier
  let range: Range
}

struct SemanticTokens: Codable {
  let data: [Int]
}

struct TextDocumentSyncOptions: Codable {
  let openClose: Bool
  let change: Int  // TextDocumentSyncKind
  let save: SaveOptions?

  init(openClose: Bool = true, change: Int = 1) {
    self.openClose = openClose
    self.change = change
    self.save = SaveOptions(includeText: false)
  }
}

struct SaveOptions: Codable {
  let includeText: Bool
}

struct CompletionOptions: Codable {
  let triggerCharacters: [String]?
  let resolveProvider: Bool?

  init(triggerCharacters: [String]) {
    self.triggerCharacters = triggerCharacters
    self.resolveProvider = false
  }
}

struct InitializeResult: Codable {
  let capabilities: ServerCapabilities
  let serverInfo: ServerInfo?

  struct ServerInfo: Codable {
    let name: String
    let version: String?
  }
}

// MARK: - Document Sync Params

struct DidOpenTextDocumentParams: Codable {
  let textDocument: TextDocumentItem
}

struct DidChangeTextDocumentParams: Codable {
  let textDocument: VersionedTextDocumentIdentifier
  let contentChanges: [TextDocumentContentChangeEvent]
}

struct DidCloseTextDocumentParams: Codable {
  let textDocument: TextDocumentIdentifier
}

struct DidSaveTextDocumentParams: Codable {
  let textDocument: TextDocumentIdentifier
  let text: String?
}
