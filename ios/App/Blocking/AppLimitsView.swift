import FamilyControls
import SwiftUI

struct AppLimitsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPicker = false
    @State private var pickerSelection = FamilyActivitySelection()
    @State private var websiteInput = ""
    @State private var websiteError: String?

    var body: some View {
        List {
            if model.isEditingLocked {
                Section {
                    Label("Strict Mode is on: you can add or tighten limits, but not loosen or remove them.", systemImage: "lock.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                if model.state.appLimits.isEmpty {
                    EmptyStateRow(
                        symbol: "timer",
                        title: "No app limits yet",
                        message: "Pick apps or categories to give them a daily time limit.",
                        actionTitle: "Add apps"
                    ) { openPicker() }
                } else {
                    ForEach(model.state.appLimits) { limit in
                        LimitRow(limit: limit)
                    }
                    .onDelete { offsets in
                        offsets.map { model.state.appLimits[$0].id }.forEach(model.deleteLimit)
                    }
                    Button { openPicker() } label: {
                        Label("Add or remove apps", systemImage: "plus.circle.fill")
                    }
                }
            } header: {
                Text("Daily limits")
            } footer: {
                Text("New apps start at \(TimeFormat.minutes(AppLimit.defaultMinutes)) a day. Limits reset at midnight.")
            }

            Section {
                ForEach(model.state.globalWebsites, id: \.self) { site in
                    Label(site, systemImage: "globe")
                }
                .onDelete { offsets in
                    offsets.map { model.state.globalWebsites[$0] }.forEach(model.removeGlobalWebsite)
                }
                HStack {
                    TextField("Add a website, e.g. reddit.com", text: $websiteInput)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit(addWebsite)
                    Button(action: addWebsite) {
                        Image(systemName: "plus.circle.fill").font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .disabled(websiteInput.trimmingCharacters(in: .whitespaces).isEmpty)
                    .accessibilityLabel("Add website")
                }
            } header: {
                Text("Always-blocked websites")
            } footer: {
                if let websiteError {
                    Text(websiteError).foregroundStyle(.red)
                } else {
                    Text("Blocked at any time of day in Safari and in-app browsers.")
                }
            }
        }
        .navigationTitle("App Limits")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if !model.state.appLimits.isEmpty || !model.state.globalWebsites.isEmpty {
                EditButton()
            }
        }
        .familyActivityPicker(isPresented: $showPicker, selection: $pickerSelection)
        .onChange(of: showPicker) { presented in
            if !presented, pickerSelection != model.limitSelection {
                model.setLimitSelection(pickerSelection)
            }
        }
    }

    private func openPicker() {
        pickerSelection = model.limitSelection
        showPicker = true
    }

    private func addWebsite() {
        guard !websiteInput.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        switch model.addGlobalWebsite(websiteInput) {
        case .added:
            websiteInput = ""
            websiteError = nil
        case .duplicate:
            websiteInput = ""
            websiteError = "That website is already blocked."
        case .invalid:
            websiteError = "“\(websiteInput)” isn't a website. Try something like youtube.com."
        case .full:
            websiteError = "iOS allows up to \(BlockEnforcer.maxFilteredDomains) blocked websites."
        }
    }
}

private struct LimitRow: View {
    @EnvironmentObject private var model: AppModel
    var limit: AppLimit

    var body: some View {
        HStack(spacing: 12) {
            LimitTargetLabel(target: limit.target)
                .lineLimit(1)
                .foregroundStyle(limit.enabled ? .primary : .secondary)
            Spacer(minLength: 8)
            Menu {
                Picker("Daily limit", selection: Binding(get: { limit.limitMinutes }, set: { model.setLimitMinutes(limit.id, $0) })) {
                    ForEach(AppLimit.options, id: \.self) { minutes in
                        Text(AppLimit.label(for: minutes)).tag(minutes)
                    }
                }
                Divider()
                Button(limit.enabled ? "Pause" : "Resume") { model.setLimitEnabled(limit.id, !limit.enabled) }
                Button("Remove", role: .destructive) { model.deleteLimit(limit.id) }
            } label: {
                HStack(spacing: 4) {
                    Text(limit.enabled ? shortLabel : "Paused")
                    Image(systemName: "chevron.up.chevron.down").font(.caption2)
                }
                .font(.subheadline.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemFill), in: Capsule())
            }
            .accessibilityLabel("Limit: \(AppLimit.label(for: limit.limitMinutes))")
        }
    }

    private var shortLabel: String {
        limit.limitMinutes == 0 ? "Always blocked" : "\(TimeFormat.minutes(limit.limitMinutes))/day"
    }
}
