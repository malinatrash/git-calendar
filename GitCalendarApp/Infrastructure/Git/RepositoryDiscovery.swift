import Foundation

protocol RepositoryDiscovering: Sendable {
    func repositories(under root: URL) -> [URL]
}

struct FileSystemRepositoryDiscovery: RepositoryDiscovering {
    private let skippedNames: Set<String> = [
        ".git", ".build", "build", "DerivedData", "node_modules", "vendor", "Pods"
    ]

    func repositories(under root: URL) -> [URL] {
        let manager = FileManager.default
        if manager.fileExists(atPath: root.appendingPathComponent(".git").path) {
            return [root]
        }

        let keys: Set<URLResourceKey> = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var result: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            guard let values = try? item.resourceValues(forKeys: keys), values.isDirectory == true else { continue }
            if values.isSymbolicLink == true || skippedNames.contains(item.lastPathComponent) {
                enumerator.skipDescendants()
                continue
            }
            if manager.fileExists(atPath: item.appendingPathComponent(".git").path) {
                result.append(item.standardizedFileURL)
                enumerator.skipDescendants()
            }
        }
        return result.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }
}
