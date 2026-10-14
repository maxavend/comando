import Foundation
import UniformTypeIdentifiers

/// What is installed and what the current project offers: the small context the
/// assistant works with.
nonisolated struct ToolInventory: Sendable {
    struct Package: Sendable, Hashable {
        var name: String
        var detail: String
    }

    struct FileInfo: Sendable, Hashable {
        var name: String
        var path: String
        var kind: Kind
        var size: Int64

        enum Kind: String, Sendable {
            case audio, video, image, folder, archive, other
        }

        var sizeText: String { ByteCountFormatter.string(fromByteCount: size, countStyle: .file) }
    }

    enum PackageManager: String, Sendable {
        case npm, pnpm, yarn, bun
    }

    var directory: String
    var executables: Set<String>
    var brew: [Package] = []
    var npmGlobals: [Package] = []
    var scripts: [String] = []
    var packageManager: PackageManager?
    var makeTargets: [String] = []
    var files: [FileInfo] = []
    var attachments: [FileInfo] = []
    var git: GitInfo?
    var gitHasRemote = false

    func has(_ tool: String) -> Bool { executables.contains(tool) }

    /// Where a tool comes from, for the reply (“incluida en macOS”, “Homebrew”…).
    func source(of tool: String) -> String {
        if ["afconvert", "avconvert", "sips", "zip", "unzip", "git", "open", "networkQuality"].contains(tool),
           !brew.contains(where: { $0.name == tool }) {
            return String(localized: "incluida en macOS")
        }
        if brew.contains(where: { $0.name == tool }) { return "Homebrew" }
        if npmGlobals.contains(where: { $0.name == tool }) { return "npm" }
        return String(localized: "instalada")
    }

    // MARK: - Gathering

    @concurrent
    static func gather(directory: String, executables: Set<String>, attachments: [URL]) async -> ToolInventory {
        var inventory = ToolInventory(directory: directory, executables: executables)
        inventory.brew = await InstalledPackages.shared.brew()
        inventory.npmGlobals = await InstalledPackages.shared.npm()
        inventory.files = listFiles(in: directory)
        inventory.attachments = attachments.map { info(for: $0, relativeTo: directory) }
        if let project = nearestFile(named: "package.json", from: directory) {
            inventory.scripts = scripts(in: project)
            let folder = (project as NSString).deletingLastPathComponent
            inventory.packageManager = manager(in: folder)
        }
        if let makefile = nearestFile(named: "Makefile", from: directory) {
            inventory.makeTargets = targets(in: makefile)
        }
        inventory.git = await GitInfo.read(in: directory)
        if inventory.git != nil {
            inventory.gitHasRemote = !(run(["git", "-C", directory, "remote"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        return inventory
    }

    static func info(for url: URL, relativeTo directory: String) -> FileInfo {
        let path = url.path(percentEncoded: false)
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentTypeKey])
        let kind: FileInfo.Kind
        if values?.isDirectory == true {
            kind = .folder
        } else if let type = values?.contentType ?? UTType(filenameExtension: url.pathExtension) {
            if type.conforms(to: .audio) { kind = .audio }
            else if type.conforms(to: .movie) || type.conforms(to: .video) { kind = .video }
            else if type.conforms(to: .image) { kind = .image }
            else if type.conforms(to: .archive) { kind = .archive }
            else { kind = .other }
        } else {
            kind = .other
        }
        let base = directory.hasSuffix("/") ? directory : directory + "/"
        let shown = path.hasPrefix(base) ? String(path.dropFirst(base.count)) : path
        return FileInfo(name: url.lastPathComponent, path: shown, kind: kind, size: Int64(values?.fileSize ?? 0))
    }

    private static func listFiles(in directory: String) -> [FileInfo] {
        let url = URL(filePath: directory, directoryHint: .isDirectory)
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentTypeKey], options: [.skipsHiddenFiles]
        )) ?? []
        return items.prefix(60).map { info(for: $0, relativeTo: directory) }
    }

    private static func nearestFile(named name: String, from directory: String) -> String? {
        var current = directory
        let home = NSHomeDirectory()
        while true {
            let candidate = (current as NSString).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate) { return candidate }
            if current == home || current == "/" { return nil }
            current = (current as NSString).deletingLastPathComponent
        }
    }

    private static func scripts(in packageJSON: String) -> [String] {
        guard let data = FileManager.default.contents(atPath: packageJSON),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let scripts = object["scripts"] as? [String: Any] else { return [] }
        return scripts.keys.sorted()
    }

    private static func manager(in folder: String) -> PackageManager {
        let exists = { FileManager.default.fileExists(atPath: (folder as NSString).appendingPathComponent($0)) }
        if exists("pnpm-lock.yaml") { return .pnpm }
        if exists("yarn.lock") { return .yarn }
        if exists("bun.lockb") || exists("bun.lock") { return .bun }
        return .npm
    }

    private static func targets(in makefile: String) -> [String] {
        guard let text = try? String(contentsOfFile: makefile, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let match = line.firstMatch(of: /^([A-Za-z0-9][A-Za-z0-9_-]*):(?!=)/) else { return nil }
            return String(match.1)
        }
    }

    static func run(_ arguments: [String], path: String = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin") -> String? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/env")
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = path
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return process.terminationStatus == 0 ? String(decoding: data, as: UTF8.self) : nil
    }
}

/// Homebrew and global npm packages, read once per launch (they rarely change).
actor InstalledPackages {
    static let shared = InstalledPackages()

    private var brewCache: [ToolInventory.Package]?
    private var npmCache: [ToolInventory.Package]?

    func brew() -> [ToolInventory.Package] {
        if let brewCache { return brewCache }
        var packages: [ToolInventory.Package] = []
        if let json = ToolInventory.run(["brew", "info", "--json=v2", "--installed"]),
           let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] {
            for formula in object["formulae"] as? [[String: Any]] ?? [] {
                if let name = formula["name"] as? String {
                    packages.append(.init(name: name, detail: formula["desc"] as? String ?? ""))
                }
            }
            for cask in object["casks"] as? [[String: Any]] ?? [] {
                if let token = cask["token"] as? String {
                    packages.append(.init(name: token, detail: cask["desc"] as? String ?? ""))
                }
            }
        }
        brewCache = packages
        return packages
    }

    func npm() -> [ToolInventory.Package] {
        if let npmCache { return npmCache }
        var packages: [ToolInventory.Package] = []
        // npm often lives under nvm, so ask the user's login shell where it is.
        if let root = ToolInventory.run(["zsh", "-lc", "npm root -g"])?.trimmingCharacters(in: .whitespacesAndNewlines),
           let names = try? FileManager.default.contentsOfDirectory(atPath: root) {
            for name in names where !name.hasPrefix(".") {
                let folders = name.hasPrefix("@")
                    ? ((try? FileManager.default.contentsOfDirectory(atPath: (root as NSString).appendingPathComponent(name))) ?? []).map { "\(name)/\($0)" }
                    : [name]
                for folder in folders {
                    let manifest = (root as NSString).appendingPathComponent("\(folder)/package.json")
                    let object = (try? JSONSerialization.jsonObject(with: Data(contentsOf: URL(filePath: manifest)))) as? [String: Any]
                    packages.append(.init(name: folder, detail: object?["description"] as? String ?? ""))
                }
            }
        }
        npmCache = packages
        return packages
    }
}
