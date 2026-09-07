import XCTest

final class GitLogParserTests: XCTestCase {
    func testParsesNumstatAndFiltersByAuthor() throws {
        let recordSeparator = "\u{1e}"
        let fieldSeparator = "\u{1f}"
        let output = """
        \(recordSeparator)abcdef123456\(fieldSeparator)2026-09-07T10:00:00+08:00\(fieldSeparator)2026-09-07T10:01:00+08:00\(fieldSeparator)Alex Smith\(fieldSeparator)developer@example.com\(fieldSeparator)feat: add calendar
        12\t3\tSources/Calendar.swift
        20\t0\tTests/CalendarTests.swift
        """
        let configuration = CalendarConfiguration(
            name: "Test",
            folderPath: "/tmp/repo",
            authorPatterns: ["developer@example.com"]
        )

        let commits = GitLogParser.parse(
            output,
            repository: URL(fileURLWithPath: "/tmp/repo"),
            configuration: configuration
        )

        let commit = try XCTUnwrap(commits.first)
        XCTAssertEqual(commits.count, 1)
        XCTAssertEqual(commit.hash, "abcdef123456")
        XCTAssertEqual(commit.files.count, 2)
        XCTAssertEqual(commit.additions, 32)
        XCTAssertEqual(commit.deletions, 3)
        XCTAssertEqual(commit.subject, "feat: add calendar")
    }

    func testRejectsDifferentAuthor() {
        let output = "\u{1e}abc\u{1f}2026-09-07T10:00:00+08:00\u{1f}2026-09-07T10:00:00+08:00\u{1f}Other\u{1f}other@example.com\u{1f}Change\n1\t0\tmain.go"
        let configuration = CalendarConfiguration(
            name: "Test",
            folderPath: "/tmp/repo",
            authorPatterns: ["developer@example.com"]
        )

        XCTAssertTrue(GitLogParser.parse(
            output,
            repository: URL(fileURLWithPath: "/tmp/repo"),
            configuration: configuration
        ).isEmpty)
    }
}
