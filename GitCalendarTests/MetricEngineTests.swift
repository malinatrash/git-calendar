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

    func testRiskProxyRewardsTestsWithoutTreatingItAsOfficialBCE() {
        var configuration = CalendarConfiguration(name: "Test", folderPath: "/tmp")
        configuration.testsExpectedAfterLines = 50
        configuration.largeChangeThreshold = 500

        let withoutTests = RiskAnalyzer.assess(
            files: [ChangedFile(path: "service.go", additions: 80, deletions: 0, isBinary: false)],
            configuration: configuration
        )
        let withTests = RiskAnalyzer.assess(
            files: [
                ChangedFile(path: "service.go", additions: 80, deletions: 0, isBinary: false),
                ChangedFile(path: "service_test.go", additions: 40, deletions: 0, isBinary: false)
            ],
            configuration: configuration
        )

        XCTAssertTrue(withoutTests.reasons.contains(.sourceWithoutTests))
        XCTAssertFalse(withTests.reasons.contains(.sourceWithoutTests))
        XCTAssertGreaterThan(withoutTests.weight, withTests.weight)
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

        XCTAssertLessThan(MetricEngine.effortUnits(for: generated), MetricEngine.effortUnits(for: meaningful))
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
}
