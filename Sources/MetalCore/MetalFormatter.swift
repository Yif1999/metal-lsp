import Foundation

/// Handles code formatting for Metal source files
public class MetalFormatter {
  public init() {}

  /// Attempts to format Metal code using clang-format, with fallback to basic formatting
  /// - Parameters:
  ///   - source: The Metal source code to format
  ///   - tabSize: Number of spaces per tab (default: 2)
  ///   - insertSpaces: Whether to use spaces instead of tabs (default: true)
  /// - Returns: Formatted code, or original code if formatting fails
  public func format(
    source: String,
    tabSize: Int = 2,
    insertSpaces: Bool = true
  ) -> String {
    // Try to use clang-format if available
    let formatter = Process()
    formatter.executableURL = URL(fileURLWithPath: "/usr/bin/clang-format")

    let inputPipe = Pipe()
    let outputPipe = Pipe()
    let errorPipe = Pipe()

    formatter.standardInput = inputPipe
    formatter.standardOutput = outputPipe
    formatter.standardError = errorPipe

    // Set formatting options
    var args: [String] = []

    // Style based on common Metal preferences (similar to LLVM)
    args.append(
      "-style={IndentWidth: \(tabSize), UseTab: \(insertSpaces ? "Never" : "ForIndentation"), ColumnLimit: 100}"
    )

    formatter.arguments = args

    do {
      try formatter.run()

      // Write source to stdin
      if let data = source.data(using: .utf8) {
        inputPipe.fileHandleForWriting.write(data)
        try? inputPipe.fileHandleForWriting.close()
      }

      formatter.waitUntilExit()

      // Read formatted output
      let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
      if let formatted = String(data: outputData, encoding: .utf8), !formatted.isEmpty {
        return formatted
      }
    } catch {
      // If clang-format fails or is not available, fall back to basic formatting
      return basicFormat(source: source, tabSize: tabSize, insertSpaces: insertSpaces)
    }

    return basicFormat(source: source, tabSize: tabSize, insertSpaces: insertSpaces)
  }

  /// Performs basic formatting without external tools
  /// This is a fallback formatter that does simple indentation fixes
  /// - Parameters:
  ///   - source: The Metal source code to format
  ///   - tabSize: Number of spaces per tab
  ///   - insertSpaces: Whether to use spaces instead of tabs
  /// - Returns: Lightly formatted code
  public func basicFormat(
    source: String,
    tabSize: Int = 2,
    insertSpaces: Bool = true
  ) -> String {
    let indentString = insertSpaces ? String(repeating: " ", count: tabSize) : "\t"
    let lines = source.components(separatedBy: .newlines)
    var formattedLines: [String] = []
    var indentLevel = 0

    for line in lines {
      let trimmed = line.trimmingCharacters(in: .whitespaces)

      // Skip empty lines
      if trimmed.isEmpty {
        formattedLines.append("")
        continue
      }

      // Decrease indent for closing braces
      if trimmed.starts(with: "}") {
        indentLevel = max(0, indentLevel - 1)
      }

      // Add line with proper indentation
      let indent = String(repeating: indentString, count: indentLevel)
      formattedLines.append(indent + trimmed)

      // Increase indent for opening braces
      if trimmed.contains("{") && !trimmed.contains("}") {
        indentLevel += 1
      } else if !trimmed.contains("{") && trimmed.contains("}") {
        // Already handled above
      } else if trimmed.contains("{") && trimmed.contains("}") {
        // Same line has both, no net change
      }
    }

    return formattedLines.joined(separator: "\n")
  }
}
