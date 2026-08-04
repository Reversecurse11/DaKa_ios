import SwiftUI

/// Block order, conditions and copy follow the Android baseline
/// `feature/dashboard/DashboardScreen.kt`: greeting header, today's check-in,
/// exercise resume, then the two progress blocks. The daily decision stays
/// above longer-term progress. Joining a course lives on the sign-in screen
/// only, so no join or pending-application entry appears here.
struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showNotifications = false
    var openCheckIn: () -> Void = {}

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: BNBUSpacing.space28) {
                    header

                    if let errorMessage = appState.errorMessage {
                        BNBUErrorPanel(message: errorMessage) {
                            Task { await appState.refreshRemoteWorkspace() }
                        }
                    }

                    if let academicYear = appState.newSemesterWelcomeAcademicYear {
                        NewSemesterWelcomePanel(academicYear: academicYear) {
                            appState.dismissNewSemesterWelcome()
                        }
                    }

                    if hasActiveEnrollment {
                        todayCheckInPanel
                    }

                    if let session = ongoingSession {
                        ExerciseResumePanel(session: session, onResume: openCheckIn)
                    }

                    progressOverview
                    progressBreakdown
                }
                .padding(.horizontal, BNBUSpacing.screen)
                .padding(.top, BNBUSpacing.space4)
                .padding(.bottom, BNBUSpacing.bottomSpacer)
            }
            .refreshable {
                await appState.refreshRemoteWorkspace()
            }
        }
        .accessibilityIdentifier("screen.dashboard")
        .task { appState.evaluateNewSemesterWelcome() }
        .sheet(isPresented: $showNotifications) {
            NotificationCenterSheet()
                .environmentObject(appState)
        }
    }

    /// Only an approved enrolment offers the daily check-in (rule 4.2).
    private var hasActiveEnrollment: Bool {
        appState.currentExerciseCourse != nil
    }

    private var ongoingSession: ExerciseSession? {
        guard let session = appState.exerciseSession, session.status == .active else { return nil }
        return session
    }

    private var hasHourRisk: Bool {
        appState.courseRemaining > 0 || appState.generalRemaining > 0
    }

    private var header: some View {
        HStack(spacing: BNBUSpacing.space16) {
            VStack(alignment: .leading, spacing: BNBUSpacing.space4) {
                Text("你好，\(appState.workspace.student.name)")
                    .font(BNBUFont.headlineLarge)
                    .tracking(BNBUFont.Tracking.headlineLarge)
                    .foregroundStyle(BNBUTheme.onSurface)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(verbatim: appState.workspace.student.displayStudentNumber)
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            NotificationBell(unreadCount: appState.unreadNoticeCount) {
                showNotifications = true
            }
        }
    }

    private var todayCheckInPanel: some View {
        let hasCheckedIn = appState.hasSubmittedCheckInToday()
        return HomeCard(contentPadding: BNBUSpacing.space20) {
            HStack(spacing: BNBUSpacing.space12) {
                Text("今日打卡")
                    .font(BNBUFont.titleLarge)
                    .foregroundStyle(BNBUTheme.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if hasCheckedIn {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(BNBUTheme.primary)
                }
            }

            Text(LocalizedStringKey(hasCheckedIn ? "今日已成功打卡" : "今天还未打卡"))
                .font(BNBUFont.headlineSmall)
                .foregroundStyle(BNBUTheme.onSurface)
                .padding(.top, BNBUSpacing.space16)

            Text(LocalizedStringKey(hasCheckedIn ? "今天的运动记录已保存。" : "完成一次运动后即可提交打卡。"))
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .padding(.top, 6)

            TimelineView(.everyMinute) { context in
                CheckInWindowStatusRow(
                    date: context.date,
                    isEnforced: appState.enforcesCheckInTimeWindow
                )
            }
            .padding(.top, BNBUSpacing.space16)

            if !hasCheckedIn {
                PrimaryActionButton(
                    title: "去打卡",
                    systemImage: "plus.app.fill",
                    accessibilityIdentifier: "dashboard.checkin.button",
                    action: openCheckIn
                )
                .padding(.top, BNBUSpacing.space20)
            }
        }
    }

    private var progressOverview: some View {
        HomeCard(contentPadding: BNBUSpacing.space20) {
            HStack(spacing: BNBUSpacing.space12) {
                Text("体育学时进度")
                    .font(BNBUFont.titleLarge)
                    .foregroundStyle(BNBUTheme.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HomeStatusPill(
                    text: appState.workspace.progress.status,
                    emphasized: !hasHourRisk
                )
            }

            Text("本学期总完成")
                .font(BNBUFont.bodySmall)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, BNBUSpacing.space28)

            progressTotalLine
                .padding(.top, BNBUSpacing.space4)

            HomeProgressBar(
                value: appState.totalCompleted,
                total: appState.hourRule.total,
                height: 8
            )
            .padding(.top, BNBUSpacing.panel)

            Text(verbatim: totalRemainingText)
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(appState.totalRemaining == 0 ? BNBUTheme.primary : BNBUTheme.onSurfaceVariant)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, BNBUSpacing.space12)
        }
    }

    private var progressTotalLine: some View {
        HStack(alignment: .bottom, spacing: 0) {
            Text(verbatim: appState.totalCompleted.localizedHourText)
                .font(.system(size: 44, weight: .semibold))
                .tracking(-1)
                .foregroundStyle(BNBUTheme.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(verbatim: "/ \(appState.hourRule.total.localizedHourText)")
                .font(BNBUFont.titleMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .padding(.leading, BNBUSpacing.space8)
                .padding(.bottom, 6)

            Spacer(minLength: BNBUSpacing.space8)

            Text(verbatim: "\(Int(appState.completionRatio * 100))%")
                .font(BNBUFont.headlineSmall)
                .foregroundStyle(BNBUTheme.primary)
                .padding(.bottom, BNBUSpacing.space4)
        }
    }

    private var totalRemainingText: String {
        if appState.totalRemaining == 0 {
            return BNBUL10n.text("已达到本学期目标")
        }
        return BNBUL10n.formatted(
            "距离本学期目标还差 %@",
            appState.totalRemaining.localizedHourText
        )
    }

    private var progressBreakdown: some View {
        VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
            Text("学时构成")
                .font(BNBUFont.titleLarge)
                .foregroundStyle(BNBUTheme.onSurface)

            HomeCard {
                ProgressMetric(
                    title: "课程相关运动",
                    value: appState.workspace.progress.course,
                    total: appState.hourRule.courseRequired,
                    // Organization credit only offsets self-directed hours, so
                    // the course metric has no offset row to show.
                    rawValue: appState.workspace.progress.course,
                    remainingHours: appState.courseRemaining
                )

                Rectangle()
                    .fill(BNBUTheme.outlineVariant.opacity(0.55))
                    .frame(height: 1)
                    .padding(.vertical, BNBUSpacing.space20)

                ProgressMetric(
                    title: "自主其他运动",
                    value: appState.workspace.progress.general,
                    total: appState.hourRule.generalRequired,
                    rawValue: appState.workspace.progress.rawGeneral,
                    remainingHours: appState.generalRemaining
                )
            }
        }
    }
}

/// Android `HomeCard`: large-radius surface, no shadow, 18pt inset unless a
/// panel opts into 20pt.
private struct HomeCard<Content: View>: View {
    private let contentPadding: CGFloat
    private let content: Content

    init(contentPadding: CGFloat = BNBUSpacing.panel, @ViewBuilder content: () -> Content) {
        self.contentPadding = contentPadding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(contentPadding)
        .background(BNBUTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.large, style: .continuous))
    }
}

