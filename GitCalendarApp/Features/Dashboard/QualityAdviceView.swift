import SwiftUI

struct QualityAdviceView: View {
    let snapshot: CalendarSnapshot

    var body: some View {
        GroupBox("Что улучшить") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(AdviceEngine.makeAdvice(snapshot: snapshot, now: snapshot.generatedAt)) { advice in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: icon(for: advice.level))
                            .foregroundStyle(color(for: advice.level))
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(advice.title).font(.headline)
                            Text(advice.detail).font(.callout).foregroundStyle(.secondary)
                        }
                    }
                }

                Divider()
                Label(
                    "Squash не считается дефектом: оценивается итоговое изменение кода. Не меняйте Git-стратегию ради proxy.",
                    systemImage: "arrow.triangle.merge"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func icon(for level: QualityAdvice.Level) -> String {
        switch level {
        case .positive: "checkmark.seal.fill"
        case .information: "info.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .critical: "xmark.octagon.fill"
        }
    }

    private func color(for level: QualityAdvice.Level) -> Color {
        switch level {
        case .positive: .green
        case .information: .blue
        case .warning: .orange
        case .critical: .red
        }
    }
}
