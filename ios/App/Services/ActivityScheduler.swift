import Foundation
import DeviceActivity
import FamilyControls
import ManagedSettings

/// Keeps DeviceActivity monitoring in sync with the schedules and limits.
///
/// Monitoring windows are only wake-up calls for the monitor extension: at every start, end and
/// usage threshold it re-runs `BlockEnforcer`, which decides from the shared state what to block.
/// Activities are only restarted when their configuration changes, so usage counted so far today
/// is not thrown away by unrelated edits.
enum ActivityScheduler {
    private struct Plan {
        var schedule: DeviceActivitySchedule
        var events: [DeviceActivityEvent.Name: DeviceActivityEvent]
        var signature: String
    }

    /// Returns a message for each activity iOS refused to monitor.
    @discardableResult
    static func sync(state: AppState, now: Date = Date()) -> [String] {
        let center = DeviceActivityCenter()
        let plans = desiredPlans(state: state, now: now)
        var signatures = SharedStore.activitySignatures()
        var problems: [String] = []

        let running = Set(center.activities.map(\.rawValue))
        let obsolete = running.subtracting(plans.keys)
        if !obsolete.isEmpty {
            center.stopMonitoring(obsolete.map { DeviceActivityName($0) })
            obsolete.forEach { signatures[$0] = nil }
        }

        for (name, plan) in plans {
            if running.contains(name), signatures[name] == plan.signature { continue }
            let activity = DeviceActivityName(name)
            center.stopMonitoring([activity])
            do {
                try center.startMonitoring(activity, during: plan.schedule, events: plan.events)
                signatures[name] = plan.signature
            } catch {
                signatures[name] = nil
                // A Strict Mode timer iOS won't monitor still ends when OpenBlock is next opened.
                if name != ActivityNames.strict {
                    problems.append("\(name): \(error.localizedDescription)")
                }
            }
        }
        SharedStore.setActivitySignatures(signatures)
        return problems
    }

    static func stopAll() {
        DeviceActivityCenter().stopMonitoring()
        SharedStore.setActivitySignatures([:])
    }

    // MARK: Plans

