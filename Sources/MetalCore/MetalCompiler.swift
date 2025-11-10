import Foundation

/// Handles Metal shader compilation and diagnostic extraction
public class MetalCompiler {
    private let temporaryDirectory: URL

    public init() {
        self.temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("metal-lsp-\(UUID().uuidString)")

        try? FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    /// Compile Metal code and return diagnostics
    public func compile(source: String, uri: String) -> [MetalDiagnostic] {
        // Create temporary file
        let tempFile = temporaryDirectory.appendingPathComponent("shader.metal")

        do {
            try source.write(to: tempFile, atomically: true, encoding: .utf8)
        } catch {
            return [MetalDiagnostic(
                line: 0,
                column: 0,
                severity: .error,
                message: "Failed to write temporary file: \(error.localizedDescription)"
            )]
        }

        // Extract include paths from the source file's directory
        var includePaths: [String] = []
        if let fileURL = URL(string: uri),
           fileURL.isFileURL {
            // Add the file's directory
            let fileDir = fileURL.deletingLastPathComponent().path
            includePaths.append(fileDir)

            // Add parent directory for relative imports like "../Common.h"
            let parentDir = fileURL.deletingLastPathComponent().deletingLastPathComponent().path
            includePaths.append(parentDir)
        }

        // Run Metal compiler
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")

        var arguments = ["metal", "-c", tempFile.path, "-o", temporaryDirectory.appendingPathComponent("shader.air").path]

        // Add include directories
        for includePath in includePaths {
            arguments.append("-I")
            arguments.append(includePath)
        }

        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return [MetalDiagnostic(
                line: 0,
                column: 0,
                severity: .error,
                message: "Failed to run Metal compiler: \(error.localizedDescription)"
            )]
        }

        // Parse stderr for diagnostics
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
        guard let errorOutput = String(data: errorData, encoding: .utf8) else {
            return []
        }

        // Clean up temporary files
        try? FileManager.default.removeItem(at: tempFile)
        try? FileManager.default.removeItem(
            at: temporaryDirectory.appendingPathComponent("shader.air")
        )

        return parseDiagnostics(from: errorOutput)
    }

    /// Parse Metal compiler output into diagnostics
    private func parseDiagnostics(from output: String) -> [MetalDiagnostic] {
        var diagnostics: [MetalDiagnostic] = []

        let lines = output.split(separator: "\n")
        for line in lines {
            let lineStr = String(line)

            // Parse format: "file.metal:line:column: error/warning: message"
            // Example: "shader.metal:10:5: error: use of undeclared identifier 'foo'"
            if let diagnostic = parseDiagnosticLine(lineStr) {
                diagnostics.append(diagnostic)
            }
        }

        return diagnostics
    }

    private func parseDiagnosticLine(_ line: String) -> MetalDiagnostic? {
        // Pattern: filename:line:column: severity: message
        let pattern = #"^.*?:(\d+):(\d+):\s*(error|warning|note):\s*(.*)$"#

        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: line,
                range: NSRange(line.startIndex..., in: line)
              ) else {
            return nil
        }

        guard match.numberOfRanges == 5 else {
            return nil
        }

        let lineNum = Int((line as NSString).substring(with: match.range(at: 1))) ?? 0
        let column = Int((line as NSString).substring(with: match.range(at: 2))) ?? 0
        let severityStr = (line as NSString).substring(with: match.range(at: 3))
        let message = (line as NSString).substring(with: match.range(at: 4))

        let severity: MetalDiagnosticSeverity
        switch severityStr {
        case "error":
            severity = .error
        case "warning":
            severity = .warning
        default:
            severity = .information
        }

        return MetalDiagnostic(
            line: max(0, lineNum - 1), // Convert to 0-based
            column: max(0, column - 1), // Convert to 0-based
            severity: severity,
            message: message
        )
    }
}

/// Represents a diagnostic from the Metal compiler
public struct MetalDiagnostic {
    public let line: Int
    public let column: Int
    public let severity: MetalDiagnosticSeverity
    public let message: String

    public init(line: Int, column: Int, severity: MetalDiagnosticSeverity, message: String) {
        self.line = line
        self.column = column
        self.severity = severity
        self.message = message
    }
}

public enum MetalDiagnosticSeverity {
    case error
    case warning
    case information
    case hint
}
