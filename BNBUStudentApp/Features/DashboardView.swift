import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @State private var showNotifications = false
    var openCheckIn: () -> Void = {}
    var openRecords: () -> Void = {}
    var openGrades: () -> Void = {}
    var openProfile: () -> Void = {}

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    Text("今天")
                        .font(.system(size: 42, weight: .bold))
                        .foregroundStyle(BNBUTheme.onSurface)
                        .accessibilityIdentifier("dashboard.title")

                    heroProgress

                    if let errorMessage = appState.errorMessage {
                        BNBUErrorPanel(message: errorMessage) {
                            Task { await appState.refreshRemoteWorkspace() }
                        }
                    }

                    priorityGlass
                    progressSection
                }
                .padding(.horizontal, BNBUSpacing.screen)
                .padding(.top, 12)
                .padding(.bottom, 20)
            }
            .accessibilityIdentifier("screen.dashboard")
            .refreshable {
                await appState.refreshRemoteWorkspace()
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Image("bnbu_emblem")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 32, height: 32)
                    .accessibilityLabel("BNBU 校徽")
            }

            ToolbarItem(placement: .topBarTrailing) {
                notificationButton
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            actionGlass
        }
        .sheet(isPresented: $showNotifications) {
            NotificationCenterSheet()
                .environmentObject(appState)
        }
    }

    private var heroProgress: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(verbatim: remainingHeadline)
                .font(.system(size: 38, weight: .semibold))
                .foregroundStyle(BNBUTheme.onSurface)
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .accessibilityIdentifier("dashboard.remaining.headline")

            Text(verbatim: completedSummary)
                .font(.title3.weight(.regular))
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            DashboardGlassProgressBar(value: appState.completionRatio)
                .accessibilityLabel("体育学时进度")
                .accessibilityValue("\(Int(appState.completionRatio * 100))%")
        }
    }

    private var priorityGlass: some View {
        Label {
            Text(verbatim: priorityText)
                .font(.headline.weight(.semibold))
                .foregroundStyle(BNBUTheme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: prioritySystemImage)
                .font(.title3.weight(.semibold))
                .foregroundStyle(BNBUTheme.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 17)
        .bnbuGlassSurface(radius: BNBURadius.extraLarge)
        .accessibilityIdentifier("dashboard.priority")
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("本学期进度")
                .font(.title3.weight(.medium))
                .foregroundStyle(BNBUTheme.onSurfaceVariant)

            VStack(spacing: 0) {
                Button(action: openCheckIn) {
                    DashboardGlassProgressRow(
                        title: "课程相关",
                        systemImage: "book.closed.fill",
                        value: progressValue(
                            completed: appState.workspace.progress.course,
                            required: appState.hourRule.courseRequired
                        ),
                        status: appState.courseRemaining == 0
                            ? BNBUL10n.text("已完成")
                            : BNBUL10n.formatted(
                                "还差 %@",
                                appState.courseRemaining.localizedHourText
                            ),
                        secondary: nil
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.progress.course")

                Divider()
                    .overlay(BNBUTheme.outline.opacity(0.24))
                    .padding(.leading, 66)

                Button(action: openCheckIn) {
                    DashboardGlassProgressRow(
                        title: "其他运动",
                        systemImage: "figure.run",
                        value: progressValue(
                            completed: appState.workspace.progress.general,
                            required: appState.hourRule.generalRequired
                        ),
                        status: appState.generalRemaining == 0
                            ? BNBUL10n.text("已完成")
                            : BNBUL10n.formatted(
                                "还差 %@",
                                appState.generalRemaining.localizedHourText
                            ),
                        secondary: organizationCreditText
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dashboard.progress.general")
            }
            .padding(.horizontal, 16)
            .bnbuGlassSurface(radius: BNBURadius.extraLarge)
        }
    }

    private var notificationButton: some View {
        Button {
            showNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: appState.unreadNoticeCount > 0 ? "bell.fill" : "bell")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(BNBUTheme.onSurface)
                    .frame(width: 40, height: 40)
                    .background(.ultraThinMaterial, in: Circle())
                    .overlay {
                        Circle()
                            .strokeBorder(BNBUTheme.surface.opacity(0.85), lineWidth: 1)
                    }
                    .padding(2)

                if appState.unreadNoticeCount > 0 {
                    Text(appState.unreadNoticeCount > 99 ? "99+" : "\(appState.unreadNoticeCount)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(BNBUTheme.onPrimary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(BNBUTheme.primary)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .strokeBorder(BNBUTheme.surface, lineWidth: 1.5)
                        }
                        .offset(x: -1, y: 2)
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboard.notifications.button")
        .accessibilityLabel("打开通知")
    }

    private var actionGlass: some View {
        HStack(spacing: 14) {
            Button(action: openCheckIn) {
                Label("开始运动", systemImage: "figure.run")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BNBUTheme.onPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(BNBUTheme.primary, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.start.button")

            Button(action: openRecords) {
                Text("查看记录")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BNBUTheme.primary)
                    .frame(width: 116)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("dashboard.records.button")
        }
        .padding(12)
        .bnbuGlassSurface(radius: BNBURadius.extraLarge, shadowOpacity: 0.1)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var remainingHeadline: String {
        guard appState.totalRemaining > 0 else {
            return BNBUL10n.text("全部学时已完成")
        }
        return BNBUL10n.formatted(
            "还差 %@",
            appState.totalRemaining.localizedHourText
        )
    }

    private var completedSummary: String {
        "\(BNBUL10n.text("已完成")) \(appState.totalCompleted.localizedHourText) / \(appState.hourRule.total.localizedHourText)"
    }

    private var priorityText: String {
        if appState.courseRemaining > 0 {
            return BNBUL10n.text("优先完成课程相关运动")
        }
        if appState.generalRemaining > 0 {
            return BNBUL10n.formatted(
                "其他运动还差 %@",
                appState.generalRemaining.localizedHourText
            )
        }
        return BNBUL10n.text("全部学时已完成")
    }

    private var prioritySystemImage: String {
        appState.totalRemaining > 0
            ? "exclamationmark.circle.fill"
            : "checkmark.circle.fill"
    }

    private var organizationCreditText: String? {
        let progress = appState.workspace.progress
        let creditedHours = max(progress.general - progress.rawGeneral, 0)
        if creditedHours > 0 {
            return "\(BNBUL10n.text("组织认证")) +\(creditedHours.localizedHourText)"
        }
        if progress.organizationCredit != nil {
            return BNBUL10n.text("组织认证")
        }
        return nil
    }

    private func progressValue(completed: Double, required: Double) -> String {
        let completedText = compactHourNumber(completed)
        let requiredText = compactHourNumber(required)
        if BNBUL10n.locale.identifier.hasPrefix("zh") {
            return "\(completedText) / \(requiredText) 小时"
        }
        return "\(completedText) / \(requiredText) hr"
    }

    private func compactHourNumber(_ value: Double) -> String {
        if value.rounded(.down) == value {
            return String(Int(value))
        }
        return String(format: "%.1f", locale: BNBUL10n.locale, value)
    }
}

private struct DashboardGlassProgressBar: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(BNBUTheme.surfaceVariant.opacity(0.86))
                    .overlay {
                        Capsule()
                            .strokeBorder(BNBUTheme.surface.opacity(0.78), lineWidth: 1)
                    }

                Capsule()
                    .fill(BNBUTheme.primary)
                    .frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 10)
    }
}

private struct DashboardGlassProgressRow: View {
    let title: String
    let systemImage: String
    let value: String
    let status: String
    let secondary: String?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            verticalLayout
        }
        .padding(.vertical, 16)
        .contentShape(Rectangle())
    }

    private var horizontalLayout: some View {
        HStack(spacing: 14) {
            icon

            VStack(alignment: .leading, spacing: 5) {
                Text(LocalizedStringKey(title))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(BNBUTheme.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                if let secondary {
                    Text(verbatim: secondary)
                        .font(.subheadline)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        .lineLimit(1)
                        .minimumScaleFactor(0.76)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 10)

            VStack(alignment: .trailing, spacing: 5) {
                Text(verbatim: value)
                    .font(.headline.weight(.medium))
                    .foregroundStyle(BNBUTheme.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                Text(verbatim: status)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BNBUTheme.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .layoutPriority(1)

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(BNBUTheme.onSurfaceVariant.opacity(0.7))
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                icon
                Text(LocalizedStringKey(title))
                    .font(.headline.weight(.semibold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BNBUTheme.onSurfaceVariant.opacity(0.7))
            }

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(verbatim: value)
                        .font(.subheadline.weight(.medium))
                    if let secondary {
                        Text(verbatim: secondary)
                            .font(.caption)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    }
                }
                Spacer()
                Text(verbatim: status)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BNBUTheme.primary)
            }
        }
    }

    private var icon: some View {
        Image(systemName: systemImage)
            .font(.title2.weight(.semibold))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(BNBUTheme.primary)
            .frame(width: 36, height: 36)
    }
}

private struct LegacyDashboardView: View {
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
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: notice.category.symbolName)
                .font(.body.weight(.semibold))
                .symbolRenderingMode(.monochrome)
                .foregroundStyle(BNBUTheme.primary)
                .frame(width: 38, height: 38)
                .background(BNBUTheme.primary.opacity(0.1), in: Circle())

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(notice.title)
                        .font(.headline.weight(notice.isUnread ? .semibold : .medium))
                        .foregroundStyle(BNBUTheme.onSurface)
                        .lineLimit(2)
                    Spacer(minLength: 4)
                    Text(notice.time)
                        .font(.caption)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                }

                Text(notice.message)
                    .font(.subheadline)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .lineLimit(2)

                Text(LocalizedStringKey(notice.category.rawValue))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BNBUTheme.primary)
            }

            VStack(spacing: 8) {
                if notice.isUnread {
                    Circle()
                        .fill(BNBUTheme.primary)
                        .frame(width: 8, height: 8)
                        .accessibilityLabel("未读")
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BNBUTheme.onSurfaceVariant.opacity(0.65))
            }
        }
        .padding(16)
        .bnbuGlassSurface(radius: BNBURadius.extraLarge, shadowOpacity: 0.045)
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
            ZStack {
                BNBUPageBackground()

                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        Label {
                            Text(verbatim: unreadBadgeText)
                        } icon: {
                            Image(systemName: appState.unreadNoticeCount > 0 ? "bell.fill" : "bell")
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)

                        Spacer()

                        Button("全部标为已读") {
                            appState.markAllNoticesRead()
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(BNBUTheme.primary)
                        .disabled(appState.unreadNoticeCount == 0)
                    }
                    .padding(.horizontal, 4)

                    ScrollView(.horizontal) {
                        HStack(spacing: 8) {
                            ForEach(DashboardNotificationFilter.allCases) { filter in
                                Button {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        selectedFilter = filter
                                    }
                                } label: {
                                    Text(LocalizedStringKey(filter.rawValue))
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(
                                            selectedFilter == filter
                                                ? BNBUTheme.onPrimary
                                                : BNBUTheme.onSurfaceVariant
                                        )
                                        .lineLimit(1)
                                        .padding(.horizontal, 14)
                                        .padding(.vertical, 8)
                                        .background(
                                            selectedFilter == filter
                                                ? BNBUTheme.primary
                                                : BNBUTheme.surface.opacity(0.62),
                                            in: Capsule()
                                        )
                                        .overlay {
                                            if selectedFilter != filter {
                                                Capsule()
                                                    .strokeBorder(
                                                        BNBUTheme.outline.opacity(0.22),
                                                        lineWidth: 1
                                                    )
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("notifications.filter.\(filter.id)")
                            }
                        }
                    }
                    .scrollIndicators(.hidden)

                    if filteredNotices.isEmpty {
                        EmptyPlaceholder(title: "暂无通知", message: "当前筛选条件下没有通知。")
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredNotices) { notice in
                                    NavigationLink {
                                        NoticeDetailView(notice: notice)
                                    } label: {
                                        NoticeRow(notice: notice)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("notifications.notice.\(notice.id)")
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .padding(.horizontal, BNBUSpacing.screen)
                .padding(.top, 8)
            }
            .navigationTitle("通知")
            .navigationBarTitleDisplayMode(.inline)
            .accessibilityIdentifier("screen.notifications")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
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