    private static func desiredPlans(state: AppState, now: Date) -> [String: Plan] {
        var plans: [String: Plan] = [:]
        let wholeDay = (start: DateComponents(hour: 0, minute: 0), end: DateComponents(hour: 23, minute: 59))

        for schedule in state.schedules where schedule.enabled && schedule.daysMask & Schedule.allDays != 0 {
            switch schedule.type {
            case .time:
                guard schedule.windowMinutes >= Schedule.minimumWindowMinutes else { continue }
                let id = schedule.id.uuidString
                let start = schedule.startMinutes % 1440
                let lastMinute = 1439
                let end = min(schedule.endMinutes, lastMinute)
                if !schedule.isOvernight, end - start >= Schedule.minimumWindowMinutes {
                    // The common case: one interval whose start and end are the window's.
                    plans[ActivityNames.timePrefix + id] = Plan(
                        schedule: DeviceActivitySchedule(intervalStart: components(start), intervalEnd: components(end), repeats: true),
                        events: [:],
                        signature: "time|\(start)|\(end)"
                    )
                } else {
                    // Overnight windows (and ones squeezed against midnight) never cross midnight
                    // inside one interval: a short interval wakes the monitor at each boundary.
                    plans[ActivityNames.timePrefix + id] = wakeUp(at: start)
                    plans[ActivityNames.timeEndPrefix + id] = wakeUp(at: schedule.endMinutes % 1440)
                }
            case .usageLimit:
                guard schedule.mode == .blocklist, schedule.usageLimitMinutes > 0,
                      !schedule.selection.isEmptySelection else { continue }
                let eventName = ActivityNames.scheduleEvent(schedule.id)
                plans[ActivityNames.usagePrefix + schedule.id.uuidString] = Plan(
                    schedule: DeviceActivitySchedule(intervalStart: wholeDay.start, intervalEnd: wholeDay.end, repeats: true),
                    events: [DeviceActivityEvent.Name(eventName): event(
                        apps: schedule.selection.applicationTokens,
                        categories: schedule.selection.categoryTokens,
                        webDomains: schedule.selection.webDomainTokens,
                        minutes: schedule.usageLimitMinutes
                    )],
                    signature: "usage|\(schedule.usageLimitMinutes)|\(fingerprint(schedule.selection))"
                )
            }
        }

        var limitEvents: [DeviceActivityEvent.Name: DeviceActivityEvent] = [:]
        var limitSignature: [String] = []
        for limit in state.appLimits where limit.enabled && limit.limitMinutes > 0 {
            var apps = Set<ApplicationToken>()
            var categories = Set<ActivityCategoryToken>()
            var webDomains = Set<WebDomainToken>()
            switch limit.target {
            case .app(let token): apps.insert(token)
            case .category(let token): categories.insert(token)
            case .web(let token): webDomains.insert(token)
            }
            let name = ActivityNames.limitEvent(limit.id)
            limitEvents[DeviceActivityEvent.Name(name)] = event(apps: apps, categories: categories, webDomains: webDomains, minutes: limit.limitMinutes)
            limitSignature.append("\(name)=\(limit.limitMinutes)")
        }
        if !limitEvents.isEmpty {
            plans[ActivityNames.limits] = Plan(
                schedule: DeviceActivitySchedule(intervalStart: wholeDay.start, intervalEnd: wholeDay.end, repeats: true),
                events: limitEvents,
                signature: "limits|" + limitSignature.sorted().joined(separator: ",")
            )
        }

        // Wake the monitor when a timed Strict Mode session ends, so its protections lift on time
        // even if OpenBlock isn't opened.
        let strict = state.strict
        let strictEnd: Date? = {
            guard strict.enabled else { return nil }
            switch strict.method {
            case .timer: return strict.endsAt
            case .cooldown: return strict.cooldownEndsAt
            default: return nil
            }
        }()
        let strictStart = (strict.method == .cooldown ? strict.unlockRequestedAt : strict.startedAt) ?? now
        if let strictEnd, strictEnd > now,
           strictEnd.timeIntervalSince(strictStart) >= TimeInterval(Schedule.minimumWindowMinutes * 60) {
            let calendar = Calendar.current
            let fields: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
            plans[ActivityNames.strict] = Plan(
                schedule: DeviceActivitySchedule(
                    intervalStart: calendar.dateComponents(fields, from: strictStart),
                    intervalEnd: calendar.dateComponents(fields, from: strictEnd),
                    repeats: false
                ),
                events: [:],
                signature: "strict|\(Int(strictEnd.timeIntervalSince1970))"
            )
        }
        return plans
    }

    /// A short daily interval that starts (or, close to midnight, ends) at `minute`, purely to
    /// wake the monitor extension at that time of day.
    private static func wakeUp(at minute: Int) -> Plan {
        let length = Schedule.minimumWindowMinutes + 5
        let range = minute + length <= 1439 ? (minute, minute + length) : (minute - length, minute)
        return Plan(
            schedule: DeviceActivitySchedule(intervalStart: components(range.0), intervalEnd: components(range.1), repeats: true),
            events: [:],
            signature: "wake|\(range.0)|\(range.1)"
        )
    }

    private static func components(_ minuteOfDay: Int) -> DateComponents {
        DateComponents(hour: (minuteOfDay % 1440) / 60, minute: minuteOfDay % 60)
    }

    private static func event(
        apps: Set<ApplicationToken>,
        categories: Set<ActivityCategoryToken>,
        webDomains: Set<WebDomainToken>,
        minutes: Int
    ) -> DeviceActivityEvent {
        let threshold = DateComponents(hour: minutes / 60, minute: minutes % 60)
        if #available(iOS 17.4, *) {
            // Count the whole day, so re-scheduling after an edit doesn't reset today's usage.
            return DeviceActivityEvent(
                applications: apps,
                categories: categories,
                webDomains: webDomains,
                threshold: threshold,
                includesPastActivity: true
            )
        }
        return DeviceActivityEvent(applications: apps, categories: categories, webDomains: webDomains, threshold: threshold)
    }

    private static func fingerprint(_ selection: FamilyActivitySelection) -> String {
        guard let data = try? JSONEncoder().encode(selection) else { return "" }
        return SharedStore.sha256(data)
    }
}
