import Foundation

protocol CalendarScanning: Sendable {
    func scan(configuration: CalendarConfiguration, now: Date) throws -> CalendarSnapshot
}

extension CalendarScanning {
    func scan(configuration: CalendarConfiguration) throws -> CalendarSnapshot {
        try scan(configuration: configuration, now: Date())
    }
}

struct GitScanner: CalendarScanning {
    struct ScanError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private let git: any GitCommandRunning
    private let discovery: any RepositoryDiscovering
    private let qualityAnalyzer: any CommitQualityAnalyzing
    private let policy: QualityAnalysisPolicy

    init(
        git: any GitCommandRunning = SystemGitClient(),
        discovery: any RepositoryDiscovering = FileSystemRepositoryDiscovery(),
        qualityAnalyzer: (any CommitQualityAnalyzing)? = nil,
        policy: QualityAnalysisPolicy = .standard
    ) {
        self.git = git
        self.discovery = discovery
        self.qualityAnalyzer = qualityAnalyzer ?? RepositoryQualityAnalyzer(git: git, policy: policy)
        self.policy = policy
    }

    func scan(configuration: CalendarConfiguration, now: Date = Date()) throws -> CalendarSnapshot {
        let root = URL(fileURLWithPath: configuration.folderPath).standardizedFileURL
        try validate(root)
        let repositories = discovery.repositories(under: root)
        guard !repositories.isEmpty else {
            throw ScanError(message: "В папке \(root.path) не найдено Git-репозиториев")
        }

        var commits: [CommitRecord] = []
        var warnings: [String] = []
        var churnByRepository: [String: [String: LineChurn]] = [:]

        for repository in repositories {
            do {
                commits.append(contentsOf: GitLogParser.parse(
                    try git.output(logArguments(configuration: configuration), in: repository),
                    repository: repository,
                    configuration: configuration
                ))
                churnByRepository[repository.path] = scanChurn(
                    repository: repository,
                    configuration: configuration,
                    now: now
                )
            } catch {
                warnings.append("\(repository.lastPathComponent): \(error.localizedDescription)")
            }
        }

        commits.sort { $0.authorDate > $1.authorDate }
        let enriched = qualityAnalyzer.enrich(
            commits: commits,
            churnByRepository: churnByRepository,
            configuration: configuration,
            now: now
        )
        return MetricEngine.makeSnapshot(
            configuration: configuration,
            repositoryPaths: repositories.map(\.path),
            commits: enriched,
            warnings: warnings,
            qualityPolicy: policy,
            now: now
        )
    }

    private func validate(_ root: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw ScanError(message: "Папка не найдена: \(root.path)")
        }
    }

    private func logArguments(configuration: CalendarConfiguration) -> [String] {
        var arguments = ["log"]
        if configuration.includeAllRefs { arguments.append("--all") }
        arguments.append(contentsOf: [
            "--no-merges",
            "--numstat",
            "--no-renames",
            "--date=iso-strict",
            "--format=\u{1e}%H\u{1f}%aI\u{1f}%cI\u{1f}%an\u{1f}%ae\u{1f}%s"
        ])
        return arguments
    }

    private func scanChurn(
        repository: URL,
        configuration: CalendarConfiguration,
        now: Date
    ) -> [String: LineChurn] {
        let since = ISO8601DateFormatter().string(
            from: now.addingTimeInterval(-Double(policy.lookbackDays) * 86_400)
        )
        var arguments = [
            "log",
            "--no-merges",
            "--reverse",
            "--since=\(since)",
            "--date=iso-strict",
            "--format=\u{1e}%H\u{1f}%aI",
            "--patch",
            "--unified=0",
            "--no-renames",
            "--no-color"
        ]
        if configuration.includeAllRefs { arguments.insert("--all", at: 1) }
        guard let output = try? git.output(arguments, in: repository) else { return [:] }
        return LineChurnAnalyzer.analyze(output, recentDays: policy.recentReworkDays)
    }
}