private struct HomeStatusPill: View {
    let text: String
    var emphasized = false

    var body: some View {
        Text(verbatim: BNBUL10n.dynamicText(text))
            .font(BNBUFont.labelMedium)
            .foregroundStyle(emphasized ? BNBUTheme.primary : BNBUTheme.onSurfaceVariant)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(emphasized ? BNBUTheme.primary.opacity(0.12) : BNBUTheme.surfaceVariant)
            .clipShape(Capsule())
    }
}

/// Android `HomeProgressBar`: fully rounded track with a configurable height.
private struct HomeProgressBar: View {
    let value: Double
    let total: Double
    let height: CGFloat

    private var ratio: Double {
        guard total > 0 else { return 0 }
        return min(max(value / total, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(BNBUTheme.surfaceVariant)
                Capsule()
                    .fill(BNBUTheme.primary)
                    .frame(width: proxy.size.width * ratio)
                    .animation(.easeInOut(duration: BNBUMotion.progress), value: ratio)
            }
        }
        .frame(height: height)
        .accessibilityElement()
        .accessibilityValue(Text(verbatim: "\(Int(ratio * 100))%"))
    }
}

private struct NotificationBell: View {
    let unreadCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: unreadCount > 0 ? "bell.badge.fill" : "bell")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(BNBUTheme.onSurface)
                    .frame(width: BNBUSpacing.touchTarget, height: BNBUSpacing.touchTarget)
                    .background(BNBUTheme.surface)
                    .clipShape(Circle())

                if unreadCount > 0 {
                    Text(verbatim: unreadCount > 99 ? "99+" : "\(unreadCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BNBUTheme.onError)
                        .padding(.horizontal, 5)
                        .frame(minHeight: 18)
                        .background(BNBUTheme.error)
                        .clipShape(Capsule())
                }
            }
        }
        .buttonStyle(BNBUPressStyle())
        .accessibilityIdentifier("dashboard.notifications.button")
        .accessibilityLabel("打开通知")
    }
}

