import Foundation

struct LineChurn: Hashable, Sendable {
    var changedCodeLines: Int
    var recentReworkLines: Int
}

enum LineChurnAnalyzer {
    private struct AddedLine {
        let date: Date
        let commitHash: String
    }

    private struct PatchCommit {
        let hash: String
        let date: Date
        let files: [PatchFile]
    }

    private struct PatchFile {
        let path: String
        let additions: [String]
        let deletions: [String]
    }

    static func analyze(_ output: String, recentDays: Int = 14) -> [String: LineChurn] {
        let commits = parse(output)
        var history: [String: [String: [AddedLine]]] = [:]
        var result: [String: LineChurn] = [:]

        for commit in commits {
            var changed = 0
            var reworked = 0
            let cutoff = commit.date.addingTimeInterval(-Double(recentDays) * 86_400)

            for file in commit.files where SourceClassifier.isSource(file.path) {
                let additions = meaningfulCounts(file.additions)
                let deletions = meaningfulCounts(file.deletions)
                changed += additions.values.reduce(0, +) + deletions.values.reduce(0, +)
                var fileHistory = history[file.path] ?? [:]

                for (line, deletionCount) in deletions {
                    let movedCount = min(deletionCount, additions[line] ?? 0)
                    let candidates = (fileHistory[line] ?? []).filter {
                        $0.date >= cutoff && $0.date < commit.date && $0.commitHash != commit.hash
                    }
                    reworked += min(max(0, deletionCount - movedCount), candidates.count)
                    if deletionCount > 0, var entries = fileHistory[line] {
                        entries.removeFirst(min(deletionCount, entries.count))
                        fileHistory[line] = entries
                    }
                }

                for (line, count) in additions {
                    fileHistory[line, default: []].append(contentsOf: Array(
                        repeating: AddedLine(date: commit.date, commitHash: commit.hash),
                        count: count
                    ))
                }
                history[file.path] = fileHistory
            }
            result[commit.hash] = LineChurn(changedCodeLines: changed, recentReworkLines: reworked)
        }
        return result
    }

    private static func meaningfulCounts(_ lines: [String]) -> [String: Int] {
        Dictionary(grouping: lines.compactMap(normalize), by: { $0 }).mapValues(\.count)
    }

    private static func normalize(_ line: String) -> String? {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.count >= 4,
              !value.hasPrefix("//"),
              !value.hasPrefix("#"),
              !value.hasPrefix("*") else { return nil }
        return value.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    private static func parse(_ output: String) -> [PatchCommit] {
        output
            .split(separator: "\u{1e}", omittingEmptySubsequences: true)
            .compactMap { parseCommit(String($0)) }
            .sorted { $0.date < $1.date }
    }

    private static func parseCommit(_ record: String) -> PatchCommit? {
        guard let newline = record.firstIndex(of: "\n") else { return nil }
        let header = String(record[..<newline])
        let fields = header.split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
        guard fields.count >= 2, let date = ISO8601DateFormatter().date(from: fields[1]) else { return nil }

        var files: [PatchFile] = []
        var path: String?
        var additions: [String] = []
        var deletions: [String] = []

        func finishFile() {
            guard let path else { return }
            files.append(PatchFile(path: path, additions: additions, deletions: deletions))
        }

        for line in record[record.index(after: newline)...].components(separatedBy: .newlines) {
            if line.hasPrefix("diff --git ") {
                finishFile()
                path = nil
                additions = []
                deletions = []
            } else if line.hasPrefix("+++ b/") {
                path = String(line.dropFirst(6))
            } else if line.hasPrefix("+") && !line.hasPrefix("+++") {
                additions.append(String(line.dropFirst()))
            } else if line.hasPrefix("-") && !line.hasPrefix("---") {
                deletions.append(String(line.dropFirst()))
            }
        }
        finishFile()
        return PatchCommit(hash: fields[0], date: date, files: files)
    }
}
