import AppKit
import SwiftUI

struct DayDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let selection: SelectedDay
    let commits: [CommitRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading) {
                    Text(selection.dayKey).font(.title2.bold())
                    Text("\(commits.count) коммитов · \(commits.reduce(0) { $0 + $1.changedLines }) изменённых строк")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Закрыть") { dismiss() }
            }

            if commits.isEmpty {
                ContentUnavailableView("Коммитов нет", systemImage: "calendar")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(commits) { commit in
                    CommitRow(commit: commit)
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(minWidth: 760, minHeight: 520)
    }
}

private struct CommitRow: View {
    let commit: CommitRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(commit.subject).font(.headline).lineLimit(2)
                Spacer()
                Text(commit.authorDate.formatted(date: .omitted, time: .shortened))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                Label(commit.repositoryName, systemImage: "shippingbox")
                Text(commit.shortHash).font(.caption.monospaced())
                Text("+\(commit.additions)").foregroundStyle(.green)
                Text("−\(commit.deletions)").foregroundStyle(.red)
                Text("\(commit.files.count) файлов")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            if !commit.riskReasons.isEmpty {
                HStack(spacing: 6) {
                    ForEach(commit.riskReasons, id: \.self) { reason in
                        Text(reason.title)
                            .font(.caption2)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.orange.opacity(0.14), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
            }

            if let quality = commit.quality {
                if quality.recentReworkLines > 0 {
                    Label(
                        "Churn: \(quality.recentReworkLines) строк (\(quality.recentReworkPercent.formatted(.number.precision(.fractionLength(1))))%) переписано за 14 дней",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .font(.caption)
                    .foregroundStyle(.blue)
                }

                ForEach(Array(quality.fileChanges.filter { !$0.issues.isEmpty }.prefix(3)), id: \.path) { file in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(file.path).font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
                        Text(file.issues.map(\.title).joined(separator: " · "))
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
            }

            HStack {
                Button("Скопировать SHA") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(commit.hash, forType: .string)
                }
                Button("Открыть папку") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: commit.repositoryPath))
                }
                Spacer()
                Text("\(commit.authorName) <\(commit.authorEmail)>")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 6)
    }
}
