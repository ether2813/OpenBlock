import SwiftUI

struct AppearanceView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                ForEach(AccentTheme.allCases) { theme in
                    Button {
                        withAnimation { model.setAccent(theme) }
                    } label: {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(theme.color.gradient)
                                .frame(width: 32, height: 32)
                                .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 1))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(theme.title).foregroundStyle(.primary)
                                Text(theme.subtitle).font(.footnote).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.state.accent == theme {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(theme.color)
                            }
                        }
                    }
                }
            } header: {
                Text("Color theme")
            }

            Section {
                Picker("Appearance", selection: Binding(get: { model.state.appearance }, set: { model.setAppearance($0) })) {
                    ForEach(AppearanceMode.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            } header: {
                Text("Appearance")
            } footer: {
                Text("The block screen uses your color theme too.")
            }
        }
        .navigationTitle("Appearance")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BlockingOptionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.state.blockAdultSites }, set: { model.setBlockAdultSites($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Block adult websites")
                        Text("Uses Apple's built-in adult content filter in Safari and in-app browsers.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .disabled(!model.isAuthorized)
            } footer: {
                if model.isStrictActive && model.state.blockAdultSites {
                    Text("Strict Mode is on, so this can't be turned off until it ends.")
                }
            }

            Section {
                Toggle(isOn: Binding(get: { model.state.notifyWhenBlocking }, set: { model.setNotifyWhenBlocking($0) })) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Notify when blocking starts")
                        Text("A quiet notification when a schedule starts or a limit is reached.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            } footer: {
                if model.notificationStatus == .denied {
                    Text("Notifications are off for OpenBlock in Settings.")
                }
            }

            Section {
                Label("Silencing notifications from blocked apps and rejecting calls aren't possible on iPhone. Use a Focus in Control Center for those.", systemImage: "info.circle")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Blocking Options")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct BlockMessageView: View {
    @EnvironmentObject private var model: AppModel
    @State private var message = ""
    @FocusState private var focused: Bool

    var body: some View {
        Form {
            Section {
                TextField("e.g. Is this really what you want to be doing?", text: $message, axis: .vertical)
                    .lineLimit(2...5)
                    .focused($focused)
            } footer: {
                Text("Shown on the block screen. Leave empty for none.")
            }

            Section("Preview") {
                VStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 34))
                        .foregroundStyle(.tint)
                    Text("Blocked").font(.title3.bold())
                    Text("Focus time · until \(TimeFormat.clock(17 * 60))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !message.trimmingCharacters(in: .whitespaces).isEmpty {
                        Text("“\(message.trimmingCharacters(in: .whitespacesAndNewlines))”")
                            .font(.subheadline.italic())
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
        }
        .navigationTitle("Block Screen Message")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            message = model.state.blockMessage
            focused = message.isEmpty
        }
        .onDisappear { model.setBlockMessage(message) }
    }
}

struct AboutBlockingView: View {
    var body: some View {
        List {
            Section {
                Text("iPhone doesn't let apps watch or cover other apps. OpenBlock uses Apple's Screen Time instead: you pick apps privately in Apple's picker, and iOS itself shows the block screen. That makes blocking reliable and battery-friendly, with a few differences.")
                    .font(.subheadline)
            }
            Section("Works like Android") {
                item("checkmark.circle.fill", .green, "Time schedules, overnight windows and days of the week")
                item("checkmark.circle.fill", .green, "Daily usage limits for schedules and single apps")
                item("checkmark.circle.fill", .green, "Blocklists, allowlists and always-blocked websites")
                item("checkmark.circle.fill", .green, "Strict Mode with timer, schedule, cooldown, charger and PIN unlocks")
                item("checkmark.circle.fill", .green, "Insights for today, the week and two weeks")
            }
            Section("Different on iPhone") {
                item("arrow.triangle.2.circlepath", .orange, "Picked apps show by icon and name, not package name")
                item("arrow.triangle.2.circlepath", .orange, "Strict Mode stops apps being deleted or installed instead of locking Settings")
                item("arrow.triangle.2.circlepath", .orange, "Backups are JSON files and restore on this iPhone")
                item("arrow.triangle.2.circlepath", .orange, "Schedule windows must be at least 15 minutes long")
            }
            Section("Not available on iPhone") {
                item("xmark.circle.fill", .red, "Launch-count limits")
                item("xmark.circle.fill", .red, "Keyword blocking inside web pages")
                item("xmark.circle.fill", .red, "Silencing notifications and rejecting calls")
                item("xmark.circle.fill", .red, "Locking Recent Apps, split screen and Settings")
                item("xmark.circle.fill", .red, "Device Owner mode")
            }
        }
        .navigationTitle("Blocking on iPhone")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func item(_ symbol: String, _ color: Color, _ text: String) -> some View {
        Label {
            Text(text)
        } icon: {
            Image(systemName: symbol).foregroundStyle(color)
        }
    }
}
