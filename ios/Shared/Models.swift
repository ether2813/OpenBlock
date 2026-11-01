import Foundation
import FamilyControls
import ManagedSettings

// MARK: - Schedules

enum BlockingMode: String, Codable, CaseIterable, Identifiable {
    case blocklist
    case allowlist

    var id: Self { self }

    var title: String {
        switch self {
        case .blocklist: return "Blocklist"
        case .allowlist: return "Allowlist"
        }
    }

    var explanation: String {
        switch self {
        case .blocklist: return "Block the apps, categories and websites you pick."
        case .allowlist: return "Allow only the apps you pick. Everything else is blocked."
        }
    }
}

enum ScheduleType: String, Codable, CaseIterable, Identifiable {
    case time
    case usageLimit

    var id: Self { self }

    var title: String {
        switch self {
        case .time: return "Time"
        case .usageLimit: return "Usage limit"
        }
    }

    var symbol: String {
        switch self {
        case .time: return "clock.fill"
        case .usageLimit: return "hourglass"
        }
    }
}

struct Schedule: Codable, Identifiable, Equatable {
    static let allDays = 127
    static let weekdays = 0b0011111
    static let weekends = 0b1100000
    /// DeviceActivity refuses monitoring windows shorter than this.
    static let minimumWindowMinutes = 15

    var id = UUID()
    var name = ""
    var enabled = true
    var mode: BlockingMode = .blocklist
    var type: ScheduleType = .time
    var usageLimitMinutes = 30
    /// Bit 0 = Monday … bit 6 = Sunday.
    var daysMask = Schedule.allDays
    var startMinutes = 9 * 60
    var endMinutes = 17 * 60
    var selection = FamilyActivitySelection()
    /// Typed domains, blocked by the system web content filter.
    var websites: [String] = []
    var createdAt = Date()
    var updatedAt = Date()

    init() {}

    var isAllDay: Bool { startMinutes == 0 && endMinutes == 1440 }
    var isOvernight: Bool { !isAllDay && startMinutes > endMinutes }

    /// Length of a TIME window in minutes, overnight windows included.
    var windowMinutes: Int {
        if isAllDay { return 1440 }
        let start = startMinutes % 1440
        let end = endMinutes % 1440
        if start == end { return 0 }
        return end > start ? end - start : 1440 - start + end
    }

    func dayEnabled(_ dayZeroBased: Int) -> Bool {
        let day = ((dayZeroBased % 7) + 7) % 7
        return daysMask & (1 << day) != 0
    }

    func isActiveDay(_ day: Int) -> Bool { enabled && dayEnabled(day) }

    /// Whether a TIME schedule is inside its window. Overnight windows belong to the day they start
    /// on, so the after-midnight part checks the previous day's bit.
    func isInWindow(day: Int, minute: Int) -> Bool {
        guard type == .time, enabled else { return false }
        if startMinutes < endMinutes {
            return dayEnabled(day) && minute >= startMinutes && minute < endMinutes
        } else if startMinutes > endMinutes {
            return (dayEnabled(day) && minute >= startMinutes) || (dayEnabled(day - 1) && minute < endMinutes)
        }
        return false
    }

    /// TIME schedules apply inside their window; limit schedules apply all day on selected days.
    func appliesNow(day: Int, minute: Int) -> Bool {
        type == .time ? isInWindow(day: day, minute: minute) : isActiveDay(day)
    }

