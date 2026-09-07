import Charts
import SwiftUI

struct DashboardView: View {
    let configuration: CalendarConfiguration
    let snapshot: CalendarSnapshot?
    let isRefreshing: Bool
    let onRefresh: () -> Void
    let onEdit: () -> Void
    let onSelectDay: (String) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                if let snapshot {
                    CurrentMonthOverview(
                        days: snapshot.days,
                        generatedAt: snapshot.generatedAt,
                        timeZoneIdentifier: configuration.timeZoneIdentifier
                    )
                    metricGrid(snapshot.summary)
                    HeatmapView(
                        days: snapshot.days,
                        timeZoneIdentifier: configuration.timeZoneIdentifier,
                        onSelectDay: onSelectDay
                    )
                    CommitFrequencyChart(days: snapshot.days, timeZoneIdentifier: configuration.timeZoneIdentifier)
                    MetricTrendChart(days: snapshot.days, timeZoneIdentifier: configuration.timeZoneIdentifier)
                    proxyExplanation
                    if !snapshot.warnings.isEmpty { warnings(snapshot.warnings) }
                } else {
                    ContentUnavailableView(
                        isRefreshing ? "Сканирую репозитории…" : "Данных пока нет",
                        systemImage: isRefreshing ? "arrow.triangle.2.circlepath" : "chart.dots.scatter",
                        description: Text("Запустите обновление, чтобы построить календарь.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 420)
                }
            }
            .padding(24)
        }
        .background {
            LinearGradient(
                colors: [Color.accentColor.opacity(0.065), Color.clear, Color.indigo.opacity(0.035)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(configuration.name).font(.largeTitle.bold())
                Text(configuration.folderPath)
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                if let generatedAt = snapshot?.generatedAt {
                    Text("Обновлено \(generatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button(action: onEdit) { Label("Настроить", systemImage: "slider.horizontal.3") }
            Button(action: onRefresh) {
                Label("Обновить", systemImage: "arrow.clockwise")
            }
            .disabled(isRefreshing)
        }
    }

    private func metricGrid(_ summary: MetricSummary) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            MetricCard(title: "Коммиты", value: "\(summary.totalCommits)", caption: "за выбранный период", tint: .green)
            MetricCard(title: "Активные будни", value: summary.activeWeekdayPercent.formatted(.number.precision(.fractionLength(0))) + "%", caption: "дней с коммитами", tint: .green)
            MetricCard(title: "Частота", value: summary.commitsPerWeek.formatted(.number.precision(.fractionLength(1))), caption: "коммитов в неделю", tint: .blue)
            MetricCard(title: "BCE/day proxy", value: summary.bcePerDayProxy.formatted(.number.precision(.fractionLength(1))), caption: "единиц на будний день", tint: .indigo)
            MetricCard(title: "ACE proxy", value: summary.aceProxy.formatted(.number.precision(.fractionLength(0))), caption: "индекс 0–100", tint: .purple)
            MetricCard(
                title: "Aberrant proxy",
                value: summary.aberrantBCEProxyPercent.formatted(.number.precision(.fractionLength(1))) + "%",
                caption: "изменений с риском",
                tint: summary.aberrantBCEProxyPercent < 10 ? .green : (summary.aberrantBCEProxyPercent < 25 ? .orange : .red)
            )
        }
    }

    private var proxyExplanation: some View {
        GroupBox("Как считаются приближённые метрики") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Это прозрачные локальные прокси, а не показатели сервиса BlueOptima.", systemImage: "info.circle.fill")
                    .foregroundStyle(.secondary)
                Text("BCE/day proxy — сумма весов содержательных изменений, распределённая по будням. ACE proxy — нормированный индекс объёма и поверхности изменений с бонусом за тесты. Aberrant proxy — доля изменённых строк, взвешенная по трём проверяемым рискам: крупный diff, слишком много затронутых исходных файлов и отсутствие тестов у существенного изменения.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Сгенерированные файлы, vendor, Pods, node_modules и binary-файлы исключаются. Пороговые значения можно изменить в настройках календаря.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
        }
    }

    private func warnings(_ warnings: [String]) -> some View {
        GroupBox("Предупреждения сканирования") {
            VStack(alignment: .leading, spacing: 5) {
                ForEach(warnings, id: \.self) { Label($0, systemImage: "exclamationmark.triangle") }
            }
            .foregroundStyle(.orange)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct CurrentMonthOverview: View {
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
        guard !workdays.isEmpty else { return 0 }
        return currentDays.reduce(0) { $0 + $1.effortUnits } / Double(workdays.count)
    }
    private var ace: Double {
        let values = currentDays.filter { $0.commitCount > 0 }.map(\.effortUnits)
        guard !values.isEmpty else { return 0 }
        return MetricEngine.aceScore(forAverageActiveDayEffort: values.reduce(0, +) / Double(values.count))
    }
    private var aberrant: Double {
        let totalLines = currentDays.reduce(0) { $0 + $1.changedLines }
        guard totalLines > 0 else { return 0 }
        let weighted = currentDays.reduce(0.0) { $0 + Double($1.changedLines) * $1.riskPercent / 100 }
        return weighted / Double(totalLines) * 100
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
                    compactMetric("Активные будни", activeWorkdayPercent.formatted(.number.precision(.fractionLength(0))) + "%", .green)
                    compactMetric("BCE/day proxy", bce.formatted(.number.precision(.fractionLength(1))), .indigo)
                    compactMetric("ACE proxy", ace.formatted(.number.precision(.fractionLength(0))), .purple)
                    compactMetric("Aberrant proxy", aberrant.formatted(.number.precision(.fractionLength(1))) + "%", aberrant < 10 ? .green : .orange)
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
}

private struct MetricCard: View {
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

struct HeatmapView: View {
    let days: [DayActivity]
    let timeZoneIdentifier: String
    let onSelectDay: (String) -> Void

    private var paddedDays: [DayActivity?] {
        guard let first = days.first else { return [] }
        let calendar = CalendarSupport.calendar(timeZoneIdentifier: timeZoneIdentifier)
        let weekday = calendar.component(.weekday, from: first.date)
        let leading = (weekday + 5) % 7
        return Array(repeating: nil, count: leading) + days.map(Optional.some)
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
                HStack {
                    Text("Календарь активности").font(.headline)
                    Spacer()
                    Text("меньше")
                    legendCell(opacity: 0.12)
                    legendCell(opacity: 0.35)
                    legendCell(opacity: 0.62)
                    legendCell(opacity: 0.95)
                    Text("больше")
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 3) {
                        ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                            VStack(spacing: 3) {
                                ForEach(0..<7, id: \.self) { index in
                                    if index < week.count, let day = week[index] {
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
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private func color(for count: Int) -> Color {
        guard count > 0 else { return Color.secondary.opacity(0.12) }
        let intensity = log(Double(count) + 1) / log(Double(maximumCount) + 1)
        return Color.green.opacity(0.25 + intensity * 0.75)
    }

    private func legendCell(opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 2).fill(Color.green.opacity(opacity)).frame(width: 11, height: 11)
    }
}

private struct CommitFrequencyChart: View {
    struct Week: Identifiable {
        var id: Date { start }
        var start: Date
        var commits: Int
        var changedLines: Int
    }

    let days: [DayActivity]
    let timeZoneIdentifier: String

    private var weeks: [Week] {
        let calendar = CalendarSupport.calendar(timeZoneIdentifier: timeZoneIdentifier)
        let grouped = Dictionary(grouping: days) { day in
            calendar.dateInterval(of: .weekOfYear, for: day.date)?.start ?? day.date
        }
        return grouped.map { start, values in
            Week(
                start: start,
                commits: values.reduce(0) { $0 + $1.commitCount },
                changedLines: values.reduce(0) { $0 + $1.changedLines }
            )
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

private struct MetricTrendChart: View {
    enum Metric: String, CaseIterable, Identifiable {
        case bce = "BCE/day"
        case ace = "ACE"
        case aberrant = "Aberrant"

        var id: String { rawValue }
        var color: Color {
            switch self {
            case .bce: .indigo
            case .ace: .purple
            case .aberrant: .orange
            }
        }
        var unit: String { self == .bce ? "ед./день" : "%" }
    }

    struct Month: Identifiable {
        var id: Date { start }
        var start: Date
        var bce: Double
        var ace: Double
        var aberrant: Double

        func value(for metric: Metric) -> Double {
            switch metric {
            case .bce: bce
            case .ace: ace
            case .aberrant: aberrant
            }
        }
    }

    let days: [DayActivity]
    let timeZoneIdentifier: String
    @State private var metric: Metric = .aberrant

    private var months: [Month] {
        let calendar = CalendarSupport.calendar(timeZoneIdentifier: timeZoneIdentifier)
        let grouped = Dictionary(grouping: days) { day in
            calendar.dateInterval(of: .month, for: day.date)?.start ?? day.date
        }
        return grouped.map { start, values in
            let workdays = values.filter { CalendarSupport.isWeekday($0.date, calendar: calendar) }
            let activeEffort = values.filter { $0.commitCount > 0 }.map(\.effortUnits)
            let totalLines = values.reduce(0) { $0 + $1.changedLines }
            let riskLines = values.reduce(0.0) { $0 + Double($1.changedLines) * $1.riskPercent / 100 }
            let averageActiveEffort = activeEffort.isEmpty ? 0 : activeEffort.reduce(0, +) / Double(activeEffort.count)
            return Month(
                start: start,
                bce: workdays.isEmpty ? 0 : values.reduce(0) { $0 + $1.effortUnits } / Double(workdays.count),
                ace: MetricEngine.aceScore(forAverageActiveDayEffort: averageActiveEffort),
                aberrant: totalLines == 0 ? 0 : riskLines / Double(totalLines) * 100
            )
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
                Chart(months) { month in
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
                    .foregroundStyle(metric.color)
                }
                .chartYAxisLabel(metric.unit)
                .frame(height: 190)
            }
            .padding(.vertical, 4)
        }
    }
}
