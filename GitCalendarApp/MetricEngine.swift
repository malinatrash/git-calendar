import Foundation

enum MetricEngine {
    static func makeSnapshot(
        configuration: CalendarConfiguration,
        repositoryPaths: [String],
        commits: [CommitRecord],
        warnings: [String] = [],
        now: Date = Date()
    ) -> CalendarSnapshot {
        let calendar = CalendarSupport.calendar(timeZoneIdentifier: configuration.timeZoneIdentifier)
        let today = calendar.startOfDay(for: now)
        let firstCommitDate = commits.map(\.authorDate).min() ?? today
        let firstDay = min(calendar.startOfDay(for: firstCommitDate), today)
        let grouped = Dictionary(grouping: commits) {
            CalendarSupport.dayKey(for: $0.authorDate, timeZoneIdentifier: configuration.timeZoneIdentifier)
        }

        var days: [DayActivity] = []
        var date = firstDay
        while date <= today {
            let key = CalendarSupport.dayKey(for: date, timeZoneIdentifier: configuration.timeZoneIdentifier)
            let dayCommits = grouped[key] ?? []
            let changedLines = dayCommits.reduce(0) { $0 + RiskAnalyzer.meaningfulChangedLines(in: $1) }
            let riskLines = dayCommits.reduce(0.0) {
                $0 + Double(RiskAnalyzer.meaningfulChangedLines(in: $1)) * $1.riskWeight
            }
            let dailyEffort = min(10, dayCommits.reduce(0) { $0 + effortUnits(for: $1) })
            days.append(DayActivity(
                dayKey: key,
                date: date,
                commitCount: dayCommits.count,
                changedLines: changedLines,
                riskPercent: changedLines == 0 ? 0 : riskLines / Double(changedLines) * 100,
                effortUnits: dailyEffort
            ))
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? today.addingTimeInterval(86_400)
        }

        let workdays = days.filter { CalendarSupport.isWeekday($0.date, calendar: calendar) }
        let activeWorkdays = workdays.filter { $0.commitCount > 0 }
        let activeDays = days.filter { $0.commitCount > 0 }.count
        let weeks = max(Double(days.count) / 7.0, 1)
        let effortByDay = grouped.values.map { dayCommits in
            min(10, dayCommits.reduce(0) { $0 + effortUnits(for: $1) })
        }
        let totalEffort = effortByDay.reduce(0, +)
        let averageActiveDayEffort = effortByDay.isEmpty ? 0 : totalEffort / Double(effortByDay.count)
        let totalMeaningfulLines = commits.reduce(0) { $0 + RiskAnalyzer.meaningfulChangedLines(in: $1) }
        let riskWeightedLines = commits.reduce(0.0) {
            $0 + Double(RiskAnalyzer.meaningfulChangedLines(in: $1)) * $1.riskWeight
        }

        let summary = MetricSummary(
            totalCommits: commits.count,
            activeDays: activeDays,
            activeWeekdayPercent: workdays.isEmpty ? 0 : Double(activeWorkdays.count) / Double(workdays.count) * 100,
            commitsPerWeek: Double(commits.count) / weeks,
            commitsPerActiveDay: activeDays == 0 ? 0 : Double(commits.count) / Double(activeDays),
            currentWeekdayStreak: weekdayStreak(days: days, calendar: calendar),
            bcePerDayProxy: workdays.isEmpty ? 0 : totalEffort / Double(workdays.count),
            aceProxy: aceScore(forAverageActiveDayEffort: averageActiveDayEffort),
            aberrantBCEProxyPercent: totalMeaningfulLines == 0 ? 0 : riskWeightedLines / Double(totalMeaningfulLines) * 100,
            repositories: repositoryPaths.count
        )

        return CalendarSnapshot(
            configurationID: configuration.id,
            generatedAt: now,
            repositoryPaths: repositoryPaths,
            commits: commits,
            days: days,
            summary: summary,
            warnings: warnings
        )
    }

    static func effortUnits(for commit: CommitRecord) -> Double {
        let lines = Double(RiskAnalyzer.meaningfulChangedLines(in: commit))
        let files = Double(RiskAnalyzer.sourceFileCount(in: commit))
        let testBonus = RiskAnalyzer.testFileCount(in: commit) > 0 ? 0.5 : 0
        guard lines > 0 || files > 0 else { return 0.2 }
        return min(8, 0.35 + log2(1 + lines) / 2.4 + sqrt(files) * 0.55 + testBonus)
    }

    static func aceScore(forAverageActiveDayEffort value: Double) -> Double {
        100 * (1 - exp(-max(0, value) / 12))
    }

    private static func weekdayStreak(days: [DayActivity], calendar: Calendar) -> Int {
        var count = 0
        for day in days.reversed() {
            if !CalendarSupport.isWeekday(day.date, calendar: calendar) { continue }
            guard day.commitCount > 0 else { break }
            count += 1
        }
        return count
    }
}
