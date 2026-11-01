import DeviceActivity
import Foundation
import ManagedSettings

/// Runs in the background whenever a monitored window starts or ends, or a usage threshold is
/// reached, and re-applies the blocks from the shared state.
final class DeviceActivityMonitorExtension: DeviceActivityMonitor {
    /// Callbacks can arrive a moment before the boundary minute, so window checks look slightly ahead.
    private static let lookAhead: TimeInterval = 60

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        let state = SharedStore.loadState()
        let clock = Clock(date: Date().addingTimeInterval(Self.lookAhead))
        BlockEnforcer.apply(state: state, clock: clock)

        guard state.notifyWhenBlocking, activity.rawValue.hasPrefix(ActivityNames.timePrefix) else { return }
        let id = String(activity.rawValue.dropFirst(ActivityNames.timePrefix.count))
        guard let schedule = state.schedules.first(where: { $0.id.uuidString == id }),
              PolicyEngine.isScheduleBlocking(schedule, clock: clock, hits: [:]) else { return }
        let until = schedule.isAllDay ? "all day" : "until \(TimeFormat.clock(schedule.endMinutes))"
        Notifier.post(
            id: "start.\(id).\(clock.dayKey)",
            title: "\(schedule.displayName) is on",
            body: "\(ScheduleSummary.targets(schedule)) blocked \(until)."
        )
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        let state = SharedStore.loadState()
        BlockEnforcer.apply(state: state, clock: Clock(date: Date().addingTimeInterval(Self.lookAhead)))
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        let clock = Clock()
        SharedStore.recordLimitHit(event.rawValue, dayKey: clock.dayKey)
        let state = SharedStore.loadState()
        BlockEnforcer.apply(state: state, clock: clock)

        guard state.notifyWhenBlocking else { return }
        if let schedule = state.schedules.first(where: { ActivityNames.scheduleEvent($0.id) == event.rawValue }),
           schedule.isActiveDay(clock.day) {
            Notifier.post(
                id: "limit.\(event.rawValue).\(clock.dayKey)",
                title: "Time's up",
                body: "\(schedule.displayName): \(TimeFormat.minutes(schedule.usageLimitMinutes)) used today."
            )
        } else if let limit = state.appLimits.first(where: { ActivityNames.limitEvent($0.id) == event.rawValue }) {
            Notifier.post(
                id: "limit.\(event.rawValue).\(clock.dayKey)",
                title: "Time's up",
                body: "You've reached today's \(TimeFormat.minutes(limit.limitMinutes)) limit."
            )
        }
    }
}

private enum ScheduleSummary {
    static func targets(_ schedule: Schedule) -> String {
        if schedule.mode == .allowlist { return "Everything except your allowed apps is" }
        let count = schedule.selection.applicationTokens.count + schedule.selection.categoryTokens.count +
            schedule.selection.webDomainTokens.count + schedule.websites.count
        return count == 1 ? "1 item is" : "\(count) items are"
    }
}
