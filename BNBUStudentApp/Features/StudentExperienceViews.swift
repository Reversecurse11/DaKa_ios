import SwiftUI
import UIKit

enum BNBUOnboarding {
    static let currentVersion = 4
    static let defaultsKey = "bnbu.onboarding.completed-version"

    static func completedVersion(
        studentID: String,
        defaults: UserDefaults = .standard
    ) -> Int {
        defaults.integer(forKey: accountKey(studentID: studentID))
    }

    static func markCompleted(
        studentID: String,
        defaults: UserDefaults = .standard
    ) {
        defaults.set(currentVersion, forKey: accountKey(studentID: studentID))
    }

    static func accountKey(studentID: String) -> String {
        defaultsKey + "." + studentID.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var page = 0

    private let pages = [
        OnboardingPage(
            eyebrow: "从首页或“运动”开始",
            title: "开始一次运动",
            detail: "选择课程和运动项目后开始计时，完成本次运动任务。",
            preview: .checkIn
        ),
        OnboardingPage(
            eyebrow: "计时、暂停后继续",
            title: "记录运动过程",
            detail: "运动中可暂停后继续，并使用照片或视频记录现场过程。",
            preview: .exerciseRecord
        ),
        OnboardingPage(
            eyebrow: "完成后确认并提交",
            title: "提交并查看记录",
            detail: "补充说明、确认凭证后提交打卡；在“记录”中查看历史运动、时长和媒体。",
            preview: .submittedRecords
        ),
        OnboardingPage(
            eyebrow: "个人中心 · 服务",
            title: "需要时提交申请",
            detail: "可提交免测、校队或社团认证申请，并查看状态、补充材料或重新提交。",
            preview: .applications
        )
    ]

    var body: some View {
        ZStack {
            BNBUPageBackground()
            VStack(spacing: 0) {
                header

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 0) {
                            Spacer(minLength: BNBUSpacing.space8)
                            OnboardingScreenshotPreview(
                                kind: item.preview,
                                isActive: page == index
                            )
                            .frame(maxWidth: 360)
                            .padding(.horizontal, BNBUSpacing.space20)
                            .scaleEffect(page == index ? 1 : 0.97)
                            .opacity(page == index ? 1 : 0.45)

                            Spacer(minLength: BNBUSpacing.space24)

                            VStack(spacing: 0) {
                                Text(LocalizedStringKey(item.eyebrow))
                                    .font(BNBUFont.labelMedium)
                                    .fontWeight(.semibold)
                                    .foregroundStyle(BNBUTheme.primary)
                                    .multilineTextAlignment(.center)
                                Spacer().frame(height: BNBUSpacing.space8)
                                Text(LocalizedStringKey(item.title))
                                    .font(BNBUFont.headlineLarge)
                                    .foregroundStyle(BNBUTheme.onSurface)
                                    .multilineTextAlignment(.center)
                                Spacer().frame(height: BNBUSpacing.space12)
                                Text(LocalizedStringKey(item.detail))
                                    .font(BNBUFont.bodyLarge)
                                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(4)
                                    .frame(maxWidth: 340)
                            }
                            .padding(.horizontal, BNBUSpacing.space20)
                            Spacer(minLength: BNBUSpacing.space16)
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                actions
            }
        }
        .interactiveDismissDisabled()
        // The walkthrough intentionally stays in Simplified Chinese, independent
        // of the app's currently selected language, matching the Android guide.
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("screen.onboarding")
    }

    /// Mirrors the Android guide header: a centred title, a back slot that only
    /// appears past the first page, and a skip that is always available.
    private var header: some View {
        HStack(spacing: 0) {
            Group {
                if page > 0 {
                    Button {
                        withAnimation { page -= 1 }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(BNBUTheme.onSurface)
                            .frame(width: 96, height: BNBUSpacing.touchTarget, alignment: .leading)
                    }
                    .accessibilityLabel(Text("上一步"))
                    .accessibilityIdentifier("onboarding.back")
                } else {
                    Color.clear.frame(width: 96, height: BNBUSpacing.touchTarget)
                }
            }

            Text("运动指引")
                .font(BNBUFont.titleMedium)
                .foregroundStyle(BNBUTheme.onSurface)
                .frame(maxWidth: .infinity)

            Button("跳过") { onComplete() }
                .font(BNBUFont.labelLarge)
                .foregroundStyle(BNBUTheme.primary)
                .frame(width: 96, height: BNBUSpacing.touchTarget, alignment: .trailing)
                .accessibilityLabel(Text("跳过运动指引并进入首页"))
                .accessibilityIdentifier("onboarding.skip")
        }
        .padding(.horizontal, BNBUSpacing.screen)
        .frame(height: 64)
    }

    private var actions: some View {
        VStack(spacing: BNBUSpacing.space16) {
            stepIndicator

            PrimaryActionButton(
                title: isLastPage ? "进入首页" : "继续",
                systemImage: isLastPage ? "house.fill" : "arrow.right",
                accessibilityIdentifier: isLastPage ? "onboarding.finish" : "onboarding.next"
            ) {
                if isLastPage {
                    onComplete()
                } else {
                    withAnimation { page += 1 }
                }
            }
        }
        .padding(.horizontal, BNBUSpacing.screen)
        .padding(.top, BNBUSpacing.space12)
        .padding(.bottom, BNBUSpacing.space16)
    }

    private var stepIndicator: some View {
        HStack(spacing: BNBUSpacing.space12) {
            Text(verbatim: "\(page + 1) / \(pages.count)")
                .font(BNBUFont.labelMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .monospacedDigit()

            HStack(spacing: 6) {
                ForEach(0..<pages.count, id: \.self) { index in
                    Capsule(style: .continuous)
                        .fill(index == page ? BNBUTheme.primary : BNBUTheme.outlineVariant)
                        .frame(width: index == page ? 20 : 6, height: 6)
                }
            }
            .animation(.easeInOut(duration: BNBUMotion.standard), value: page)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: "当前第 \(page + 1) 步，共 \(pages.count) 步"))
    }

    private var isLastPage: Bool {
        page == pages.count - 1
    }
}

struct HelpCenterView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    @State private var searchText = ""
    @State private var showOnboarding = false
    @State private var expandedArticleID: String?