/// Reuses the check-in screen's window rule so the two screens can never
/// disagree about whether a session may start right now (rule 3.3).
private struct CheckInWindowStatusRow: View {
    let date: Date
    let isEnforced: Bool

    private var canStart: Bool {
        !isEnforced || CheckInTimeWindowRule.canStartExercise(at: date)
    }

    private var detail: String {
        if canStart {
            return BNBUL10n.formatted("每日打卡时间 %@", CheckInTimeWindowRule.displayText)
        }
        return CheckInTimeWindowRule.startBlockedMessage
    }

    var body: some View {
        HStack(spacing: BNBUSpacing.buttonGap) {
            Image(systemName: "timer")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(canStart ? BNBUTheme.onPrimaryContainer : BNBUTheme.onErrorContainer)
                .padding(BNBUSpacing.space8)
                .background(canStart ? BNBUTheme.primaryContainer : BNBUTheme.errorContainer)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(canStart ? "当前可开始运动" : "当前不可开始运动"))
                    .font(BNBUFont.bodyMedium.weight(.medium))
                    .foregroundStyle(BNBUTheme.onSurface)
                Text(verbatim: detail)
                    .font(BNBUFont.bodySmall)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(LocalizedStringKey(canStart ? "可开始" : "不可开始"))
                .font(BNBUFont.labelMedium)
                .foregroundStyle(canStart ? BNBUTheme.onPrimaryContainer : BNBUTheme.onErrorContainer)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(canStart ? BNBUTheme.primaryContainer : BNBUTheme.errorContainer)
                .clipShape(Capsule())
        }
    }
}

private struct ExerciseResumePanel: View {
    let session: ExerciseSession
    let onResume: () -> Void

    var body: some View {
        HomeCard {
            HStack(spacing: BNBUSpacing.buttonGap) {
                Image(systemName: "timer")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(BNBUTheme.primary)
                Text("运动进行中")
                    .font(BNBUFont.titleLarge)
                    .foregroundStyle(BNBUTheme.onSurface)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            DashboardFactRow(
                label: "开始时间",
                value: session.startTime.formatted(
                    Date.FormatStyle().hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)
                ),
                font: BNBUFont.bodyMedium
            )
            .padding(.top, BNBUSpacing.space16)

            TimelineView(.periodic(from: .now, by: 1)) { context in
                DashboardFactRow(
                    label: "已运动时长",
                    value: Self.durationText(session.elapsed(at: context.date)),
                    font: BNBUFont.bodyMedium
                )
            }
            .padding(.top, BNBUSpacing.buttonGap)

            PrimaryActionButton(
                title: "继续进入",
                systemImage: "timer",
                accessibilityIdentifier: "dashboard.resumeExercise.button",
                action: onResume
            )
            .padding(.top, BNBUSpacing.space20)
        }
    }

    private static func durationText(_ duration: TimeInterval) -> String {
        let seconds = max(Int(duration), 0)
        return String(format: "%02d:%02d:%02d", seconds / 3_600, (seconds % 3_600) / 60, seconds % 60)
    }
}

private struct ProgressMetric: View {
    let title: String
    let value: Double
    let total: Double
    let rawValue: Double
    let remainingHours: Double

    private var offsetHours: Double {
        max(value - rawValue, 0)
    }

