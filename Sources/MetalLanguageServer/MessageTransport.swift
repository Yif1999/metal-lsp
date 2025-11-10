import Foundation

/// Handles reading and writing JSON-RPC messages over stdio using Content-Length header protocol
class MessageTransport {
    private let input: FileHandle
    private let output: FileHandle
    private let logMessages: Bool
    private var buffer = Data()

    init(
        input: FileHandle = FileHandle.standardInput,
        output: FileHandle = FileHandle.standardOutput,
        logMessages: Bool = false
    ) {
        self.input = input
        self.output = output
        self.logMessages = logMessages
    }

    /// Read the next message from input
    func readMessage() throws -> Data? {
        // Read headers
        guard let headers = try readHeaders() else {
            return nil
        }

        // Extract Content-Length
        guard let contentLengthStr = headers["Content-Length"],
              let contentLength = Int(contentLengthStr) else {
            throw TransportError.missingContentLength
        }

        // Read the content
        let content = try readData(length: contentLength)

        if logMessages {
            if let jsonString = String(data: content, encoding: .utf8) {
                logToStderr("← Received: \(jsonString)")
            }
        }

        return content
    }

    /// Write a message to output
    func writeMessage(_ data: Data) throws {
        let contentLength = data.count
        let header = "Content-Length: \(contentLength)\r\n\r\n"

        guard let headerData = header.data(using: .utf8) else {
            throw TransportError.encodingError
        }

        if logMessages {
            if let jsonString = String(data: data, encoding: .utf8) {
                logToStderr("→ Sending: \(jsonString)")
            }
        }

        output.write(headerData)
        output.write(data)
    }

    /// Write an encodable object as JSON
    func writeJSON<T: Encodable>(_ value: T) throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(value)
        try writeMessage(data)
    }

    // MARK: - Private Helpers

    private func readHeaders() throws -> [String: String]? {
        var headers: [String: String] = [:]

        while true {
            guard let line = try readLine() else {
                return nil
            }

            // Empty line indicates end of headers
            if line.isEmpty {
                break
            }

            // Parse header "Key: Value"
            let parts = line.split(separator: ":", maxSplits: 1)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                headers[key] = value
            }
        }

        return headers
    }

    private func readLine() throws -> String? {
        while true {
            // Check if we have a complete line in buffer
            if let newlineRange = buffer.range(of: "\r\n".data(using: .utf8)!) {
                let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)

                if let line = String(data: lineData, encoding: .utf8) {
                    return line
                }
            }

            // Read more data
            let chunk = input.availableData
            if chunk.isEmpty {
                return nil // EOF
            }
            buffer.append(chunk)
        }
    }

    private func readData(length: Int) throws -> Data {
        var result = Data()
        result.reserveCapacity(length)

        // First use any buffered data
        if !buffer.isEmpty {
            let bytesToTake = min(buffer.count, length)
            result.append(buffer.prefix(bytesToTake))
            buffer.removeFirst(bytesToTake)
        }

        // Read remaining bytes
        while result.count < length {
            let chunk = input.availableData
            if chunk.isEmpty {
                throw TransportError.unexpectedEOF
            }

            let remaining = length - result.count
            let bytesToTake = min(chunk.count, remaining)
            result.append(chunk.prefix(bytesToTake))

            // Put back any extra bytes
            if chunk.count > bytesToTake {
                buffer.insert(contentsOf: chunk.suffix(from: bytesToTake), at: buffer.startIndex)
            }
        }

        return result
    }

    private func logToStderr(_ message: String) {
        let log = "[\(Date())] \(message)\n"
        if let data = log.data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }
}

enum TransportError: Error, LocalizedError {
    case missingContentLength
    case encodingError
    case unexpectedEOF

    var errorDescription: String? {
        switch self {
        case .missingContentLength:
            return "Missing Content-Length header"
        case .encodingError:
            return "Failed to encode message"
        case .unexpectedEOF:
            return "Unexpected end of file"
        }
    }
}