    private let onReplayOnboarding: (() -> Void)?

    init(onReplayOnboarding: (() -> Void)? = nil) {
        self.onReplayOnboarding = onReplayOnboarding
    }

    private let entries = [
        HelpEntry(
            category: "登录与密码",
            question: "无法登录或忘记密码怎么办？",
            answer: "请先确认学号和密码无误。当前 App 尚未接入忘记密码接口；需要重置时，请联系课程教师或系统管理员。",
            keywords: ["账号", "学号", "邮箱", "重置", "锁定", "login", "password"]
        ),
        HelpEntry(
            category: "运动打卡",
            question: "如何完成一次运动打卡？",
            answer: "选择打卡类型和运动项目后开始计时，可暂停或继续。结束时确认时长，选择至少 1 张现场照片或 1 个现场视频作为凭证，然后提交。",
            keywords: ["开始运动", "结束运动", "暂停", "时长", "每日一次", "check-in"]
        ),
        HelpEntry(
            category: "定位",
            question: "为什么获取不到定位？",
            answer: "请在 iPhone“设置 → 隐私与安全性 → 定位服务”中允许本 App 使用定位。定位失败不会阻止计时和提交，记录会显示为“未获取位置”。",
            keywords: ["GPS", "权限", "室内", "位置", "location"]
        ),
        HelpEntry(
            category: "凭证上传",
            question: "照片和视频凭证有什么限制？",
            answer: "凭证必须在运动过程中或结束后的提交环节使用相机现场拍摄，不能从相册选择。每次最多提交 6 张照片和 1 个视频，且至少选择其中 1 项。",
            keywords: ["照片", "视频", "相机", "相册", "6张", "upload", "evidence"]
        ),
        HelpEntry(
            category: "草稿恢复",
            question: "未提交内容或拍摄凭证还能找回吗？",
            answer: "服务不可用或运动未满 1 小时时，本机可保留允许恢复的草稿。回到打卡页检查草稿并在服务恢复后重新提交；主动放弃运动或退出登录会清除相应本地内容。",
            keywords: ["本地", "待重试", "恢复", "未满一小时", "draft"]
        ),
        HelpEntry(
            category: "课程与成绩",
            question: "在哪里查看课程和成绩？",
            answer: "课程页可查看当前和历史课程，成绩页显示当前服务返回的成绩。公示状态、历史成绩版本和“未录入”区分仍需服务端接口支持。",
            keywords: ["公示", "历史课程", "未录入", "分数", "grade", "course"]
        ),
        HelpEntry(
            category: "体测免测",
            question: "如何提交体测免测申请？",
            answer: "从个人页进入申请中心，选择对应免测类型，填写申请信息并上传证明材料后提交。正式提交和处理结果需要联网并由任课教师审核。",
            keywords: ["800米", "1000米", "证明材料", "申请", "exemption"]
        ),
        HelpEntry(
            category: "组织认证",
            question: "如何申请校队或社团认证？",
            answer: "当前个人页只能查看已有校队或社团认证。新申请、证明上传和教师审核入口仍需服务端接口接入后开放。",
            keywords: ["校队", "社团", "抵扣", "教师审核", "organization"]
        ),
        HelpEntry(
            category: "通知",
            question: "为什么收不到通知？",
            answer: "请在 iPhone“设置 → 通知”中允许本 App 发送通知。通知不会包含姓名、具体成绩等个人信息；关键事项也可能通过学校邮箱送达。",
            keywords: ["推送", "提醒", "邮件", "APNs", "notification"]
        ),
        HelpEntry(
            category: "系统维护",
            question: "维护期间可以做什么？",
            answer: "维护公告会说明影响范围和预计恢复时间。服务暂时不可用时，请保留本机草稿，恢复后重新进入对应页面并按提示提交。",
            keywords: ["服务不可用", "恢复", "公告", "maintenance"]
        ),
        HelpEntry(
            category: "服务反馈",
            question: "如何反馈无法解决的问题？",
            answer: "先记录发生时间、所在页面和错误提示，再通过学校公布的服务反馈渠道提交。截图仅在你主动选择时上传，请勿包含密码等敏感信息。",
            keywords: ["客服", "故障", "截图", "错误", "feedback"]
        ),
        HelpEntry(
            category: "离线说明",
            question: "没有网络时哪些内容可以使用？",
            answer: "内置基础帮助可离线查看。成绩可显示最近一次缓存并提示可能不是最新；各类申请需要联网。完整离线打卡属于后续版本能力，当前请在联网后提交。",
            keywords: ["无网络", "缓存", "离线打卡", "offline"]
        )
    ]

