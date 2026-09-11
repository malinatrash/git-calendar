import Foundation
import XCTest

final class GitScannerIntegrationTests: XCTestCase {
    func testScansNestedRepositoriesAndFiltersAuthor() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("git-calendar-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try createRepository(at: root.appendingPathComponent("service-a"), subject: "feat: first")
        try createRepository(at: root.appendingPathComponent("nested/service-b"), subject: "feat: second")

        let configuration = CalendarConfiguration(
            name: "Fixture",
            folderPath: root.path,
            authorPatterns: ["calendar@example.com"]
        )
        let snapshot = try GitScanner().scan(configuration: configuration)

        XCTAssertEqual(snapshot.repositoryPaths.count, 2)
        XCTAssertEqual(snapshot.commits.count, 2)
        XCTAssertEqual(Set(snapshot.commits.map(\.repositoryName)), ["service-a", "service-b"])
        XCTAssertEqual(snapshot.warnings, [])
    }

    func testAlwaysExcludesMergeCommits() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("git-calendar-merge-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try createRepository(at: root, subject: "initial")

        try runGit(["checkout", "-q", "-b", "feature"], at: root)
        try "package feature\n".write(to: root.appendingPathComponent("feature.go"), atomically: true, encoding: .utf8)
        try runGit(["add", "feature.go"], at: root)
        try runGit(["commit", "--quiet", "-m", "feature"], at: root)
        try runGit(["checkout", "-q", "-"], at: root)
        try "package main\n".write(to: root.appendingPathComponent("other.go"), atomically: true, encoding: .utf8)
        try runGit(["add", "other.go"], at: root)
        try runGit(["commit", "--quiet", "-m", "main change"], at: root)
        try runGit(["merge", "--quiet", "--no-ff", "feature", "-m", "merge feature"], at: root)

        var configuration = CalendarConfiguration(
            name: "Fixture",
            folderPath: root.path,
            authorPatterns: ["calendar@example.com"]
        )
        configuration.includeMerges = true
        configuration.largeChangeThreshold = 1
        configuration.testsExpectedAfterLines = 1
        configuration.wideChangeFileThreshold = 1

        let snapshot = try GitScanner().scan(configuration: configuration)

        XCTAssertEqual(snapshot.commits.count, 3)
        XCTAssertFalse(snapshot.commits.contains { $0.subject == "merge feature" })
        XCTAssertTrue(snapshot.commits.contains {
            $0.riskReasons.contains(.largeChange)
                && $0.riskReasons.contains(.wideChange)
                && $0.riskReasons.contains(.sourceWithoutTests)
        })
    }

    private func createRepository(at url: URL, subject: String) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try runGit(["init", "--quiet"], at: url)
        try runGit(["config", "user.name", "Calendar Test"], at: url)
        try runGit(["config", "user.email", "calendar@example.com"], at: url)
        try "package calendar\n".write(to: url.appendingPathComponent("main.go"), atomically: true, encoding: .utf8)
        try runGit(["add", "main.go"], at: url)
        try runGit(["commit", "--quiet", "-m", subject], at: url)
    }

    private func runGit(_ arguments: [String], at directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", directory.path] + arguments
        process.standardOutput = Pipe()
        let errors = Pipe()
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let data = errors.fileHandleForReading.readDataToEndOfFile()
            XCTFail(String(decoding: data, as: UTF8.self))
        }
    }
}
