import Foundation

enum SharedConstants {
    static var appGroup: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupIdentifier") as? String ?? ""
    }
    static let widgetKind = "GitCalendarWidget"
}

struct CalendarConfiguration: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var name: String
    var folderPath: String
    var authorPatterns: [String]
    var timeZoneIdentifier: String
    var refreshIntervalMinutes: Int
    var includeMerges: Bool
    var includeAllRefs: Bool
    var largeChangeThreshold: Int
    var testsExpectedAfterLines: Int
    var wideChangeFileThreshold: Int

    init(
        id: UUID = UUID(),
        name: String,
        folderPath: String,
        authorPatterns: [String] = [],
        timeZoneIdentifier: String = TimeZone.current.identifier,
        refreshIntervalMinutes: Int = 15,
        includeMerges: Bool = false,
        includeAllRefs: Bool = true,
        largeChangeThreshold: Int = 600,
        testsExpectedAfterLines: Int = 80,
        wideChangeFileThreshold: Int = 20
    ) {
        self.id = id
        self.name = name
        self.folderPath = folderPath
        self.authorPatterns = authorPatterns
        self.timeZoneIdentifier = timeZoneIdentifier
        self.refreshIntervalMinutes = refreshIntervalMinutes
        self.includeMerges = includeMerges
        self.includeAllRefs = includeAllRefs
        self.largeChangeThreshold = largeChangeThreshold
        self.testsExpectedAfterLines = testsExpectedAfterLines
        self.wideChangeFileThreshold = wideChangeFileThreshold
    }
}

struct ChangedFile: Codable, Hashable, Sendable {
    var path: String
    var additions: Int
    var deletions: Int
    var isBinary: Bool

    var changedLines: Int { additions + deletions }
}

enum RiskReason: String, Codable, CaseIterable, Hashable, Sendable {
    case largeChange
    case wideChange
    case sourceWithoutTests

    var title: String {
        switch self {
        case .largeChange: "Крупное изменение"
        case .wideChange: "Широкая область изменения"
        case .sourceWithoutTests: "Код без сопутствующих тестов"
        }
    }
}

struct CommitRecord: Codable, Identifiable, Hashable, Sendable {
    var id: String { "\(repositoryPath)#\(hash)" }
    var hash: String
    var repositoryName: String
    var repositoryPath: String
    var authorName: String
    var authorEmail: String
    var authorDate: Date
    var committerDate: Date
    var subject: String
    var files: [ChangedFile]
    var riskReasons: [RiskReason]
    var riskWeight: Double

    var shortHash: String { String(hash.prefix(8)) }
    var additions: Int { files.reduce(0) { $0 + $1.additions } }
    var deletions: Int { files.reduce(0) { $0 + $1.deletions } }
    var changedLines: Int { additions + deletions }
}

struct DayActivity: Codable, Identifiable, Hashable, Sendable {
    var id: String { dayKey }
    var dayKey: String
    var date: Date
    var commitCount: Int
    var changedLines: Int
    var riskPercent: Double
    var effortUnits: Double
}

struct MetricSummary: Codable, Hashable, Sendable {
    var totalCommits: Int
    var activeDays: Int
    var activeWeekdayPercent: Double
    var commitsPerWeek: Double
    var commitsPerActiveDay: Double
    var currentWeekdayStreak: Int
    var bcePerDayProxy: Double
    var aceProxy: Double
    var aberrantBCEProxyPercent: Double
    var repositories: Int

    static let empty = MetricSummary(
        totalCommits: 0,
        activeDays: 0,
        activeWeekdayPercent: 0,
        commitsPerWeek: 0,
        commitsPerActiveDay: 0,
        currentWeekdayStreak: 0,
        bcePerDayProxy: 0,
        aceProxy: 0,
        aberrantBCEProxyPercent: 0,
        repositories: 0
    )
}

struct CalendarSnapshot: Codable, Identifiable, Hashable, Sendable {
    var id: UUID { configurationID }
    var configurationID: UUID
    var generatedAt: Date
    var repositoryPaths: [String]
    var commits: [CommitRecord]
    var days: [DayActivity]
    var summary: MetricSummary
    var warnings: [String]
}

struct WidgetCalendarSnapshot: Codable, Identifiable, Hashable, Sendable {
    var id: UUID { configurationID }
    var configurationID: UUID
    var name: String
    var timeZoneIdentifier: String
    var generatedAt: Date
    var days: [DayActivity]
    var summary: MetricSummary
}

extension CalendarSnapshot {
    func widgetSnapshot(name: String, timeZoneIdentifier: String) -> WidgetCalendarSnapshot {
        WidgetCalendarSnapshot(
            configurationID: configurationID,
            name: name,
            timeZoneIdentifier: timeZoneIdentifier,
            generatedAt: generatedAt,
            days: days,
            summary: summary
        )
    }
}