    private var query: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var filteredEntries: [HelpEntry] {
        guard !query.isEmpty else { return entries }

        return entries.filter { entry in
            entry.searchTerms.contains { term in
                localized(term).localizedCaseInsensitiveContains(query)
                    || term.localizedCaseInsensitiveContains(query)
            }
        }
    }

    private var filteredArticles: [HelpArticle] {
        guard !query.isEmpty else { return appState.helpArticles }
        return appState.helpArticles.filter { $0.matches(query) }
    }

    /// Categories in name order, matching Android's sorted grouping. A blank
    /// category is published as "其他" rather than an unlabelled block.
    private var articleCategories: [(name: String, articles: [HelpArticle])] {
        Dictionary(grouping: filteredArticles) { article in
            article.category.isEmpty ? BNBUL10n.text("其他") : article.category
        }
        .map { (name: $0.key, articles: $0.value) }
        .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BNBUPageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(eyebrow: "HELP", title: "帮助中心")
                        Text("帮助内容由管理员发布，会随服务更新；页面底部的内置帮助保存在 App 内，无网络时也可以查看。")
                            .font(BNBUFont.bodyMedium)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)

                        publishedArticlesSection

                        bundledEntriesSection

                        SecondaryActionButton(title: "重新查看新手引导", systemImage: "rectangle.on.rectangle") {
                            replayOnboarding()
                        }
                        .accessibilityIdentifier("help.replay-onboarding")

