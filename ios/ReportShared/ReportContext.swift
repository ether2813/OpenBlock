import DeviceActivity
import SwiftUI

/// One report scene per period, so the report extension knows how many days it is drawing even
/// when some of them have no usage at all.
extension DeviceActivityReport.Context {
    static let insightsDay = Self("Insights.day")
    static let insightsWeek = Self("Insights.week")
    static let insightsTwoWeeks = Self("Insights.twoWeeks")
}