    private var detail: String {
        if remainingHours == 0 {
            return BNBUL10n.text("已完成")
        }
        if offsetHours > 0 {
            return BNBUL10n.formatted("抵扣后实际打卡还需 %@", remainingHours.localizedHourText)
        }
        return BNBUL10n.formatted("还差 %@", remainingHours.localizedHourText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: BNBUSpacing.buttonGap) {
            HStack(spacing: BNBUSpacing.space12) {
                Text(LocalizedStringKey(title))
                    .font(BNBUFont.titleMedium)
                    .foregroundStyle(BNBUTheme.onSurface)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HomeStatusPill(text: detail, emphasized: value >= total)
            }

            HomeProgressBar(value: value, total: total, height: 6)

            DashboardFactRow(
                label: "已打卡",
                value: rawValue.localizedHourText,
                font: BNBUFont.bodySmall
            )

            if offsetHours > 0 {
                DashboardFactRow(
                    label: "组织抵扣",
                    value: BNBUL10n.formatted("已抵扣 %@", offsetHours.localizedHourText),
                    font: BNBUFont.bodySmall
                )
            }

            DashboardFactRow(
                label: "合计",
                value: "\(value.localizedHourText) / \(total.localizedHourText)",
                font: BNBUFont.bodySmall,
                emphasized: true
            )
        }
    }
}

private struct DashboardFactRow: View {
    let label: String
    let value: String
    let font: Font
    var emphasized = false

    var body: some View {
        HStack(spacing: BNBUSpacing.space8) {
            Text(LocalizedStringKey(label))
                .font(font)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            Spacer(minLength: BNBUSpacing.space8)
            Text(verbatim: value)
                .font(emphasized ? font.weight(.medium) : font)
                .foregroundStyle(emphasized ? BNBUTheme.onSurface : BNBUTheme.onSurfaceVariant)
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
                        .font(BNBUFont.labelMedium)
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
                        .font(BNBUFont.titleMedium)
                        .foregroundStyle(BNBUTheme.ink)
                    Spacer()
                    StatusBadge(text: notice.time)
                }
                Text(notice.message)
                    .font(BNBUFont.bodyMedium)
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
    @State private var openedNotice: StudentNotice?

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    Label("通知", systemImage: appState.unreadNoticeCount > 0 ? "bell.badge.fill" : "bell")
                        .font(BNBUFont.titleLarge)
                    Spacer()
                    StatusBadge(text: unreadBadgeText)
                }

                HStack {
                    Spacer()
                    Button("全部标为已读") {
                        appState.markAllNoticesRead()
                    }
                    .font(BNBUFont.titleSmall)
                    .disabled(appState.unreadNoticeCount == 0)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: BNBUSpacing.space8) {
                        ForEach(DashboardNotificationFilter.allCases) { filter in
                            BNBUFilterChip(
                                title: filter.rawValue,
                                isSelected: filter == selectedFilter
                            ) {
                                selectedFilter = filter
                            }
                            .accessibilityIdentifier("notifications.filter.\(filter.rawValue)")
                        }
                    }
                }
                .padding(.vertical, 10)

                if filteredNotices.isEmpty {
                    EmptyPlaceholder(title: "暂无通知", message: "当前筛选条件下没有通知。")
                    Spacer()
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(filteredNotices) { notice in
                                Button {
                                    if notice.isUnread {
                                        appState.markNoticeRead(id: notice.id)
                                    }
                                    // A review notice is about an application, so
                                    // it opens the application itself rather than a
                                    // restatement of the notice.
                                    if notice.category == .review {
                                        appState.opensExemptionCentre = true
                                        dismiss()
                                        return
                                    }
                                    // Opening a notice marks it read, which drops
                                    // it out of the "unread" filter. The detail is
                                    // therefore pushed from a captured copy so the
                                    // destination never depends on a row that is
                                    // about to disappear.
                                    openedNotice = notice
                                } label: {
                                    NoticeRow(notice: notice)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("notice.\(notice.id)")
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, BNBUSpacing.screen)
            .padding(.top, 8)
            .background(BNBUTheme.background)
            .navigationDestination(item: $openedNotice) { notice in
                NoticeDetailView(notice: notice)
            }
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

/// Mirrors Android `NewSemesterWelcomePanel`. Shown once per academic year so a
/// returning student understands why last term's data is gone.
private struct NewSemesterWelcomePanel: View {
    let academicYear: String
    let onDismiss: () -> Void

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space8) {
                Text("新学期已开始")
                    .font(BNBUFont.titleLarge)
                    .foregroundStyle(BNBUTheme.onSurface)
                Text(verbatim: BNBUL10n.formatted(
                    "已切换至 %@，旧学期的本地数据已清除。请扫码或输入邀请码加入本学期课程。",
                    academicYear
                ))
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)

                Button("开始使用", action: onDismiss)
                    .font(BNBUFont.labelLarge)
                    .foregroundStyle(BNBUTheme.primary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.top, BNBUSpacing.space4)
                    .accessibilityIdentifier("dashboard.newSemester.dismiss")
            }
        }
        .accessibilityIdentifier("dashboard.newSemester")
    }
}
