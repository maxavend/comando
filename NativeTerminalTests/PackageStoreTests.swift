import Foundation
import Testing
@testable import NativeTerminal

struct PackageStoreTests {
    @Test func readsUVToolList() {
        let packages = PackageStore.parseUVList("""
        kimi-cli v1.37.0
        - kimi
        - kimi-cli
        ruff v0.6.1
        - ruff
        """)
        #expect(packages.map(\.name) == ["kimi-cli", "ruff"])
        #expect(packages.map(\.version) == ["1.37.0", "0.6.1"])
        #expect(packages.first?.commands == ["kimi", "kimi-cli"])
    }

    @Test func commandsMatchTheManager() {
        var formula = ManagedPackage(name: "ffmpeg", source: .formula, version: "8.1")
        #expect(formula.upgradeCommand == "brew upgrade ffmpeg")
        formula.source = .cask
        #expect(formula.uninstallCommand == "brew uninstall --cask ffmpeg")

        var npm = ManagedPackage(name: "@google/gemini-cli", source: .npm, version: "0.37.0")
        npm.nodeVersion = "24.14.0"
        #expect(npm.upgradeCommand == "npm install -g @google/gemini-cli@latest")
        // Another Node version's globals are changed through nvm.
        npm.isActiveNode = false
        #expect(npm.uninstallCommand == "nvm exec 24.14.0 npm uninstall -g @google/gemini-cli")
        #expect(npm.origin == "npm global · Node 24.14.0")
    }

    @Test func findsTheNpmRootOnThePath() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "nt-node-\(UUID().uuidString.prefix(6))")
        let bin = folder.appending(path: "bin")
        try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let npm = bin.appending(path: "npm")
        try "#!/bin/sh".write(to: npm, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: npm.path(percentEncoded: false))
        let root = ToolInventory.npmRoot(path: ["/nonexistent", bin.path(percentEncoded: false)])
        #expect(root == folder.appending(path: "lib/node_modules").standardizedFileURL.path(percentEncoded: false).trimmingSuffix("/"))
    }

    @Test func catalogMatchesEverydayRequests() {
        #expect(ToolCatalog.match("¿cómo descargo un video de youtube?")?.id == "yt-dlp")
        #expect(ToolCatalog.match("quiero achicar un pdf")?.id == "ghostscript")
        #expect(ToolCatalog.match("mi disco está lleno, qué ocupa espacio")?.id == "ncdu")
        #expect(ToolCatalog.match("hazme un sándwich") == nil)
    }
}
