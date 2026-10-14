import Foundation

/// Names of the commands available on `$PATH`, cached per `$PATH`.
final class ExecutableIndex {
    static let shared = ExecutableIndex()

    private static let builtins = [
        "alias", "bg", "cd", "echo", "exit", "export", "fg", "history", "jobs", "popd",
        "pushd", "pwd", "source", "type", "unalias", "unset", "which",
    ]

    private var cache: (path: [String], names: [String]) = ([], [])

    /// Forgets the cached names, after something was installed or removed.
    func invalidate() {
        cache = ([], [])
    }

    func names(for pathEntries: [String]) -> [String] {
        if cache.path != pathEntries || cache.names.isEmpty {
            var names = Set(Self.builtins)
            for folder in pathEntries {
                names.formUnion((try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [])
            }
            cache = (pathEntries, Array(names))
        }
        return cache.names
    }
}
