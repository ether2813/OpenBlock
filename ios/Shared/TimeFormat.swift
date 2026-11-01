import Foundation

enum TimeFormat {
    /// "1h 5m", "4m 10s", "12s".
    static func compact(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m \(seconds)s" }
        return "\(seconds)s"
    }

    /// Screen-time style duration without seconds: "2h 5m", "45m", "0m".
    static func duration(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval)) / 60
        let hours = total / 60
        let minutes = total % 60
        if hours > 0 { return minutes == 0 ? "\(hours)h" : "\(hours)h \(minutes)m" }
        return "\(minutes)m"
    }

    /// "45m", "2h", "1h 30m", "3d".
    static func minutes(_ minutes: Int) -> String {
        let value = max(0, minutes)
        let days = value / 1440
        let hours = (value % 1440) / 60
        let mins = value % 60
        if days > 0 { return hours == 0 && mins == 0 ? "\(days)d" : "\(days)d \(hours)h" }
        if hours > 0 { return mins == 0 ? "\(hours)h" : "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    /// Clock label for a minute of day in the user's 12/24-hour preference. 1440 is midnight.
    static func clock(_ minuteOfDay: Int) -> String {
        var components = DateComponents()
        components.hour = (minuteOfDay % 1440) / 60
        components.minute = minuteOfDay % 60
        let date = Calendar.current.date(from: components) ?? Date()
        return clockFormatter.string(from: date)
    }

    /// Clock label for a moment, with the weekday when it isn't today.
    static func clock(at date: Date) -> String {
        let calendar = Calendar.current
        let minutes = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if calendar.isDateInToday(date) { return clock(minutes) }
        return "\(weekdayFormatter.string(from: date)) \(clock(minutes))"
    }

    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    static let shortDayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    static let narrowDayNames = ["M", "T", "W", "T", "F", "S", "S"]

    static func days(_ mask: Int) -> String {
        switch mask & 127 {
        case 127: return "Every day"
        case Schedule.weekdays: return "Weekdays"
        case Schedule.weekends: return "Weekends"
        case 0: return "No days"
        default:
            return shortDayNames.enumerated()
                .filter { mask & (1 << $0.offset) != 0 }
                .map(\.element)
                .joined(separator: ", ")
        }
    }

    static func plural(_ count: Int, _ noun: String, plural: String? = nil) -> String {
        "\(count) \(count == 1 ? noun : (plural ?? noun + "s"))"
    }
}

/// A moment split into the pieces schedules care about. Day 0 is Monday.
struct Clock {
    let date: Date
    let day: Int
    let minute: Int
    let dayKey: String

    init(date: Date = Date(), calendar: Calendar = .current) {
        self.date = date
        let parts = calendar.dateComponents([.year, .month, .day, .weekday, .hour, .minute], from: date)
        // Calendar weekday: 1 = Sunday … 7 = Saturday.
        day = ((parts.weekday ?? 2) + 5) % 7
        minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        dayKey = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

enum WebPatterns {
    /// Lowercases and strips scheme, "www.", paths and trailing slashes, so "https://www.X.com/a" == "x.com".
    static func normalize(_ value: String) -> String {
        var pattern = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        for prefix in ["http://", "https://", "www."] where pattern.hasPrefix(prefix) {
            pattern.removeFirst(prefix.count)
        }
        if let slash = pattern.firstIndex(of: "/") { pattern = String(pattern[..<slash]) }
        return pattern.trimmingCharacters(in: CharacterSet(charactersIn: "/ ."))
    }

    /// A plausible domain: letters, digits, dots and dashes with at least one dot.
    static func isDomain(_ value: String) -> Bool {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-")
        return value.contains(".") && !value.hasPrefix(".") && !value.hasSuffix(".") &&
            value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }
}
