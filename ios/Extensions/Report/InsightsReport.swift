import Charts
import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI
import UIKit

@main
struct OpenBlockReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        InsightsReport(context: .insightsDay, periodDays: 1) { InsightsReportView(summary: $0) }
        InsightsReport(context: .insightsWeek, periodDays: 7) { InsightsReportView(summary: $0) }
        InsightsReport(context: .insightsTwoWeeks, periodDays: 14) { InsightsReportView(summary: $0) }
    }
}

struct InsightsSummary {
    struct Day: Identifiable {
        var date: Date
        var duration: TimeInterval
        var id: Date { date }
    }

    struct AppUsage: Identifiable {
        var id: String
        var token: ApplicationToken?
        var name: String
        var duration: TimeInterval
        var pickups: Int
    }

    var periodDays = 1
    var total: TimeInterval = 0
    /// One entry per day of the period, oldest first, including days without any usage.
    var days: [Day] = []
    var apps: [AppUsage] = []
    var pickups = 0
    var accent: AccentTheme = .sky

    var dailyAverage: TimeInterval { total / Double(max(1, periodDays)) }
}

struct InsightsReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context
    let periodDays: Int
    let content: (InsightsSummary) -> InsightsReportView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> InsightsSummary {
        let state = SharedStore.loadState()
        let hiddenApps = state.hiddenFromInsights.applicationTokens
        let hiddenCategories = state.hiddenFromInsights.categoryTokens
        let calendar = Calendar.current
        var dayTotals: [Date: TimeInterval] = [:]
        var apps: [String: InsightsSummary.AppUsage] = [:]
        var pickups = 0

        for await deviceData in data {
            for await segment in deviceData.activitySegments {
                let day = calendar.startOfDay(for: segment.dateInterval.start)
                var segmentTotal = segment.totalActivityDuration
                for await category in segment.categories {
                    if let token = category.category.token, hiddenCategories.contains(token) {
                        segmentTotal -= category.totalActivityDuration
                        continue
                    }
                    for await activity in category.applications {
                        let token = activity.application.token
                        if let token, hiddenApps.contains(token) {
                            segmentTotal -= activity.totalActivityDuration
                            continue
                        }
                        let name = activity.application.localizedDisplayName ?? activity.application.bundleIdentifier ?? "App"
                        // The token identifies an app reliably; names and bundle IDs can be missing.
                        let key = token.map { "token.\($0.hashValue)" } ?? activity.application.bundleIdentifier ?? name
                        var usage = apps[key] ?? .init(id: key, token: token, name: name, duration: 0, pickups: 0)
                        usage.duration += activity.totalActivityDuration
                        usage.pickups += activity.numberOfPickups
                        apps[key] = usage
                        pickups += activity.numberOfPickups
                    }
                }
                dayTotals[day, default: 0] += max(0, segmentTotal)
            }
        }

        var summary = InsightsSummary()
        summary.periodDays = periodDays
        let today = calendar.startOfDay(for: Date())
        summary.days = (0..<periodDays).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { InsightsSummary.Day(date: $0, duration: dayTotals[$0] ?? 0) }
        }
        summary.total = summary.days.reduce(0) { $0 + $1.duration }
        summary.apps = apps.values.filter { $0.duration >= 60 }.sorted { $0.duration > $1.duration }.prefix(12).map { $0 }
        summary.pickups = pickups
        summary.accent = state.accent
        return summary
    }
}

struct InsightsReportView: View {
    let summary: InsightsSummary

    private var isSingleDay: Bool { summary.periodDays <= 1 }

    private var accent: Color {
        let (light, dark) = summary.accent.accentHex
        return Color(uiColor: UIColor { traits in
            let hex = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(
                red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1
            )
        })
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 4) {
                    Text(isSingleDay ? "SCREEN TIME TODAY" : "PAST \(summary.periodDays) DAYS")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                    Text(TimeFormat.duration(summary.total))
                        .font(.system(size: 44, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(isSingleDay ? "\(summary.pickups) pickups" : "Daily average \(TimeFormat.duration(summary.dailyAverage))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)

                if !isSingleDay, summary.total > 0 {
                    Chart {
                        ForEach(summary.days) { day in
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Hours", day.duration / 3600)
                            )
                            .foregroundStyle(accent.gradient)
                            .cornerRadius(4)
                        }
                        // Drawn once, not once per bar.
                        RuleMark(y: .value("Average", summary.dailyAverage / 3600))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .day, count: summary.periodDays > 7 ? 2 : 1)) { _ in
                            AxisValueLabel(format: summary.periodDays > 7 ? Date.FormatStyle.dateTime.day() : Date.FormatStyle.dateTime.weekday(.narrow))
                        }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let hours = value.as(Double.self) {
                                    // Short days get gridlines below an hour; label those in minutes.
                                    Text(hours > 0 && hours < 1 ? "\(Int((hours * 60).rounded()))m" : "\(Int(hours))h")
                                }
                            }
                        }
                    }
                    .frame(height: 170)
                    .padding(.vertical, 6)
                }
            }

            Section {
                if summary.apps.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "chart.bar").font(.title2).foregroundStyle(.tint)
                        Text("Nothing tracked yet").font(.headline)
                        Text("Screen Time usage appears here. It never leaves this iPhone.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                } else {
                    let top = summary.apps.first?.duration ?? 1
                    ForEach(summary.apps) { app in
                        HStack(spacing: 12) {
                            Group {
                                if let token = app.token {
                                    Label(token).labelStyle(.iconOnly)
                                } else {
                                    Image(systemName: "app.fill").foregroundStyle(.secondary)
                                }
                            }
                            .frame(width: 30, height: 30)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(app.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                                    Spacer()
                                    Text(TimeFormat.duration(app.duration))
                                        .font(.subheadline.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                }
                                GeometryReader { proxy in
                                    ZStack(alignment: .leading) {
                                        Capsule().fill(Color(.tertiarySystemFill))
                                        Capsule()
                                            .fill(accent)
                                            .frame(width: max(4, proxy.size.width * app.duration / top))
                                    }
                                }
                                .frame(height: 5)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } header: {
                Text("Most used apps")
            }
        }
        .listStyle(.insetGrouped)
        .tint(accent)
    }
}
