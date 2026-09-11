import SwiftUI

struct CurrentMonthOverview: View {
    let days: [DayActivity]
    let generatedAt: Date
    let timeZoneIdentifier: String

    private var currentDays: [DayActivity] {
        let calendar = CalendarSupport.calendar(timeZoneIdentifier: timeZoneIdentifier)
        return days.filter { calendar.isDate($0.date, equalTo: generatedAt, toGranularity: .month) }
    }

    private var workdays: [DayActivity] {
        let calendar = CalendarSupport.calendar(timeZoneIdentifier: timeZoneIdentifier)
        return currentDays.filter { CalendarSupport.isWeekday($0.date, calendar: calendar) }
    }

    private var commits: Int { currentDays.reduce(0) { $0 + $1.commitCount } }

    private var activeWorkdayPercent: Double {
        guard !workdays.isEmpty else { return 0 }
        return Double(workdays.filter { $0.commitCount > 0 }.count) / Double(workdays.count) * 100
    }

    private var bce: Double {
        let active = workdays.filter { ($0.actualEffortUnits ?? $0.effortUnits) > 0 }
        guard !active.isEmpty else { return 0 }
        return active.reduce(0) { $0 + $1.effortUnits } / Double(active.count)
    }

    private var ace: Double {
        let values = currentDays.map { $0.actualEffortUnits ?? $0.effortUnits }.filter { $0 > 0 }
        guard !values.isEmpty else { return 0 }
        return values.reduce(0, +) / Double(values.count)
    }

    private var aberrant: Double {
        let analyzed = currentDays.reduce(0.0) { $0 + ($1.analyzedEffortUnits ?? 0) }
        guard analyzed > 0 else { return 0 }
        let weighted = currentDays.reduce(0.0) {
            $0 + ($1.analyzedEffortUnits ?? 0) * $1.riskPercent / 100
        }
        return weighted / analyzed * 100
    }

    private var averageInterval: Double? {
        let calendar = CalendarSupport.calendar(timeZoneIdentifier: timeZoneIdentifier)
        return MetricEngine.averageDayInterval(
            dates: currentDays.filter { $0.commitCount > 0 }.map(\.date),
            calendar: calendar
        )
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ru_RU")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: generatedAt).capitalized
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(monthTitle).font(.headline)
                    Text("с начала месяца").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                HStack(spacing: 18) {
                    compactMetric("Коммиты", "\(commits)", .green)
                    compactMetric("Активные будни", percent(activeWorkdayPercent), .green)
                    compactMetric("BCE/day proxy", decimal(bce), .indigo)
                    compactMetric("ACE/day proxy", decimal(ace), .purple)
                    compactMetric("Aberrant proxy", percent(aberrant), aberrant < 10 ? .green : .orange)
                    compactMetric(
                        "Средний интервал",
                        averageInterval.map { decimal($0) + " дн." } ?? "—",
                        averageInterval.map { $0 > 2 ? .red : .green } ?? .secondary
                    )
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func compactMetric(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.headline.monospacedDigit()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func percent(_ value: Double) -> String { decimal(value) + "%" }
}

struct MetricCard: View {
    let title: String
    let value: String
    let caption: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.bold()).foregroundStyle(tint)
            Text(caption).font(.caption2).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, minHeight: 78, alignment: .leading)
        .padding(14)
        .metricGlassSurface()
    }
}
