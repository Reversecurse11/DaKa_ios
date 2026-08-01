import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case dashboard = "首页"
    case courses = "课程"
    case checkin = "打卡"
    case grades = "运动进度"
    case profile = "我的"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .dashboard: return "rectangle.grid.2x2"
        case .courses: return "book.closed"
        case .checkin: return "plus.app"
        case .grades: return "chart.bar.xaxis"
        case .profile: return "person.crop.circle"
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .dashboard: return "tab.dashboard"
        case .courses: return "tab.courses"
        case .checkin: return "tab.checkin"
        case .grades: return "tab.grades"
        case .profile: return "tab.profile"
        }
    }
}

struct AppRootView: View {
    @State private var selectedTab: AppTab = .dashboard

    var body: some View {
        if #available(iOS 26.0, *) {
            tabs
                .tabBarMinimizeBehavior(.never)
        } else {
            tabs
        }
    }

    private var tabs: some View {
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    tabContent(for: tab)
                }
                .tabItem {
                    Label {
                        Text(LocalizedStringKey(tab.rawValue))
                    } icon: {
                        if tab == .dashboard {
                            Image("bnbu_emblem")
                        } else {
                            Image(systemName: tab.systemImage)
                        }
                    }
                    .accessibilityIdentifier(tab.accessibilityIdentifier)
                }
                .tag(tab)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bnbuOpenDestination)) { notification in
            if let destination = notification.object as? AppTab {
                selectedTab = destination
            }
        }
    }

    @ViewBuilder
    private func tabContent(for tab: AppTab) -> some View {
        switch tab {
        case .dashboard:
            DashboardView(openCheckIn: { selectedTab = .checkin })
        case .courses:
            CoursesView()
        case .checkin:
            CheckInView()
        case .grades:
            GradesView()
        case .profile:
            ProfileView()
        }
    }

}
