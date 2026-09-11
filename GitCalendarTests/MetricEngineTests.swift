import Foundation
import XCTest

final class MetricEngineTests: XCTestCase {
    func testStatisticsBeginAtFirstMatchingCommit() throws {
        let configuration = CalendarConfiguration(name: "Test", folderPath: "/tmp")
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-07T12:00:00Z"))
        let commit = makeCommit(
            date: "2026-08-20T09:00:00Z",
            files: [ChangedFile(path: "main.go", additions: 4, deletions: 0, isBinary: false)]
        )

        let snapshot = MetricEngine.makeSnapshot(
            configuration: configuration,
            repositoryPaths: ["/tmp/repo"],
            commits: [commit],
            now: now
        )

        XCTAssertEqual(snapshot.days.first?.dayKey, "2026-08-20")
        XCTAssertEqual(snapshot.days.last?.dayKey, "2026-09-07")
    }

    func testBuildsContinuousCalendarAndFrequency() throws {
        let timeZone = "Asia/Irkutsk"
        let configuration = CalendarConfiguration(
            name: "Test",
            folderPath: "/tmp/test",
            authorPatterns: ["developer@example.com"],
            timeZoneIdentifier: timeZone,
            refreshIntervalMinutes: 15
        )
        let now = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-09-07T12:00:00+08:00"))
        let commits = [
            makeCommit(date: "2026-09-07T09:00:00+08:00", files: [ChangedFile(path: "main.go", additions: 20, deletions: 2, isBinary: false)]),
            makeCommit(date: "2026-09-04T18:00:00+08:00", files: [ChangedFile(path: "service.go", additions: 10, deletions: 1, isBinary: false)])
        ]

        let snapshot = MetricEngine.makeSnapshot(
            configuration: configuration,
            repositoryPaths: ["/tmp/test/repo"],
            commits: commits,
            now: now
        )

        XCTAssertEqual(snapshot.days.count, 4)
        XCTAssertEqual(snapshot.summary.totalCommits, 2)
        XCTAssertEqual(snapshot.summary.activeDays, 2)
        XCTAssertEqual(snapshot.summary.repositories, 1)
        XCTAssertEqual(snapshot.days.first?.dayKey, "2026-09-04")
        XCTAssertEqual(snapshot.days.last?.dayKey, "2026-09-07")
        XCTAssertEqual(snapshot.summary.commitsPerWeek, 2)
        XCTAssertGreaterThan(snapshot.days.last?.effortUnits ?? 0, 0)
    }

    func testRelativeRiskFlagsWorseningButNotImprovement() {
        let thresholds = MetricThresholds.fallback
        let healthy = metrics(complexity: 10)
        let complex = metrics(complexity: 40)

        let worsening = RelativeRiskAnalyzer.assess(
            path: "service.go",
            before: healthy,
            after: complex,
            thresholds: thresholds
        )
        let improvement = RelativeRiskAnalyzer.assess(
            path: "service.go",
            before: complex,
            after: healthy,
            thresholds: thresholds
        )

        XCTAssertTrue(worsening.issues.contains(.highComplexity))
        XCTAssertGreaterThan(worsening.riskScore, 0)
        XCTAssertTrue(improvement.improvements.contains(.highComplexity))
        XCTAssertEqual(improvement.riskScore, 0)
    }

    func testGeneratedCodeDoesNotInflateEffort() {
        let generated = makeCommit(
            date: "2026-09-07T09:00:00+08:00",
            files: [ChangedFile(path: "api/service.pb.go", additions: 10_000, deletions: 0, isBinary: false)]
        )
        let meaningful = makeCommit(
            date: "2026-09-07T09:00:00+08:00",
            files: [ChangedFile(path: "service.go", additions: 100, deletions: 0, isBinary: false)]
        )

        XCTAssertEqual(MetricEngine.effortUnits(for: generated), 0)
        XCTAssertGreaterThan(MetricEngine.effortUnits(for: meaningful), 0)
    }

    func testAverageCommitIntervalUsesUniqueCalendarDays() throws {
        let calendar = CalendarSupport.calendar(timeZoneIdentifier: "UTC")
        let commits = [
            makeCommit(date: "2026-09-01T09:00:00Z", files: []),
            makeCommit(date: "2026-09-01T18:00:00Z", files: []),
            makeCommit(date: "2026-09-04T09:00:00Z", files: [])
        ]

        XCTAssertEqual(MetricEngine.averageCommitIntervalDays(commits: commits, calendar: calendar), 3)
    }

    func testLineChurnFindsRecentlyRewrittenLineButNotMove() {
        let output = """
        \u{1e}first\u{1f}2026-09-01T10:00:00Z
        diff --git a/main.go b/main.go
        +++ b/main.go
        @@ -0,0 +1,2 @@
        +value := calculateResult(input)
        +moved := preserveThisLine()
        \u{1e}second\u{1f}2026-09-03T10:00:00Z
        diff --git a/main.go b/main.go
        +++ b/main.go
        @@ -1,2 +1,2 @@
        -value := calculateResult(input)
        -moved := preserveThisLine()
        +value := calculateResult(validatedInput)
        +moved := preserveThisLine()
        """

        let churn = LineChurnAnalyzer.analyze(output)

        XCTAssertEqual(churn["second"]?.recentReworkLines, 1)
    }

    func testStaticAnalysisCountsGoImportBlockAndControlFlow() {
        let source = """
        package sample
        import (
            "context"
            "fmt"
        )
        func run(ok bool) {
            if ok {
                for i := 0; i < 2; i++ {}
            }
        }
        """

        let metrics = StaticSourceAnalyzer.analyze(source, path: "main.go")

        XCTAssertEqual(metrics.dependencyCount, 2)
        XCTAssertEqual(metrics.functionCount, 1)
        XCTAssertGreaterThanOrEqual(metrics.cyclomaticComplexity, 3)
    }

    func testSwiftOptionalTypesDoNotCountAsBranches() {
        let source = """
        func parse(value: String?) -> String? {
            value
        }
        """

        let metrics = StaticSourceAnalyzer.analyze(source, path: "Parser.swift")

        XCTAssertEqual(metrics.cyclomaticComplexity, 1)
    }

    private func makeCommit(date: String, files: [ChangedFile]) -> CommitRecord {
        let parsed = ISO8601DateFormatter().date(from: date)!
        return CommitRecord(
            hash: UUID().uuidString,
            repositoryName: "repo",
            repositoryPath: "/tmp/repo",
            authorName: "Developer",
            authorEmail: "developer@example.com",
            authorDate: parsed,
            committerDate: parsed,
            subject: "Test commit",
            files: files,
            riskReasons: [],
            riskWeight: 0
        )
    }

    private func metrics(complexity: Int) -> SourceMetrics {
        SourceMetrics(
            codeLines: 120,
            commentRatio: 0.10,
            longLineRatio: 0,
            cyclomaticComplexity: complexity,
            maximumNesting: 2,
            dependencyCount: 4,
            functionCount: 5,
            maximumFunctionLength: 20
        )
    }
}
