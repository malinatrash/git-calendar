import Charts
import SwiftUI

struct CommitFrequencyChart: View {
    struct Week: Identifiable {
        var id: Date { start }
        var start: Date
        var commits: Int
    }

    let days: [DayActivity]
    let timeZoneIdentifier: String

    private var weeks: [Week] {
        let calendar = CalendarSupport.calendar(timeZoneIdentifier: timeZoneIdentifier)
        let grouped = Dictionary(grouping: days) {
            calendar.dateInterval(of: .weekOfYear, for: $0.date)?.start ?? $0.date
        }
        return grouped.map { start, values in
            Week(start: start, commits: values.reduce(0) { $0 + $1.commitCount })
        }
        .sorted { $0.start < $1.start }
        .suffix(26)
        .map { $0 }
    }

    var body: some View {
        GroupBox("Частота коммитов — последние 26 недель") {
            Chart(weeks) { week in
                BarMark(
                    x: .value("Неделя", week.start, unit: .weekOfYear),
                    y: .value("Коммиты", week.commits)
                )
                .foregroundStyle(.green.gradient)
                .accessibilityLabel(week.start.formatted(date: .abbreviated, time: .omitted))
                .accessibilityValue("\(week.commits) коммитов")
            }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 190)
            .padding(.top, 8)
        }
    }
}

struct MetricTrendChart: View {
    enum Metric: String, CaseIterable, Identifiable {
        case bce = "BCE/day"
        case ace = "ACE/day"
        case aberrant = "Aberrant"
        case interval = "Интервал"

        var id: String { rawValue }
        var color: Color {
            switch self {
            case .bce: .indigo
            case .ace: .purple
            case .aberrant: .orange
            case .interval: .blue
            }
        }
        var unit: String {
            switch self {
            case .aberrant: "%"
            case .interval: "дни"
            case .bce, .ace: "ед./день"
            }
        }
    }

    struct Month: Identifiable {
        var id: Date { start }
        var start: Date
        var bce: Double
        var ace: Double
        var aberrant: Double
        var averageInterval: Double?

        func value(for metric: Metric) -> Double {
            switch metric {
            case .bce: bce
            case .ace: ace
            case .aberrant: aberrant
            case .interval: averageInterval ?? 0
            }
        }
    }

    let days: [DayActivity]
    let timeZoneIdentifier: String
    @State private var metric: Metric = .aberrant

    private var months: [Month] {
        let calendar = CalendarSupport.calendar(timeZoneIdentifier: timeZoneIdentifier)
        let grouped = Dictionary(grouping: days) {
            calendar.dateInterval(of: .month, for: $0.date)?.start ?? $0.date
        }
        return grouped.map { start, values in
            makeMonth(start: start, values: values, calendar: calendar)
        }
        .sorted { $0.start < $1.start }
        .suffix(12)
        .map { $0 }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Динамика proxy-метрик").font(.headline)
                    Spacer()
                    Picker("Метрика", selection: $metric) {
                        ForEach(Metric.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 330)
                }
                Chart {
                    ForEach(displayedMonths) { month in
                        LineMark(
                            x: .value("Месяц", month.start, unit: .month),
                            y: .value(metric.rawValue, month.value(for: metric))
                        )
                        .foregroundStyle(metric.color)
                        .interpolationMethod(.catmullRom)
                        PointMark(
                            x: .value("Месяц", month.start, unit: .month),
                            y: .value(metric.rawValue, month.value(for: metric))
                        )
                        .foregroundStyle(pointColor(for: month))
                    }
                    if metric == .interval {
                        RuleMark(y: .value("Порог", 2))
                            .foregroundStyle(.red.opacity(0.65))
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    }
                }
                .chartYAxisLabel(metric.unit)
                .frame(height: 190)
            }
            .padding(.vertical, 4)
        }
    }

    private func makeMonth(start: Date, values: [DayActivity], calendar: Calendar) -> Month {
        let workdays = values.filter { CalendarSupport.isWeekday($0.date, calendar: calendar) }
        let activeWorkdays = workdays.filter { ($0.actualEffortUnits ?? $0.effortUnits) > 0 }
        let activeEffort = values.map { $0.actualEffortUnits ?? $0.effortUnits }.filter { $0 > 0 }
        let analyzedEffort = values.reduce(0.0) { $0 + ($1.analyzedEffortUnits ?? 0) }
        let aberrantEffort = values.reduce(0.0) {
            $0 + ($1.analyzedEffortUnits ?? 0) * $1.riskPercent / 100
        }
        return Month(
            start: start,
            bce: average(activeWorkdays.map(\.effortUnits)),
            ace: average(activeEffort),
            aberrant: analyzedEffort == 0 ? 0 : aberrantEffort / analyzedEffort * 100,
            averageInterval: MetricEngine.averageDayInterval(
                dates: values.filter { $0.commitCount > 0 }.map(\.date),
                calendar: calendar
            )
        )
    }

    private var displayedMonths: [Month] {
        metric == .interval ? months.filter { $0.averageInterval != nil } : months
    }

    private func pointColor(for month: Month) -> Color {
        guard metric == .interval else { return metric.color }
        return month.value(for: metric) > 2 ? .red : .green
    }

    private func average(_ values: [Double]) -> Double {
        values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
    }
}
