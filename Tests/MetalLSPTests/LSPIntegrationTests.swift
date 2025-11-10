import Testing
import Foundation
@testable import MetalLanguageServer
@testable import MetalCore

/// Integration tests that verify LSP protocol compliance
/// These tests simulate a real LSP client communicating with the server
@Suite("LSP Integration Tests")
struct LSPIntegrationTests {

    // MARK: - Helper Methods

    func startServer() throws -> (process: Process, inputPipe: Pipe, outputPipe: Pipe, errorPipe: Pipe) {
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        let process = Process()

        // Find the metal-lsp binary
        let binaryPath: String
        if FileManager.default.fileExists(atPath: ".build/release/metal-lsp") {
            binaryPath = ".build/release/metal-lsp"
        } else if FileManager.default.fileExists(atPath: ".build/debug/metal-lsp") {
            binaryPath = ".build/debug/metal-lsp"
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

        return (process, inputPipe, outputPipe, errorPipe)
    }

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
              let lengthStr = contentLengthLine.split(separator: ":").last?.trimmingCharacters(in: .whitespaces),
              let contentLength = Int(lengthStr) else {
            return nil
        }

        // Read content
        let contentData = try outputPipe.fileHandleForReading.read(upToCount: contentLength)!

        return try JSONSerialization.jsonObject(with: contentData) as? [String: Any]
    }

    // MARK: - Tests

    @Test("Server initializes correctly")
    func serverInitialize() throws {
        let (process, inputPipe, outputPipe, _) = try startServer()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        // Send initialize request
        let initializeRequest: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "processId": NSNull(),
                "rootUri": "file:///tmp/test",
                "capabilities": [:]
            ]
        ]

        try sendMessage(initializeRequest, to: inputPipe)

        // Read response
        guard let response = try readMessage(from: outputPipe) else {
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

        // Send initialized notification
        let initializedNotification: [String: Any] = [
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": [:]
        ]
        try sendMessage(initializedNotification, to: inputPipe)
    }

    @Test("Completion provides Metal built-ins")
    func completion() throws {
        let (process, inputPipe, outputPipe, _) = try startServer()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        // Initialize
        try sendMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "processId": NSNull(),
                "rootUri": "file:///tmp/test",
                "capabilities": [:]
            ]
        ], to: inputPipe)
        _ = try readMessage(from: outputPipe)

        try sendMessage([
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": [:]
        ], to: inputPipe)

        // Open document
        try sendMessage([
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": [
                "textDocument": [
                    "uri": "file:///tmp/test.metal",
                    "languageId": "metal",
                    "version": 1,
                    "text": "#include <metal_stdlib>\nusing namespace metal;\n\nkernel void test() {\n    float\n}\n"
                ]
            ]
        ], to: inputPipe)

        // Request completion
        try sendMessage([
            "jsonrpc": "2.0",
            "id": 2,
            "method": "textDocument/completion",
            "params": [
                "textDocument": ["uri": "file:///tmp/test.metal"],
                "position": ["line": 4, "character": 9]
            ]
        ], to: inputPipe)

        guard let response = try readMessage(from: outputPipe) else {
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
        let (process, inputPipe, outputPipe, _) = try startServer()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        // Initialize
        try sendMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "processId": NSNull(),
                "rootUri": "file:///tmp/test",
                "capabilities": [:]
            ]
        ], to: inputPipe)
        _ = try readMessage(from: outputPipe)

        try sendMessage([
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": [:]
        ], to: inputPipe)

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
        try sendMessage([
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": [
                "textDocument": [
                    "uri": testFile.absoluteString,
                    "languageId": "metal",
                    "version": 1,
                    "text": errorCode
                ]
            ]
        ], to: inputPipe)

        // Save document (triggers validation)
        try sendMessage([
            "jsonrpc": "2.0",
            "method": "textDocument/didSave",
            "params": [
                "textDocument": ["uri": testFile.absoluteString]
            ]
        ], to: inputPipe)

        // Read diagnostic notification
        var foundDiagnostics = false
        for _ in 0..<5 {
            if let message = try readMessage(from: outputPipe, timeout: 1.0),
               let method = message["method"] as? String,
               method == "textDocument/publishDiagnostics" {

                guard let params = message["params"] as? [String: Any],
                      let diagnostics = params["diagnostics"] as? [[String: Any]] else {
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
        let (process, inputPipe, outputPipe, _) = try startServer()
        defer {
            if process.isRunning {
                process.terminate()
            }
        }

        // Initialize
        try sendMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "processId": NSNull(),
                "rootUri": "file:///tmp/test",
                "capabilities": [:]
            ]
        ], to: inputPipe)
        _ = try readMessage(from: outputPipe)

        try sendMessage([
            "jsonrpc": "2.0",
            "method": "initialized",
            "params": [:]
        ], to: inputPipe)

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
        try sendMessage([
            "jsonrpc": "2.0",
            "method": "textDocument/didOpen",
            "params": [
                "textDocument": [
                    "uri": metalFile.absoluteString,
                    "languageId": "metal",
                    "version": 1,
                    "text": metalContent
                ]
            ]
        ], to: inputPipe)

        // Save document (triggers validation)
        try sendMessage([
            "jsonrpc": "2.0",
            "method": "textDocument/didSave",
            "params": [
                "textDocument": ["uri": metalFile.absoluteString]
            ]
        ], to: inputPipe)

        // Read diagnostic notification
        var foundDiagnostics = false
        var diagnosticsCount = -1

        for _ in 0..<5 {
            if let message = try readMessage(from: outputPipe, timeout: 1.0),
               let method = message["method"] as? String,
               method == "textDocument/publishDiagnostics" {

                guard let params = message["params"] as? [String: Any],
                      let diagnostics = params["diagnostics"] as? [[String: Any]] else {
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

    @Test("Server shuts down gracefully")
    func shutdown() throws {
        let (process, inputPipe, outputPipe, _) = try startServer()

        // Initialize
        try sendMessage([
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": [
                "processId": NSNull(),
                "rootUri": "file:///tmp/test",
                "capabilities": [:]
            ]
        ], to: inputPipe)
        _ = try readMessage(from: outputPipe)

        // Shutdown
        try sendMessage([
            "jsonrpc": "2.0",
            "id": 2,
            "method": "shutdown",
            "params": NSNull()
        ], to: inputPipe)

        guard let response = try readMessage(from: outputPipe) else {
            Issue.record("No shutdown response")
            return
        }

        #expect(response["id"] as? Int == 2)
        #expect(response["result"] != nil)

        // Exit
        try sendMessage([
            "jsonrpc": "2.0",
            "method": "exit",
            "params": NSNull()
        ], to: inputPipe)

        // Wait for process to exit
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
    }
}

enum TestError: Error {
    case binaryNotFound
}
