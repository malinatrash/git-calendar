import Foundation

enum SharedStoreError: LocalizedError {
    case appGroupUnavailable

    var errorDescription: String? {
        switch self {
        case .appGroupUnavailable:
            "Общий контейнер виджета недоступен. Запустите корректно подписанную сборку Git Calendar."
        }
    }
}

enum SharedStore {
    private static let configurationsFileName = "calendar-configurations-v2.json"
    private static let widgetSnapshotsFileName = "widget-snapshots-v2.json"

    static var isAppGroupAvailable: Bool {
        sharedContainerDirectory != nil
    }

    private static var sharedContainerDirectory: URL? {
        guard !SharedConstants.appGroup.isEmpty else { return nil }
        return FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedConstants.appGroup
        )?.appendingPathComponent("Library/Application Support/GitCalendar", isDirectory: true)
    }

    private static var configurationsURL: URL? {
        sharedContainerDirectory?.appendingPathComponent(configurationsFileName)
    }

    private static var widgetSnapshotsURL: URL? {
        sharedContainerDirectory?.appendingPathComponent(widgetSnapshotsFileName)
    }

    private static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("GitCalendar", isDirectory: true)
    }

    private static var snapshotsURL: URL {
        applicationSupportDirectory.appendingPathComponent("snapshots-v2.json")
    }

    static func loadConfigurations() -> [CalendarConfiguration] {
        guard let url = configurationsURL, let data = try? Data(contentsOf: url) else { return [] }
        return decode([CalendarConfiguration].self, from: data) ?? []
    }

    static func saveConfigurations(_ configurations: [CalendarConfiguration]) throws {
        guard let url = configurationsURL, let directory = sharedContainerDirectory else {
            throw SharedStoreError.appGroupUnavailable
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(configurations).write(to: url, options: .atomic)
    }

    static func loadWidgetSnapshots() -> [WidgetCalendarSnapshot] {
        guard let url = widgetSnapshotsURL, let data = try? Data(contentsOf: url) else { return [] }
        return decode([WidgetCalendarSnapshot].self, from: data) ?? []
    }

    static func saveWidgetSnapshots(_ snapshots: [WidgetCalendarSnapshot]) throws {
        guard let url = widgetSnapshotsURL, let directory = sharedContainerDirectory else {
            throw SharedStoreError.appGroupUnavailable
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try encoder.encode(snapshots).write(to: url, options: .atomic)
    }

    static func loadSnapshots() -> [CalendarSnapshot] {
        guard let data = try? Data(contentsOf: snapshotsURL) else { return [] }
        return decode([CalendarSnapshot].self, from: data) ?? []
    }

    static func saveSnapshots(_ snapshots: [CalendarSnapshot]) throws {
        try FileManager.default.createDirectory(
            at: applicationSupportDirectory,
            withIntermediateDirectories: true
        )
        try encoder.encode(snapshots).write(to: snapshotsURL, options: .atomic)
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data?) -> T? {
        guard let data else { return nil }
        return try? decoder.decode(type, from: data)
    }
}
