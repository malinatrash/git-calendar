import Foundation

enum CalendarSupport {
    static func calendar(timeZoneIdentifier: String) -> Calendar {
        var calendar = Calendar(identifier: .iso8601)
        calendar.locale = Locale(identifier: "ru_RU")
        calendar.firstWeekday = 2
        calendar.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        return calendar
    }

    static func dayKey(for date: Date, timeZoneIdentifier: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func date(fromDayKey key: String, timeZoneIdentifier: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = calendar(timeZoneIdentifier: timeZoneIdentifier)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    static func isWeekday(_ date: Date, calendar: Calendar) -> Bool {
        !calendar.isDateInWeekend(date)
    }
}