    var hasTargets: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty ||
            !selection.webDomainTokens.isEmpty || (mode == .blocklist && !websites.isEmpty)
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? defaultName : trimmed
    }

    var defaultName: String {
        switch type {
        case .usageLimit: return "Daily usage limit"
        case .time: return isAllDay ? "All-day block" : "Focus time"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, enabled, mode, type, usageLimitMinutes, daysMask, startMinutes, endMinutes, selection, websites, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        mode = (try? c.decodeIfPresent(BlockingMode.self, forKey: .mode)) ?? .blocklist
        type = (try? c.decodeIfPresent(ScheduleType.self, forKey: .type)) ?? .time
        usageLimitMinutes = try c.decodeIfPresent(Int.self, forKey: .usageLimitMinutes) ?? 30
        daysMask = try c.decodeIfPresent(Int.self, forKey: .daysMask) ?? Schedule.allDays
        startMinutes = try c.decodeIfPresent(Int.self, forKey: .startMinutes) ?? 9 * 60
        endMinutes = try c.decodeIfPresent(Int.self, forKey: .endMinutes) ?? 17 * 60
        selection = (try? c.decodeIfPresent(FamilyActivitySelection.self, forKey: .selection)) ?? FamilyActivitySelection()
        websites = try c.decodeIfPresent([String].self, forKey: .websites) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

// MARK: - App limits

enum LimitTarget: Codable, Hashable {
    case app(ApplicationToken)
    case category(ActivityCategoryToken)
    case web(WebDomainToken)
}

struct AppLimit: Codable, Identifiable, Equatable {
    static let defaultMinutes = 30
    static let options = [0, 5, 10, 15, 30, 45, 60, 90, 120, 180, 240]

    var id = UUID()
    var target: LimitTarget
    var enabled = true
    /// 0 means "always block".
    var limitMinutes = AppLimit.defaultMinutes

    init(target: LimitTarget, limitMinutes: Int = AppLimit.defaultMinutes) {
        self.target = target
        self.limitMinutes = limitMinutes
    }

    /// Whether moving from the current limit to `next` makes the limit looser.
    func isLoosening(to next: Int) -> Bool {
        if limitMinutes == 0 { return next != 0 }
        if next == 0 { return false }
        return next > limitMinutes
    }

    static func label(for minutes: Int) -> String {
        minutes == 0 ? "Always block" : "\(TimeFormat.minutes(minutes)) a day"
    }
}

// MARK: - Strict Mode

enum StrictUnlockMethod: String, Codable, CaseIterable, Identifiable {
    case timer
    case schedules
    case cooldown
    case charger
    case pin

    var id: Self { self }

    var title: String {
        switch self {
        case .timer: return "Timer"
        case .schedules: return "Follow schedules"
        case .cooldown: return "Cooldown"
        case .charger: return "Charger"
        case .pin: return "PIN code"
        }
    }

    var explanation: String {
        switch self {
        case .timer: return "Strict Mode turns off by itself when the timer runs out."
        case .schedules: return "Strict Mode is on whenever one of your schedules is active."
        case .cooldown: return "Request an unlock, then wait out the cooldown period."
        case .charger: return "Unlock only while your iPhone is connected to power."
        case .pin: return "Unlock any time with a PIN code."
        }
    }

    var symbol: String {
        switch self {
        case .timer: return "timer"
        case .schedules: return "calendar.badge.clock"
        case .cooldown: return "hourglass.bottomhalf.filled"
        case .charger: return "bolt.fill"
        case .pin: return "key.fill"
        }
    }

    var difficulty: Difficulty {
        switch self {
        case .timer, .schedules: return .hard
        case .cooldown, .charger: return .medium
        case .pin: return .easy
        }
    }

    var usesDuration: Bool { self == .timer || self == .cooldown }

    enum Difficulty: String {
        case easy = "Easy"
        case medium = "Medium"
        case hard = "Hard"
    }
}

struct StrictState: Codable, Equatable {
    var enabled = false
    var method: StrictUnlockMethod = .timer
    var durationMinutes = 60
    var startedAt: Date?
    var endsAt: Date?
    var unlockRequestedAt: Date?

    var cooldownEndsAt: Date? {
        unlockRequestedAt.map { $0.addingTimeInterval(TimeInterval(durationMinutes * 60)) }
    }

    func isActive(now: Date, anyScheduleActive: Bool) -> Bool {
        guard enabled else { return false }
        switch method {
        case .timer: return endsAt.map { now < $0 } ?? false
        case .cooldown: return cooldownEndsAt.map { now < $0 } ?? true
        case .schedules: return anyScheduleActive
        case .charger, .pin: return true
        }
    }

    /// Timer and cooldown sessions end on their own; once they have, the session is over for good.
    func hasExpired(now: Date) -> Bool {
        guard enabled else { return false }
        switch method {
        case .timer: return endsAt.map { now >= $0 } ?? true
        case .cooldown: return cooldownEndsAt.map { now >= $0 } ?? false
        default: return false
        }
    }
}

struct StrictOptions: Codable, Equatable {
    /// No pausing, editing or deleting schedules and limits in the app.
    var lockEditing = true
    /// Apps (including OpenBlock) can't be deleted.
    var preventAppRemoval = true
    /// The App Store can't install new apps.
    var preventAppInstallation = false
    /// Date & Time must stay on "Set Automatically" so schedules can't be dodged by changing the clock.
    var requireAutomaticTime = true

    init() {}

    private enum CodingKeys: String, CodingKey { case lockEditing, preventAppRemoval, preventAppInstallation, requireAutomaticTime }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lockEditing = try c.decodeIfPresent(Bool.self, forKey: .lockEditing) ?? true
        preventAppRemoval = try c.decodeIfPresent(Bool.self, forKey: .preventAppRemoval) ?? true
        preventAppInstallation = try c.decodeIfPresent(Bool.self, forKey: .preventAppInstallation) ?? false
        requireAutomaticTime = try c.decodeIfPresent(Bool.self, forKey: .requireAutomaticTime) ?? true
    }

    var protections: [String] {
        var items: [String] = []
        if lockEditing { items.append("Pausing, editing or deleting schedules and app limits") }
        if preventAppRemoval { items.append("Deleting apps, including OpenBlock") }
        if preventAppInstallation { items.append("Installing apps from the App Store") }
        if requireAutomaticTime { items.append("Changing the date and time") }
        return items
    }
}

// MARK: - Appearance

enum AccentTheme: String, Codable, CaseIterable, Identifiable {
    case sky
    case violet
    case red

    var id: Self { self }

    var title: String {
        switch self {
        case .sky: return "Sky"
        case .violet: return "Violet"
        case .red: return "Red"
        }
    }

    var subtitle: String {
        switch self {
        case .sky: return "Clear and calm"
        case .violet: return "Focused and expressive"
        case .red: return "Bold and decisive"
        }
    }

    /// (light, dark) as 0xRRGGBB.
    var accentHex: (UInt32, UInt32) {
        switch self {
        case .sky: return (0x1686D9, 0x54B5FF)
        case .violet: return (0x7C4DDB, 0xAE8BFF)
        case .red: return (0xD94A4A, 0xFF7E7E)
        }
    }
}

enum AppearanceMode: String, Codable, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: Self { self }

    var title: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }
}

