import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showNotifications = false
    var openCheckIn: () -> Void = {}
    var openGrades: () -> Void = {}
    var openProfile: () -> Void = {}

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let errorMessage = appState.errorMessage {
                        BNBUErrorPanel(message: errorMessage) {
                            Task { await appState.refreshRemoteWorkspace() }
                        }
                    }
                    progressPanel
                    riskPanel
                    focusPlan
                    nextTasks
                }
                .padding(BNBUSpacing.screen)
            }
            .refreshable {
                await appState.refreshRemoteWorkspace()
            }
        }
        .accessibilityIdentifier("screen.dashboard")
        .sheet(isPresented: $showNotifications) {
            NotificationCenterSheet()
                .environmentObject(appState)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            BrandMark(compact: true)
            VStack(alignment: .leading, spacing: 5) {
                Text("你好，\(appState.workspace.student.name)")
                    .font(.title.weight(.medium))
                    .foregroundStyle(BNBUTheme.ink)
                Text("\(appState.workspace.student.college) · \(appState.workspace.student.displayStudentNumber)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BNBUTheme.muted)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                notificationButton
                StatusBadge(text: appState.workspace.progress.status, filled: true)
            }
        }
    }

    private var notificationButton: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: appState.unreadNoticeCount > 0 ? "bell.badge.fill" : "bell")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(BNBUTheme.onSurface)
                    .frame(width: 44, height: 44)
                    .background(BNBUTheme.surfaceVariant)
                    .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))

                if appState.unreadNoticeCount > 0 {
                    Text(appState.unreadNoticeCount > 99 ? "99+" : "\(appState.unreadNoticeCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(BNBUTheme.onPrimary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(BNBUTheme.primary)
                        .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboard.notifications.button")
        .accessibilityLabel("打开通知")
    }

    private var progressPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 18) {
                SectionTitle(eyebrow: "Sports Credit", title: "体育学时进度")

                HStack(alignment: .firstTextBaseline) {
                    Text(appState.totalCompleted.hourText)
                        .font(.system(size: 46, weight: .regular))
                    Text("/ \(appState.hourRule.total.hourText)")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(BNBUTheme.muted)
                    Spacer()
                    Text("\(Int(appState.completionRatio * 100))%")
                        .font(.title2.weight(.medium))
                        .foregroundStyle(BNBUTheme.blue)
                }

                HourProgressBar(value: appState.totalCompleted, total: appState.hourRule.total)

                VStack(spacing: 14) {
                    ProgressLine(
                        title: "课程相关",
                        value: appState.workspace.progress.course,
                        total: appState.hourRule.courseRequired,
                        detail: "还差 \(appState.courseRemaining.hourText)"
                    )
                    ProgressLine(
                        title: "其他运动",
                        value: appState.workspace.progress.general,
                        total: appState.hourRule.generalRequired,
                        detail: appState.generalRemaining == 0 ? "已完成" : "还差 \(appState.generalRemaining.hourText)"
                    )
                }
            }
        }
    }

    private var riskPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text(hasHourRisk ? "当前风险提示" : "当前状态稳定")
                    .font(.headline.weight(.medium))
                Text(riskText)
                    .font(.subheadline.weight(.regular))
                    .foregroundStyle(BNBUTheme.muted)
                    .lineSpacing(3)
            }
        }
    }

    private var nextTasks: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(eyebrow: "Deadline", title: "近期任务")
            if appState.activeTasks.isEmpty {
                EmptyPlaceholder(title: "暂无近期任务", message: "当前没有进行中的打卡任务；新任务发布后会在这里显示。")
            } else {
                ForEach(appState.activeTasks.prefix(2)) { task in
                    TaskRow(task: task)
                }
            }
        }
    }

    private var focusPlan: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(eyebrow: "Plan", title: "本周行动计划")

            SwissPanel {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(focusPlanItems) { item in
                        FocusPlanRow(item: item)
                    }
                }
            }
        }
    }

    private var focusPlanItems: [FocusPlanItem] {
        var items: [FocusPlanItem] = []
        if appState.courseRemaining > 0 {
            items.append(
                FocusPlanItem(
                    title: "优先补齐课程相关 \(appState.courseRemaining.hourText)",
                    detail: appState.activeTasks.isEmpty ? "课程相关不能被组织抵扣替代；当前暂无可提交任务，请等待老师发布。" : "课程相关不能被组织抵扣替代，建议先完成 GEPE101 相关任务。",
                    systemImage: "target",
                    status: "高优先级"
                )
            )
        }
        if items.isEmpty {
            items.append(
                FocusPlanItem(
                    title: "当前没有阻塞事项",
                    detail: "保持运动记录连续性，关注下一次课程任务发布。",
                    systemImage: "checkmark.seal",
                    status: "稳定"
                )
            )
        }
        return Array(items.prefix(4))
    }

    private var hasHourRisk: Bool {
        appState.courseRemaining > 0 || appState.generalRemaining > 0
    }

    private var riskText: String {
        if appState.courseRemaining > 0 && appState.generalRemaining > 0 {
            return "课程相关还差 \(appState.courseRemaining.hourText)，其他运动还差 \(appState.generalRemaining.hourText)。请优先关注课程任务和可计入的自主运动。"
        }
        if appState.courseRemaining > 0 {
            return "课程相关还差 \(appState.courseRemaining.hourText)。其他运动已由组织认证完成，但不能替代课程相关学时。"
        }
        if appState.generalRemaining > 0 {
            return "其他运动还差 \(appState.generalRemaining.hourText)。可通过自主运动打卡或有效组织认证完成。"
        }
        return "课程相关与其他运动均达到本学期要求，请继续关注课程任务和成绩缺失项。"
    }

}

