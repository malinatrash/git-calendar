import AppIntents
import SwiftUI
import WidgetKit

struct GitCalendarEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetCalendarSnapshot?
    let configuration: CalendarWidgetIntent
}

struct GitCalendarProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> GitCalendarEntry {
        GitCalendarEntry(date: Date(), snapshot: Self.preview, configuration: CalendarWidgetIntent())
    }

    func snapshot(for configuration: CalendarWidgetIntent, in context: Context) async -> GitCalendarEntry {
        entry(for: configuration)
    }

    func timeline(for configuration: CalendarWidgetIntent, in context: Context) async -> Timeline<GitCalendarEntry> {
        let entry = entry(for: configuration)
        return Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(15 * 60)))
    }

    private func entry(for configuration: CalendarWidgetIntent) -> GitCalendarEntry {
        let snapshots = SharedStore.loadWidgetSnapshots()
        let selected = configuration.calendar.flatMap { selected in
            snapshots.first { $0.configurationID == selected.id }
        } ?? snapshots.first
        return GitCalendarEntry(date: Date(), snapshot: selected, configuration: configuration)
    }

    private static var preview: WidgetCalendarSnapshot {
        let now = Date()
        let days = (0..<112).map { offset in
            DayActivity(
                dayKey: "preview-\(offset)",
                date: Calendar.current.date(byAdding: .day, value: -111 + offset, to: now) ?? now,
                commitCount: offset % 9 == 0 ? 4 : (offset % 4 == 0 ? 1 : 0),
                changedLines: 0,
                riskPercent: 0,
                effortUnits: 0
            )
        }
        return WidgetCalendarSnapshot(
            configurationID: UUID(),
            name: "My projects",
            timeZoneIdentifier: TimeZone.current.identifier,
            generatedAt: now,
            days: days,
            summary: .empty
        )
    }
}

struct GitCalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: GitCalendarEntry

    var body: some View {
        if let snapshot = entry.snapshot {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(snapshot.name).font(.headline).lineLimit(1)
                        Text("\(snapshot.summary.commitsPerWeek.formatted(.number.precision(.fractionLength(1)))) коммита/нед")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("\(snapshot.summary.totalCommits)").font(.headline.monospacedDigit()).foregroundStyle(.green)
                        Text("Aberrant ~\(snapshot.summary.aberrantBCEProxyPercent.formatted(.number.precision(.fractionLength(0))))%")
                            .font(.caption2)
                            .foregroundStyle(snapshot.summary.aberrantBCEProxyPercent < 10 ? .green : .orange)
                    }
                }
                WidgetHeatmap(
                    calendarID: snapshot.configurationID,
                    days: Array(snapshot.days.suffix(dayLimit)),
                    maximumCount: max(snapshot.days.map(\.commitCount).max() ?? 1, 1),
                    timeZoneIdentifier: snapshot.timeZoneIdentifier
                )
                Spacer(minLength: 0)
                HStack {
                    Text("BCE/day proxy \(snapshot.summary.bcePerDayProxy.formatted(.number.precision(.fractionLength(1))))")
                    Spacer()
                    Text(snapshot.generatedAt, style: .time)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .containerBackground(.fill.tertiary, for: .widget)
        } else {
            ContentUnavailableView("Нет календаря", systemImage: "calendar.badge.plus")
                .containerBackground(.fill.tertiary, for: .widget)
        }
    }

    private var dayLimit: Int {
        switch family {
        case .systemLarge: 182
        case .systemMedium: 112
        default: 49
        }
    }
}

private struct WidgetHeatmap: View {
    let calendarID: UUID
    let days: [DayActivity]
    let maximumCount: Int
    let timeZoneIdentifier: String

    private var paddedDays: [DayActivity?] {
        guard let first = days.first else { return [] }
        let weekday = CalendarSupport.calendar(timeZoneIdentifier: timeZoneIdentifier).component(.weekday, from: first.date)
        let leading = (weekday + 5) % 7
        return Array(repeating: nil, count: leading) + days.map(Optional.some)
    }

    private var weeks: [[DayActivity?]] {
        stride(from: 0, to: paddedDays.count, by: 7).map {
            Array(paddedDays[$0..<min($0 + 7, paddedDays.count)])
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let spacing = 2.0
            let cell = max(4, min(12, (geometry.size.height - spacing * 6) / 7))
            HStack(alignment: .top, spacing: spacing) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { index in
                            if index < week.count, let day = week[index] {
                                Link(destination: dayURL(day.dayKey)) {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(color(for: day.commitCount))
                                        .frame(width: cell, height: cell)
                                        .overlay(alignment: .center) {
                                            if day.riskPercent >= 25 {
                                                Circle().fill(.orange).frame(width: 2.5, height: 2.5)
                                            }
                                        }
                                }
                                .accessibilityLabel("\(day.dayKey), коммитов: \(day.commitCount)")
                            } else {
                                Color.clear.frame(width: cell, height: cell)
                            }
                        }
                    }
                }
            }
        }
    }

    private func color(for count: Int) -> Color {
        guard count > 0 else { return .secondary.opacity(0.13) }
        let intensity = log(Double(count) + 1) / log(Double(maximumCount) + 1)
        return .green.opacity(0.25 + intensity * 0.75)
    }

    private func dayURL(_ dayKey: String) -> URL {
        var components = URLComponents()
        components.scheme = "gitcalendar"
        components.host = "day"
        components.path = "/\(calendarID.uuidString)/\(dayKey)"
        return components.url ?? URL(fileURLWithPath: "/")
    }
}

struct GitCalendarWidget: Widget {
    let kind = SharedConstants.widgetKind

    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: CalendarWidgetIntent.self, provider: GitCalendarProvider()) { entry in
            GitCalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("Git Calendar")
        .description("Локальная Git-активность выбранной папки.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
