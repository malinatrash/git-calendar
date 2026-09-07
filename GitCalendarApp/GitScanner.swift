import Foundation

struct GitScanner: Sendable {
    struct ScanError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func scan(configuration: CalendarConfiguration, now: Date = Date()) throws -> CalendarSnapshot {
        let rootURL = URL(fileURLWithPath: configuration.folderPath).standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ScanError(message: "Папка не найдена: \(rootURL.path)")
        }

        let repositories = discoverRepositories(under: rootURL)
        guard !repositories.isEmpty else {
            throw ScanError(message: "В папке \(rootURL.path) не найдено Git-репозиториев")
        }

        var commits: [CommitRecord] = []
        var warnings: [String] = []

        for repository in repositories {
            do {
                let output = try gitLog(repository: repository, configuration: configuration)
                commits.append(contentsOf: GitLogParser.parse(
                    output,
                    repository: repository,
                    configuration: configuration
                ))
            } catch {
                warnings.append("\(repository.lastPathComponent): \(error.localizedDescription)")
            }
        }

        commits.sort { $0.authorDate > $1.authorDate }
        return MetricEngine.makeSnapshot(
            configuration: configuration,
            repositoryPaths: repositories.map(\.path),
            commits: commits,
            warnings: warnings,
            now: now
        )
    }

    private func discoverRepositories(under root: URL) -> [URL] {
        let manager = FileManager.default
        if manager.fileExists(atPath: root.appendingPathComponent(".git").path) {
            return [root]
        }

        let skippedNames: Set<String> = [
            ".git", ".build", "build", "DerivedData", "node_modules", "vendor", "Pods"
        ]
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isHiddenKey]
        guard let enumerator = manager.enumerator(
            at: root,
            includingPropertiesForKeys: keys,
            options: [.skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        var result: [URL] = []
        while let item = enumerator.nextObject() as? URL {
            guard let values = try? item.resourceValues(forKeys: Set(keys)), values.isDirectory == true else { continue }

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

    private func gitLog(
        repository: URL,
        configuration: CalendarConfiguration
    ) throws -> String {
        var arguments = [
            "-C", repository.path,
            "log"
        ]
        if configuration.includeAllRefs { arguments.append("--all") }
        if !configuration.includeMerges { arguments.append("--no-merges") }
        arguments.append(contentsOf: [
            "--numstat",
            "--no-renames",
            "--date=iso-strict",
            "--format=\u{1e}%H\u{1f}%aI\u{1f}%cI\u{1f}%an\u{1f}%ae\u{1f}%s"
        ])

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment.merging(["LC_ALL": "C.UTF-8"]) { _, new in new }

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let message = String(decoding: errorData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw ScanError(message: message.isEmpty ? "git log завершился с кодом \(process.terminationStatus)" : message)
        }
        return String(decoding: data, as: UTF8.self)
    }
}

enum GitLogParser {
    static func parse(
        _ output: String,
        repository: URL,
        configuration: CalendarConfiguration
    ) -> [CommitRecord] {
        output
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .compactMap { parseRecord(String($0), repository: repository, configuration: configuration) }
            .filter { matchesIdentity($0, patterns: configuration.authorPatterns) }
    }

    private static func parseRecord(
        _ value: String,
        repository: URL,
        configuration: CalendarConfiguration
    ) -> CommitRecord? {
        let lines = value.split(omittingEmptySubsequences: true) { $0.isNewline }
        guard let header = lines.first else { return nil }
        let fields = header.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 6,
              let authorDate = parseISO8601(fields[1]),
              let committerDate = parseISO8601(fields[2]) else { return nil }

        let files = lines.dropFirst().compactMap(parseNumstat)
        let assessment = RiskAnalyzer.assess(files: files, configuration: configuration)
        return CommitRecord(
            hash: fields[0],
            repositoryName: repository.lastPathComponent,
            repositoryPath: repository.path,
            authorName: fields[3],
            authorEmail: fields[4],
            authorDate: authorDate,
            committerDate: committerDate,
            subject: fields[5],
            files: files,
            riskReasons: assessment.reasons,
            riskWeight: assessment.weight
        )
    }

    private static func parseNumstat(_ line: Substring) -> ChangedFile? {
        let fields = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count == 3 else { return nil }
        let binary = fields[0] == "-" || fields[1] == "-"
        return ChangedFile(
            path: String(fields[2]),
            additions: Int(fields[0]) ?? 0,
            deletions: Int(fields[1]) ?? 0,
            isBinary: binary
        )
    }

    private static func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }

    private static func matchesIdentity(_ commit: CommitRecord, patterns: [String]) -> Bool {
        let normalized = patterns.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }.filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return true }
        let identity = "\(commit.authorName) <\(commit.authorEmail)>".lowercased()
        return normalized.contains { identity.contains($0) }
    }
}

enum RiskAnalyzer {
    struct Assessment {
        let reasons: [RiskReason]
        let weight: Double
    }

    static func assess(files: [ChangedFile], configuration: CalendarConfiguration) -> Assessment {
        let meaningful = files.filter { !$0.isBinary && !isGeneratedOrVendored($0.path) }
        let sourceFiles = meaningful.filter { isSource($0.path) && !isTest($0.path) }
        let testFiles = meaningful.filter { isTest($0.path) }
        let sourceLines = sourceFiles.reduce(0) { $0 + $1.changedLines }

        var reasons: [RiskReason] = []
        var weight = 0.0
        if sourceLines >= configuration.largeChangeThreshold {
            reasons.append(.largeChange)
            weight += 0.20
        }
        if sourceFiles.count >= configuration.wideChangeFileThreshold {
            reasons.append(.wideChange)
            weight += 0.15
        }
        if sourceLines >= configuration.testsExpectedAfterLines && testFiles.isEmpty {
            reasons.append(.sourceWithoutTests)
            weight += 0.65
        }
        return Assessment(reasons: reasons, weight: min(1, weight))
    }

    static func meaningfulChangedLines(in commit: CommitRecord) -> Int {
        commit.files
            .filter { !$0.isBinary && !isGeneratedOrVendored($0.path) }
            .reduce(0) { $0 + $1.changedLines }
    }

    static func sourceFileCount(in commit: CommitRecord) -> Int {
        commit.files.filter { !$0.isBinary && isSource($0.path) && !isTest($0.path) && !isGeneratedOrVendored($0.path) }.count
    }

    static func testFileCount(in commit: CommitRecord) -> Int {
        commit.files.filter { isTest($0.path) }.count
    }

    private static func isGeneratedOrVendored(_ path: String) -> Bool {
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

    private static func isTest(_ path: String) -> Bool {
        let lower = path.lowercased()
        return lower.hasSuffix("_test.go")
            || lower.contains("/tests/")
            || lower.contains("/test/")
            || lower.contains(".test.")
            || lower.contains(".spec.")
    }

    private static func isSource(_ path: String) -> Bool {
        let sourceExtensions: Set<String> = [
            "go", "swift", "m", "mm", "h", "kt", "kts", "java", "js", "jsx", "ts", "tsx",
            "py", "rb", "rs", "c", "cc", "cpp", "cs", "php", "scala", "sql", "proto", "yaml", "yml"
        ]
        return sourceExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased())
    }
}
