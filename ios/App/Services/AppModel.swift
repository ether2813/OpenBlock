import Combine
import FamilyControls
import Foundation
import SwiftUI
import UIKit
import UserNotifications

struct Banner: Identifiable, Equatable {
    enum Style { case info, success, warning }

    let id = UUID()
    var text: String
    var style: Style = .info
}

enum MainTab: Hashable {
    case blocking, strict, insights, more
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: AppState
    @Published private(set) var authorization: AuthorizationStatus
    @Published private(set) var notificationStatus: UNAuthorizationStatus = .notDetermined
    @Published private(set) var isCharging = false
    @Published private(set) var now = Date()
    @Published var banner: Banner?
    @Published var selectedTab: MainTab = .blocking

    private var cancellables = Set<AnyCancellable>()
    private var lastEnforcedSignature = ""

    init() {
        state = SharedStore.loadState()
        authorization = AuthorizationCenter.shared.authorizationStatus

        AuthorizationCenter.shared.$authorizationStatus
            .receive(on: RunLoop.main)
            .sink { [weak self] status in
                guard let self else { return }
                let changed = self.authorization != status
                self.authorization = status
                if changed, status == .approved { self.enforce(force: true) }
            }
            .store(in: &cancellables)

        UIDevice.current.isBatteryMonitoringEnabled = true
        updateCharging()
        NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.updateCharging() }
            .store(in: &cancellables)

