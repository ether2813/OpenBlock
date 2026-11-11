import SwiftUI

enum StrictStatus {
    static func line(for strict: StrictState, now: Date, charging: Bool) -> String {
        switch strict.method {
        case .timer:
            guard let end = strict.endsAt else { return "Unlocks when the timer runs out" }
            return "Unlocks in \(TimeFormat.compact(end.timeIntervalSince(now))) · at \(TimeFormat.clock(at: end))"
        case .cooldown:
            if let end = strict.cooldownEndsAt {
                return "Unlocks in \(TimeFormat.compact(end.timeIntervalSince(now))) · at \(TimeFormat.clock(at: end))"
            }
            return "Request an unlock, then wait \(TimeFormat.minutes(strict.durationMinutes))"
        case .charger:
            return charging ? "Connected to power — you can unlock now" : "Unlocks only while connected to power"
        case .pin:
            return "Unlock any time with your PIN"
        case .schedules:
            return "Locked while a schedule is active"
        }
    }
}

struct StrictHomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showConfirm = false
    @State private var showPINUnlock = false
    @State private var showPINSetup = false
    @State private var confirmAfterPINSetup = false
    @State private var confirmCooldown = false

    static let durationOptions = [15, 30, 60, 120, 300, 720, 1440, 4320, 10080]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    hero
                }
                .listRowBackground(Color.clear)

                if !model.isAuthorized {
                    Section { ScreenTimeSetupCard() }
                }

                if model.isStrictActive {
                    activeSections
                } else if model.state.strict.enabled && model.state.strict.method == .schedules {
                    armedSections
                } else {
                    setupSections
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Strict Mode")
            .sheet(isPresented: $showConfirm) {
                StrictConfirmView().environmentObject(model)
            }
            .sheet(isPresented: $showPINUnlock) {
                PINSheet(mode: .unlock).environmentObject(model)
            }
            // The confirmation opens only once the PIN sheet has fully closed; presenting one
            // sheet while another is still dismissing is silently dropped by iOS.
            .sheet(isPresented: $showPINSetup, onDismiss: {
                if confirmAfterPINSetup {
                    confirmAfterPINSetup = false
                    showConfirm = true
                }
            }) {
                PINSheet(mode: .set) { confirmAfterPINSetup = true }.environmentObject(model)
            }
        }
    }

    // MARK: Hero

    private var hero: some View {
        let locked = model.isStrictActive
        return VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(locked ? 0.18 : 0.1))
                    .frame(width: 128, height: 128)
                Circle()
                    .fill(Color.accentColor.opacity(locked ? 0.28 : 0.16))
                    .frame(width: 92, height: 92)
                Image(systemName: locked ? "lock.fill" : "lock.open.fill")
                    .font(.system(size: 40, weight: .semibold))
                    .foregroundStyle(.tint)
            }
            Text(locked ? "Your blocks are locked" : "Your blocks are unlocked")
                .font(.title2.bold())
            Text(locked
                 ? "You can't pause, loosen or delete blocks until Strict Mode unlocks."
                 : "Strict Mode stops you from pausing, editing or deleting your blocks, and can stop apps being deleted.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    // MARK: Inactive

    @ViewBuilder
    private var setupSections: some View {
        Section {
            NavigationLink {
                UnlockMethodView()
            } label: {
                HStack {
                    Label("Unlock method", systemImage: model.state.strictMethod.symbol)
                    Spacer()
                    Text(model.state.strictMethod.title).foregroundStyle(.secondary)
                }
            }
            if model.state.strictMethod.usesDuration {
                Picker(selection: Binding(get: { model.state.strictDurationMinutes }, set: { model.setStrictDuration($0) })) {
                    ForEach(Self.durationOptions, id: \.self) { Text(TimeFormat.minutes($0)).tag($0) }
                } label: {
                    Label(model.state.strictMethod == .timer ? "Duration" : "Cooldown", systemImage: "clock")
                }
                .pickerStyle(.menu)
            }
            NavigationLink {
                StrictOptionsView()
            } label: {
                HStack {
                    Label("What gets locked", systemImage: "checklist")
                    Spacer()
                    Text("\(model.state.strictOptions.protections.count)").foregroundStyle(.secondary)
                }
            }
        } footer: {
            Text(model.state.strictMethod.explanation)
        }

        Section {
            Button {
                if model.state.strictMethod == .pin && !model.state.hasPin {
                    showPINSetup = true
                } else {
                    showConfirm = true
                }
            } label: {
                Label("Activate Strict Mode", systemImage: "lock.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!model.isAuthorized)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
        }
    }

    // MARK: Armed (follow schedules, none active)

    @ViewBuilder
    private var armedSections: some View {
        Section {
            Label("Strict Mode follows your schedules. It locks again as soon as one becomes active.", systemImage: "calendar.badge.clock")
                .font(.subheadline)
        }
        Section {
            Button("Turn Off Strict Mode", role: .destructive) { model.deactivateStrict() }
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: Active

    @ViewBuilder
    private var activeSections: some View {
        let strict = model.state.strict
        Section {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack {
                    Image(systemName: strict.method.symbol).foregroundStyle(.tint)
                    Text(StrictStatus.line(for: strict, now: context.date, charging: model.isCharging))
                        .font(.body.monospacedDigit())
                }
            }
            if let startedAt = strict.startedAt {
                LabeledContent("Started", value: TimeFormat.clock(at: startedAt))
            }
        } header: {
            Text("Status")
        }

        Section {
            let protections = model.state.strictOptions.protections
            if protections.isEmpty {
                Text("Nothing extra. Choose protections under “What gets locked” next time.")
                    .foregroundStyle(.secondary)
            }
            ForEach(protections, id: \.self) { item in
                Label(item, systemImage: "lock.fill")
            }
        } header: {
            Text("Locked right now")
        }

        switch strict.method {
        case .cooldown where strict.unlockRequestedAt == nil:
            Section {
                Button { confirmCooldown = true } label: {
                    Text("Request Unlock").frame(maxWidth: .infinity)
                }
                .confirmationDialog(
                    "Start the \(TimeFormat.minutes(strict.durationMinutes)) cooldown?",
                    isPresented: $confirmCooldown,
                    titleVisibility: .visible
                ) {
                    Button("Start Cooldown") { model.requestStrictUnlock() }
                } message: {
                    Text("Strict Mode unlocks when it ends. This can't be cancelled.")
                }
            }
        case .charger:
            Section {
                Button { model.unlockWithCharger() } label: {
                    Label(model.isCharging ? "Unlock Now" : "Connect to Power to Unlock", systemImage: "bolt.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!model.isCharging)
            }
        case .pin:
            Section {
                Button { showPINUnlock = true } label: {
                    Label("Unlock with PIN", systemImage: "key.fill").frame(maxWidth: .infinity)
                }
            }
        default:
            EmptyView()
        }
    }
}

struct StrictConfirmView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(summary)
                }
                Section {
                    let protections = model.state.strictOptions.protections
                    if protections.isEmpty {
                        Text("Nothing extra is locked.").foregroundStyle(.secondary)
                    }
                    ForEach(protections, id: \.self) { item in
                        Label(item, systemImage: "exclamationmark.lock.fill")
                            .foregroundStyle(.primary)
                            .symbolRenderingMode(.multicolor)
                    }
                    NavigationLink("Change what gets locked") { StrictOptionsView() }
                } header: {
                    Text("While it's on, you can't")
                }
                Section {
                    Label("Settings → Screen Time can still turn off OpenBlock's access. Set a Screen Time passcode someone else knows for the strongest protection.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Activate Strict Mode?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Activate") {
                        model.activateStrict()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var summary: String {
        let duration = model.state.strictDurationMinutes
        switch model.state.strictMethod {
        case .timer:
            let end = Date().addingTimeInterval(TimeInterval(duration * 60))
            return "Strict Mode stays on for \(TimeFormat.minutes(duration)), until \(TimeFormat.clock(at: end)). It can't be ended early."
        case .schedules: return "Strict Mode will be on whenever one of your schedules is active."
        case .cooldown: return "To unlock, you'll request it and then wait \(TimeFormat.minutes(duration))."
        case .charger: return "You'll only be able to unlock while your iPhone is connected to power."
        case .pin: return "You can unlock any time with your PIN."
        }
    }
}

struct UnlockMethodView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPINSetup = false

    var body: some View {
        List {
            Section {
                ForEach(StrictUnlockMethod.allCases) { method in
                    Button {
                        if method == .pin && !model.state.hasPin {
                            showPINSetup = true
                        } else {
                            model.setStrictMethod(method)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            IconBadge(symbol: method.symbol, color: .accentColor, size: 32)
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(method.title).foregroundStyle(.primary)
                                    Text(method.difficulty.rawValue.uppercased())
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(method.difficulty.color)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(method.difficulty.color.opacity(0.14), in: Capsule())
                                }
                                Text(method.explanation)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if model.state.strictMethod == method {
                                Image(systemName: "checkmark").font(.body.weight(.semibold)).foregroundStyle(.tint)
                            }
                        }
                    }
                    .disabled(model.isStrictActive)
                }
            } footer: {
                Text(model.isStrictActive ? "The unlock method can't be changed while Strict Mode is on." : "How Strict Mode can be turned off once it's on.")
            }
        }
        .navigationTitle("Unlock Method")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showPINSetup) {
            PINSheet(mode: .set) { model.setStrictMethod(.pin) }.environmentObject(model)
        }
    }
}

struct StrictOptionsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let locked = model.isStrictActive
        Form {
            Section {
                toggle("Lock blocking in the app", "No pausing, editing or deleting schedules and limits.", \.lockEditing)
                toggle("Prevent deleting apps", "Apps can't be deleted from the Home Screen, including OpenBlock.", \.preventAppRemoval)
                toggle("Prevent installing apps", "The App Store can't install new apps.", \.preventAppInstallation)
                toggle("Lock date & time", "Keeps “Set Automatically” on, so schedules can't be dodged by changing the clock.", \.requireAutomaticTime)
            } footer: {
                Text(locked ? "These can't be changed while Strict Mode is on." : "Everything goes back to normal when Strict Mode unlocks.")
            }
            .disabled(locked)
        }
        .navigationTitle("What Gets Locked")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ title: String, _ subtitle: String, _ keyPath: WritableKeyPath<StrictOptions, Bool>) -> some View {
        Toggle(isOn: Binding(
            get: { model.state.strictOptions[keyPath: keyPath] },
            set: { value in
                var options = model.state.strictOptions
                options[keyPath: keyPath] = value
                model.setStrictOptions(options)
            }
        )) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(subtitle).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}
