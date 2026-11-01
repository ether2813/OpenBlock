import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers
import UserNotifications

struct MoreView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPIN = false
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())

                Section("Blocking") {
                    NavigationLink {
                        BlockingOptionsView()
                    } label: {
                        row("Blocking options", "Adult websites, notifications", symbol: "slider.horizontal.3", color: .blue)
                    }
                    NavigationLink {
                        AppLimitsView()
                    } label: {
                        row("App limits & websites",
                            "\(TimeFormat.plural(model.state.appLimits.count, "app")) · \(TimeFormat.plural(model.state.globalWebsites.count, "website"))",
                            symbol: "timer", color: .orange)
                    }
                    Button { showPIN = true } label: {
                        row("Strict Mode PIN", model.state.hasPin ? "Change your PIN" : "Not set", symbol: "key.fill", color: .gray)
                    }
                }

                Section("Personalize") {
                    NavigationLink {
                        AppearanceView()
                    } label: {
                        row("Appearance", "\(model.state.accent.title) · \(model.state.appearance.title)", symbol: "paintpalette.fill", color: .pink)
                    }
                    NavigationLink {
                        BlockMessageView()
                    } label: {
                        row("Block screen message", model.state.blockMessage.isEmpty ? "Not set" : model.state.blockMessage,
                            symbol: "text.bubble.fill", color: .teal)
                    }
                }

                Section("Permissions") {
                    PermissionRow(
                        title: "Screen Time",
                        subtitle: "Required to block apps and websites",
                        symbol: "hourglass",
                        color: .indigo,
                        granted: model.isAuthorized
                    ) {
                        Task { await model.requestAuthorization() }
                    }
                    PermissionRow(
                        title: "Notifications",
                        subtitle: "Tells you when blocking starts",
                        symbol: "bell.badge.fill",
                        color: .red,
                        granted: model.notificationStatus == .authorized || model.notificationStatus == .provisional
                    ) {
                        Task { await model.requestNotifications() }
                    }
                }

                Section {
                    ShareLink(
                        item: BackupFile(model: model),
                        preview: SharePreview("OpenBlock backup", image: Image(systemName: "doc.text"))
                    ) {
                        row("Export backup", "Save schedules, limits and settings", symbol: "square.and.arrow.up", color: .green)
                    }
                    Button { showImporter = true } label: {
                        row("Import backup", "Restore from a backup file", symbol: "square.and.arrow.down", color: .green)
                    }
                } header: {
                    Text("Data")
                } footer: {
                    Text("Picked apps are stored as private Screen Time tokens, so a backup restores fully on this iPhone. A live Strict Mode session is never exported.")
                }

                Section {
                    NavigationLink {
                        AboutBlockingView()
                    } label: {
                        row("How blocking works on iPhone", "What's different from Android", symbol: "questionmark.circle.fill", color: .blue)
                    }
                } footer: {
                    Text("OpenBlock \(Bundle.main.versionString)")
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("More")
            .sheet(isPresented: $showPIN) {
                PINSheet(mode: .set).environmentObject(model)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.json]) { result in
                guard case .success(let url) = result else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    model.importBackup(data)
                } else {
                    model.banner = Banner(text: "Couldn't read that file", style: .warning)
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 72, height: 72)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            VStack(spacing: 2) {
                Text("OpenBlock").font(.title2.bold())
                Text("Private, offline focus controls").font(.subheadline).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                stat("Schedules", "\(model.state.schedules.filter(\.enabled).count)")
                stat("App limits", "\(model.state.appLimits.filter(\.enabled).count)")
                stat("Websites", "\(model.state.globalWebsites.count)")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func row(_ title: String, _ subtitle: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).foregroundStyle(.primary)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct PermissionRow: View {
    var title: String
    var subtitle: String
    var symbol: String
    var color: Color
    var granted: Bool
    var action: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            IconBadge(symbol: symbol, color: color)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer()
            if granted {
                Label("Allowed", systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.green)
            } else {
                Button("Allow", action: action)
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
            }
        }
    }
}

/// The exported backup, created only when the user actually shares it.
struct BackupFile: Transferable {
    let model: AppModel

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .json) { file in
            try await file.model.exportBackup()
        }
        .suggestedFileName("OpenBlock-backup.json")
    }
}

extension Bundle {
    var versionString: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }
}
