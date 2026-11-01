import FamilyControls
import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Draws OpenBlock's block screen on top of shielded apps and websites.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        configuration(
            name: application.localizedDisplayName,
            matchesSelection: { selection in
                guard let token = application.token else { return false }
                return selection.applicationTokens.contains(token)
            },
            matchesLimit: { target in
                if case .app(let token) = target { return token == application.token }
                return false
            }
        )
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        configuration(
            name: application.localizedDisplayName,
            matchesSelection: { selection in
                if let token = application.token, selection.applicationTokens.contains(token) { return true }
                if let token = category.token, selection.categoryTokens.contains(token) { return true }
                return false
            },
            matchesLimit: { target in
                switch target {
                case .app(let token): return token == application.token
                case .category(let token): return token == category.token
                case .web: return false
                }
            }
        )
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        configuration(
            name: webDomain.domain,
            matchesSelection: { selection in
                guard let token = webDomain.token else { return false }
                return selection.webDomainTokens.contains(token)
            },
            matchesLimit: { target in
                if case .web(let token) = target { return token == webDomain.token }
                return false
            }
        )
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        configuration(
            name: webDomain.domain,
            matchesSelection: { selection in
                if let token = webDomain.token, selection.webDomainTokens.contains(token) { return true }
                if let token = category.token, selection.categoryTokens.contains(token) { return true }
                return false
            },
            matchesLimit: { target in
                switch target {
                case .web(let token): return token == webDomain.token
                case .category(let token): return token == category.token
                case .app: return false
                }
            }
        )
    }

    private func configuration(
        name: String?,
        matchesSelection: (FamilyActivitySelection) -> Bool,
        matchesLimit: (LimitTarget) -> Bool
    ) -> ShieldConfiguration {
        let state = SharedStore.loadState()
        let reason = PolicyEngine.reason(
            state: state,
            clock: Clock(),
            hits: SharedStore.limitHits(),
            matchesSelection: matchesSelection,
            matchesLimit: matchesLimit
        )
        let accent = UIColor.shieldAccent(state.accent)
        let title = reason?.title ?? "Blocked"
        var lines: [String] = []
        if let name, !name.isEmpty { lines.append(name) }
        lines.append(reason?.detail ?? "Blocked by your focus settings.")
        if !state.blockMessage.isEmpty { lines.append("\n“\(state.blockMessage)”") }

        return ShieldConfiguration(
            backgroundBlurStyle: .systemUltraThinMaterial,
            backgroundColor: UIColor.systemBackground.withAlphaComponent(0.4),
            icon: UIImage(systemName: reason?.title == "Time's up" ? "hourglass" : "lock.shield.fill")?
                .withTintColor(accent, renderingMode: .alwaysOriginal),
            title: ShieldConfiguration.Label(text: title, color: .label),
            subtitle: ShieldConfiguration.Label(text: lines.joined(separator: "\n"), color: .secondaryLabel),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: .white),
            primaryButtonBackgroundColor: accent,
            secondaryButtonLabel: nil
        )
    }
}

private extension UIColor {
    static func shieldAccent(_ theme: AccentTheme) -> UIColor {
        let (light, dark) = theme.accentHex
        return UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        }
    }
}
