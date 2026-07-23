import SwiftUI

enum AppTab: String, CaseIterable, Identifiable {
    case dashboard = "首页"
    case courses = "课程"
    case checkin = "打卡"
    case grades = "成绩"
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
        TabView(selection: $selectedTab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    tabContent(for: tab)
                }
                .accessibilityIdentifier(tab.accessibilityIdentifier)
                .tag(tab)
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            StudentBottomBar(selectedTab: $selectedTab)
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
            DashboardView(
                openCheckIn: { selectedTab = .checkin },
                openGrades: { selectedTab = .grades },
                openProfile: { selectedTab = .profile }
            )
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

private struct StudentBottomBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.24)) {
                        selectedTab = tab
                    }
                } label: {
                    VStack(spacing: 4) {
                        Group {
                            if tab == .dashboard {
                                Image("bnbu_emblem")
                                    .resizable()
                                    .scaledToFit()
                                    .padding(4)
                            } else {
                                Image(systemName: tab.systemImage)
                                    .font(.system(size: 21, weight: .medium))
                            }
                        }
                        .frame(width: 54, height: 30)
                        .background(selectedTab == tab ? BNBUTheme.primaryContainer : Color.clear)
                        .clipShape(Capsule())
                        Text(LocalizedStringKey(tab.rawValue))
                            .font(.caption2.weight(.medium))
                    }
                    .foregroundStyle(selectedTab == tab ? BNBUTheme.onSurface : BNBUTheme.onSurfaceVariant)
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(tab.accessibilityIdentifier)
                .accessibilityLabel(Text(LocalizedStringKey(tab.rawValue)))
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(BNBUTheme.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(BNBUTheme.outline.opacity(0.18))
                .frame(height: 0.5)
        }
    }

}
