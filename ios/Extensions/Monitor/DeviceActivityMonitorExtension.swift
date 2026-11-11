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
        refresh(after: activity)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        refresh(after: activity)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        let clock = Clock()
        // iOS reports a threshold again when monitoring restarts after an edit.
        let alreadyKnown = SharedStore.limitHits()[event.rawValue] == clock.dayKey
        SharedStore.recordLimitHit(event.rawValue, dayKey: clock.dayKey)
        let state = SharedStore.loadState()
        BlockEnforcer.apply(state: state, clock: clock)

        guard state.notifyWhenBlocking, !alreadyKnown,
              SharedStore.markNotified(event.rawValue, dayKey: clock.dayKey) else { return }
        if let schedule = state.schedules.first(where: { ActivityNames.scheduleEvent($0.id) == event.rawValue }) {
            guard schedule.isActiveDay(clock.day) else { return }
            Notifier.post(
                id: event.rawValue,
                title: "Time's up",
                body: "\(schedule.displayName): \(TimeFormat.minutes(schedule.usageLimitMinutes)) used today."
            )
        } else if let limit = state.appLimits.first(where: { ActivityNames.limitEvent($0.id) == event.rawValue }), limit.enabled {
            Notifier.post(
                id: event.rawValue,
                title: "Time's up",
                body: "You've reached today's \(TimeFormat.minutes(limit.limitMinutes)) limit."
            )
        }
    }

    /// Every interval boundary is just a wake-up call: what to block is decided from the shared state.
    private func refresh(after activity: DeviceActivityName) {
        let state = SharedStore.loadState()
        let clock = Clock(date: Date().addingTimeInterval(Self.lookAhead))
        BlockEnforcer.apply(state: state, clock: clock)
        notifyIfScheduleJustStarted(activity, state: state, clock: clock)
    }

    private func notifyIfScheduleJustStarted(_ activity: DeviceActivityName, state: AppState, clock: Clock) {
        guard state.notifyWhenBlocking, activity.rawValue.hasPrefix(ActivityNames.timePrefix) else { return }
        let id = String(activity.rawValue.dropFirst(ActivityNames.timePrefix.count))
        guard let schedule = state.schedules.first(where: { $0.id.uuidString == id }),
              PolicyEngine.isScheduleBlocking(schedule, clock: clock, hits: [:]) else { return }
        // Monitoring that begins mid-window (after an edit) also reports a start; only the real
        // start of the window is worth a notification.
        let sinceStart = (clock.minute - schedule.startMinutes % 1440 + 1440) % 1440
        guard sinceStart <= 2, SharedStore.markNotified("start.\(id)", dayKey: clock.dayKey) else { return }
        let until = schedule.isAllDay ? "all day" : "until \(TimeFormat.clock(schedule.endMinutes))"
        Notifier.post(
            id: "start.\(id)",
            title: "\(schedule.displayName) is on",
            body: "\(ScheduleSummary.targets(schedule)) blocked \(until)."
        )
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