                        SecondaryActionButton(title: "打开系统设置", systemImage: "gear") {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                openURL(url)
                            }
                        }
                    }
                    .padding(BNBUSpacing.screen)
                }
            }
            .task { await appState.refreshHelpArticles() }
            .navigationTitle("帮助中心")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("搜索帮助内容...")
            )
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView {
                showOnboarding = false
            }
        }
        .accessibilityIdentifier("screen.help")
    }

    /// Server-published content, with the load states Android shows: a spinner
    /// while fetching, a retry on failure, and a notice when the shown copy is
    /// the last cached one.
    @ViewBuilder
    private var publishedArticlesSection: some View {
        if appState.isShowingCachedHelpArticles {
            Text("当前正在显示最近缓存的帮助内容。")
                .font(BNBUFont.bodySmall)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .accessibilityIdentifier("help.cached-notice")
        }

        if appState.isLoadingHelpArticles {
            SwissPanel {
                HStack(spacing: BNBUSpacing.space12) {
                    ProgressView()
                    Text("正在加载帮助内容…")
                        .font(BNBUFont.bodyMedium)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, BNBUSpacing.space12)
            }
            .accessibilityIdentifier("help.loading")
        } else if let failure = appState.helpArticlesError {
            SwissPanel {
                VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                    Text("帮助内容加载失败")
                        .font(BNBUFont.titleMedium)
                    Text(failure)
                        .font(BNBUFont.bodyMedium)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    SecondaryActionButton(title: "点击重试", systemImage: "arrow.clockwise") {
                        Task { await appState.refreshHelpArticles() }
                    }
                    .accessibilityIdentifier("help.retry")
                }
            }
            // The panel carries the state's own identifier, so its children must
            // stay reachable for the retry to be tappable in tests.
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("help.load-failed")
        } else if filteredArticles.isEmpty {
            SwissPanel {
                ContentUnavailableView(
                    appState.helpArticles.isEmpty ? "暂无帮助内容" : "未找到相关帮助",
                    systemImage: appState.helpArticles.isEmpty ? "text.book.closed" : "magnifyingglass",
                    description: Text(
                        LocalizedStringKey(
                            appState.helpArticles.isEmpty
                                ? "管理员尚未发布帮助内容，可先查看下方内置帮助。"
                                : "请尝试其他关键词，或查看下方内置帮助。"
                        )
                    )
                )
                .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("help.articles-empty")
        } else {
            ForEach(articleCategories, id: \.name) { group in
                Text(group.name)
                    .font(BNBUFont.titleSmall)
                    .foregroundStyle(BNBUTheme.primary)
                    .padding(.top, BNBUSpacing.space4)

                ForEach(group.articles) { article in
                    HelpDisclosureCard(
                        title: article.title,
                        answer: article.content,
                        isExpanded: expandedArticleID == article.id
                    ) {
                        withAnimation(.easeInOut(duration: BNBUMotion.standard)) {
                            expandedArticleID = expandedArticleID == article.id ? nil : article.id
                        }
                    }
                    .accessibilityIdentifier("help.article.\(article.id)")
                }
            }
        }
    }

    /// Basics that ship with the app so the page still answers the common
    /// questions when the service cannot be reached at all.
    @ViewBuilder
    private var bundledEntriesSection: some View {
        if !filteredEntries.isEmpty {
            Text("内置离线帮助")
                .font(BNBUFont.titleSmall)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .padding(.top, BNBUSpacing.space8)
                .accessibilityIdentifier("help.bundled-title")

            ForEach(filteredEntries) { entry in
                HelpDisclosureCard(
                    title: entry.question,
                    answer: entry.answer,
                    caption: entry.category,
                    isExpanded: expandedArticleID == entry.id
                ) {
                    withAnimation(.easeInOut(duration: BNBUMotion.standard)) {
                        expandedArticleID = expandedArticleID == entry.id ? nil : entry.id
                    }
                }
            }
        }
    }

    private func localized(_ value: String) -> String {
        String(localized: String.LocalizationValue(value), locale: locale)
    }

    private func replayOnboarding() {
        guard let onReplayOnboarding else {
            showOnboarding = true
            return
        }

        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            onReplayOnboarding()
        }
    }
}

private struct OnboardingPage {
    let eyebrow: String
    let title: String
    let detail: String
    let preview: OnboardingPreviewKind
}

/// One collapsed help answer. Both published and bundled content use it so a
/// student cannot tell which source a card came from by its shape.
private struct HelpDisclosureCard: View {
    let title: String
    let answer: String
    var caption: String?
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space8) {
                if let caption, !caption.isEmpty {
                    Text(LocalizedStringKey(caption))
                        .font(BNBUFont.labelMedium)
                        .foregroundStyle(BNBUTheme.primary)
                        .textCase(.uppercase)
                }

                HStack(alignment: .firstTextBaseline, spacing: BNBUSpacing.space12) {
                    Text(LocalizedStringKey(title))
                        .font(BNBUFont.titleMedium)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                }

                if isExpanded {
                    Text(LocalizedStringKey(answer))
                        .font(BNBUFont.bodyMedium)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(perform: onTap)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(Text(isExpanded ? "收起答案" : "展开答案"))
    }
}