        Timer.publish(every: 5, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.tick(date) }
            .store(in: &cancellables)
    }

    // MARK: Derived state

    var isAuthorized: Bool { authorization == .approved }
    var clock: Clock { Clock(date: now) }
    var isStrictActive: Bool { PolicyEngine.isStrictActive(state, clock: clock) }
    var isEditingLocked: Bool { isStrictActive && state.strictOptions.lockEditing }
    var limitHits: [String: String] { SharedStore.limitHits() }

    func isBlocking(_ schedule: Schedule) -> Bool {
        PolicyEngine.isScheduleBlocking(schedule, clock: clock, hits: limitHits)
    }

    // MARK: Lifecycle

    func appBecameActive() {
        state = SharedStore.loadState()
        authorization = AuthorizationCenter.shared.authorizationStatus
        now = Date()
        endExpiredStrictSession()
        if isAuthorized {
            // Cheap when nothing changed, and restores monitoring iOS may have dropped.
            ActivityScheduler.sync(state: state, now: now)
        }
        enforce(force: true)
        refreshNotificationStatus()
    }

    private func tick(_ date: Date) {
        // `now` drives what the screens show, so only publish it when the minute changes;
        // publishing every tick would redraw the whole app (and reload Insights) every few seconds.
        if Int(date.timeIntervalSince1970) / 60 != Int(now.timeIntervalSince1970) / 60 {
            now = date
        }
        endExpiredStrictSession()
        enforce(force: false)
    }

    private func updateCharging() {
        let batteryState = UIDevice.current.batteryState
        isCharging = batteryState == .charging || batteryState == .full
    }

    private func endExpiredStrictSession() {
        let date = Date()
        guard state.strict.hasExpired(now: date) else { return }
        now = date
        state.strict = StrictState()
        persist(sync: true)
        banner = Banner(text: "Strict Mode has ended", style: .success)
    }

    /// Re-applies restrictions. Unforced calls only do work when what should be blocked changed.
    private func enforce(force: Bool) {
        guard isAuthorized else { return }
        let clock = Clock()
        let hits = limitHits
        let active = state.schedules.filter { PolicyEngine.isScheduleBlocking($0, clock: clock, hits: hits) }.map(\.id.uuidString)
        let signature = active.sorted().joined(separator: ",") + "|\(PolicyEngine.isStrictActive(state, clock: clock))|\(clock.dayKey)"
        guard force || signature != lastEnforcedSignature else { return }
        lastEnforcedSignature = signature
        BlockEnforcer.apply(state: state, clock: clock, hits: hits)
    }

    private func persist(sync: Bool) {
        state.schedules.sort { $0.createdAt < $1.createdAt }
        SharedStore.saveState(state)
        guard isAuthorized else { return }
        if sync {
            let problems = ActivityScheduler.sync(state: state, now: now)
            if !problems.isEmpty {
                banner = Banner(text: "iOS couldn't schedule every block. Check the times, or use fewer schedules.", style: .warning)
            }
        }
        enforce(force: true)
    }

    private func update(sync: Bool = true, _ change: (inout AppState) -> Void) {
        change(&state)
        persist(sync: sync)
    }

    private func refuseWhileLocked(_ message: String) -> Bool {
        guard isEditingLocked else { return false }
        banner = Banner(text: message, style: .warning)
        return true
    }

    // MARK: Permissions

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            authorization = AuthorizationCenter.shared.authorizationStatus
            if isAuthorized {
                persist(sync: true)
                banner = Banner(text: "Screen Time access is on", style: .success)
            }
        } catch {
            authorization = AuthorizationCenter.shared.authorizationStatus
            // Matched by case, not ==: FamilyControlsError only gained Equatable in iOS 16.4.
            if let familyError = error as? FamilyControlsError, case .authorizationCanceled = familyError {
                banner = Banner(text: "Screen Time access wasn't granted", style: .warning)
            } else {
                // Typical for a build signed without the Family Controls entitlement.
                banner = Banner(text: "Screen Time access couldn't be turned on. This build may not be signed for Screen Time.", style: .warning)
            }
        }
    }

    func refreshNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in self.notificationStatus = status }
        }
    }

    func requestNotifications() async {
        // Once denied, iOS never shows the prompt again; only Settings can turn them back on.
        let wasDenied = notificationStatus == .denied
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        refreshNotificationStatus()
        if wasDenied, let url = URL(string: UIApplication.openSettingsURLString) {
            await UIApplication.shared.open(url)
        }
    }

    func completeOnboarding() {
        update(sync: false) { $0.hasCompletedOnboarding = true }
    }

    // MARK: Schedules

    func saveSchedule(_ schedule: Schedule) {
        var schedule = schedule
        schedule.updatedAt = Date()
        let previous = state.schedules.first { $0.id == schedule.id }
        update { state in
            if let index = state.schedules.firstIndex(where: { $0.id == schedule.id }) {
                state.schedules[index] = schedule
            } else {
                state.schedules.append(schedule)
            }
        }
        // A changed usage limit starts from a clean slate; renaming or changing days must not
        // lift a limit that was already reached today.
        let limitChanged = previous.map {
            $0.type != schedule.type || $0.usageLimitMinutes != schedule.usageLimitMinutes || $0.selection != schedule.selection
        } ?? true
        if limitChanged {
            SharedStore.clearLimitHit(ActivityNames.scheduleEvent(schedule.id))
            enforce(force: true)
        }
        banner = Banner(text: "Schedule saved", style: .success)
        if state.notifyWhenBlocking, notificationStatus == .notDetermined {
            Task { await requestNotifications() }
        }
    }

    func canEditSchedule() -> Bool {
        !refuseWhileLocked("Strict Mode is on — schedules can't be changed until it ends")
    }

    func setScheduleEnabled(_ id: UUID, _ enabled: Bool) {
        if !enabled, refuseWhileLocked("Strict Mode is on — schedules can't be paused until it ends") { return }
        update { state in
            guard let index = state.schedules.firstIndex(where: { $0.id == id }) else { return }
            state.schedules[index].enabled = enabled
            state.schedules[index].updatedAt = Date()
        }
    }

    func duplicateSchedule(_ id: UUID) {
        guard var copy = state.schedules.first(where: { $0.id == id }) else { return }
        copy.id = UUID()
        copy.name = "\(copy.displayName) (copy)"
        copy.createdAt = Date()
        copy.updatedAt = Date()
        update { $0.schedules.append(copy) }
    }

    func deleteSchedule(_ id: UUID) {
        if refuseWhileLocked("Strict Mode is on — schedules can't be deleted until it ends") { return }
        update { $0.schedules.removeAll { $0.id == id } }
    }

    // MARK: App limits

    /// Matches the limits to a picker selection: new picks get the default limit, unpicked ones go.
    func setLimitSelection(_ selection: FamilyActivitySelection) {
        var wanted: [LimitTarget] = selection.applicationTokens.map { .app($0) }
        wanted += selection.categoryTokens.map { .category($0) }
        wanted += selection.webDomainTokens.map { .web($0) }
        let wantedSet = Set(wanted)
        let existing = Set(state.appLimits.map(\.target))
        let removing = existing.subtracting(wantedSet)
        let locked = isEditingLocked
        update { state in
            for target in wanted where !existing.contains(target) {
                state.appLimits.append(AppLimit(target: target))
            }
            if !locked {
                state.appLimits.removeAll { removing.contains($0.target) }
            }
        }
        if !removing.isEmpty, locked {
            banner = Banner(text: "Strict Mode is on — limits can be added, not removed", style: .warning)
        }
    }

    var limitSelection: FamilyActivitySelection {
        var selection = FamilyActivitySelection()
        for limit in state.appLimits {
            switch limit.target {
            case .app(let token): selection.applicationTokens.insert(token)
            case .category(let token): selection.categoryTokens.insert(token)
            case .web(let token): selection.webDomainTokens.insert(token)
            }
        }
        return selection
    }

    func setLimitMinutes(_ id: UUID, _ minutes: Int) {
        guard let limit = state.appLimits.first(where: { $0.id == id }) else { return }
        if limit.isLoosening(to: minutes), refuseWhileLocked("Strict Mode is on — limits can only be tightened") { return }
        update { state in
            guard let index = state.appLimits.firstIndex(where: { $0.id == id }) else { return }
            state.appLimits[index].limitMinutes = minutes
            state.appLimits[index].enabled = true
        }
        SharedStore.clearLimitHit(ActivityNames.limitEvent(id))
        enforce(force: true)
    }

    func setLimitEnabled(_ id: UUID, _ enabled: Bool) {
        if !enabled, refuseWhileLocked("Strict Mode is on — limits can't be paused until it ends") { return }
        update { state in
            guard let index = state.appLimits.firstIndex(where: { $0.id == id }) else { return }
            state.appLimits[index].enabled = enabled
        }
    }

    func deleteLimit(_ id: UUID) {
        if refuseWhileLocked("Strict Mode is on — limits can't be removed until it ends") { return }
        update { $0.appLimits.removeAll { $0.id == id } }
    }

    // MARK: Websites

    enum WebsiteResult { case added, duplicate, invalid, full }

    func addGlobalWebsite(_ raw: String) -> WebsiteResult {
        let domain = WebPatterns.normalize(raw)
        guard WebPatterns.isDomain(domain) else { return .invalid }
        guard !state.globalWebsites.contains(domain) else { return .duplicate }
        guard state.globalWebsites.count < BlockEnforcer.maxFilteredDomains else { return .full }
        update(sync: false) { $0.globalWebsites.append(domain) }
        return .added
    }

    func removeGlobalWebsite(_ domain: String) {
        if refuseWhileLocked("Strict Mode is on — blocks can't be removed until it ends") { return }
        update(sync: false) { $0.globalWebsites.removeAll { $0 == domain } }
    }

    // MARK: Blocking options

    func setBlockAdultSites(_ on: Bool) {
        if !on, isStrictActive {
            banner = Banner(text: "Strict Mode is on — this can't be turned off until it ends", style: .warning)
            return
        }
        update(sync: false) { $0.blockAdultSites = on }
    }

    func setNotifyWhenBlocking(_ on: Bool) {
        update(sync: false) { $0.notifyWhenBlocking = on }
        if on, notificationStatus == .notDetermined {
            Task { await requestNotifications() }
        }
    }

    func setBlockMessage(_ message: String) {
        update(sync: false) { $0.blockMessage = message.trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    func setHiddenFromInsights(_ selection: FamilyActivitySelection) {
        update(sync: false) { $0.hiddenFromInsights = selection }
    }

    // MARK: Appearance

    func setAccent(_ accent: AccentTheme) { update(sync: false) { $0.accent = accent } }
    func setAppearance(_ appearance: AppearanceMode) { update(sync: false) { $0.appearance = appearance } }

    // MARK: Strict Mode

    func setStrictMethod(_ method: StrictUnlockMethod) {
        guard !isStrictActive else { return }
        update(sync: false) { $0.strictMethod = method }
    }

    func setStrictDuration(_ minutes: Int) {
        guard !isStrictActive else { return }
        update(sync: false) { $0.strictDurationMinutes = max(Schedule.minimumWindowMinutes, minutes) }
    }

    func setStrictOptions(_ options: StrictOptions) {
        guard !isStrictActive else { return }
        update(sync: false) { $0.strictOptions = options }
    }

    func activateStrict() {
        let start = Date()
        update { state in
            state.strict = StrictState(
                enabled: true,
                method: state.strictMethod,
                durationMinutes: state.strictDurationMinutes,
                startedAt: start,
                endsAt: state.strictMethod == .timer ? start.addingTimeInterval(TimeInterval(state.strictDurationMinutes * 60)) : nil,
                unlockRequestedAt: nil
            )
        }
        banner = Banner(text: "Strict Mode is on", style: .success)
    }

    func requestStrictUnlock() {
        guard state.strict.method == .cooldown, state.strict.unlockRequestedAt == nil else { return }
        update { $0.strict.unlockRequestedAt = Date() }
    }

    func deactivateStrict() {
        update { $0.strict = StrictState() }
        banner = Banner(text: "Strict Mode is off", style: .info)
    }

    func unlockWithCharger() {
        guard isCharging else {
            banner = Banner(text: "Connect your iPhone to power first", style: .warning)
            return
        }
        deactivateStrict()
    }

    func unlockWithPIN(_ pin: String) -> Bool {
        guard verifyPIN(pin) else { return false }
        deactivateStrict()
        return true
    }

    // MARK: PIN

    func verifyPIN(_ pin: String) -> Bool {
        state.hasPin && SharedStore.hashPin(pin, salt: state.pinSalt) == state.pinHash
    }

    /// Returns an error message, or nil when the PIN was saved.
    func setPIN(current: String, new: String, repeated: String) -> String? {
        if state.hasPin, !verifyPIN(current) { return "Current PIN is wrong" }
        guard (4...8).contains(new.count), new.allSatisfy(\.isNumber) else { return "Use 4 to 8 digits" }
        guard new == repeated else { return "PINs don't match" }
        let salt = UUID().uuidString
        update(sync: false) { state in
            state.pinSalt = salt
            state.pinHash = SharedStore.hashPin(new, salt: salt)
        }
        banner = Banner(text: "PIN saved", style: .success)
        return nil
    }

    // MARK: Backup

    struct Backup: Codable {
        var format = "openblock-backup"
        var version = 1
        var exportedAt = Date()
        var state: AppState
    }

    func exportBackup() throws -> Data {
        var exported = state
        // A live Strict Mode session is never exported, like the Android app.
        exported.strict = StrictState()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(Backup(state: exported))
    }

    func importBackup(_ data: Data) {
        // A backup can loosen anything, including what Strict Mode itself locks.
        if isStrictActive {
            banner = Banner(text: "Strict Mode is on — backups can't be restored until it ends", style: .warning)
            return
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let backup = try? decoder.decode(Backup.self, from: data), backup.format == "openblock-backup" else {
            banner = Banner(text: "That file isn't an OpenBlock backup", style: .warning)
            return
        }
        let liveStrict = state.strict
        update { state in
            state = backup.state
            state.strict = liveStrict
            state.hasCompletedOnboarding = true
        }
        banner = Banner(
            text: "Restored \(TimeFormat.plural(backup.state.schedules.count, "schedule")) and \(TimeFormat.plural(backup.state.appLimits.count, "limit"))",
            style: .success
        )
    }
}
