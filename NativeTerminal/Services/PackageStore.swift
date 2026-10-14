import Foundation
import Observation

/// Something installed by a package manager.
nonisolated struct ManagedPackage: Identifiable, Hashable, Sendable {
    enum Source: String, CaseIterable, Sendable {
        case formula, cask, npm, pipx, uv

        var title: String {
            switch self {
            case .formula: String(localized: "Homebrew")
            case .cask: String(localized: "Apps de Homebrew")
            case .npm: String(localized: "npm global")
            case .pipx: String(localized: "pipx")
            case .uv: String(localized: "uv")
            }
        }

        var systemImage: String {
            switch self {
            case .formula: "mug"
            case .cask: "macwindow"
            case .npm: "shippingbox"
            case .pipx, .uv: "chevron.left.forwardslash.chevron.right"
            }
        }
    }

    var name: String
    var source: Source
    var version: String
    var detail = ""
    /// Newest version, when known to be newer than `version`.
    var latest: String?
    /// Installed by the person, not pulled in by something else or bundled.
    var isOnRequest = true
    var installedAt: Date?
    var homepage: URL?
    /// Folder that holds it, for its size and “Show in Finder”.
    var location: String?
    /// For npm: the Node version it belongs to (each has its own globals).
    var nodeVersion: String?
    var isActiveNode = true
    /// Commands it adds to the shell.
    var commands: [String] = []

    var id: String { "\(source.rawValue):\(nodeVersion ?? ""):\(name)" }
    var isOutdated: Bool { latest != nil }

    /// Runs a package-manager command for another Node version through nvm.
    private var nodePrefix: String {
        guard source == .npm, !isActiveNode, let nodeVersion else { return "" }
        return "nvm exec \(nodeVersion) "
    }

    private var quotedName: String { ShellEscape.quote(name) }

    var upgradeCommand: String {
        switch source {
        case .formula: "brew upgrade \(quotedName)"
        case .cask: "brew upgrade --cask \(quotedName)"
        case .npm: nodePrefix + "npm install -g \(ShellEscape.quote(name + "@latest"))"
        case .pipx: "pipx upgrade \(quotedName)"
        case .uv: "uv tool upgrade \(quotedName)"
        }
    }

    var uninstallCommand: String {
        switch source {
        case .formula: "brew uninstall \(quotedName)"
        case .cask: "brew uninstall --cask \(quotedName)"
        case .npm: nodePrefix + "npm uninstall -g \(quotedName)"
        case .pipx: "pipx uninstall \(quotedName)"
        case .uv: "uv tool uninstall \(quotedName)"
        }
    }

    /// Where it came from, in a few words (“npm · Node 24.15.0”).
    var origin: String {
        if let nodeVersion { return "\(source.title) · Node \(nodeVersion)" }
        return source.title
    }
}

/// Everything installed through Homebrew, npm, pipx and uv, for the Tools window.
@Observable
final class PackageStore {
    private(set) var packages: [ManagedPackage] = []
    private(set) var isLoading = false
    private(set) var isCheckingUpdates = false
    private(set) var nodeVersions: [String] = []
    private(set) var activeNodeVersion: String?
    private(set) var hasLoaded = false

    /// - Parameter path: the shell's `$PATH`, to find the npm, pipx and uv it uses.
    func reload(path: [String]) async {
        guard !isLoading else { return }
        isLoading = true
        let result = await Self.gather(path: path)
        packages = result.packages
        nodeVersions = result.nodeVersions
        activeNodeVersion = result.activeNode
        isLoading = false
        hasLoaded = true
        await checkNpmUpdates(path: path)
    }

    /// `npm outdated` asks the registry, so it runs after the list is shown.
    private func checkNpmUpdates(path: [String]) async {
        guard packages.contains(where: { $0.source == .npm && $0.isActiveNode }) else { return }
        isCheckingUpdates = true
        let latest = await Self.npmOutdated(path: path)
        for index in packages.indices where packages[index].source == .npm && packages[index].isActiveNode {
            if let version = latest[packages[index].name], version != packages[index].version {
                packages[index].latest = version
            }
        }
        isCheckingUpdates = false
    }

