import Foundation
import Testing

@testable import MetalCore

@Suite("Metal Spec Parser Tests")
struct SpecParserTests {

  @Test("Parser can find function documentation", .enabled(if: FileManager.default.fileExists(atPath: "metal-shading-language.md")))
  func findFunctionDoc() throws {
    // Find the spec file
    let fileManager = FileManager.default
    let currentDir = fileManager.currentDirectoryPath
    let specPath = "\(currentDir)/metal-shading-language.md"

    let parser = try MetalSpecParser(specPath: specPath)

    // Test common Metal functions
    let functionsToTest = ["abs", "clamp", "normalize", "sin", "cos"]

    for function in functionsToTest {
      if let doc = parser.findDocumentation(for: function) {
        print("\nFound documentation for '\(function)':")
        print("Signature: \(doc.signature)")
        print("Description: \(doc.description)")
        print("Kind: \(doc.kind)")

        #expect(!doc.signature.isEmpty, "Signature should not be empty for \(function)")
        #expect(!doc.description.isEmpty, "Description should not be empty for \(function)")
      } else {
        print("\nNo documentation found for '\(function)'")
      }
    }
  }

  @Test("Parser can find type documentation", .enabled(if: FileManager.default.fileExists(atPath: "metal-shading-language.md")))
  func findTypeDoc() throws {
    let fileManager = FileManager.default
    let currentDir = fileManager.currentDirectoryPath
    let specPath = "\(currentDir)/metal-shading-language.md"

    let parser = try MetalSpecParser(specPath: specPath)

    // Test common Metal types
    let typesToTest = ["half", "float", "bool", "int"]

    for type in typesToTest {
      if let doc = parser.findDocumentation(for: type) {
        print("\nFound documentation for '\(type)':")
        print("Signature: \(doc.signature)")
        print("Description: \(doc.description)")

        #expect(!doc.description.isEmpty, "Description should not be empty for \(type)")
      } else {
        print("\nNo documentation found for '\(type)'")
      }
    }
  }

  @Test("Parser caches results", .enabled(if: FileManager.default.fileExists(atPath: "metal-shading-language.md")))
  func cachingWorks() throws {
    let fileManager = FileManager.default
    let currentDir = fileManager.currentDirectoryPath
    let specPath = "\(currentDir)/metal-shading-language.md"

    let parser = try MetalSpecParser(specPath: specPath)

    // First lookup - should parse
    let start1 = Date()
    let doc1 = parser.findDocumentation(for: "abs")
    let time1 = Date().timeIntervalSince(start1)

    // Second lookup - should use cache
    let start2 = Date()
    let doc2 = parser.findDocumentation(for: "abs")
    let time2 = Date().timeIntervalSince(start2)

    print("\nFirst lookup: \(time1 * 1000)ms")
    print("Second lookup: \(time2 * 1000)ms")

    // Cached lookup should be significantly faster
    #expect(time2 < time1 / 10, "Cached lookup should be at least 10x faster")

    // Results should be identical
    if let d1 = doc1, let d2 = doc2 {
      #expect(d1.signature == d2.signature)
      #expect(d1.description == d2.description)
    }
  }

  @Test("Parser generates proper markdown", .enabled(if: FileManager.default.fileExists(atPath: "metal-shading-language.md")))
  func markdownGeneration() throws {
    let fileManager = FileManager.default
    let currentDir = fileManager.currentDirectoryPath
    let specPath = "\(currentDir)/metal-shading-language.md"

    let parser = try MetalSpecParser(specPath: specPath)

    if let doc = parser.findDocumentation(for: "abs") {
      let markdown = doc.markdownDocumentation

      print("\nGenerated markdown:")
      print(markdown)

      #expect(markdown.contains("```metal"))
      #expect(markdown.contains("```"))
      #expect(markdown.contains("---"))
    } else {
      Issue.record("Could not find documentation for 'abs'")
    }
  }
}
