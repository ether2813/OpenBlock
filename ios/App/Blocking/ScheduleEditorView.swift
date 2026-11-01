import FamilyControls
import SwiftUI

struct ScheduleEditorView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft: Schedule
    @State private var showPicker = false
    @State private var websiteInput = ""
    @State private var websiteError: String?
    @State private var confirmDelete = false
    let isNew: Bool

    init(schedule: Schedule, isNew: Bool) {
        _draft = State(initialValue: schedule)
        self.isNew = isNew
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(draft.defaultName, text: $draft.name)
                        .textInputAutocapitalization(.sentences)
                        .submitLabel(.done)
                } header: {
                    Text("Name")
                }

                Section {
                    Picker("Mode", selection: $draft.mode.animation()) {
                        ForEach(BlockingMode.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(draft.mode.explanation)
                }

                targetsSection

                if draft.mode == .blocklist {
                    websitesSection
                }

                conditionSection

                Section {
                    DayPicker(mask: $draft.daysMask)
                    Menu {
                        Button("Every day") { draft.daysMask = Schedule.allDays }
                        Button("Weekdays") { draft.daysMask = Schedule.weekdays }
                        Button("Weekends") { draft.daysMask = Schedule.weekends }
                    } label: {
                        HStack {
                            Text(TimeFormat.days(draft.daysMask)).foregroundStyle(.primary)
                            Spacer()
                            Text("Presets").foregroundStyle(.tint)
                        }
                    }
                } header: {
                    Text("Days")
                }

                if !isNew {
                    Section {
                        Button("Delete Schedule", role: .destructive) { confirmDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .navigationTitle(isNew ? "New Schedule" : "Edit Schedule")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(validationMessage != nil)
                }
            }
            .familyActivityPicker(isPresented: $showPicker, selection: $draft.selection)
            .confirmationDialog("Delete \(draft.displayName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Schedule", role: .destructive) {
                    model.deleteSchedule(draft.id)
                    dismiss()
                }
            }
            .onChange(of: draft.mode) { mode in
                if mode == .allowlist { draft.type = .time }
            }
        }
    }

    // MARK: Sections

    private var targetsSection: some View {
        Section {
            Button {
                showPicker = true
            } label: {
                HStack(spacing: 12) {
                    IconBadge(symbol: draft.mode == .allowlist ? "checkmark.shield.fill" : "xmark.shield.fill",
                              color: draft.mode == .allowlist ? .green : .accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(draft.mode == .allowlist ? "Choose allowed apps" : "Choose apps & categories")
                            .foregroundStyle(.primary)
                        Text(selectionSubtitle)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                }
            }
            if !draft.selection.isEmptySelection {
                SelectionPreview(selection: draft.selection, limit: 8)
            }
        } header: {
            Text(draft.mode == .allowlist ? "Allowed apps" : "What to block")
        } footer: {
            if draft.mode == .allowlist {
                Text("Phone, Messages, emergency calls and Settings always stay available.")
            }
        }
    }

    private var selectionSubtitle: String {
        if draft.selection.isEmptySelection {
            return draft.mode == .allowlist ? "Nothing allowed yet — every app will be blocked" : "Nothing selected yet"
        }
        return draft.selection.summary
    }

    private var websitesSection: some View {
        Section {
            ForEach(draft.websites, id: \.self) { site in
                Label(site, systemImage: "globe")
            }
            .onDelete { draft.websites.remove(atOffsets: $0) }
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
                .disabled(websiteInput.trimmingCharacters(in: .whitespaces).isEmpty)
                .buttonStyle(.borderless)
                .accessibilityLabel("Add website")
            }
        } header: {
            Text("Websites")
        } footer: {
            if let websiteError {
                Text(websiteError).foregroundStyle(.red)
            } else {
                Text("Blocks the site and its subdomains in Safari and in-app browsers while this schedule is blocking.")
            }
        }
    }

    private var conditionSection: some View {
        Section {
            if draft.mode == .blocklist {
                Picker("Condition", selection: $draft.type.animation()) {
                    ForEach(ScheduleType.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            switch draft.type {
            case .time:
                TimeRail(start: draft.startMinutes, end: draft.endMinutes)
                Toggle("All day", isOn: allDayBinding.animation())
                if !draft.isAllDay {
                    DatePicker("From", selection: minuteBinding(\.startMinutes), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: minuteBinding(\.endMinutes), displayedComponents: .hourAndMinute)
                }
            case .usageLimit:
                Stepper(value: $draft.usageLimitMinutes, in: 5...(23 * 60 + 55), step: 5) {
                    HStack {
                        Text("Daily limit")
                        Spacer()
                        Text(TimeFormat.minutes(draft.usageLimitMinutes))
                            .font(.body.monospacedDigit().weight(.semibold))
                            .foregroundStyle(.tint)
                    }
                }
                HStack(spacing: 8) {
                    ForEach([15, 30, 60, 120], id: \.self) { minutes in
                        Button(TimeFormat.minutes(minutes)) { draft.usageLimitMinutes = minutes }
                            .buttonStyle(.bordered)
                            .tint(draft.usageLimitMinutes == minutes ? .accentColor : .secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderless)
            }
        } header: {
            Text("When to block")
        } footer: {
            Text(conditionFooter)
        }
    }

    private var conditionFooter: String {
        if let message = validationMessage { return message }
        switch draft.type {
        case .time:
            if draft.isOvernight { return "Ends the next morning. Overnight schedules count toward the day they start on." }
            return "Blocks during this window on the selected days."
        case .usageLimit:
            return "Blocks the selected apps once their combined use reaches the limit. Resets at midnight."
        }
    }

    // MARK: Bindings

    private var allDayBinding: Binding<Bool> {
        Binding {
            draft.isAllDay
        } set: { allDay in
            draft.startMinutes = allDay ? 0 : 9 * 60
            draft.endMinutes = allDay ? 1440 : 17 * 60
        }
    }

    private func minuteBinding(_ keyPath: WritableKeyPath<Schedule, Int>) -> Binding<Date> {
        Binding {
            let minutes = draft[keyPath: keyPath] % 1440
            return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: Date()) ?? Date()
        } set: { date in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
            var minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            // An end time of midnight means the end of the day.
            if keyPath == \Schedule.endMinutes, minutes == 0 { minutes = 1440 }
            draft[keyPath: keyPath] = minutes
        }
    }

    // MARK: Actions

    private var validationMessage: String? {
        if draft.daysMask & Schedule.allDays == 0 { return "Pick at least one day." }
        if draft.mode == .blocklist && !draft.hasTargets { return "Choose at least one app, category or website to block." }
        switch draft.type {
        case .time:
            if draft.windowMinutes == 0 { return "Start and end can't be the same time." }
            if draft.windowMinutes < Schedule.minimumWindowMinutes {
                return "iOS needs a window of at least \(Schedule.minimumWindowMinutes) minutes."
            }
        case .usageLimit:
            if draft.selection.isEmptySelection { return "Usage limits need apps or categories from the picker." }
            if draft.usageLimitMinutes <= 0 { return "Pick a daily limit." }
        }
        return nil
    }

    private func addWebsite() {
        let domain = WebPatterns.normalize(websiteInput)
        guard !domain.isEmpty else { return }
        guard WebPatterns.isDomain(domain) else {
            websiteError = "“\(websiteInput)” isn't a website. Try something like youtube.com."
            return
        }
        websiteError = nil
        if !draft.websites.contains(domain) { draft.websites.append(domain) }
        websiteInput = ""
    }

    private func save() {
        if !websiteInput.trimmingCharacters(in: .whitespaces).isEmpty { addWebsite() }
        guard validationMessage == nil else { return }
        model.saveSchedule(draft)
        dismiss()
    }
}
