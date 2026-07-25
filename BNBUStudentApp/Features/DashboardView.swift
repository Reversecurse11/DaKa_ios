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
                    recentRecords
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
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                headerIdentity
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    notificationButton
                    StatusBadge(text: progressStatusText, filled: true)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                headerIdentity
                HStack(spacing: 10) {
                    StatusBadge(text: progressStatusText, filled: true)
                    Spacer()
                    notificationButton
                }
            }
        }
    }

    private var headerIdentity: some View {
        HStack(alignment: .top, spacing: 14) {
            BrandMark(compact: true)
            VStack(alignment: .leading, spacing: 5) {
                Text("你好，\(appState.workspace.student.name)")
                    .font(.title.weight(.medium))
                    .foregroundStyle(BNBUTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("\(appState.workspace.student.college) · \(appState.workspace.student.displayStudentNumber)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BNBUTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
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

                ViewThatFits(in: .horizontal) {
                    progressTotalLine
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: appState.totalCompleted.localizedHourText)
                                .font(.system(size: 42, weight: .regular))
                            Text(verbatim: "/ \(appState.hourRule.total.localizedHourText)")
                                .font(.title3.weight(.medium))
                                .foregroundStyle(BNBUTheme.muted)
                        }
                        Text("\(Int(appState.completionRatio * 100))%")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(BNBUTheme.blue)
                    }
                }

                HourProgressBar(value: appState.totalCompleted, total: appState.hourRule.total)

                VStack(spacing: 14) {
                    ProgressLine(
                        title: "课程相关",
                        value: appState.workspace.progress.course,
                        total: appState.hourRule.courseRequired,
                        detail: BNBUL10n.formatted(
                            "还差 %@",
                            appState.courseRemaining.localizedHourText
                        )
                    )
                    ProgressLine(
                        title: "其他运动",
                        value: appState.workspace.progress.general,
                        total: appState.hourRule.generalRequired,
                        detail: appState.generalRemaining == 0
                            ? BNBUL10n.text("已完成")
                            : BNBUL10n.formatted(
                                "还差 %@",
                                appState.generalRemaining.localizedHourText
                            )
                    )
                }
            }
        }
    }

    private var progressTotalLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(verbatim: appState.totalCompleted.localizedHourText)
                .font(.system(size: 46, weight: .regular))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(verbatim: "/ \(appState.hourRule.total.localizedHourText)")
                .font(.title3.weight(.medium))
                .foregroundStyle(BNBUTheme.muted)
            Spacer(minLength: 8)
            Text("\(Int(appState.completionRatio * 100))%")
                .font(.title2.weight(.medium))
                .foregroundStyle(BNBUTheme.blue)
        }
    }

    private var riskPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text(LocalizedStringKey(hasHourRisk ? "当前风险提示" : "当前状态稳定"))
                    .font(.headline.weight(.medium))
                Text(verbatim: riskText)
                    .font(.subheadline.weight(.regular))
                    .foregroundStyle(BNBUTheme.muted)
                    .lineSpacing(3)
            }
        }
    }

    private var recentRecords: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(eyebrow: "Recent", title: "最近打卡")
            if appState.submittedCheckInRecords.isEmpty {
                EmptyPlaceholder(title: "暂无打卡记录", message: "完成一次不少于 1 小时的运动并提交后，记录会显示在这里。")
            } else {
                ForEach(appState.submittedCheckInRecords.prefix(2)) { record in
                    NavigationLink {
                        RecordDetailView(record: record)
                    } label: {
                        RecordCard(record: record)
                    }
                    .buttonStyle(.plain)
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
                    title: BNBUL10n.formatted(
                        "优先补齐课程相关 %@",
                        appState.courseRemaining.localizedHourText
                    ),
                    detail: BNBUL10n.text("课程相关不能被组织抵扣替代，建议在课程相关运动中完成计时打卡。"),
                    systemImage: "target",
                    status: BNBUL10n.text("高优先级")
                )
            )
        }
        if items.isEmpty {
            items.append(
                FocusPlanItem(
                    title: BNBUL10n.text("当前没有阻塞事项"),
                    detail: BNBUL10n.text("保持运动记录连续性，关注下一次课程任务发布。"),
                    systemImage: "checkmark.seal",
                    status: BNBUL10n.text("稳定")
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
            return BNBUL10n.formatted(
                "课程相关还差 %@，其他运动还差 %@。请优先关注课程任务和可计入的自主运动。",
                appState.courseRemaining.localizedHourText,
                appState.generalRemaining.localizedHourText
            )
        }
        if appState.courseRemaining > 0 {
            return BNBUL10n.formatted(
                "课程相关还差 %@。其他运动已由组织认证完成，但不能替代课程相关学时。",
                appState.courseRemaining.localizedHourText
            )
        }
        if appState.generalRemaining > 0 {
            return BNBUL10n.formatted(
                "其他运动还差 %@。可通过自主运动打卡或有效组织认证完成。",
                appState.generalRemaining.localizedHourText
            )
        }
        return BNBUL10n.text("课程相关与其他运动均达到本学期要求，请继续关注课程任务和成绩缺失项。")
    }

    private var progressStatusText: String {
        if appState.courseRemaining > 0 {
            return BNBUL10n.formatted(
                "课程还差 %@",
                appState.courseRemaining.localizedHourText
            )
        }
        if appState.generalRemaining > 0 {
            return BNBUL10n.formatted(
                "其他运动还差 %@",
                appState.generalRemaining.localizedHourText
            )
        }
        return BNBUL10n.text("全部学时已完成")
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
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(verbatim: item.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(BNBUTheme.ink)
                        Spacer()
                        StatusBadge(text: item.status)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: item.title)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(BNBUTheme.ink)
                        StatusBadge(text: item.status)
                    }
                }
                Text(verbatim: item.detail)
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
            Text(LocalizedStringKey(label))
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
            Label {
                Text(LocalizedStringKey(title))
            } icon: {
                Image(systemName: systemImage)
            }
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
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text(LocalizedStringKey(title))
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text(verbatim: "\(value.localizedHourText) / \(total.localizedHourText)")
                        .font(.subheadline.weight(.medium))
                    StatusBadge(text: detail)
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey(title))
                        .font(.subheadline.weight(.medium))
                    HStack {
                        Text(verbatim: "\(value.localizedHourText) / \(total.localizedHourText)")
                            .font(.subheadline.weight(.medium))
                        Spacer()
                        StatusBadge(text: detail)
                    }
                }
            }
            HourProgressBar(value: value, total: total)
        }
    }
}

struct NoticeRow: View {
    let notice: StudentNotice

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label {
                        Text(LocalizedStringKey(notice.category.rawValue))
                    } icon: {
                        Image(systemName: notice.category.symbolName)
                    }
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
                    StatusBadge(text: unreadBadgeText)
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
                        Text(LocalizedStringKey(filter.rawValue)).tag(filter)
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

    private var unreadBadgeText: String {
        let count = appState.unreadNoticeCount
        if count == 0 {
            return BNBUL10n.text("暂无未读")
        }
        if BNBUL10n.locale.identifier.hasPrefix("zh") {
            return "\(count) 条未读"
        }
        return count == 1 ? "1 unread" : "\(count) unread"
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
