import Foundation

/// Exports documents to PDF with the iWork app that opens them, driven by
/// AppleScript from the shell (Pages also opens Word and RTF files).
nonisolated enum DocumentExport {
    static func app(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "pages", "doc", "docx", "rtf", "rtfd", "odt": "Pages"
        case "key", "ppt", "pptx", "odp": "Keynote"
        case "numbers", "xls", "xlsx", "ods": "Numbers"
        default: nil
        }
    }

    static func isInstalled(_ app: String) -> Bool {
        FileManager.default.fileExists(atPath: "/Applications/\(app).app")
    }

    /// `osascript` that opens the document, saves a PDF next to it and closes it.
    static func command(for file: String, in directory: String) -> (command: String, output: String, app: String)? {
        let ext = (file as NSString).pathExtension
        guard let app = app(forExtension: ext), isInstalled(app) else { return nil }
        let input = file.hasPrefix("/") ? file : (directory as NSString).appendingPathComponent(file)
        let output = (file as NSString).deletingPathExtension + ".pdf"
        let absoluteOutput = (input as NSString).deletingPathExtension + ".pdf"
        let lines = [
            "tell application \"\(app)\"",
            "set theDocument to open (POSIX file \(appleScriptString(input)))",
            "export theDocument to (POSIX file \(appleScriptString(absoluteOutput))) as PDF",
            "close theDocument saving no",
            "end tell",
        ]
        let command = "osascript " + lines.map { "-e " + ShellEscape.quote($0) }.joined(separator: " ")
        return (command, output, app)
    }

    /// A quoted AppleScript string literal.
    private static func appleScriptString(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