private struct HelpEntry: Identifiable {
    var id: String { question }
    let category: String
    let question: String
    let answer: String
    let keywords: [String]

    var searchTerms: [String] {
        [category, question, answer] + keywords
    }
}

private enum OnboardingPreviewKind {
    case checkIn
    case exerciseRecord
    case submittedRecords
    case grades
    case applications

    var accessibilitySummary: String {
        switch self {
        case .checkIn:
            return "开始一次运动动态演示：展示选择课程、运动项目和开始计时。"
        case .exerciseRecord:
            return "记录运动过程动态演示：展示计时、暂停继续和现场拍摄。"
        case .submittedRecords:
            return "提交并查看记录动态演示：展示补充说明、确认凭证和历史记录。"
        case .grades:
            return "成绩查看动态演示：展示成绩同步和各项成绩逐步更新。"
        case .applications:
            return "申请中心动态演示：展示选择申请、提交材料和教师审核进度。"
        }
    }
}

private struct OnboardingScreenshotPreview: View {
    let kind: OnboardingPreviewKind
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animationStep = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(0..<4, id: \.self) { step in
                        Circle()
                            .fill(
                                step == animationStep
                                    ? BNBUTheme.primary
                                    : BNBUTheme.outline.opacity(0.35)
                            )
                            .frame(width: step == animationStep ? 7 : 5, height: step == animationStep ? 7 : 5)
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: animationStep)
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
            }
            .font(BNBUFont.labelSmall)
            .foregroundStyle(BNBUTheme.onSurfaceVariant)
            .padding(.horizontal, 14)
            .frame(height: 28)

            Divider()

            previewContent
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 272)
        .background(BNBUTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BNBUTheme.outline.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 12, y: 6)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(LocalizedStringKey(kind.accessibilitySummary)))
        .task(id: isActive && !reduceMotion) {
            animationStep = 0
            guard isActive, !reduceMotion else { return }

            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_100_000_000)
                guard !Task.isCancelled else { break }
                withAnimation(.easeInOut(duration: 0.45)) {
                    animationStep = (animationStep + 1) % 4
                }
            }
        }
    }

    @ViewBuilder
    private var previewContent: some View {
        switch kind {
        case .checkIn:
            checkInPreview
        case .exerciseRecord:
            exerciseRecordPreview
        case .submittedRecords:
            submittedRecordsPreview
        case .grades:
            gradesPreview
        case .applications:
            applicationsPreview
        }
    }

    private var checkInPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            PreviewHeader(title: "运动打卡", symbol: "figure.run")
            HStack {
                PreviewStatusPill(
                    title: checkInStatus,
                    color: animationStep == 2 ? BNBUTheme.secondary : BNBUTheme.tertiary
                )
                Spacer()
                Text("剩余 12h")
                    .font(BNBUFont.labelMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
            }
            HStack(spacing: 8) {
                PreviewChoice(title: "课程运动", selected: true)
                PreviewChoice(title: "其他运动", selected: false)
            }
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(BNBUTheme.primaryContainer)
                    Image(systemName: "location.fill")
                        .foregroundStyle(BNBUTheme.primary)
                }
                .frame(width: 46, height: 46)
                .scaleEffect(animationStep == 0 && isActive && !reduceMotion ? 1.12 : 1)
                .animation(
                    .easeInOut(duration: 0.55).repeatCount(2, autoreverses: true),
                    value: animationStep
                )

                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: checkInElapsedTime)
                        .font(BNBUFont.titleLarge.monospacedDigit())
                        .contentTransition(.numericText())
                    Text(LocalizedStringKey(checkInDetail))
                        .font(BNBUFont.labelSmall)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                }
            }
            Spacer(minLength: 0)
            PreviewPrimaryButton(title: checkInButtonTitle, symbol: checkInButtonSymbol)
        }
    }

    private var gradesPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            PreviewHeader(title: "成绩", symbol: "chart.bar.doc.horizontal")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("2025–2026 第二学期")
                        .font(BNBUFont.labelMedium)
                    Text("体育 II")
                        .font(BNBUFont.titleMedium)
                }
                Spacer()
                PreviewStatusPill(
                    title: animationStep == 3 ? "成绩已更新" : "成绩同步中",
                    color: animationStep == 3 ? BNBUTheme.tertiary : BNBUTheme.secondary
                )
            }
            .padding(10)
            .background(BNBUTheme.surfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            PreviewGradeRow(
                title: "体育打卡",
                value: animationStep >= 1 ? "86" : "--",
                highlighted: animationStep == 1
            )
            PreviewGradeRow(
                title: "专项考试",
                value: animationStep >= 2 ? "未录入" : "--",
                highlighted: animationStep == 2
            )
            PreviewGradeRow(
                title: "体质测试",
                value: animationStep >= 3 ? "92" : "--",
                highlighted: animationStep == 3
            )
            Spacer(minLength: 0)
            HStack {
                Label("查看历史课程", systemImage: "clock.arrow.circlepath")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(BNBUFont.labelMedium)
            .foregroundStyle(BNBUTheme.primary)
        }
    }

    private var exerciseRecordPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            PreviewHeader(title: "运动中", symbol: "figure.run")

            HStack(spacing: 14) {
                Text(verbatim: recordElapsedTime)
                    .font(BNBUFont.headlineSmall.monospacedDigit())
                    .foregroundStyle(BNBUTheme.onSurface)
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                ZStack {
                    Circle().fill(BNBUTheme.primary)
                    Image(systemName: animationStep == 2 ? "play.fill" : "pause.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(BNBUTheme.onPrimary)
                }
                .frame(width: 40, height: 40)
            }

            Capsule(style: .continuous)
                .fill(BNBUTheme.surfaceContainerHighest)
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule(style: .continuous)
                            .fill(BNBUTheme.primary)
                            .frame(width: proxy.size.width * recordProgress)
                    }
                }
                .animation(.easeInOut(duration: 0.45), value: animationStep)

            HStack(spacing: 8) {
                PreviewChoice(title: "拍照", selected: animationStep == 1)
                PreviewChoice(title: "录像", selected: animationStep == 3)
            }

            Spacer(minLength: 0)
            PreviewStatusPill(
                title: animationStep == 2 ? "暂停后可继续本次运动" : "正在记录运动时长",
                color: animationStep == 2 ? BNBUTheme.secondary : BNBUTheme.tertiary
            )
        }
    }

    private var submittedRecordsPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            PreviewHeader(title: "完成记录", symbol: "clock.arrow.circlepath")

            ForEach(Array(recordChecklist.enumerated()), id: \.offset) { index, title in
                HStack(spacing: 10) {
                    Text(LocalizedStringKey(title))
                        .font(BNBUFont.bodySmall)
                        .foregroundStyle(BNBUTheme.onSurface)
                    Spacer(minLength: 0)
                    Image(systemName: index <= animationStep ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 15))
                        .foregroundStyle(
                            index <= animationStep ? BNBUTheme.primary : BNBUTheme.outlineVariant
                        )
                }
                .padding(.vertical, 5)
                .animation(.easeInOut(duration: 0.35), value: animationStep)
            }

            Spacer(minLength: 0)
            PreviewStatusPill(title: "在“记录”中查看历史", color: BNBUTheme.tertiary)
        }
    }

    private var recordChecklist: [String] {
        ["补充说明", "确认现场凭证", "提交本次打卡"]
    }

    private var recordElapsedTime: String {
        switch animationStep {
        case 0: return "00:12:05"
        case 1: return "00:24:31"
        case 2: return "00:32:18"
        default: return "00:41:52"
        }
    }

    private var recordProgress: Double {
        switch animationStep {
        case 0: return 0.24
        case 1: return 0.45
        case 2: return 0.62
        default: return 0.83
        }
    }

    private var applicationsPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            PreviewHeader(title: "申请中心", symbol: "doc.badge.plus")
            Text("选择要提交的申请")
                .font(BNBUFont.bodySmall)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)

            PreviewApplicationCard(
                title: "体测免测申请",
                detail: "800 米 / 1000 米",
                symbol: "heart.text.square",
                highlighted: animationStep == 0
            )
            PreviewApplicationCard(
                title: "校队 / 社团认证",
                detail: "上传证明材料，由任课教师审核",
                symbol: "person.3.fill",
                highlighted: animationStep == 1
            )
            Spacer(minLength: 0)
            PreviewStatusPill(title: applicationStatus, color: BNBUTheme.tertiary)
        }
    }

    private var checkInStatus: String {
        switch animationStep {
        case 0: return "正在定位"
        case 1: return "运动进行中"
        case 2: return "运动已暂停"
        default: return "运动进行中"
        }
    }

    private var checkInElapsedTime: String {
        switch animationStep {
        case 0: return "00:00:00"
        case 1: return "00:18:24"
        default: return "00:42:08"
        }
    }

    private var checkInDetail: String {
        switch animationStep {
        case 0: return "正在获取当前位置"
        case 1: return "正在记录运动时长"
        case 2: return "计时已暂停，可现场拍摄"
        default: return "计时已继续，可随时结束"
        }
    }

    private var checkInButtonTitle: String {
        switch animationStep {
        case 0: return "开始运动"
        case 1: return "暂停运动"
        case 2: return "继续运动"
        default: return "结束运动"
        }
    }

    private var checkInButtonSymbol: String {
        switch animationStep {
        case 0: return "play.fill"
        case 1: return "pause.fill"
        case 2: return "play.fill"
        default: return "stop.fill"
        }
    }

    private var applicationStatus: String {
        switch animationStep {
        case 0: return "选择申请类型"
        case 1: return "填写并上传材料"
        case 2: return "材料已提交"
        default: return "教师审核中"
        }
    }
}

