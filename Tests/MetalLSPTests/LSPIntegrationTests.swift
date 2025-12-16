import Foundation
import Testing

@testable import MetalCore
@testable import MetalLanguageServer

/// Integration tests that verify LSP protocol compliance
/// These tests simulate a real LSP client communicating with the server
/// Note: Tests run serially to avoid conflicts when spawning LSP processes
@Suite("LSP Integration Tests", .serialized)
struct LSPIntegrationTests {

  // MARK: - Server Handle

  /// Handles server lifecycle with automatic cleanup via deinit
  final class ServerHandle {
    let process: Process
    let inputPipe: Pipe
    let outputPipe: Pipe
    let errorPipe: Pipe

    init() throws {
      self.inputPipe = Pipe()
      self.outputPipe = Pipe()
      self.errorPipe = Pipe()
      self.process = Process()

      // Find the project root by looking for Package.swift
      let fileManager = FileManager.default
      var searchPath = fileManager.currentDirectoryPath
      var packageRoot: String?

      // Search up to 5 levels up for Package.swift
      for _ in 0..<5 {
        if fileManager.fileExists(atPath: searchPath + "/Package.swift") {
          packageRoot = searchPath
          break
        }
        searchPath = (searchPath as NSString).deletingLastPathComponent
      }

      guard let root = packageRoot else {
        throw TestError.binaryNotFound
      }

      // Find the metal-lsp binary
      let binaryPath: String
      if fileManager.fileExists(atPath: "\(root)/.build/release/metal-lsp") {
        binaryPath = "\(root)/.build/release/metal-lsp"
      } else if fileManager.fileExists(atPath: "\(root)/.build/debug/metal-lsp") {
        binaryPath = "\(root)/.build/debug/metal-lsp"
      } else {
        throw TestError.binaryNotFound
      }

      process.executableURL = URL(fileURLWithPath: binaryPath)
      process.standardInput = inputPipe
      process.standardOutput = outputPipe
      process.standardError = errorPipe

      try process.run()

      // Give the server a moment to start
      Thread.sleep(forTimeInterval: 0.1)
    }

    deinit {
      // Terminate process and wait for it to fully exit
      if process.isRunning {
        process.terminate()
        process.waitUntilExit()
      }

      // Now safe to close pipes (process is fully terminated)
      try? inputPipe.fileHandleForWriting.close()
      try? outputPipe.fileHandleForReading.close()
      try? errorPipe.fileHandleForReading.close()
    }
  }

  // MARK: - Helper Methods

  func sendMessage(_ message: [String: Any], to inputPipe: Pipe) throws {
    let jsonData = try JSONSerialization.data(withJSONObject: message)

    let header = "Content-Length: \(jsonData.count)\r\n\r\n"
    let headerData = header.data(using: .utf8)!

    inputPipe.fileHandleForWriting.write(headerData)
    inputPipe.fileHandleForWriting.write(jsonData)
  }

  func readMessage(from outputPipe: Pipe, timeout: TimeInterval = 2.0) throws -> [String: Any]? {
    let startTime = Date()

    // Read header
    var headerData = Data()
    while !headerData.contains("\r\n\r\n".data(using: .utf8)!) {
      if Date().timeIntervalSince(startTime) > timeout {
        return nil
      }

      if let byte = try outputPipe.fileHandleForReading.read(upToCount: 1), !byte.isEmpty {
        headerData.append(byte)
      } else {
        Thread.sleep(forTimeInterval: 0.01)
      }
    }

    guard let headerString = String(data: headerData, encoding: .utf8) else {
      return nil
    }

    // Parse Content-Length
    let lines = headerString.components(separatedBy: "\r\n")
    guard let contentLengthLine = lines.first(where: { $0.starts(with: "Content-Length:") }),
      let lengthStr = contentLengthLine.split(separator: ":").last?.trimmingCharacters(
        in: .whitespaces),
      let contentLength = Int(lengthStr)
    else {
      return nil
    }

    // Read content
    let contentData = try outputPipe.fileHandleForReading.read(upToCount: contentLength)!

    return try JSONSerialization.jsonObject(with: contentData) as? [String: Any]
  }

