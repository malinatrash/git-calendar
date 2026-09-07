import Foundation

enum SharedStore {
    private static let configurationsKey = "calendarConfigurations.v1"
    private static let widgetSnapshotsKey = "widgetSnapshots.v1"

    private static var sharedDefaults: UserDefaults {
        UserDefaults(suiteName: SharedConstants.appGroup) ?? .standard
    }

    private static var applicationSupportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("GitCalendar", isDirectory: true)
    }

    private static var snapshotsURL: URL {
        applicationSupportDirectory.appendingPathComponent("snapshots.json")
    }

    static func loadConfigurations() -> [CalendarConfiguration] {
        decode([CalendarConfiguration].self, from: sharedDefaults.data(forKey: configurationsKey)) ?? []
    }

    static func saveConfigurations(_ configurations: [CalendarConfiguration]) throws {
        sharedDefaults.set(try encoder.encode(configurations), forKey: configurationsKey)
    }

    static func loadWidgetSnapshots() -> [WidgetCalendarSnapshot] {
        decode([WidgetCalendarSnapshot].self, from: sharedDefaults.data(forKey: widgetSnapshotsKey)) ?? []
    }

    static func saveWidgetSnapshots(_ snapshots: [WidgetCalendarSnapshot]) throws {
        sharedDefaults.set(try encoder.encode(snapshots), forKey: widgetSnapshotsKey)
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