    // MARK: - Gathering

    nonisolated struct Snapshot: Sendable {
        var packages: [ManagedPackage]
        var nodeVersions: [String]
        var activeNode: String?
    }

    @concurrent
    static func gather(path: [String]) async -> Snapshot {
        async let brew = brewPackages()
        async let npm = npmPackages(path: path)
        async let pipx = pipxPackages(path: path)
        async let uv = uvPackages(path: path)
        let (npmPackages, nodeVersions, activeNode) = await npm
        let all = await brew + npmPackages + pipx + uv
        return Snapshot(
            packages: all.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            nodeVersions: nodeVersions,
            activeNode: activeNode
        )
    }

    @concurrent
    private static func brewPackages() async -> [ManagedPackage] {
        guard let json = ToolInventory.run(["brew", "info", "--json=v2", "--installed"]),
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any] else { return [] }
        let prefix = FileManager.default.fileExists(atPath: "/opt/homebrew") ? "/opt/homebrew" : "/usr/local"
        var packages: [ManagedPackage] = []
        for formula in object["formulae"] as? [[String: Any]] ?? [] {
            guard let name = formula["name"] as? String else { continue }
            let installed = (formula["installed"] as? [[String: Any]])?.last
            let stable = (formula["versions"] as? [String: Any])?["stable"] as? String
            let version = installed?["version"] as? String ?? stable ?? ""
            var package = ManagedPackage(name: name, source: .formula, version: version)
            package.detail = formula["desc"] as? String ?? ""
            package.isOnRequest = installed?["installed_on_request"] as? Bool ?? true
            package.installedAt = (installed?["time"] as? Double).map(Date.init(timeIntervalSince1970:))
            package.homepage = (formula["homepage"] as? String).flatMap(URL.init(string:))
            package.location = "\(prefix)/Cellar/\(name)"
            if formula["outdated"] as? Bool == true, let stable, stable != version { package.latest = stable }
            packages.append(package)
        }
        for cask in object["casks"] as? [[String: Any]] ?? [] {
            guard let token = cask["token"] as? String else { continue }
            let version = cask["installed"] as? String ?? cask["version"] as? String ?? ""
            var package = ManagedPackage(name: token, source: .cask, version: version)
            let title = (cask["name"] as? [String])?.first
            package.detail = [title, cask["desc"] as? String].compactMap { $0 }.joined(separator: " — ")
            package.installedAt = (cask["installed_time"] as? Double).map(Date.init(timeIntervalSince1970:))
            package.homepage = (cask["homepage"] as? String).flatMap(URL.init(string:))
            package.location = "\(prefix)/Caskroom/\(token)"
            if cask["outdated"] as? Bool == true, let latest = cask["version"] as? String, latest != version {
                package.latest = latest
            }
            packages.append(package)
        }
        return packages
    }

    /// Globals of every Node version under nvm, plus the active one, since each
    /// version keeps its own and they are easy to lose track of.
    @concurrent
    private static func npmPackages(path: [String]) async -> ([ManagedPackage], [String], String?) {
        let activeRoot = ToolInventory.npmRoot(path: path)
        var roots: [(root: String, node: String?)] = []
        let nvm = NSHomeDirectory() + "/.nvm/versions/node"
        let versions = ((try? FileManager.default.contentsOfDirectory(atPath: nvm)) ?? [])
            .filter { $0.hasPrefix("v") }
            .sorted { $0.localizedStandardCompare($1) == .orderedDescending }
        for version in versions {
            roots.append(("\(nvm)/\(version)/lib/node_modules", String(version.dropFirst())))
        }
        if let activeRoot, !roots.contains(where: { $0.root == activeRoot }) {
            roots.append((activeRoot, nil))
        }
        let activeNode = roots.first { $0.root == activeRoot }?.node

        var packages: [ManagedPackage] = []
        for (root, node) in roots {
            for folder in moduleFolders(in: root) {
                let path = (root as NSString).appendingPathComponent(folder)
                guard let data = FileManager.default.contents(atPath: path + "/package.json"),
                      let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                var package = ManagedPackage(name: manifest["name"] as? String ?? folder, source: .npm,
                                             version: manifest["version"] as? String ?? "")
                package.detail = manifest["description"] as? String ?? ""
                package.location = path
                package.nodeVersion = node
                package.isActiveNode = root == activeRoot
                // npm and corepack ship with Node itself.
                package.isOnRequest = !["npm", "corepack"].contains(package.name)
                package.installedAt = (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
                package.homepage = (manifest["homepage"] as? String).flatMap(URL.init(string:))
                if let bin = manifest["bin"] as? [String: Any] {
                    package.commands = bin.keys.sorted()
                } else if manifest["bin"] is String {
                    package.commands = [package.name.split(separator: "/").last.map(String.init) ?? package.name]
                }
                packages.append(package)
            }
        }
        return (packages, roots.compactMap(\.node), activeNode)
    }

    nonisolated private static func moduleFolders(in root: String) -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root)) ?? []
        return names.filter { !$0.hasPrefix(".") }.flatMap { name -> [String] in
            guard name.hasPrefix("@") else { return [name] }
            let scoped = (try? FileManager.default.contentsOfDirectory(atPath: (root as NSString).appendingPathComponent(name))) ?? []
            return scoped.filter { !$0.hasPrefix(".") }.map { "\(name)/\($0)" }
        }
    }

    @concurrent
    private static func npmOutdated(path: [String]) async -> [String: String] {
        // `npm outdated` exits with 1 when something is outdated, so read it regardless.
        guard let json = ToolInventory.run(["npm", "outdated", "-g", "--json"], path: ToolInventory.searchPath(path), acceptsFailure: true),
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: [String: Any]] else { return [:] }
        return object.compactMapValues { $0["latest"] as? String }
    }

    @concurrent
    private static func pipxPackages(path: [String]) async -> [ManagedPackage] {
        guard let json = ToolInventory.run(["pipx", "list", "--json"], path: ToolInventory.searchPath(path)),
              let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let venvs = object["venvs"] as? [String: [String: Any]] else { return [] }
        let home = NSHomeDirectory()
        return venvs.compactMap { name, venv in
            guard let main = (venv["metadata"] as? [String: Any])?["main_package"] as? [String: Any] else { return nil }
            var package = ManagedPackage(name: main["package"] as? String ?? name, source: .pipx,
                                         version: main["package_version"] as? String ?? "")
            package.commands = main["apps"] as? [String] ?? []
            package.location = "\(home)/.local/pipx/venvs/\(name)"
            package.installedAt = (try? FileManager.default.attributesOfItem(atPath: package.location!))?[.creationDate] as? Date
            return package
        }
    }

    /// `uv tool list` prints “name v1.2.3” followed by “- command” lines.
    @concurrent
    private static func uvPackages(path: [String]) async -> [ManagedPackage] {
        guard let text = ToolInventory.run(["uv", "tool", "list"], path: ToolInventory.searchPath(path)) else { return [] }
        return parseUVList(text)
    }

    nonisolated static func parseUVList(_ text: String) -> [ManagedPackage] {
        let home = NSHomeDirectory()
        var packages: [ManagedPackage] = []
        for line in text.split(separator: "\n").map(String.init) {
            if line.hasPrefix("- "), !packages.isEmpty {
                packages[packages.count - 1].commands.append(String(line.dropFirst(2)))
            } else if let match = line.firstMatch(of: /^(\S+) v(\S+)/) {
                var package = ManagedPackage(name: String(match.1), source: .uv, version: String(match.2))
                package.location = "\(home)/.local/share/uv/tools/\(match.1)"
                packages.append(package)
            }
        }
        return packages
    }

    /// Disk space used by a folder, counted off the main thread.
    @concurrent
    static func size(of path: String) async -> Int64 {
        folderSize(path)
    }

    nonisolated private static func folderSize(_ path: String) -> Int64 {
        let url = URL(filePath: path, directoryHint: .isDirectory)
        guard let items = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let item as URL in items {
            total += Int64((try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}
