import DeviceActivity
import FamilyControls
import SwiftUI

enum InsightPeriod: String, CaseIterable, Identifiable {
    case day, week, twoWeeks

    var id: Self { self }

    var title: String {
        switch self {
        case .day: return "Today"
        case .week: return "Week"
        case .twoWeeks: return "2 Weeks"
        }
    }

    var days: Int {
        switch self {
        case .day: return 1
        case .week: return 7
        case .twoWeeks: return 14
        }
    }
}

struct InsightsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var period: InsightPeriod = .day

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Period", selection: $period) {
                    ForEach(InsightPeriod.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                if model.isAuthorized {
                    // The report is drawn by the Screen Time report extension; usage data never
                    // reaches the app itself.
                    DeviceActivityReport(.insights, filter: filter)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .id(period)
                } else {
                    List { Section { ScreenTimeSetupCard() } }
                        .listStyle(.insetGrouped)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Insights")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    NavigationLink {
                        InsightSettingsView()
                    } label: {
                        Label("Insight settings", systemImage: "slider.horizontal.3")
                    }
                }
            }
        }
    }

    private var filter: DeviceActivityFilter {
        let calendar = Calendar.current
        let now = Date()
        let start = calendar.date(byAdding: .day, value: -(period.days - 1), to: calendar.startOfDay(for: now)) ?? now
        return DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: now)),
            users: .all,
            devices: .init([.iPhone, .iPad])
        )
    }
}

struct InsightSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showPicker = false
    @State private var selection = FamilyActivitySelection()

    var body: some View {
        Form {
            Section {
                Button {
                    selection = model.state.hiddenFromInsights
                    showPicker = true
                } label: {
                    HStack {
                        Text("Hidden apps").foregroundStyle(.primary)
                        Spacer()
                        Text(model.state.hiddenFromInsights.isEmptySelection ? "None" : model.state.hiddenFromInsights.summary)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right").font(.footnote.weight(.semibold)).foregroundStyle(.tertiary)
                    }
                }
                if !model.state.hiddenFromInsights.isEmptySelection {
                    SelectionPreview(selection: model.state.hiddenFromInsights, limit: 8)
                }
            } footer: {
                Text("Hidden apps are left out of Insights but still count toward limits. Screen Time data never leaves this iPhone.")
            }
        }
        .navigationTitle("Insight Settings")
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(isPresented: $showPicker, selection: $selection)
        .onChange(of: showPicker) { presented in
            if !presented, selection != model.state.hiddenFromInsights {
                model.setHiddenFromInsights(selection)
            }
        }
    }
}
