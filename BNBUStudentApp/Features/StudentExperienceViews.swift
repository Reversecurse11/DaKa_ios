import SwiftUI
import UIKit

enum BNBUOnboarding {
    static let currentVersion = 2
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
            title: "打卡流程",
            detail: "选择打卡类型，开始并结束运动，使用现场拍摄的照片或视频作为凭证后提交。",
            preview: .checkIn
        ),
        OnboardingPage(
            title: "成绩查看",
            detail: "查看当前服务返回的成绩构成与缺失项；公示状态、历史成绩版本和“未录入”区分仍待服务端接入。",
            preview: .grades
        ),
        OnboardingPage(
            title: "申请提交",
            detail: "在申请中心提交体测免测并查看进度；校队、社团的新认证申请仍待服务端接口接入。",
            preview: .applications
        )
    ]

    var body: some View {
        ZStack {
            BNBUPageBackground()
            VStack(spacing: 18) {
                HStack {
                    BrandMark(compact: true)
                    Spacer()
                    if page < pages.count - 1 {
                        Button("跳过") { onComplete() }
                            .font(.subheadline.weight(.medium))
                            .accessibilityIdentifier("onboarding.skip")
                    }
                }
                .padding(.horizontal, BNBUSpacing.screen)
                .padding(.top, 12)

                TabView(selection: $page) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { index, item in
                        VStack(spacing: 20) {
                            Spacer(minLength: 4)
                            OnboardingScreenshotPreview(kind: item.preview)
                                .frame(maxWidth: 360)
                                .padding(.horizontal, 24)
                            VStack(spacing: 12) {
                                Text(LocalizedStringKey(item.title))
                                    .font(.title.weight(.semibold))
                                    .multilineTextAlignment(.center)
                                Text(LocalizedStringKey(item.detail))
                                    .font(.body)
                                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                    .multilineTextAlignment(.center)
                                    .lineSpacing(4)
                            }
                            .padding(.horizontal, 28)
                            Spacer()
                        }
                        .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))

                Button {
                    if page == pages.count - 1 {
                        onComplete()
                    } else {
                        withAnimation { page += 1 }
                    }
                } label: {
                    Text(
                        page == pages.count - 1
                            ? LocalizedStringKey("开始使用")
                            : LocalizedStringKey("下一步")
                    )
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.horizontal, BNBUSpacing.screen)
                .padding(.bottom, 18)
                .accessibilityIdentifier(page == pages.count - 1 ? "onboarding.finish" : "onboarding.next")
            }
        }
        .interactiveDismissDisabled()
        // The onboarding walkthrough intentionally stays in Simplified Chinese,
        // independent of the app's currently selected language.
        .environment(\.locale, Locale(identifier: "zh-Hans"))
        .accessibilityIdentifier("screen.onboarding")
    }
}

struct HelpCenterView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.openURL) private var openURL

    @State private var searchText = ""
    @State private var showOnboarding = false

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

    private var filteredEntries: [HelpEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return entries }

        return entries.filter { entry in
            entry.searchTerms.contains { term in
                localized(term).localizedCaseInsensitiveContains(query)
                    || term.localizedCaseInsensitiveContains(query)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BNBUPageBackground()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        SectionTitle(eyebrow: "OFFLINE HELP", title: "帮助中心")
                        Text("以下内容保存在 App 内，无网络时也可以查看。")
                            .font(.subheadline)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)

                        if filteredEntries.isEmpty {
                            SwissPanel {
                                ContentUnavailableView(
                                    "未找到相关帮助",
                                    systemImage: "magnifyingglass",
                                    description: Text("请尝试搜索“打卡”“密码”“成绩”或“申请”。")
                                )
                                .frame(maxWidth: .infinity)
                            }
                        } else {
                            ForEach(filteredEntries) { entry in
                                SwissPanel {
                                    VStack(alignment: .leading, spacing: 8) {
                                        Text(LocalizedStringKey(entry.category))
                                            .font(.caption.weight(.semibold))
                                            .foregroundStyle(BNBUTheme.primary)
                                            .textCase(.uppercase)
                                        Text(LocalizedStringKey(entry.question))
                                            .font(.headline.weight(.medium))
                                        Text(LocalizedStringKey(entry.answer))
                                            .font(.subheadline)
                                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                            .lineSpacing(3)
                                    }
                                }
                            }
                        }

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
            .navigationTitle("帮助中心")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text("搜索帮助内容")
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
    let title: String
    let detail: String
    let preview: OnboardingPreviewKind
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
    case grades
    case applications
}

