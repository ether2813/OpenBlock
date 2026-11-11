import FamilyControls
import SwiftUI

struct BlockingHomeView: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: Schedule?
    @State private var pendingDelete: Schedule?

    var body: some View {
        NavigationStack {
            List {
                if !model.isAuthorized {
                    Section { ScreenTimeSetupCard() }
                }

                if model.isStrictActive {
                    Section {
                        Button { model.selectedTab = .strict } label: {
                            HStack(spacing: 12) {
                                IconBadge(symbol: "lock.fill", color: .accentColor, size: 34)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Strict Mode is on").font(.headline).foregroundStyle(.primary)
                                    // Its own clock, so the countdown ticks without redrawing the list.
                                    TimelineView(.periodic(from: .now, by: 1)) { context in
                                        Text(StrictStatus.line(for: model.state.strict, now: context.date, charging: model.isCharging))
                                            .font(.subheadline.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                Section {
                    if model.state.schedules.isEmpty {
                        EmptyStateRow(
                            symbol: "calendar.badge.plus",
                            title: "No schedules yet",
                            message: "Block apps and websites during set hours, or cap how long you use them each day.",
                            actionTitle: "Create a schedule"
                        ) { startNewSchedule() }
                    } else {
                        ForEach(model.state.schedules) { schedule in
                            ScheduleRow(schedule: schedule, isBlocking: model.isBlocking(schedule), clock: model.clock) {
                                model.setScheduleEnabled(schedule.id, $0)
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { edit(schedule) }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { pendingDelete = schedule } label: { Label("Delete", systemImage: "trash") }
                                Button { model.duplicateSchedule(schedule.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                    .tint(.indigo)
                            }
                            .contextMenu {
                                Button { edit(schedule) } label: { Label("Edit", systemImage: "pencil") }
                                Button { model.duplicateSchedule(schedule.id) } label: { Label("Duplicate", systemImage: "plus.square.on.square") }
                                Button(role: .destructive) { pendingDelete = schedule } label: { Label("Delete", systemImage: "trash") }
                            }
                        }
                    }
                } header: {
                    Text("Schedules")
                }

                Section {
                    AppLimitsSummary()
                } header: {
                    Text("App limits & websites")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Blocking")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { startNewSchedule() } label: { Label("New schedule", systemImage: "plus") }
                }
            }
            .sheet(item: $editing) { schedule in
                ScheduleEditorView(schedule: schedule, isNew: !model.state.schedules.contains { $0.id == schedule.id })
                    .environmentObject(model)
            }
            .confirmationDialog(
                "Delete \(pendingDelete?.displayName ?? "schedule")?",
                isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("Delete Schedule", role: .destructive) {
                    if let id = pendingDelete?.id { model.deleteSchedule(id) }
                    pendingDelete = nil
                }
            }
        }
    }

    private func startNewSchedule() {
        editing = Schedule()
    }

    private func edit(_ schedule: Schedule) {
        guard model.canEditSchedule() else { return }
        editing = schedule
    }
}

struct ScheduleRow: View {
    var schedule: Schedule
    var isBlocking: Bool
    var clock: Clock
    var onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(
                symbol: schedule.type.symbol,
                color: schedule.enabled ? (isBlocking ? .accentColor : .gray) : Color(.systemGray3),
                size: 34
            )
            .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(schedule.displayName)
                    .font(.headline)
                    .foregroundStyle(schedule.enabled ? .primary : .secondary)
                    .lineLimit(1)
                Text("\(schedule.mode.title) · \(ScheduleText.condition(schedule))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(TimeFormat.days(schedule.daysMask)) · \(ScheduleText.targets(schedule))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                let status = ScheduleText.status(schedule, isBlocking: isBlocking, clock: clock)
                StatusLabel(text: status.text, color: status.color)
                    .padding(.top, 2)
            }
            Spacer(minLength: 8)
            Toggle("Enabled", isOn: Binding(get: { schedule.enabled }, set: onToggle))
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

enum ScheduleText {
    static func condition(_ schedule: Schedule) -> String {
        switch schedule.type {
        case .usageLimit: return "Up to \(TimeFormat.minutes(schedule.usageLimitMinutes)) a day"
        case .time: return schedule.isAllDay ? "All day" : "\(TimeFormat.clock(schedule.startMinutes)) – \(TimeFormat.clock(schedule.endMinutes))"
        }
    }

    static func targets(_ schedule: Schedule) -> String {
        if schedule.mode == .allowlist {
            let count = schedule.selection.applicationTokens.count
            return count == 0 ? "All apps blocked" : "\(TimeFormat.plural(count, "app")) allowed"
        }
        var parts: [String] = []
        let picked = schedule.selection.summary
        if !picked.isEmpty { parts.append(picked) }
        if !schedule.websites.isEmpty { parts.append(TimeFormat.plural(schedule.websites.count, "site")) }
        return parts.isEmpty ? "Nothing selected" : parts.joined(separator: ", ")
    }

    static func status(_ schedule: Schedule, isBlocking: Bool, clock: Clock) -> (text: String, color: Color) {
        guard schedule.enabled else { return ("Paused", .secondary) }
        switch schedule.type {
        case .time:
            if isBlocking {
                return (schedule.isAllDay ? "Blocking now · all day" : "Blocking now · until \(TimeFormat.clock(schedule.endMinutes))", .accentColor)
            }
            if schedule.isActiveDay(clock.day), schedule.startMinutes > clock.minute {
                return ("Starts at \(TimeFormat.clock(schedule.startMinutes))", .secondary)
            }
            return ("Not active right now", .secondary)
        case .usageLimit:
            if !schedule.isActiveDay(clock.day) { return ("Not active today", .secondary) }
            return isBlocking ? ("Limit reached · blocking now", .red) : ("Counting usage today", .accentColor)
        }
    }
}

private struct AppLimitsSummary: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let limits = model.state.appLimits
        let websites = model.state.globalWebsites
        if limits.isEmpty && websites.isEmpty {
            NavigationLink {
                AppLimitsView()
            } label: {
                HStack(spacing: 12) {
                    IconBadge(symbol: "timer", color: .orange, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add app limits").font(.headline)
                        Text("Give apps a daily time limit, or always block apps and websites.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        } else {
            ForEach(limits.prefix(4)) { limit in
                NavigationLink {
                    AppLimitsView()
                } label: {
                    HStack {
                        LimitTargetLabel(target: limit.target)
                            .lineLimit(1)
                            .foregroundStyle(limit.enabled ? .primary : .secondary)
                        Spacer()
                        Text(limit.enabled ? AppLimit.label(for: limit.limitMinutes) : "Paused")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            NavigationLink {
                AppLimitsView()
            } label: {
                let more = max(0, limits.count - 4)
                let parts = [
                    more > 0 ? "\(more) more" : nil,
                    websites.isEmpty ? nil : TimeFormat.plural(websites.count, "website")
                ].compactMap { $0 }
                Text(parts.isEmpty ? "Manage" : "Manage · " + parts.joined(separator: " · "))
                    .foregroundStyle(.tint)
            }
        }
    }
}
