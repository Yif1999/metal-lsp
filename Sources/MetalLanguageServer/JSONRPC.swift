import Foundation

// MARK: - JSON-RPC Message Types


/// JSON-RPC Request
struct JSONRPCRequest: Codable {
  let jsonrpc: String
  let id: RequestID
  let method: String
  let params: JSONValue?

  enum CodingKeys: String, CodingKey {
    case jsonrpc, id, method, params
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
    self.id = try container.decode(RequestID.self, forKey: .id)
    self.method = try container.decode(String.self, forKey: .method)
    self.params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
  }
}

/// JSON-RPC Response
struct JSONRPCResponse: Codable {
  let jsonrpc: String
  let id: RequestID?
  let result: JSONValue?
  let error: ResponseError?

  init(id: RequestID?, result: JSONValue) {
    self.jsonrpc = "2.0"
    self.id = id
    self.result = result
    self.error = nil
  }

  init(id: RequestID?, error: ResponseError) {
    self.jsonrpc = "2.0"
    self.id = id
    self.result = nil
    self.error = error
  }
}

/// JSON-RPC Notification (no id, no response expected)
struct JSONRPCNotification: Codable {
  let jsonrpc: String
  let method: String
  let params: JSONValue?

  init(method: String, params: JSONValue? = nil) {
    self.jsonrpc = "2.0"
    self.method = method
    self.params = params
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.jsonrpc = try container.decode(String.self, forKey: .jsonrpc)
    self.method = try container.decode(String.self, forKey: .method)
    self.params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
  }

  enum CodingKeys: String, CodingKey {
    case jsonrpc, method, params
  }
}

/// Response error
struct ResponseError: Codable, Error {
  let code: Int
  let message: String
  let data: JSONValue?

  init(code: ErrorCode, message: String, data: JSONValue? = nil) {
    self.code = code.rawValue
    self.message = message
    self.data = data
  }
}

/// Standard JSON-RPC error codes
enum ErrorCode: Int {
  case parseError = -32700
  case invalidRequest = -32600
  case methodNotFound = -32601
  case invalidParams = -32602
  case internalError = -32603

  // LSP specific errors
  case serverNotInitialized = -32002
  case unknownErrorCode = -32001
  case requestCancelled = -32800
  case contentModified = -32801
}

/// Request ID can be string, number, or null
enum RequestID: Codable, Hashable {
  case string(String)
  case number(Int)

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let number = try? container.decode(Int.self) {
      self = .number(number)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Request ID must be string or number"
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    }
  }
}

/// Generic JSON value for params and results
enum JSONValue: Codable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSONValue])
  case object([String: JSONValue])

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if container.decodeNil() {
      self = .null
    } else if let bool = try? container.decode(Bool.self) {
      self = .bool(bool)
    } else if let number = try? container.decode(Double.self) {
      self = .number(number)
    } else if let string = try? container.decode(String.self) {
      self = .string(string)
    } else if let array = try? container.decode([JSONValue].self) {
      self = .array(array)
    } else if let object = try? container.decode([String: JSONValue].self) {
      self = .object(object)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Unable to decode JSON value"
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .null:
      try container.encodeNil()
    case .bool(let value):
      try container.encode(value)
    case .number(let value):
      try container.encode(value)
    case .string(let value):
      try container.encode(value)
    case .array(let value):
      try container.encode(value)
    case .object(let value):
      try container.encode(value)
    }
  }
}

// Helper to convert JSONValue to concrete types
extension JSONValue {
  func decode<T: Decodable>(_ type: T.Type) throws -> T {
    let data = try JSONEncoder().encode(self)
    return try JSONDecoder().decode(type, from: data)
  }
}

// Helper to create JSONValue from encodable types
extension JSONValue {
  static func from<T: Encodable>(_ value: T) throws -> JSONValue {
    let data = try JSONEncoder().encode(value)
    return try JSONDecoder().decode(JSONValue.self, from: data)
  }
}