private struct OnboardingScreenshotPreview: View {
    let kind: OnboardingPreviewKind

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Capsule()
                    .fill(BNBUTheme.onSurface.opacity(0.7))
                    .frame(width: 34, height: 5)
                Spacer()
                Image(systemName: "wifi")
                Image(systemName: "battery.100")
            }
            .font(.caption2)
            .foregroundStyle(BNBUTheme.onSurfaceVariant)
            .padding(.horizontal, 14)
            .frame(height: 28)

            Divider()

            previewContent
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(height: 252)
        .background(BNBUTheme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(BNBUTheme.outline.opacity(0.45), lineWidth: 1)
        }
        .shadow(color: Color.black.opacity(0.10), radius: 12, y: 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var previewContent: some View {
        switch kind {
        case .checkIn:
            checkInPreview
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
                PreviewStatusPill(title: "今日可打卡", color: BNBUTheme.tertiary)
                Spacer()
                Text("剩余 12h")
                    .font(.caption.weight(.medium))
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

                VStack(alignment: .leading, spacing: 3) {
                    Text("00:00:00")
                        .font(.title3.monospacedDigit().weight(.semibold))
                    Text("开始后可暂停并现场拍摄")
                        .font(.caption2)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                }
            }
            Spacer(minLength: 0)
            PreviewPrimaryButton(title: "开始运动", symbol: "play.fill")
        }
    }

    private var gradesPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            PreviewHeader(title: "成绩", symbol: "chart.bar.doc.horizontal")
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("2025–2026 第二学期")
                        .font(.caption.weight(.medium))
                    Text("体育 II")
                        .font(.headline)
                }
                Spacer()
                PreviewStatusPill(title: "公示中", color: BNBUTheme.secondary)
            }
            .padding(10)
            .background(BNBUTheme.surfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            PreviewGradeRow(title: "体育打卡", value: "86")
            PreviewGradeRow(title: "专项考试", value: "未录入")
            PreviewGradeRow(title: "体质测试", value: "92")
            Spacer(minLength: 0)
            HStack {
                Label("查看历史课程", systemImage: "clock.arrow.circlepath")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(BNBUTheme.primary)
        }
    }

    private var applicationsPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            PreviewHeader(title: "申请中心", symbol: "doc.badge.plus")
            Text("选择要提交的申请")
                .font(.caption)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)

            PreviewApplicationCard(
                title: "体测免测申请",
                detail: "800 米 / 1000 米",
                symbol: "heart.text.square"
            )
            PreviewApplicationCard(
                title: "校队 / 社团认证",
                detail: "上传证明材料，由任课教师审核",
                symbol: "person.3.fill"
            )
            Spacer(minLength: 0)
            PreviewStatusPill(title: "可随时查看处理进度", color: BNBUTheme.tertiary)
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
                .font(.headline.weight(.semibold))
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
            .font(.caption.weight(.medium))
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
            .font(.caption2.weight(.semibold))
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
        .font(.caption.weight(.semibold))
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

    var body: some View {
        HStack {
            Text(LocalizedStringKey(title))
                .font(.caption)
            Spacer()
            Text(LocalizedStringKey(value))
                .font(.caption.weight(.semibold))
                .foregroundStyle(value == "未录入" ? BNBUTheme.onSurfaceVariant : BNBUTheme.onSurface)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(BNBUTheme.surfaceVariant.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}

private struct PreviewApplicationCard: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(BNBUTheme.primary)
                .frame(width: 34, height: 34)
                .background(BNBUTheme.primaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .font(.caption.weight(.semibold))
                Text(LocalizedStringKey(detail))
                    .font(.caption2)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .lineLimit(1)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
        }
        .padding(10)
        .background(BNBUTheme.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
