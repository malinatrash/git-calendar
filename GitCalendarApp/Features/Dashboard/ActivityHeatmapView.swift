import SwiftUI

struct HeatmapView: View {
    let days: [DayActivity]
    let timeZoneIdentifier: String
    let onSelectDay: (String) -> Void

    private var paddedDays: [DayActivity?] {
        guard let first = days.first else { return [] }
        let calendar = CalendarSupport.calendar(timeZoneIdentifier: timeZoneIdentifier)
        let weekday = calendar.component(.weekday, from: first.date)
        return Array(repeating: nil, count: (weekday + 5) % 7) + days.map(Optional.some)
    }

    private var weeks: [[DayActivity?]] {
        stride(from: 0, to: paddedDays.count, by: 7).map {
            Array(paddedDays[$0..<min($0 + 7, paddedDays.count)])
        }
    }

    private var maximumCount: Int { max(days.map(\.commitCount).max() ?? 1, 1) }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                legend
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: 3) {
                                ForEach(0..<7, id: \.self) { index in
                                    dayCell(index < week.count ? week[index] : nil)
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var legend: some View {
        HStack {
            Text("Календарь активности").font(.headline)
            Spacer()
            Text("меньше")
            ForEach([0.12, 0.35, 0.62, 0.95], id: \.self) { opacity in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.green.opacity(opacity))
                    .frame(width: 11, height: 11)
            }
            Text("больше")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func dayCell(_ day: DayActivity?) -> some View {
        if let day {
            Button { onSelectDay(day.dayKey) } label: {
                RoundedRectangle(cornerRadius: 2.5)
                    .fill(color(for: day.commitCount))
                    .frame(width: 13, height: 13)
                    .overlay {
                        if day.riskPercent >= 25 {
                            Circle().fill(.orange).frame(width: 3.5, height: 3.5)
                        }
                    }
            }
            .buttonStyle(.plain)
            .help("\(day.dayKey): \(day.commitCount) коммитов, \(day.changedLines) строк")
        } else {
            Color.clear.frame(width: 13, height: 13)
        }
    }

    private func color(for count: Int) -> Color {
        guard count > 0 else { return Color.secondary.opacity(0.12) }
        let intensity = log(Double(count) + 1) / log(Double(maximumCount) + 1)
        return Color.green.opacity(0.25 + intensity * 0.75)
    }
}
