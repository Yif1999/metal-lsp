import Foundation
import ArgumentParser
import MetalLanguageServer

@main
struct MetalLSPCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "metal-lsp",
        abstract: "Metal Shading Language Server Protocol implementation",
        version: "0.1.0"
    )

    @Flag(name: .long, help: "Enable verbose logging to stderr")
    var verbose: Bool = false

    @Flag(name: .long, help: "Log communication to stderr")
    var logMessages: Bool = false

    mutating func run() throws {
        let server = LanguageServer(
            verbose: verbose,
            logMessages: logMessages
        )

        try server.run()
    }
}