// MARK: - Whole app state

/// Everything the app and its extensions share through the App Group.
struct AppState: Codable, Equatable {
    var schedules: [Schedule] = []
    var appLimits: [AppLimit] = []
    /// Always-blocked domains, independent of schedules.
    var globalWebsites: [String] = []
    var blockAdultSites = false
    var notifyWhenBlocking = true
    var blockMessage = ""
    var accent: AccentTheme = .sky
    var appearance: AppearanceMode = .system
    var strict = StrictState()
    var strictOptions = StrictOptions()
    /// The method and duration the next Strict Mode session will use.
    var strictMethod: StrictUnlockMethod = .timer
    var strictDurationMinutes = 60
    var pinHash = ""
    var pinSalt = ""
    var hiddenFromInsights = FamilyActivitySelection()
    var hasCompletedOnboarding = false

    init() {}

    var hasPin: Bool { !pinHash.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case schedules, appLimits, globalWebsites, blockAdultSites, notifyWhenBlocking, blockMessage, accent, appearance
        case strict, strictOptions, strictMethod, strictDurationMinutes, pinHash, pinSalt, hiddenFromInsights, hasCompletedOnboarding
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schedules = (try? c.decodeIfPresent([Schedule].self, forKey: .schedules)) ?? []
        appLimits = (try? c.decodeIfPresent([AppLimit].self, forKey: .appLimits)) ?? []
        globalWebsites = try c.decodeIfPresent([String].self, forKey: .globalWebsites) ?? []
        blockAdultSites = try c.decodeIfPresent(Bool.self, forKey: .blockAdultSites) ?? false
        notifyWhenBlocking = try c.decodeIfPresent(Bool.self, forKey: .notifyWhenBlocking) ?? true
        blockMessage = try c.decodeIfPresent(String.self, forKey: .blockMessage) ?? ""
        accent = (try? c.decodeIfPresent(AccentTheme.self, forKey: .accent)) ?? .sky
        appearance = (try? c.decodeIfPresent(AppearanceMode.self, forKey: .appearance)) ?? .system
        strict = (try? c.decodeIfPresent(StrictState.self, forKey: .strict)) ?? StrictState()
        strictOptions = (try? c.decodeIfPresent(StrictOptions.self, forKey: .strictOptions)) ?? StrictOptions()
        strictMethod = (try? c.decodeIfPresent(StrictUnlockMethod.self, forKey: .strictMethod)) ?? .timer
        strictDurationMinutes = try c.decodeIfPresent(Int.self, forKey: .strictDurationMinutes) ?? 60
        pinHash = try c.decodeIfPresent(String.self, forKey: .pinHash) ?? ""
        pinSalt = try c.decodeIfPresent(String.self, forKey: .pinSalt) ?? ""
        hiddenFromInsights = (try? c.decodeIfPresent(FamilyActivitySelection.self, forKey: .hiddenFromInsights)) ?? FamilyActivitySelection()
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
    }
}

extension FamilyActivitySelection {
    var isEmptySelection: Bool {
        applicationTokens.isEmpty && categoryTokens.isEmpty && webDomainTokens.isEmpty
    }

    /// "3 apps, 1 category, 2 websites".
    var summary: String {
        var parts: [String] = []
        if !applicationTokens.isEmpty { parts.append(TimeFormat.plural(applicationTokens.count, "app")) }
        if !categoryTokens.isEmpty { parts.append(TimeFormat.plural(categoryTokens.count, "category", plural: "categories")) }
        if !webDomainTokens.isEmpty { parts.append(TimeFormat.plural(webDomainTokens.count, "website")) }
        return parts.joined(separator: ", ")
    }
}