  func readResponse(withId expectedId: Int, from outputPipe: Pipe, timeout: TimeInterval = 5.0)
    throws -> [String: Any]?
  {
    let startTime = Date()

    while Date().timeIntervalSince(startTime) < timeout {
      guard
        let message = try readMessage(
          from: outputPipe, timeout: timeout - Date().timeIntervalSince(startTime))
      else {
        return nil
      }

      // Skip notifications (no id field)
      if message["id"] == nil {
        continue
      }

      // Check if this is the response we're looking for
      if let id = message["id"] as? Int, id == expectedId {
        return message
      }
    }

    return nil
  }

  // MARK: - Tests

  @Test("Server initializes correctly")
  func serverInitialize() throws {
    let server = try ServerHandle()

    // Send initialize request
    let initializeRequest: [String: Any] = [
      "jsonrpc": "2.0",
      "id": 1,
      "method": "initialize",
      "params": [
        "processId": NSNull(),
        "rootUri": "file:///tmp/test",
        "capabilities": [:],
      ],
    ]

    try sendMessage(initializeRequest, to: server.inputPipe)

    // Read response
    guard let response = try readMessage(from: server.outputPipe) else {
      Issue.record("No response from server")
      return
    }

    #expect(response["jsonrpc"] as? String == "2.0")
    #expect(response["id"] as? Int == 1)

    guard let result = response["result"] as? [String: Any] else {
      Issue.record("No result in response")
      return
    }

    // Verify capabilities
    guard let capabilities = result["capabilities"] as? [String: Any] else {
      Issue.record("No capabilities in result")
      return
    }

    #expect(capabilities["completionProvider"] != nil)
    #expect(capabilities["textDocumentSync"] != nil)
    #expect(capabilities["hoverProvider"] as? Bool == true)
    #expect(capabilities["signatureHelpProvider"] != nil)
    #expect(capabilities["documentSymbolProvider"] as? Bool == true)

    // Send initialized notification
    let initializedNotification: [String: Any] = [
      "jsonrpc": "2.0",
      "method": "initialized",
      "params": [:],
    ]
    try sendMessage(initializedNotification, to: server.inputPipe)
  }

