import Foundation

struct QualityAnalysisPolicy: Sendable {
    let lookbackDays: Int
    let recentReworkDays: Int
    let maximumCommits: Int
    let maximumFilesPerCommit: Int
    let maximumBaselineFiles: Int

    static let standard = QualityAnalysisPolicy(
        lookbackDays: 180,
        recentReworkDays: 14,
        maximumCommits: 240,
        maximumFilesPerCommit: 12,
        maximumBaselineFiles: 300
    )
}

protocol CommitQualityAnalyzing: Sendable {
    func enrich(
        commits: [CommitRecord],
        churnByRepository: [String: [String: LineChurn]],
        configuration: CalendarConfiguration,
        now: Date
    ) -> [CommitRecord]
}

struct RepositoryQualityAnalyzer: CommitQualityAnalyzing {
    private let git: any GitCommandRunning
    private let policy: QualityAnalysisPolicy

    init(git: any GitCommandRunning, policy: QualityAnalysisPolicy = .standard) {
        self.git = git
        self.policy = policy
    }

    func enrich(
        commits: [CommitRecord],
        churnByRepository: [String: [String: LineChurn]],
        configuration: CalendarConfiguration,
        now: Date = Date()
    ) -> [CommitRecord] {
        let cutoff = now.addingTimeInterval(-Double(policy.lookbackDays) * 86_400)
        let selectedIDs = Set(
            commits
                .filter { $0.authorDate >= cutoff && !SourceClassifier.sourceFiles(in: $0).isEmpty }
                .sorted { $0.authorDate > $1.authorDate }
                .prefix(policy.maximumCommits)
                .map(\.id)
        )
        let repositories = Dictionary(grouping: commits.filter { selectedIDs.contains($0.id) }, by: \.repositoryPath)
        let thresholds = repositories.mapValues { repositoryCommits in
            makeThresholds(repository: URL(fileURLWithPath: repositoryCommits[0].repositoryPath))
        }

        return commits.map { commit in
            let churn = churnByRepository[commit.repositoryPath]?[commit.hash]
            guard selectedIDs.contains(commit.id), let relativeThresholds = thresholds[commit.repositoryPath] else {
                return withChurn(commit, churn: churn)
            }
            return analyze(
                commit,
                thresholds: relativeThresholds,
                churn: churn,
                configuration: configuration
            )
        }
    }

    private func analyze(
        _ commit: CommitRecord,
        thresholds: RelativeThresholds,
        churn: LineChurn?,
        configuration: CalendarConfiguration
    ) -> CommitRecord {
        let eligible = SourceClassifier.sourceFiles(in: commit)
        let selected = eligible
            .sorted { $0.changedLines > $1.changedLines }
            .prefix(policy.maximumFilesPerCommit)
        let repository = URL(fileURLWithPath: commit.repositoryPath)
        var fileChanges: [FileQualityChange] = []

        for file in selected {
            guard let afterSource = source(path: file.path, revision: commit.hash, repository: repository) else { continue }
            let beforeSource = source(path: file.path, revision: "\(commit.hash)^", repository: repository) ?? ""
            let before = StaticSourceAnalyzer.analyze(beforeSource, path: file.path)
            let after = StaticSourceAnalyzer.analyze(afterSource, path: file.path)
            fileChanges.append(RelativeRiskAnalyzer.assess(
                path: file.path,
                before: before,
                after: after,
                thresholds: thresholds.values(for: file.path)
            ))
        }

        let fileByPath = Dictionary(uniqueKeysWithValues: eligible.map { ($0.path, $0) })
        let totalWeight = fileChanges.reduce(0.0) { result, change in
            result + Double(max(1, fileByPath[change.path]?.changedLines ?? 1))
        }
        let weightedRisk = fileChanges.reduce(0.0) { result, change in
            result + Double(max(1, fileByPath[change.path]?.changedLines ?? 1)) * change.riskScore
        }
        let risk = totalWeight == 0 ? 0 : weightedRisk / totalWeight
        var reasons = Array(Set(fileChanges.flatMap(\.issues))).sorted { $0.rawValue < $1.rawValue }
        reasons.append(contentsOf: workflowSignals(for: commit, configuration: configuration))

        var enriched = commit
        enriched.riskReasons = Array(Set(reasons)).sorted { $0.rawValue < $1.rawValue }
        enriched.riskWeight = risk
        enriched.quality = CommitQuality(
            analyzedSourceFiles: fileChanges.count,
            eligibleSourceFiles: eligible.count,
            fileChanges: fileChanges,
            recentReworkLines: churn?.recentReworkLines ?? 0,
            changedCodeLines: churn?.changedCodeLines ?? 0
        )
        return enriched
    }

    private func withChurn(_ commit: CommitRecord, churn: LineChurn?) -> CommitRecord {
        guard let churn, churn.recentReworkLines > 0 else { return commit }
        var enriched = commit
        enriched.quality = CommitQuality(
            analyzedSourceFiles: 0,
            eligibleSourceFiles: SourceClassifier.sourceFileCount(in: commit),
            fileChanges: [],
            recentReworkLines: churn.recentReworkLines,
            changedCodeLines: churn.changedCodeLines
        )
        return enriched
    }

    private func workflowSignals(
        for commit: CommitRecord,
        configuration: CalendarConfiguration
    ) -> [RiskReason] {
        let sourceLines = SourceClassifier.sourceFiles(in: commit).reduce(0) { $0 + $1.changedLines }
        var result: [RiskReason] = []
        if sourceLines >= configuration.largeChangeThreshold { result.append(.largeChange) }
        if SourceClassifier.sourceFileCount(in: commit) >= configuration.wideChangeFileThreshold {
            result.append(.wideChange)
        }
        if sourceLines >= configuration.testsExpectedAfterLines
            && SourceClassifier.testFileCount(in: commit) == 0 {
            result.append(.sourceWithoutTests)
        }
        return result
    }

    private func makeThresholds(repository: URL) -> RelativeThresholds {
        guard let output = try? git.output(["ls-files", "-z"], in: repository) else {
            return RelativeThresholds(samples: [])
        }
        let paths = output.split(separator: "\0").map(String.init).filter {
            SourceClassifier.isSource($0) && !SourceClassifier.isGeneratedOrVendored($0)
        }
        let sampledPaths = evenlySample(paths, limit: policy.maximumBaselineFiles)
        let samples = sampledPaths.compactMap { path -> (path: String, metrics: SourceMetrics)? in
            guard let content = workingTreeSource(path: path, repository: repository) else { return nil }
            return (path, StaticSourceAnalyzer.analyze(content, path: path))
        }
        return RelativeThresholds(samples: samples)
    }

    private func evenlySample(_ values: [String], limit: Int) -> [String] {
        guard values.count > limit, limit > 0 else { return values }
        let step = Double(values.count) / Double(limit)
        return (0..<limit).map { values[min(Int(Double($0) * step), values.count - 1)] }
    }

    private func workingTreeSource(path: String, repository: URL) -> String? {
        let file = repository.appendingPathComponent(path).standardizedFileURL
        guard file.path.hasPrefix(repository.standardizedFileURL.path + "/"),
              let data = try? Data(contentsOf: file),
              data.count <= 512_000 else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func source(path: String, revision: String, repository: URL) -> String? {
        guard let value = try? git.output(["show", "\(revision):\(path)"], in: repository),
              value.utf8.count <= 512_000 else { return nil }
        return value
    }
}
