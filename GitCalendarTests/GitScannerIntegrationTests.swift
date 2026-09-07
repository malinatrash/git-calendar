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
