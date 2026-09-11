import Foundation

enum GitLogParser {
    static func parse(
        _ output: String,
        repository: URL,
        configuration: CalendarConfiguration
    ) -> [CommitRecord] {
        output
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .compactMap { parseRecord(String($0), repository: repository) }
            .filter { matchesIdentity($0, patterns: configuration.authorPatterns) }
    }

    private static func parseRecord(_ value: String, repository: URL) -> CommitRecord? {
        let lines = value.split(omittingEmptySubsequences: true) { $0.isNewline }
        guard let header = lines.first else { return nil }
        let fields = header.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 6,
              let authorDate = parseISO8601(fields[1]),
              let committerDate = parseISO8601(fields[2]) else { return nil }

        return CommitRecord(
            hash: fields[0],
            repositoryName: repository.lastPathComponent,
            repositoryPath: repository.path,
            authorName: fields[3],
            authorEmail: fields[4],
            authorDate: authorDate,
            committerDate: committerDate,
            subject: fields[5],
            files: lines.dropFirst().compactMap(parseNumstat),
            riskReasons: [],
            riskWeight: 0
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
        let normalized = patterns
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return true }
        let identity = "\(commit.authorName) <\(commit.authorEmail)>".lowercased()
        return normalized.contains { identity.contains($0) }
    }
}
