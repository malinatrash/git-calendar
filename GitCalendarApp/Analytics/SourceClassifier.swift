import Foundation

enum SourceClassifier {
    private static let sourceExtensions: Set<String> = [
        "go", "swift", "m", "mm", "h", "kt", "kts", "java", "js", "jsx", "ts", "tsx",
        "py", "rb", "rs", "c", "cc", "cpp", "cs", "php", "scala", "sql", "proto", "yaml", "yml"
    ]

    static func meaningfulFiles(in commit: CommitRecord) -> [ChangedFile] {
        commit.files.filter { !$0.isBinary && !isGeneratedOrVendored($0.path) }
    }

    static func sourceFiles(in commit: CommitRecord) -> [ChangedFile] {
        meaningfulFiles(in: commit).filter { isSource($0.path) && !isTest($0.path) }
    }

    static func meaningfulChangedLines(in commit: CommitRecord) -> Int {
        meaningfulFiles(in: commit).reduce(0) { $0 + $1.changedLines }
    }

    static func sourceFileCount(in commit: CommitRecord) -> Int {
        sourceFiles(in: commit).count
    }

    static func testFileCount(in commit: CommitRecord) -> Int {
        meaningfulFiles(in: commit).filter { isTest($0.path) }.count
    }

    static func isGeneratedOrVendored(_ path: String) -> Bool {
        let normalized = "/\(path.lowercased())/"
        return normalized.contains("/vendor/")
            || normalized.contains("/node_modules/")
            || normalized.contains("/pods/")
            || normalized.contains("/generated/")
            || normalized.contains("/mock/")
            || normalized.contains("/mocks/")
            || normalized.contains(".generated.")
            || normalized.hasSuffix(".pb.go/")
    }

    static func isTest(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix("_test.go")
            || lower.contains("/tests/")
            || lower.contains("/test/")
            || lower.contains(".test.")
            || lower.contains(".spec.")
            || lower.hasSuffix("tests.swift")
    }

    static func isSource(_ path: String) -> Bool {
        sourceExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }

    static func languageKey(for path: String) -> String {
        URL(fileURLWithPath: path).pathExtension.lowercased()
    }
}
