import Foundation
import FamilyControls
import ManagedSettings

extension ManagedSettingsStore.Name {
    static let openBlockRules = Self("openblock.rules")
    static let openBlockWeb = Self("openblock.web")
    static let openBlockStrict = Self("openblock.strict")
}

/// Turns the shared state into Screen Time restrictions. Idempotent: the app and the monitor
/// extension call it whenever anything may have changed.
enum BlockEnforcer {
    /// The system web filter accepts at most 50 specific domains.
    static let maxFilteredDomains = 50
    /// iOS ignores a shield (or an exception list) with more than 50 individual tokens.
    static let maxShieldTokens = 50

    static func apply(state: AppState, clock: Clock = Clock(), hits: [String: String] = SharedStore.limitHits()) {
        applyRules(state: state, clock: clock, hits: hits)
        applyWeb(state: state, clock: clock, hits: hits)
        applyStrict(state: state, clock: clock)
    }

    static func clearAll() {
        ManagedSettingsStore(named: .openBlockRules).clearAllSettings()
        ManagedSettingsStore(named: .openBlockWeb).clearAllSettings()
        ManagedSettingsStore(named: .openBlockStrict).clearAllSettings()
    }

    private static func applyRules(state: AppState, clock: Clock, hits: [String: String]) {
        var apps = Set<ApplicationToken>()
        var categories = Set<ActivityCategoryToken>()
        var webTokens = Set<WebDomainToken>()
        var allowed: Set<ApplicationToken>?

        for schedule in state.schedules where PolicyEngine.isScheduleBlocking(schedule, clock: clock, hits: hits) {
            switch schedule.mode {
            case .blocklist:
                apps.formUnion(schedule.selection.applicationTokens)
                categories.formUnion(schedule.selection.categoryTokens)
                webTokens.formUnion(schedule.selection.webDomainTokens)
            case .allowlist:
                // With several allowlists active, an app must be allowed by all of them.
                let tokens = schedule.selection.applicationTokens
                allowed = allowed.map { $0.intersection(tokens) } ?? tokens
            }
        }

        for limit in state.appLimits where PolicyEngine.isLimitBlocking(limit, clock: clock, hits: hits) {
            switch limit.target {
            case .app(let token): apps.insert(token)
            case .category(let token): categories.insert(token)
            case .web(let token): webTokens.insert(token)
            }
        }

        let store = ManagedSettingsStore(named: .openBlockRules)
        // Past the token limit iOS would drop the whole set, so block as much as it accepts.
        store.shield.applications = apps.isEmpty ? nil : Set(apps.prefix(maxShieldTokens))
        store.shield.webDomains = webTokens.isEmpty ? nil : Set(webTokens.prefix(maxShieldTokens))
        if let allowed {
            store.shield.applicationCategories = .all(except: Set(allowed.prefix(maxShieldTokens)))
        } else if !categories.isEmpty {
            store.shield.applicationCategories = .specific(categories, except: Set<ApplicationToken>())
        } else {
            store.shield.applicationCategories = nil
        }
        store.shield.webDomainCategories = categories.isEmpty ? nil : .specific(categories, except: Set<WebDomainToken>())
    }

    /// Domains typed by hand go through the system web content filter, which covers Safari and
    /// in-app browsers.
    private static func applyWeb(state: AppState, clock: Clock, hits: [String: String]) {
        var domains = state.globalWebsites
        for schedule in state.schedules where schedule.mode == .blocklist &&
            PolicyEngine.isScheduleBlocking(schedule, clock: clock, hits: hits) {
            domains.append(contentsOf: schedule.websites)
        }
        var seen = Set<String>()
        let unique = domains.map(WebPatterns.normalize).filter { !$0.isEmpty && seen.insert($0).inserted }
        let blocked = Set(unique.prefix(maxFilteredDomains).map { WebDomain(domain: $0) })

        let store = ManagedSettingsStore(named: .openBlockWeb)
        if state.blockAdultSites {
            store.webContent.blockedByFilter = .auto(blocked)
        } else if !blocked.isEmpty {
            store.webContent.blockedByFilter = .specific(blocked)
        } else {
            store.webContent.blockedByFilter = nil
        }
    }

    private static func applyStrict(state: AppState, clock: Clock) {
        let store = ManagedSettingsStore(named: .openBlockStrict)
        guard PolicyEngine.isStrictActive(state, clock: clock) else {
            store.clearAllSettings()
            return
        }
        let options = state.strictOptions
        store.application.denyAppRemoval = options.preventAppRemoval ? true : nil
        store.application.denyAppInstallation = options.preventAppInstallation ? true : nil
        store.dateAndTime.requireAutomaticDateAndTime = options.requireAutomaticTime ? true : nil
    }
}
