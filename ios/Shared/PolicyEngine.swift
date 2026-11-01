import Foundation
import FamilyControls
import ManagedSettings

/// Pure decisions about what should be blocked right now. No side effects.
enum PolicyEngine {
    static func isScheduleBlocking(_ schedule: Schedule, clock: Clock, hits: [String: String]) -> Bool {
        guard schedule.enabled else { return false }
        switch schedule.type {
        case .time:
            return schedule.isInWindow(day: clock.day, minute: clock.minute)
        case .usageLimit:
            return schedule.isActiveDay(clock.day) && hits[ActivityNames.scheduleEvent(schedule.id)] == clock.dayKey
        }
    }

    static func isLimitBlocking(_ limit: AppLimit, clock: Clock, hits: [String: String]) -> Bool {
        guard limit.enabled else { return false }
        return limit.limitMinutes == 0 || hits[ActivityNames.limitEvent(limit.id)] == clock.dayKey
    }

    static func anyScheduleApplies(_ state: AppState, clock: Clock) -> Bool {
        state.schedules.contains { $0.appliesNow(day: clock.day, minute: clock.minute) }
    }

    static func isStrictActive(_ state: AppState, clock: Clock) -> Bool {
        state.strict.isActive(now: clock.date, anyScheduleActive: anyScheduleApplies(state, clock: clock))
    }

    /// Why something is blocked, for the shield and the app.
    struct Reason {
        var title: String
        var detail: String
    }

    /// The first active rule that covers `matches`, described for the block screen.
    static func reason(
        state: AppState,
        clock: Clock,
        hits: [String: String],
        matchesSelection: (FamilyActivitySelection) -> Bool,
        matchesLimit: (LimitTarget) -> Bool
    ) -> Reason? {
        for schedule in state.schedules where isScheduleBlocking(schedule, clock: clock, hits: hits) {
            let covered: Bool
            switch schedule.mode {
            case .blocklist: covered = matchesSelection(schedule.selection)
            case .allowlist: covered = !matchesSelection(schedule.selection)
            }
            guard covered else { continue }
            switch schedule.type {
            case .time:
                let until = schedule.isAllDay ? "all day" : "until \(TimeFormat.clock(schedule.endMinutes))"
                let prefix = schedule.mode == .allowlist ? "Only allowed apps" : schedule.displayName
                return Reason(title: "Blocked", detail: "\(prefix) · \(until)")
            case .usageLimit:
                return Reason(
                    title: "Time's up",
                    detail: "\(schedule.displayName) · \(TimeFormat.minutes(schedule.usageLimitMinutes)) a day limit reached"
                )
            }
        }
        for limit in state.appLimits where isLimitBlocking(limit, clock: clock, hits: hits) && matchesLimit(limit.target) {
            if limit.limitMinutes == 0 { return Reason(title: "Blocked", detail: "Always blocked by your app limits") }
            return Reason(title: "Time's up", detail: "Daily limit of \(TimeFormat.minutes(limit.limitMinutes)) reached")
        }
        return nil
    }
}
