import SwiftUI
#if canImport(StatusPanel)
import StatusPanel
import MenuBarPanel
import ActivityPanel
import CalendarPanel
import PRPanel
import AIUsagePanel
#endif

// Each popup design by name, for the bar and for the design thumbnails
// in the settings window. The default design comes first. Keep the names
// in sync with the switches below.
public let panelDesignNames: [String: [(value: String?, title: String)]] = [
    "status": [(nil, "Gauge"), ("control-center", "Control Center"), ("settings", "Settings")],
    "menubar": [(nil, "List"), ("grid", "Grid"), ("dock", "Dock")],
    "activity": [(nil, "Monitor"), ("widgets", "Widgets"), ("top", "Top")],
    "clock": [(nil, "Timeline"), ("up-next", "Up Next"), ("month", "Month")],
    "github-prs": [(nil, "Inbox"), ("reminders", "Reminders"), ("tracker", "Tracker")],
    "ai-usage": [(nil, "Rings"), ("screen-time", "Screen Time"), ("forecast", "Forecast")],
]

public func statusPanel(_ design: String?, _ report: StatusReport, _ actions: StatusActions) -> AnyView {
    switch design {
    case "control-center": return AnyView(ControlCenterStatusPanel(report: report, actions: actions))
    case "settings": return AnyView(SettingsStatusPanel(report: report, actions: actions))
    default: return AnyView(GaugeStatusPanel(report: report, actions: actions))
    }
}

public func menuBarPanel(_ design: String?, _ report: MenuBarReport, _ actions: MenuBarActions) -> AnyView {
    switch design {
    case "grid": return AnyView(GridMenuBarPanel(report: report, actions: actions))
    case "dock": return AnyView(DockMenuBarPanel(report: report, actions: actions))
    default: return AnyView(ListMenuBarPanel(report: report, actions: actions))
    }
}

public func activityPanel(_ design: String?, _ report: ActivityReport, _ actions: ActivityActions) -> AnyView {
    switch design {
    case "widgets": return AnyView(WidgetsActivityPanel(report: report, actions: actions))
    case "top": return AnyView(TopActivityPanel(report: report, actions: actions))
    default: return AnyView(MonitorActivityPanel(report: report, actions: actions))
    }
}

public func calendarPanel(_ design: String?, _ report: CalendarReport, _ actions: CalendarActions) -> AnyView {
    switch design {
    case "up-next": return AnyView(UpNextCalendarPanel(report: report, actions: actions))
    case "month": return AnyView(MonthCalendarPanel(report: report, actions: actions))
    default: return AnyView(TimelineCalendarPanel(report: report, actions: actions))
    }
}

public func prPanel(_ design: String?, _ report: PRReport, _ actions: PRActions) -> AnyView {
    switch design {
    case "reminders": return AnyView(RemindersPRPanel(report: report, actions: actions))
    case "tracker": return AnyView(TrackerPRPanel(report: report, actions: actions))
    default: return AnyView(InboxPRPanel(report: report, actions: actions))
    }
}

public func aiUsagePanel(_ design: String?, _ report: AIUsageReport, _ actions: AIUsageActions) -> AnyView {
    switch design {
    case "screen-time": return AnyView(ScreenTimeAIUsagePanel(report: report, actions: actions))
    case "forecast": return AnyView(ForecastAIUsagePanel(report: report, actions: actions))
    default: return AnyView(RingsAIUsagePanel(report: report, actions: actions))
    }
}

// A design drawn with the sample data of the Xcode previews, and buttons
// that do nothing, for the settings window.
public func designPreview(kind: String, design: String?) -> AnyView? {
    switch kind {
    case "status": return statusPanel(design, .onBattery, .init())
    case "menubar": return menuBarPanel(design, .busy, .init())
    case "activity": return activityPanel(design, .building, .init())
    case "clock": return calendarPanel(design, .busy, .init())
    case "github-prs": return prPanel(design, .busy, .init())
    case "ai-usage": return aiUsagePanel(design, .busy, .init())
    default: return nil
    }
}