private struct PreviewHeader: View {
    let title: String
    let symbol: String

    var body: some View {
        HStack {
            Image(systemName: symbol)
                .foregroundStyle(BNBUTheme.primary)
            Text(LocalizedStringKey(title))
                .font(BNBUFont.titleMedium)
            Spacer()
            Image(systemName: "ellipsis")
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
        }
    }
}

private struct PreviewChoice: View {
    let title: String
    let selected: Bool

    var body: some View {
        Text(LocalizedStringKey(title))
            .font(BNBUFont.labelMedium)
            .foregroundStyle(selected ? BNBUTheme.onPrimary : BNBUTheme.onSurfaceVariant)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(selected ? BNBUTheme.primary : BNBUTheme.surfaceVariant)
            .clipShape(Capsule())
    }
}

private struct PreviewStatusPill: View {
    let title: String
    let color: Color

    var body: some View {
        Text(LocalizedStringKey(title))
            .font(BNBUFont.labelSmall)
            .foregroundStyle(color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct PreviewPrimaryButton: View {
    let title: String
    let symbol: String

    var body: some View {
        Label {
            Text(LocalizedStringKey(title))
        } icon: {
            Image(systemName: symbol)
        }
        .font(BNBUFont.labelMedium)
        .foregroundStyle(BNBUTheme.onPrimary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(BNBUTheme.primary)
        .clipShape(Capsule())
    }
}

private struct PreviewGradeRow: View {
    let title: String
    let value: String
    let highlighted: Bool

    var body: some View {
        HStack {
            Text(LocalizedStringKey(title))
                .font(BNBUFont.bodySmall)
            Spacer()
            Text(LocalizedStringKey(value))
                .font(BNBUFont.labelMedium)
                .foregroundStyle(value == "未录入" ? BNBUTheme.onSurfaceVariant : BNBUTheme.onSurface)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(highlighted ? BNBUTheme.primaryContainer : BNBUTheme.surfaceVariant.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 9))
        .animation(.easeInOut(duration: 0.35), value: highlighted)
    }
}

private struct PreviewApplicationCard: View {
    let title: String
    let detail: String
    let symbol: String
    let highlighted: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.primary)
                .frame(width: 34, height: 34)
                .background(BNBUTheme.primaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(BNBUFont.labelMedium)
                Text(LocalizedStringKey(detail))
                    .font(BNBUFont.labelSmall)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(BNBUFont.bodySmall)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
        }
        .padding(10)
        .background(highlighted ? BNBUTheme.primaryContainer : BNBUTheme.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .scaleEffect(highlighted ? 1.015 : 1)
        .animation(.easeInOut(duration: 0.35), value: highlighted)
    }
}
