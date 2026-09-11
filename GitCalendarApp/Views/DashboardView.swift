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
                    dashboard(snapshot)
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

    @ViewBuilder
    private func dashboard(_ snapshot: CalendarSnapshot) -> some View {
        CurrentMonthOverview(
            days: snapshot.days,
            generatedAt: snapshot.generatedAt,
            timeZoneIdentifier: configuration.timeZoneIdentifier
        )
        metricGrid(snapshot.summary)
        QualityAdviceView(snapshot: snapshot)
        HeatmapView(
            days: snapshot.days,
            timeZoneIdentifier: configuration.timeZoneIdentifier,
            onSelectDay: onSelectDay
        )
        CommitFrequencyChart(days: snapshot.days, timeZoneIdentifier: configuration.timeZoneIdentifier)
        MetricTrendChart(days: snapshot.days, timeZoneIdentifier: configuration.timeZoneIdentifier)
        proxyExplanation
        if !snapshot.warnings.isEmpty { warnings(snapshot.warnings) }
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
            Button(action: onRefresh) { Label("Обновить", systemImage: "arrow.clockwise") }
                .disabled(isRefreshing)
        }
    }

    private func metricGrid(_ summary: MetricSummary) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 12)], spacing: 12) {
            MetricCard(title: "Коммиты", value: "\(summary.totalCommits)", caption: "без merge", tint: .green)
            MetricCard(title: "Активные будни", value: percent(summary.activeWeekdayPercent, digits: 0), caption: "дней с коммитами", tint: .green)
            MetricCard(title: "Частота", value: decimal(summary.commitsPerWeek), caption: "коммитов в неделю", tint: .blue)
            MetricCard(title: "BCE/day proxy", value: decimal(summary.bcePerDayProxy), caption: "с дневным лимитом 5", tint: .indigo)
            MetricCard(title: "ACE/day proxy", value: decimal(summary.aceProxy), caption: "без дневного лимита", tint: .purple)
            MetricCard(
                title: "Средний интервал",
                value: summary.averageCommitIntervalDays.map { decimal($0) + " дн." } ?? "—",
                caption: "за 90 дней, без merge",
                tint: (summary.averageCommitIntervalDays ?? 0) > 2 ? .red : .green
            )
            MetricCard(
                title: "Aberrant proxy",
                value: percent(summary.aberrantBCEProxyPercent),
                caption: summary.analyzedCommitPercent.map { "покрытие анализа \(percent($0, digits: 0))" } ?? "нет анализируемых изменений",
                tint: summary.aberrantBCEProxyPercent < 10 ? .green : (summary.aberrantBCEProxyPercent < 25 ? .orange : .red)
            )
        }
    }

    private var proxyExplanation: some View {
        GroupBox("Как считаются приближённые метрики") {
            VStack(alignment: .leading, spacing: 8) {
                Label("Это прозрачные локальные прокси, а не показатели сервиса BlueOptima.", systemImage: "info.circle.fill")
                    .foregroundStyle(.secondary)
                Text("BCE/day оценивает объём, сложность и связанность изменений с дневным лимитом 5; ACE/day показывает оценку без лимита. Aberrant — доля оценённого Coding Effort, где изменение ухудшило относительные пороги размера, сложности, вложенности, связанности, длины функций или читаемости файла.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text("Порог — 90-й перцентиль файлов того же языка с консервативным минимумом. Окно: 180 дней, до 240 коммитов и 12 файлов на коммит. Churn, тесты и размер diff — отдельные сигналы.")
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

    private func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(1)))
    }

    private func percent(_ value: Double, digits: Int = 1) -> String {
        value.formatted(.number.precision(.fractionLength(digits))) + "%"
    }
}
