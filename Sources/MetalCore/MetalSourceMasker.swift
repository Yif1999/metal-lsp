import Foundation

public enum MetalSourceMasker {
  public static func mask(_ source: String) -> String {
    let chars = Array(source)
    var result = Array(repeating: Character(" "), count: chars.count)

    enum State {
      case code
      case lineComment
      case blockComment
      case string
      case charLiteral
    }

    var state: State = .code
    var i = 0

    while i < chars.count {
      let c = chars[i]
      let next = (i + 1 < chars.count) ? chars[i + 1] : nil

      switch state {
      case .code:
        if c == "/", next == "/" {
          result[i] = " "
          result[i + 1] = " "
          state = .lineComment
          i += 2
          continue
        }

        if c == "/", next == "*" {
          result[i] = " "
          result[i + 1] = " "
          state = .blockComment
          i += 2
          continue
        }

        if c == "\"" {
          result[i] = "\""
          state = .string
          i += 1
          continue
        }

        if c == "'" {
          result[i] = "'"
          state = .charLiteral
          i += 1
          continue
        }

        result[i] = c
        i += 1

      case .lineComment:
        if c == "\n" {
          result[i] = "\n"
          state = .code
        } else {
          result[i] = " "
        }
        i += 1

      case .blockComment:
        if c == "\n" {
          result[i] = "\n"
          i += 1
          continue
        }

        if c == "*", next == "/" {
          result[i] = " "
          result[i + 1] = " "
          state = .code
          i += 2
          continue
        }

        result[i] = " "
        i += 1

      case .string:
        if c == "\\", next != nil {
          result[i] = " "
          if chars.indices.contains(i + 1) {
            result[i + 1] = " "
          }
          i += 2
          continue
        }

        if c == "\"" {
          result[i] = "\""
          state = .code
          i += 1
          continue
        }

        if c == "\n" {
          result[i] = "\n"
          state = .code
          i += 1
          continue
        }

        result[i] = " "
        i += 1

      case .charLiteral:
        if c == "\\", next != nil {
          result[i] = " "
          if chars.indices.contains(i + 1) {
            result[i + 1] = " "
          }
          i += 2
          continue
        }

        if c == "'" {
          result[i] = "'"
          state = .code
          i += 1
          continue
        }

        if c == "\n" {
          result[i] = "\n"
          state = .code
          i += 1
          continue
        }

        result[i] = " "
        i += 1
      }
    }

    return String(result)
  }
}