private struct FocusPlanItem: Identifiable, Hashable {
    var id: String { title }
    let title: String
    let detail: String
    let systemImage: String
    let status: String
}

private struct FocusPlanRow: View {
    let item: FocusPlanItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: item.systemImage)
                .font(.headline.weight(.medium))
                .foregroundStyle(BNBUTheme.blue)
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(item.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BNBUTheme.ink)
                    Spacer()
                    StatusBadge(text: item.status)
                }
                Text(item.detail)
                    .font(.caption.weight(.regular))
                    .foregroundStyle(BNBUTheme.muted)
                    .lineSpacing(2)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct ActionMiniMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.caption2.weight(.medium))
                .foregroundStyle(BNBUTheme.muted)
            Text(value)
                .font(.title3.weight(.medium))
                .foregroundStyle(BNBUTheme.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(BNBUTheme.blueSoft)
        .bnbuOutlinedSurface()
    }
}

private struct DashboardShortcutButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
                .foregroundStyle(BNBUTheme.surface)
                .background(BNBUTheme.ink)
        }
        .buttonStyle(.plain)
    }
}

private struct ProgressLine: View {
    let title: String
    let value: Double
    let total: Double
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Spacer()
                Text("\(value.hourText) / \(total.hourText)")
                    .font(.subheadline.weight(.medium))
                StatusBadge(text: detail)
            }
            HourProgressBar(value: value, total: total)
        }
    }
}

struct TaskRow: View {
    let task: CourseTask

    var body: some View {
        SwissPanel {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: task.creditType.symbolName)
                    .font(.title2.weight(.medium))
                    .frame(width: 32)
                    .foregroundStyle(BNBUTheme.blue)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(task.title)
                            .font(.headline.weight(.medium))
                        Spacer()
                        StatusBadge(text: task.creditType.rawValue)
                    }
                    Text("截止：\(task.deadline)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BNBUTheme.ink)
                    Text("证明：\(task.proof)")
                        .font(.caption.weight(.regular))
                        .foregroundStyle(BNBUTheme.muted)
                }
            }
        }
    }
}

struct NoticeRow: View {
    let notice: StudentNotice

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(notice.category.rawValue, systemImage: notice.category.symbolName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BNBUTheme.blue)
                    Spacer()
                    if notice.isUnread {
                        Circle()
                            .fill(BNBUTheme.blue)
                            .frame(width: 9, height: 9)
                    }
                }

                HStack(alignment: .firstTextBaseline) {
                    Text(notice.title)
                        .font(.headline.weight(.medium))
                        .foregroundStyle(BNBUTheme.ink)
                    Spacer()
                    StatusBadge(text: notice.time)
                }
                Text(notice.message)
                    .font(.subheadline.weight(.regular))
                    .foregroundStyle(BNBUTheme.muted)
            }
        }
    }
}

private enum DashboardNotificationFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case unread = "未读"
    case deadline = "截止提醒"
    case application = "申请与材料"

    var id: String { rawValue }
}

private struct NotificationCenterSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var selectedFilter: DashboardNotificationFilter = .all

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Label("通知", systemImage: appState.unreadNoticeCount > 0 ? "bell.badge.fill" : "bell")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    StatusBadge(text: appState.unreadNoticeCount > 0 ? "\(appState.unreadNoticeCount) 条未读" : "暂无未读")
                }

                HStack {
                    Spacer()
                    Button("全部标为已读") {
                        appState.markAllNoticesRead()
                    }
                    .font(.subheadline.weight(.medium))
                    .disabled(appState.unreadNoticeCount == 0)
                }

                Picker("通知筛选", selection: $selectedFilter) {
                    ForEach(DashboardNotificationFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }
                .pickerStyle(.segmented)

                if filteredNotices.isEmpty {
                    EmptyPlaceholder(title: "暂无通知", message: "当前筛选条件下没有通知。")
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredNotices) { notice in
                                NavigationLink {
                                    NoticeDetailView(notice: notice)
                                } label: {
                                    NoticeRow(notice: notice)
                                }
                                .buttonStyle(.plain)
                                .simultaneousGesture(TapGesture().onEnded {
                                    if notice.isUnread {
                                        appState.markNoticeRead(id: notice.id)
                                    }
                                })
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, BNBUSpacing.screen)
            .padding(.top, 8)
            .background(BNBUTheme.background)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var filteredNotices: [StudentNotice] {
        appState.workspace.notices.filter { notice in
            switch selectedFilter {
            case .all:
                return true
            case .unread:
                return notice.isUnread
            case .deadline:
                return notice.category == .deadline
            case .application:
                return notice.category == .review
            }
        }
    }
}
