import Foundation
import PDFKit
import Quartz

/// Small commands that come with Comando and run from the shell, so tasks
/// macOS has no command for (like shrinking a PDF) stay visible in the chat.
///
/// They live as scripts on the shell's `$PATH` that call the app's own
/// executable with a flag; the app does the work and exits without a window.
nonisolated enum BuiltInTools {
    static let compressPDF = "comprimir-pdf"

    /// Folder with the scripts, added to `$PATH` by the shell integration.
    static var directory: URL {
        ShellIntegration.directory.deletingLastPathComponent().appending(path: "bin", directoryHint: .isDirectory)
    }

    /// Writes the scripts, pointing at this copy of the app. Safe on every launch.
    static func install() throws {
        guard let executable = Bundle.main.executablePath else { return }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let script = directory.appending(path: compressPDF)
        let contents = """
        #!/bin/sh
        # Comando: reduce el peso de un PDF con el filtro de macOS.
        exec \(ShellEscape.quote(executable)) --\(compressPDF) "$@"

        """
        try contents.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path(percentEncoded: false))
    }

    /// Runs a tool when the app was launched as one; returns its exit code.
    static func runIfRequested(_ arguments: [String] = CommandLine.arguments) -> Int32? {
        guard arguments.count >= 2, arguments[1] == "--\(compressPDF)" else { return nil }
        return compress(Array(arguments.dropFirst(2)))
    }

    private static func compress(_ arguments: [String]) -> Int32 {
        guard let inputPath = arguments.first else {
            print("Uso: \(compressPDF) archivo.pdf [archivo-comprimido.pdf]")
            return 2
        }
        let input = URL(filePath: inputPath)
        let output = arguments.count > 1
            ? URL(filePath: arguments[1])
            : input.deletingPathExtension().appendingPathExtension("pdf").deletingLastPathComponent()
                .appending(path: input.deletingPathExtension().lastPathComponent + "-comprimido.pdf")
        guard let document = PDFDocument(url: input) else {
            print("No pude abrir “\(input.lastPathComponent)” como PDF.")
            return 1
        }
        guard let filter = QuartzFilter(url: URL(filePath: "/System/Library/Filters/Reduce File Size.qfilter")) else {
            print("No encontré el filtro “Reducir tamaño de archivo” de macOS.")
            return 1
        }
        guard document.write(to: output, withOptions: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]) else {
            print("No pude guardar “\(output.lastPathComponent)”.")
            return 1
        }
        let before = size(of: input), after = size(of: output)
        let format = ByteCountFormatStyle(style: .file)
        if after < before {
            let saved = Int((1 - Double(after) / Double(max(before, 1))) * 100)
            print("Listo: \(output.lastPathComponent) pesa \(format.format(after)) (antes \(format.format(before)), \(saved) % menos).")
        } else {
            print("Listo: \(output.lastPathComponent) pesa \(format.format(after)). El original ya estaba bastante optimizado.")
        }
        return 0
    }

    private static func size(of url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }
}
