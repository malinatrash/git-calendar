import Foundation

enum MetricEngine {
    static func makeSnapshot(
        configuration: CalendarConfiguration,
        repositoryPaths: [String],
        commits: [CommitRecord],
        warnings: [String] = [],
        qualityPolicy: QualityAnalysisPolicy = .standard,
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
            let changedLines = dayCommits.reduce(0) { $0 + SourceClassifier.meaningfulChangedLines(in: $1) }
            let analyzedCommits = dayCommits.filter { ($0.quality?.analyzedSourceFiles ?? 0) > 0 }
            let analyzedEffort = analyzedCommits.reduce(0) { $0 + effortUnits(for: $1) }
            let aberrantEffort = analyzedCommits.reduce(0.0) {
                $0 + effortUnits(for: $1) * $1.riskWeight
            }
            let actualEffort = dayCommits.reduce(0) { $0 + effortUnits(for: $1) }
            let dailyEffort = min(5, actualEffort)
            days.append(DayActivity(
                dayKey: key,
                date: date,
                commitCount: dayCommits.count,
                changedLines: changedLines,
                riskPercent: analyzedEffort == 0 ? 0 : aberrantEffort / analyzedEffort * 100,
                effortUnits: dailyEffort,
                analyzedEffortUnits: analyzedEffort,
                actualEffortUnits: actualEffort
            ))
            date = calendar.date(byAdding: .day, value: 1, to: date) ?? today.addingTimeInterval(86_400)
        }

        let workdays = days.filter { CalendarSupport.isWeekday($0.date, calendar: calendar) }
        let activeWorkdays = workdays.filter { $0.commitCount > 0 }
        let codingWorkdays = workdays.filter { ($0.actualEffortUnits ?? 0) > 0 }
        let activeDays = days.filter { $0.commitCount > 0 }.count
        let weeks = max(Double(days.count) / 7.0, 1)
        let actualEffortByDay = grouped.values.map { dayCommits in
            dayCommits.reduce(0) { $0 + effortUnits(for: $1) }
        }.filter { $0 > 0 }
        let totalEffort = codingWorkdays.reduce(0) { $0 + $1.effortUnits }
        let totalActualEffort = actualEffortByDay.reduce(0, +)
        let averageActiveDayEffort = actualEffortByDay.isEmpty ? 0 : totalActualEffort / Double(actualEffortByDay.count)
        let analysisCutoff = now.addingTimeInterval(
            -Double(qualityPolicy.lookbackDays) * 86_400
        )
        let sourceCommits = commits.filter {
            $0.authorDate >= analysisCutoff && SourceClassifier.sourceFileCount(in: $0) > 0
        }
        let analyzedCommits = sourceCommits.filter { ($0.quality?.analyzedSourceFiles ?? 0) > 0 }
        let analyzedEffort = analyzedCommits.reduce(0) { $0 + effortUnits(for: $1) }
        let aberrantEffort = analyzedCommits.reduce(0.0) {
            $0 + effortUnits(for: $1) * $1.riskWeight
        }

        let summary = MetricSummary(
            totalCommits: commits.count,
            activeDays: activeDays,
            activeWeekdayPercent: workdays.isEmpty ? 0 : Double(activeWorkdays.count) / Double(workdays.count) * 100,
            commitsPerWeek: Double(commits.count) / weeks,
            commitsPerActiveDay: activeDays == 0 ? 0 : Double(commits.count) / Double(activeDays),
            currentWeekdayStreak: weekdayStreak(days: days, calendar: calendar),
            bcePerDayProxy: codingWorkdays.isEmpty ? 0 : totalEffort / Double(codingWorkdays.count),
            aceProxy: averageActiveDayEffort,
            aberrantBCEProxyPercent: analyzedEffort == 0 ? 0 : aberrantEffort / analyzedEffort * 100,
            repositories: repositoryPaths.count,
            averageCommitIntervalDays: averageCommitIntervalDays(
                commits: commits.filter { $0.authorDate >= now.addingTimeInterval(-90 * 86_400) },
                calendar: calendar
            ),
            analyzedCommitPercent: sourceCommits.isEmpty ? nil : Double(analyzedCommits.count) / Double(sourceCommits.count) * 100
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
        let sourceFiles = SourceClassifier.sourceFiles(in: commit)
        let lines = Double(sourceFiles.reduce(0) { $0 + $1.changedLines })
        let files = Double(sourceFiles.count)
        guard lines > 0 || files > 0 else { return 0 }
        let changes = commit.quality?.fileChanges ?? []
        let complexityDelta = changes.reduce(0) {
            $0 + abs($1.after.cyclomaticComplexity - $1.before.cyclomaticComplexity)
        }
        let dependencyDelta = changes.reduce(0) {
            $0 + abs($1.after.dependencyCount - $1.before.dependencyCount)
        }
        return min(
            12,
            0.30
                + log2(1 + lines) / 2.5
                + sqrt(files) * 0.45
                + log2(1 + Double(complexityDelta)) / 4
                + log2(1 + Double(dependencyDelta)) / 5
        )
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

    static func averageCommitIntervalDays(commits: [CommitRecord], calendar: Calendar) -> Double? {
        averageDayInterval(
            dates: commits.map(\.authorDate),
            calendar: calendar
        )
    }

    static func averageDayInterval(dates: [Date], calendar: Calendar) -> Double? {
        let activeDays = Set(dates.map { calendar.startOfDay(for: $0) }).sorted()
        guard activeDays.count > 1 else { return nil }
        let totalDays = zip(activeDays, activeDays.dropFirst()).reduce(0) { result, pair in
            result + (calendar.dateComponents([.day], from: pair.0, to: pair.1).day ?? 0)
        }
        return Double(totalDays) / Double(activeDays.count - 1)
    }
}
