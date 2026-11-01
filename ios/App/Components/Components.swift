import FamilyControls
import ManagedSettings
import SwiftUI

/// A tinted rounded-square symbol, like the icons in the Settings app.
struct IconBadge: View {
    var symbol: String
    var color: Color
    var size: CGFloat = 30

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.5, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(color.gradient, in: RoundedRectangle(cornerRadius: size * 0.26, style: .continuous))
            .accessibilityHidden(true)
    }
}

/// A small coloured status line with a leading dot.
struct StatusLabel: View {
    var text: String
    var color: Color
    var showsDot = true

    var body: some View {
        HStack(spacing: 6) {
            if showsDot {
                Circle().fill(color).frame(width: 7, height: 7)
            }
            Text(text)
                .font(.caption.weight(.semibold))
                .foregroundStyle(color)
        }
    }
}

/// An empty state for inside a List section.
struct EmptyStateRow: View {
    var symbol: String
    var title: String
    var message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30, weight: .regular))
                .foregroundStyle(.tint)
                .padding(.top, 8)
            Text(title).font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}

/// Shown until the user gives OpenBlock Screen Time access, without which nothing can be blocked.
struct ScreenTimeSetupCard: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                IconBadge(symbol: "hourglass", color: .indigo, size: 36)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Allow Screen Time access").font(.headline)
                    Text("OpenBlock uses Apple's Screen Time to block apps and websites. Your data stays on this iPhone.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button {
                Task { await model.requestAuthorization() }
            } label: {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(.vertical, 6)
    }
}

/// Icons of picked apps, categories and websites, overlapping like an avatar stack.
struct SelectionPreview: View {
    var selection: FamilyActivitySelection
    var limit = 6

    private var tokens: [AnyView] {
        var views: [AnyView] = []
        for token in selection.applicationTokens.prefix(limit) {
            views.append(AnyView(Label(token).labelStyle(.iconOnly)))
        }
        for token in selection.categoryTokens.prefix(max(0, limit - views.count)) {
            views.append(AnyView(Label(token).labelStyle(.iconOnly)))
        }
        for token in selection.webDomainTokens.prefix(max(0, limit - views.count)) {
            views.append(AnyView(Label(token).labelStyle(.iconOnly)))
        }
        return views
    }

    var body: some View {
        let total = selection.applicationTokens.count + selection.categoryTokens.count + selection.webDomainTokens.count
        HStack(spacing: 4) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, view in
                view
                    .frame(width: 26, height: 26)
                    .scaleEffect(0.9)
            }
            if total > limit {
                Text("+\(total - limit)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(.quaternary, in: Capsule())
            }
        }
    }
}

/// Seven round day toggles, Monday first.
struct DayPicker: View {
    @Binding var mask: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                let selected = mask & (1 << index) != 0
                Button {
                    mask ^= (1 << index)
                } label: {
                    Text(TimeFormat.narrowDayNames[index])
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .foregroundStyle(selected ? Color.white : Color.primary)
                        .background(
                            Circle().fill(selected ? AnyShapeStyle(TintShapeStyle()) : AnyShapeStyle(Color(.tertiarySystemFill)))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(TimeFormat.shortDayNames[index])
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(.vertical, 4)
    }
}

/// A 24-hour bar with the blocked window filled in.
struct TimeRail: View {
    var start: Int
    var end: Int

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { proxy in
                let width = proxy.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Color(.tertiarySystemFill))
                    ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                        Capsule()
                            .fill(.tint)
                            .frame(width: max(6, width * CGFloat(segment.1 - segment.0) / 1440))
                            .offset(x: width * CGFloat(segment.0) / 1440)
                    }
                }
            }
            .frame(height: 10)
            HStack {
                ForEach(["00", "06", "12", "18", "24"], id: \.self) { hour in
                    Text(hour)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if hour != "24" { Spacer() }
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Blocks from \(TimeFormat.clock(start)) to \(TimeFormat.clock(end))")
    }

    private var segments: [(Int, Int)] {
        if start == 0 && end == 1440 { return [(0, 1440)] }
        if start < end { return [(start, end)] }
        return [(start, 1440), (0, end)]
    }
}

/// A transient message pinned to the top of the screen.
struct BannerModifier: ViewModifier {
    @Binding var banner: Banner?

    func body(content: Content) -> some View {
        content.overlay(alignment: .top) {
            if let banner {
                HStack(spacing: 10) {
                    Image(systemName: symbol(for: banner.style))
                        .foregroundStyle(color(for: banner.style))
                    Text(banner.text)
                        .font(.subheadline.weight(.medium))
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.regularMaterial, in: Capsule())
                .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onTapGesture { self.banner = nil }
                .task(id: banner.id) {
                    try? await Task.sleep(nanoseconds: 2_600_000_000)
                    withAnimation(.easeInOut) { self.banner = nil }
                }
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: banner)
    }

    private func symbol(for style: Banner.Style) -> String {
        switch style {
        case .info: return "info.circle.fill"
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }

    private func color(for style: Banner.Style) -> Color {
        switch style {
        case .info: return .accentColor
        case .success: return .green
        case .warning: return .orange
        }
    }
}

extension View {
    func banner(_ banner: Binding<Banner?>) -> some View {
        modifier(BannerModifier(banner: banner))
    }
}

/// Shows a single app, category or website token with its icon and name.
struct LimitTargetLabel: View {
    var target: LimitTarget

    var body: some View {
        switch target {
        case .app(let token): Label(token)
        case .category(let token): Label(token)
        case .web(let token): Label(token)
        }
    }
}
