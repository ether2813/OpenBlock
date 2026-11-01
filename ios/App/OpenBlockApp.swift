import SwiftUI

@main
struct OpenBlockApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .tint(model.state.accent.color)
                .preferredColorScheme(model.state.appearance.colorScheme)
                .onChange(of: scenePhase) { phase in
                    if phase == .active { model.appBecameActive() }
                }
                .onAppear { model.appBecameActive() }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        TabView(selection: $model.selectedTab) {
            BlockingHomeView()
                .tabItem { Label("Blocking", systemImage: "shield.lefthalf.filled") }
                .tag(MainTab.blocking)
            StrictHomeView()
                .tabItem { Label("Strict", systemImage: model.isStrictActive ? "lock.fill" : "lock.open") }
                .tag(MainTab.strict)
            InsightsView()
                .tabItem { Label("Insights", systemImage: "chart.bar.xaxis") }
                .tag(MainTab.insights)
            MoreView()
                .tabItem { Label("More", systemImage: "ellipsis.circle") }
                .tag(MainTab.more)
        }
        .banner($model.banner)
        .fullScreenCover(isPresented: .constant(!model.state.hasCompletedOnboarding)) {
            OnboardingView()
                .environmentObject(model)
                .tint(model.state.accent.color)
        }
    }
}

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 28) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                        .padding(.top, 56)
                    VStack(spacing: 8) {
                        Text("Welcome to OpenBlock")
                            .font(.largeTitle.bold())
                            .multilineTextAlignment(.center)
                        Text("Private, offline focus controls.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 22) {
                        feature("calendar.badge.clock", "Schedules", "Block apps and websites during set hours, or after a daily usage limit.")
                        feature("timer", "App limits", "Give single apps a daily time budget, or block them outright.")
                        feature("lock.fill", "Strict Mode", "Lock your blocks so you can't switch them off on impulse.")
                        feature("hand.raised.fill", "Private by design", "No accounts, no tracking, no internet. Everything stays on this iPhone.")
                    }
                    .padding(.horizontal, 8)
                }
                .padding(.horizontal, 24)
            }
            VStack(spacing: 12) {
                Button {
                    Task {
                        await model.requestAuthorization()
                        model.completeOnboarding()
                    }
                } label: {
                    Text("Allow Screen Time access").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Not now") { model.completeOnboarding() }
                    .font(.subheadline)
                Text("Apple asks for your Face ID or passcode. OpenBlock never sees your usage data — it stays inside Screen Time.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
        }
        .interactiveDismissDisabled()
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
