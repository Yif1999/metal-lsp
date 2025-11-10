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

    if let items = response["result"] as? [[String: Any]] {
      #expect(!items.isEmpty, "Should have completion items")

      let labels = items.compactMap { $0["label"] as? String }
      #expect(labels.contains { $0.contains("float") }, "Should contain float completions")
    }
  }

  @Test("Diagnostics reports errors in Metal code")
  func diagnostics() throws {
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

    // Send exit notification (don't wait for actual exit, defer will clean up)
    try sendMessage(
      [
        "jsonrpc": "2.0",
        "method": "exit",
        "params": NSNull(),
      ], to: server.inputPipe)
  }
}

enum TestError: Error {
  case binaryNotFound
}