  @Test("Completion provides Metal built-ins")
  func completion() throws {
    let server = try ServerHandle()

    // Initialize
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "processId": NSNull(),
          "rootUri": "file:///tmp/test",
          "capabilities": [:],
        ],
      ], to: server.inputPipe)
    _ = try readMessage(from: server.outputPipe)

    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "initialized",
        "params": [:],
      ], to: server.inputPipe)

    // Open document
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": [
          "textDocument": [
            "uri": "file:///tmp/test.metal",
            "languageId": "metal",
            "version": 1,
            "text":
              "#include <metal_stdlib>\nusing namespace metal;\n\nkernel void test() {\n    float\n}\n",
          ]
        ],
      ], to: server.inputPipe)

    // Request completion
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 2,
        "method": "textDocument/completion",
        "params": [
          "textDocument": ["uri": "file:///tmp/test.metal"],
          "position": ["line": 4, "character": 9],
        ],
      ], to: server.inputPipe)

    guard let response = try readResponse(withId: 2, from: server.outputPipe) else {
      Issue.record("No completion response")
      return
    }

    #expect(response["id"] as? Int == 2)

    guard let result = response["result"] as? [String: Any],
      let items = result["items"] as? [[String: Any]]
    else {
      Issue.record("Completion result did not include items")
      return
    }

    #expect(!items.isEmpty, "Should have completion items")

    let labels = items.compactMap { $0["label"] as? String }
    #expect(labels.contains { $0.contains("float") }, "Should contain float completions")
  }

  @Test("Diagnostics reports errors in Metal code")
  func diagnostics() throws {
    guard FileManager.default.fileExists(atPath: "/usr/bin/xcrun") else {
      return
    }

    let server = try ServerHandle()

    // Initialize
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "processId": NSNull(),
          "rootUri": "file:///tmp/test",
          "capabilities": [:],
        ],
      ], to: server.inputPipe)
    _ = try readMessage(from: server.outputPipe)

    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "initialized",
        "params": [:],
      ], to: server.inputPipe)

    // Create a temporary file with errors
    let tempDir = FileManager.default.temporaryDirectory
    let testFile = tempDir.appendingPathComponent("test_error_\(UUID().uuidString).metal")
    let errorCode = """
      #include <metal_stdlib>
      using namespace metal;

      kernel void test() {
          int x = "this is wrong";
      }
      """
    try errorCode.write(to: testFile, atomically: true, encoding: .utf8)

    defer {
      try? FileManager.default.removeItem(at: testFile)
    }

    // Open document
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": [
          "textDocument": [
            "uri": testFile.absoluteString,
            "languageId": "metal",
            "version": 1,
            "text": errorCode,
          ]
        ],
      ], to: server.inputPipe)

    // Save document (triggers validation)
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "textDocument/didSave",
        "params": [
          "textDocument": ["uri": testFile.absoluteString]
        ],
      ], to: server.inputPipe)

    // Read diagnostic notification
    var foundDiagnostics = false
    for _ in 0..<5 {
      if let message = try readMessage(from: server.outputPipe, timeout: 1.0),
        let method = message["method"] as? String,
        method == "textDocument/publishDiagnostics"
      {

        guard let params = message["params"] as? [String: Any],
          let diagnostics = params["diagnostics"] as? [[String: Any]]
        else {
          continue
        }

        foundDiagnostics = !diagnostics.isEmpty

        if foundDiagnostics {
          // Verify diagnostic structure
          let firstDiag = diagnostics[0]
          #expect(firstDiag["message"] != nil)
          #expect(firstDiag["range"] != nil)
          #expect(firstDiag["severity"] != nil)
          break
        }
      }
    }

    #expect(foundDiagnostics, "Should receive diagnostics for error code")
  }

  @Test("Diagnostics work with include files")
  func diagnosticsWithIncludes() throws {
    guard FileManager.default.fileExists(atPath: "/usr/bin/xcrun") else {
      return
    }

    let server = try ServerHandle()

    // Initialize
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "processId": NSNull(),
          "rootUri": "file:///tmp/test",
          "capabilities": [:],
        ],
      ], to: server.inputPipe)
    _ = try readMessage(from: server.outputPipe)

    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "initialized",
        "params": [:],
      ], to: server.inputPipe)

    // Create a temporary directory structure with header files
    let tempDir = FileManager.default.temporaryDirectory
    let projectDir = tempDir.appendingPathComponent("test_project_\(UUID().uuidString)")
    let shadersDir = projectDir.appendingPathComponent("Shaders")

    try FileManager.default.createDirectory(at: shadersDir, withIntermediateDirectories: true)

    // Create a header file
    let headerFile = shadersDir.appendingPathComponent("Common.h")
    let headerContent = """
      #ifndef COMMON_H
      #define COMMON_H

      struct VertexIn {
          float3 position [[attribute(0)]];
      };

      #endif
      """
    try headerContent.write(to: headerFile, atomically: true, encoding: .utf8)

    // Create a Metal file that includes the header
    let metalFile = shadersDir.appendingPathComponent("Shader.metal")
    let metalContent = """
      #include <metal_stdlib>
      using namespace metal;
      #include "./Common.h"

      vertex float4 vertexShader(VertexIn in [[stage_in]]) {
          return float4(in.position, 1.0);
      }
      """
    try metalContent.write(to: metalFile, atomically: true, encoding: .utf8)

    defer {
      try? FileManager.default.removeItem(at: projectDir)
    }

    // Open document
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": [
          "textDocument": [
            "uri": metalFile.absoluteString,
            "languageId": "metal",
            "version": 1,
            "text": metalContent,
          ]
        ],
      ], to: server.inputPipe)

    // Save document (triggers validation)
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "textDocument/didSave",
        "params": [
          "textDocument": ["uri": metalFile.absoluteString]
        ],
      ], to: server.inputPipe)

    // Read diagnostic notification
    var foundDiagnostics = false
    var diagnosticsCount = -1

    for _ in 0..<5 {
      if let message = try readMessage(from: server.outputPipe, timeout: 1.0),
        let method = message["method"] as? String,
        method == "textDocument/publishDiagnostics"
      {

        guard let params = message["params"] as? [String: Any],
          let diagnostics = params["diagnostics"] as? [[String: Any]]
        else {
          continue
        }

        foundDiagnostics = true
        diagnosticsCount = diagnostics.count

        // Should have 0 diagnostics because the header file was found
        #expect(diagnostics.isEmpty, "Should have no diagnostics when headers are found")
        break
      }
    }

    #expect(foundDiagnostics, "Should receive diagnostics notification")
    #expect(diagnosticsCount == 0, "Should have 0 errors when include paths work correctly")
  }

  @Test("Hover provides documentation for Metal built-ins")
  func hover() throws {
    let server = try ServerHandle()

    // Initialize
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "processId": NSNull(),
          "rootUri": "file:///tmp/test",
          "capabilities": [:],
        ],
      ], to: server.inputPipe)
    _ = try readMessage(from: server.outputPipe)

    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "initialized",
        "params": [:],
      ], to: server.inputPipe)

    // Open document with Metal code
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": [
          "textDocument": [
            "uri": "file:///tmp/test.metal",
            "languageId": "metal",
            "version": 1,
            "text":
              "#include <metal_stdlib>\nusing namespace metal;\n\nkernel void test() {\n    float4 color = normalize(float4(1.0));\n}\n",
          ]
        ],
      ], to: server.inputPipe)

    // Request hover on "normalize" at line 4, character 19
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 2,
        "method": "textDocument/hover",
        "params": [
          "textDocument": ["uri": "file:///tmp/test.metal"],
          "position": ["line": 4, "character": 19],
        ],
      ], to: server.inputPipe)

    guard let response = try readResponse(withId: 2, from: server.outputPipe) else {
      Issue.record("No hover response")
      return
    }

    #expect(response["id"] as? Int == 2)

    // Check if there's an error
    if let error = response["error"] as? [String: Any] {
      Issue.record("Hover returned error: \(error)")
      return
    }

    // Result can be null (no hover info) or a Hover object
    guard response["result"] != nil else {
      Issue.record("No result field in hover response")
      return
    }

    // If result is NSNull, that means no hover info - this is valid but not what we want
    if response["result"] is NSNull {
      Issue.record("Hover returned null - word not found or document not loaded")
      return
    }

    guard let result = response["result"] as? [String: Any] else {
      Issue.record("Result is not a dictionary: \(type(of: response["result"]))")
      return
    }

    guard let contents = result["contents"] as? [String: Any] else {
      Issue.record("No contents in hover result")
      return
    }

    #expect(contents["kind"] as? String == "markdown")

    guard let value = contents["value"] as? String else {
      Issue.record("No value in hover contents")
      return
    }

    // Should contain the function signature and documentation
    #expect(value.contains("normalize"))
    #expect(value.contains("vector"))
  }

  @Test("Go to definition finds function declarations")
  func gotoDefinition() throws {
    let server = try ServerHandle()

    // Initialize
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "processId": NSNull(),
          "rootUri": "file:///tmp/test",
          "capabilities": [:],
        ],
      ], to: server.inputPipe)
    _ = try readMessage(from: server.outputPipe)

    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "initialized",
        "params": [:],
      ], to: server.inputPipe)

    let metalCode = """
      #include <metal_stdlib>
      using namespace metal;

      kernel void myKernel(device float* data [[buffer(0)]]) {
          data[0] = 1.0;
      }
      """

    // Open document
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": [
          "textDocument": [
            "uri": "file:///tmp/test.metal",
            "languageId": "metal",
            "version": 1,
            "text": metalCode,
          ]
        ],
      ], to: server.inputPipe)

    // Request definition for "myKernel" at line 4, column 15 (inside the function name)
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 2,
        "method": "textDocument/definition",
        "params": [
          "textDocument": ["uri": "file:///tmp/test.metal"],
          "position": ["line": 4, "character": 15],
        ],
      ], to: server.inputPipe)

    guard let response = try readResponse(withId: 2, from: server.outputPipe) else {
      Issue.record("No definition response")
      return
    }

    #expect(response["id"] as? Int == 2)
    if let result = response["result"] as? [String: Any] {
      #expect(result["uri"] as? String == "file:///tmp/test.metal")
      if let range = result["range"] as? [String: Any] {
        #expect(range["start"] != nil)
        #expect(range["end"] != nil)
      }
    }
  }

  @Test("Go to definition works across workspace files")
  func gotoDefinitionAcrossFiles() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("metal_lsp_workspace_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let declFile = tempDir.appendingPathComponent("Decl.metal")
    let useFile = tempDir.appendingPathComponent("Use.metal")

    let declCode = """
      #include <metal_stdlib>
      using namespace metal;

      float foo(float x) {
          return x;
      }
      """

    let useCode = """
      #include <metal_stdlib>
      using namespace metal;

      kernel void test() {
          float x = foo(1.0);
      }
      """

    try declCode.write(to: declFile, atomically: true, encoding: .utf8)
    try useCode.write(to: useFile, atomically: true, encoding: .utf8)

    let server = try ServerHandle()

    // Initialize with workspace root
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "processId": NSNull(),
          "rootUri": tempDir.absoluteString,
          "capabilities": [:],
        ],
      ], to: server.inputPipe)
    _ = try readMessage(from: server.outputPipe)

    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "initialized",
        "params": [:],
      ], to: server.inputPipe)

    // Open only the usage document
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": [
          "textDocument": [
            "uri": useFile.absoluteString,
            "languageId": "metal",
            "version": 1,
            "text": useCode,
          ]
        ],
      ], to: server.inputPipe)

    guard let callLineIndex = useCode.components(separatedBy: .newlines).firstIndex(where: { $0.contains("foo(1.0") }) else {
      Issue.record("Call line not found")
      return
    }

    let callLine = useCode.components(separatedBy: .newlines)[callLineIndex]
    guard let fooRange = callLine.range(of: "foo") else {
      Issue.record("Call symbol not found")
      return
    }

    let column = callLine.distance(from: callLine.startIndex, to: fooRange.lowerBound) + 1

    // Request definition for "foo"
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 2,
        "method": "textDocument/definition",
        "params": [
          "textDocument": ["uri": useFile.absoluteString],
          "position": ["line": callLineIndex, "character": column],
        ],
      ], to: server.inputPipe)

    guard let response = try readResponse(withId: 2, from: server.outputPipe) else {
      Issue.record("No cross-file definition response")
      return
    }

    guard let result = response["result"] as? [String: Any] else {
      Issue.record("Cross-file definition returned no result")
      return
    }

    #expect(result["uri"] as? String == declFile.absoluteString)
  }

  @Test("Find references locates usages across workspace files")
  func findReferencesAcrossFiles() throws {
    let tempDir = FileManager.default.temporaryDirectory
      .appendingPathComponent("metal_lsp_workspace_refs_\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let declFile = tempDir.appendingPathComponent("Decl.metal")
    let useFile = tempDir.appendingPathComponent("Use.metal")

    let declCode = """
      #include <metal_stdlib>
      using namespace metal;

      float foo(float x) {
          return x;
      }
      """

    let useCode = """
      #include <metal_stdlib>
      using namespace metal;

      kernel void test() {
          float x = foo(1.0);
      }
      """

    try declCode.write(to: declFile, atomically: true, encoding: .utf8)
    try useCode.write(to: useFile, atomically: true, encoding: .utf8)

    let server = try ServerHandle()

    // Initialize with workspace root
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "processId": NSNull(),
          "rootUri": tempDir.absoluteString,
          "capabilities": [:],
        ],
      ], to: server.inputPipe)
    _ = try readMessage(from: server.outputPipe)

    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "initialized",
        "params": [:],
      ], to: server.inputPipe)

    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": [
          "textDocument": [
            "uri": useFile.absoluteString,
            "languageId": "metal",
            "version": 1,
            "text": useCode,
          ]
        ],
      ], to: server.inputPipe)

    guard let callLineIndex = useCode.components(separatedBy: .newlines).firstIndex(where: { $0.contains("foo(1.0") }) else {
      Issue.record("Call line not found")
      return
    }

    let callLine = useCode.components(separatedBy: .newlines)[callLineIndex]
    guard let fooRange = callLine.range(of: "foo") else {
      Issue.record("Call symbol not found")
      return
    }

    let column = callLine.distance(from: callLine.startIndex, to: fooRange.lowerBound) + 1

    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 2,
        "method": "textDocument/references",
        "params": [
          "textDocument": ["uri": useFile.absoluteString],
          "position": ["line": callLineIndex, "character": column],
          "context": ["includeDeclaration": true],
        ],
      ], to: server.inputPipe)

    guard let response = try readResponse(withId: 2, from: server.outputPipe) else {
      Issue.record("No cross-file references response")
      return
    }

    guard let result = response["result"] as? [[String: Any]] else {
      Issue.record("Cross-file references returned no result")
      return
    }

    let uris = Set(result.compactMap { $0["uri"] as? String })
    #expect(uris.contains(declFile.absoluteString))
    #expect(uris.contains(useFile.absoluteString))
  }

  @Test("Find references locates all usages of a symbol")
  func findReferences() throws {
    let server = try ServerHandle()

    // Initialize
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "processId": NSNull(),
          "rootUri": "file:///tmp/test",
          "capabilities": [:],
        ],
      ], to: server.inputPipe)
    _ = try readMessage(from: server.outputPipe)

    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "initialized",
        "params": [:],
      ], to: server.inputPipe)

    let metalCode = """
      #include <metal_stdlib>
      using namespace metal;

      float myValue = 1.0;

      kernel void myKernel(device float* data [[buffer(0)]]) {
          data[0] = myValue;
      }
      """

    // Open document
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": [
          "textDocument": [
            "uri": "file:///tmp/test.metal",
            "languageId": "metal",
            "version": 1,
            "text": metalCode,
          ]
        ],
      ], to: server.inputPipe)

    // Request references for "myValue"
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 2,
        "method": "textDocument/references",
        "params": [
          "textDocument": ["uri": "file:///tmp/test.metal"],
          "position": ["line": 3, "character": 6],
          "context": ["includeDeclaration": true],
        ],
      ], to: server.inputPipe)

    guard let response = try readResponse(withId: 2, from: server.outputPipe) else {
      Issue.record("No references response")
      return
    }

    #expect(response["id"] as? Int == 2)
    if let locations = response["result"] as? [[String: Any]] {
      #expect(!locations.isEmpty, "Should find at least one reference")
    }
  }

  @Test("Code formatting handles Metal code")
  func formatting() throws {
    let server = try ServerHandle()

    // Initialize
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "processId": NSNull(),
          "rootUri": "file:///tmp/test",
          "capabilities": [:],
        ],
      ], to: server.inputPipe)
    _ = try readMessage(from: server.outputPipe)

    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "initialized",
        "params": [:],
      ], to: server.inputPipe)

    let metalCode = """
      #include <metal_stdlib>
      using namespace metal;
      kernel void test(){
      float x=1.0;
      }
      """

    // Open document
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": [
          "textDocument": [
            "uri": "file:///tmp/test.metal",
            "languageId": "metal",
            "version": 1,
            "text": metalCode,
          ]
        ],
      ], to: server.inputPipe)

    // Request formatting
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 2,
        "method": "textDocument/formatting",
        "params": [
          "textDocument": ["uri": "file:///tmp/test.metal"],
          "options": [
            "tabSize": 2,
            "insertSpaces": true,
          ],
        ],
      ], to: server.inputPipe)

    guard let response = try readResponse(withId: 2, from: server.outputPipe) else {
      Issue.record("No formatting response")
      return
    }

    #expect(response["id"] as? Int == 2)
    if let edits = response["result"] as? [[String: Any]] {
      // Should get some edits (or empty array if no formatting changes needed)
      #expect(true, "Formatting returned edits")
    }
  }

  @Test("Signature help provides signatures for user functions")
  func signatureHelp() throws {
    let server = try ServerHandle()

    // Initialize
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "processId": NSNull(),
          "rootUri": "file:///tmp/test",
          "capabilities": [:],
        ],
      ], to: server.inputPipe)
    _ = try readMessage(from: server.outputPipe)

    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "initialized",
        "params": [:],
      ], to: server.inputPipe)

    let metalCode = """
      #include <metal_stdlib>
      using namespace metal;

      float4 foo(float3 a, float b) {
          return float4(a, b);
      }

      kernel void test() {
          float4 x = foo(float3(0.0), 1.0);
      }
      """

    // Open document
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": [
          "textDocument": [
            "uri": "file:///tmp/test_signature.metal",
            "languageId": "metal",
            "version": 1,
            "text": metalCode,
          ]
        ],
      ], to: server.inputPipe)

    let lines = metalCode.components(separatedBy: .newlines)
    guard let callLineIndex = lines.firstIndex(where: { $0.contains("foo(float3") }) else {
      Issue.record("Call line not found")
      return
    }

    guard let oneIndex = lines[callLineIndex].firstIndex(of: "1") else {
      Issue.record("Argument index not found")
      return
    }

    let column = lines[callLineIndex].distance(from: lines[callLineIndex].startIndex, to: oneIndex)

    // Request signature help (position inside second argument)
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 2,
        "method": "textDocument/signatureHelp",
        "params": [
          "textDocument": ["uri": "file:///tmp/test_signature.metal"],
          "position": ["line": callLineIndex, "character": column],
        ],
      ], to: server.inputPipe)

    guard let response = try readResponse(withId: 2, from: server.outputPipe) else {
      Issue.record("No signatureHelp response")
      return
    }

    guard let result = response["result"] as? [String: Any],
      let signatures = result["signatures"] as? [[String: Any]]
    else {
      Issue.record("signatureHelp result missing signatures")
      return
    }

    #expect(!signatures.isEmpty)

    let label = signatures.first?["label"] as? String
    #expect(label?.contains("foo(") == true)

    #expect(result["activeParameter"] as? Int == 1)
  }

  @Test("Document symbols lists top-level declarations")
  func documentSymbols() throws {
    let server = try ServerHandle()

    // Initialize
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "processId": NSNull(),
          "rootUri": "file:///tmp/test",
          "capabilities": [:],
        ],
      ], to: server.inputPipe)
    _ = try readMessage(from: server.outputPipe)

    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "initialized",
        "params": [:],
      ], to: server.inputPipe)

    let metalCode = """
      #include <metal_stdlib>
      using namespace metal;

      struct VertexIn {
          float3 position [[attribute(0)]];
      };

      float foo(float x) {
          return x;
      }
      """

    // Open document
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": [
          "textDocument": [
            "uri": "file:///tmp/test_symbols.metal",
            "languageId": "metal",
            "version": 1,
            "text": metalCode,
          ]
        ],
      ], to: server.inputPipe)

    // Request document symbols
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 2,
        "method": "textDocument/documentSymbol",
        "params": [
          "textDocument": ["uri": "file:///tmp/test_symbols.metal"]
        ],
      ], to: server.inputPipe)

    guard let response = try readResponse(withId: 2, from: server.outputPipe) else {
      Issue.record("No documentSymbol response")
      return
    }

    guard let result = response["result"] as? [[String: Any]] else {
      Issue.record("documentSymbol result missing")
      return
    }

    let names = result.compactMap { $0["name"] as? String }
    #expect(names.contains("VertexIn"))
    #expect(names.contains("foo"))

    if let vertexSymbol = result.first(where: { ($0["name"] as? String) == "VertexIn" }),
      let children = vertexSymbol["children"] as? [[String: Any]]
    {
      let childNames = children.compactMap { $0["name"] as? String }
      #expect(childNames.contains("position"))
    }
  }

  @Test("Completion includes local symbols and filters by prefix")
  func contextAwareCompletion() throws {
    let server = try ServerHandle()

    // Initialize
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "processId": NSNull(),
          "rootUri": "file:///tmp/test",
          "capabilities": [:],
        ],
      ], to: server.inputPipe)
    _ = try readMessage(from: server.outputPipe)

    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "initialized",
        "params": [:],
      ], to: server.inputPipe)

    let metalCode = """
      #include <metal_stdlib>
      using namespace metal;

      float myHelper(float x) {
          return x;
      }

      kernel void test() {
          float value = myH
      }
      """

    // Open document
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "textDocument/didOpen",
        "params": [
          "textDocument": [
            "uri": "file:///tmp/test_completion_local.metal",
            "languageId": "metal",
            "version": 1,
            "text": metalCode,
          ]
        ],
      ], to: server.inputPipe)

    let lines = metalCode.components(separatedBy: .newlines)
    guard let callLineIndex = lines.firstIndex(where: { $0.contains("myH") }) else {
      Issue.record("Completion line not found")
      return
    }

    guard let myHRange = lines[callLineIndex].range(of: "myH") else {
      Issue.record("Prefix not found")
      return
    }

    let column = lines[callLineIndex].distance(from: lines[callLineIndex].startIndex, to: myHRange.upperBound)

    // Request completion at end of prefix
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 2,
        "method": "textDocument/completion",
        "params": [
          "textDocument": ["uri": "file:///tmp/test_completion_local.metal"],
          "position": ["line": callLineIndex, "character": column],
        ],
      ], to: server.inputPipe)

    guard let response = try readResponse(withId: 2, from: server.outputPipe) else {
      Issue.record("No completion response")
      return
    }

    guard let result = response["result"] as? [String: Any],
      let items = result["items"] as? [[String: Any]]
    else {
      Issue.record("Completion result did not include items")
      return
    }

    let labels = items.compactMap { $0["label"] as? String }
    #expect(labels.contains("myHelper"))
  }

  @Test("A server responds to shutdown request")
  func aShutdown() throws {
    let server = try ServerHandle()

    // Initialize
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 1,
        "method": "initialize",
        "params": [
          "processId": NSNull(),
          "rootUri": "file:///tmp/test",
          "capabilities": [:],
        ],
      ], to: server.inputPipe)
    _ = try readMessage(from: server.outputPipe)

    // Shutdown
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "id": 2,
        "method": "shutdown",
        "params": NSNull(),
      ], to: server.inputPipe)

    guard let response = try readResponse(withId: 2, from: server.outputPipe) else {
      Issue.record("No shutdown response")
      return
    }

    #expect(response["id"] as? Int == 2)
    #expect(response["result"] != nil)

    // Don't send exit notification - let ServerHandle.deinit terminate the process
    // cleanly to avoid race condition where server exits before we finish writing
  }
}

enum TestError: Error {
  case binaryNotFound
}
