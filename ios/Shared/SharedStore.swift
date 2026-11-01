import Foundation
import CryptoKit

/// App Group storage shared by the app and its extensions.
///
/// The app owns `state`; extensions only ever write `limitHits`, so the two never overwrite each
/// other's changes.
enum SharedStore {
    static let appGroup = "group.com.openblock.app"

    private static let stateKey = "openblock.state.v1"
    private static let hitsKey = "openblock.limitHits.v1"
    private static let signaturesKey = "openblock.activitySignatures.v1"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroup) ?? .standard
    }

    static func loadState() -> AppState {
        guard let data = defaults.data(forKey: stateKey) else { return AppState() }
        return (try? JSONDecoder().decode(AppState.self, from: data)) ?? AppState()
    }

    static func saveState(_ state: AppState) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: stateKey)
    }

    // MARK: Usage limits reached

    /// Event name → day key ("2026-11-01") of the day its usage threshold was reached.
    static func limitHits() -> [String: String] {
        defaults.dictionary(forKey: hitsKey) as? [String: String] ?? [:]
    }

    static func recordLimitHit(_ eventName: String, dayKey: String) {
        var hits = limitHits()
        hits[eventName] = dayKey
        // Old days never matter again; keep the dictionary small.
        hits = hits.filter { $0.value == dayKey }
        defaults.set(hits, forKey: hitsKey)
    }

    static func clearLimitHit(_ eventName: String) {
        var hits = limitHits()
        hits[eventName] = nil
        defaults.set(hits, forKey: hitsKey)
    }

    // MARK: DeviceActivity bookkeeping

    static func activitySignatures() -> [String: String] {
        defaults.dictionary(forKey: signaturesKey) as? [String: String] ?? [:]
    }

    static func setActivitySignatures(_ signatures: [String: String]) {
        defaults.set(signatures, forKey: signaturesKey)
    }

    // MARK: Helpers

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func hashPin(_ pin: String, salt: String) -> String {
        sha256(Data((salt + ":" + pin).utf8))
    }
}

/// Event and activity names, shared so the monitor extension can map callbacks back to rules.
enum ActivityNames {
    static let timePrefix = "time."
    static let usagePrefix = "usage."
    static let limits = "limits"
    static let strict = "strict"

    static func scheduleEvent(_ id: UUID) -> String { "schedule.\(id.uuidString)" }
    static func limitEvent(_ id: UUID) -> String { "limit.\(id.uuidString)" }
}
