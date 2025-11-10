import Foundation
import Testing

@testable import MetalCore
@testable import MetalLanguageServer

@Suite("Metal LSP Unit Tests")
struct MetalLSPTests {

  @Test("Metal hardcoded completions are not empty")
  func metalBuiltinsNotEmpty() {
    let completions = MetalBuiltins.getHardcodedCompletions()
    #expect(!completions.isEmpty, "Hardcoded completions should not be empty")
  }

  @Test("Metal documentation contains float4")
  func metalDocsContainsFloat4() {
    let docs = MetalDocumentation()
    let entry = docs.lookup("float4")
    #expect(entry != nil, "Documentation should contain float4 type")
  }

  @Test("Metal built-ins contain kernel keywords")
  func metalBuiltinsContainsKernelKeyword() {
    #expect(MetalBuiltins.keywords.contains("kernel"))
    #expect(MetalBuiltins.keywords.contains("vertex"))
    #expect(MetalBuiltins.keywords.contains("fragment"))
  }

  @Test("Position equality works correctly")
  func positionEquality() {
    let pos1 = Position(line: 5, character: 10)
    let pos2 = Position(line: 5, character: 10)
    let pos3 = Position(line: 5, character: 11)

    #expect(pos1 == pos2)
    #expect(pos1 != pos3)
  }

  @Test("Range creation works correctly")
  func rangeCreation() {
    let start = Position(line: 0, character: 0)
    let end = Position(line: 0, character: 5)
    let range = Range(start: start, end: end)

    #expect(range.start == start)
    #expect(range.end == end)
  }

  @Test("Document manager opens and closes documents")
  func documentManager() {
    let manager = DocumentManager()
    let uri = "file:///test.metal"
    let text = "kernel void test() {}"

    manager.openDocument(uri: uri, text: text, version: 1)

    let doc = manager.getDocument(uri: uri)
    #expect(doc != nil)
    #expect(doc?.text == text)
    #expect(doc?.version == 1)

    manager.closeDocument(uri: uri)
    let closedDoc = manager.getDocument(uri: uri)
    #expect(closedDoc == nil)
  }

  @Test("Document line access works correctly")
  func documentLineAccess() {
    let manager = DocumentManager()
    let uri = "file:///test.metal"
    let text = "line 0\nline 1\nline 2"

    manager.openDocument(uri: uri, text: text, version: 1)

    let doc = manager.getDocument(uri: uri)
    #expect(doc?.line(at: 0) == "line 0")
    #expect(doc?.line(at: 1) == "line 1")
    #expect(doc?.line(at: 2) == "line 2")
    #expect(doc?.line(at: 3) == nil)
  }

  @Test("JSONValue encoding and decoding")
  func jsonValueEncoding() throws {
    let value = JSONValue.string("test")
    let encoded = try JSONEncoder().encode(value)
    let decoded = try JSONDecoder().decode(JSONValue.self, from: encoded)

    if case .string(let str) = decoded {
      #expect(str == "test")
    } else {
      Issue.record("Expected string value")
    }
  }

  @Test("RequestID encoding and decoding")
  func requestIDEncoding() throws {
    let stringID = RequestID.string("test-123")
    let numberID = RequestID.number(42)

    let stringData = try JSONEncoder().encode(stringID)
    let numberData = try JSONEncoder().encode(numberID)

    let decodedString = try JSONDecoder().decode(RequestID.self, from: stringData)
    let decodedNumber = try JSONDecoder().decode(RequestID.self, from: numberData)

    #expect(decodedString == stringID)
    #expect(decodedNumber == numberID)
  }
}
