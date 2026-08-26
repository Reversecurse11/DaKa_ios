import PhotosUI
import SwiftUI

/// Problem reporting, reached from Settings. Mirrors the Android
/// `FeedbackScreen`: a submit tab and a ticket-list tab behind one segmented
/// control, with a full-screen confirmation once a report is accepted.
struct FeedbackView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var tab: FeedbackTab = .submit
    @State private var submittedTicket: FeedbackTicket?

    var body: some View {
        NavigationStack {
            ZStack {
                BNBUPageBackground()

                if let submittedTicket {
                    FeedbackSubmittedView(
                        ticket: submittedTicket,
                        onViewStatus: {
                            self.submittedTicket = nil
                            tab = .tickets
                        },
                        onBack: { self.submittedTicket = nil }
                    )
                } else {
                    content
                }
            }
            .navigationTitle(Text("问题反馈"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("feedback.close")
                }
            }
        }
        .accessibilityIdentifier("screen.feedback")
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                SectionTitle(eyebrow: "SUPPORT", title: "问题反馈")

                BNBUSegmentedControl(
                    values: FeedbackTab.allCases,
                    selection: $tab,
                    title: \.title,
                    identifier: { "feedback.tab.\($0.rawValue)" }
                )

                if let userError = appState.userFacingError {
                    BNBUErrorPanel(error: userError)
                } else if let message = appState.errorMessage {
                    ValidationPanel(message: message)
                }

                switch tab {
                case .submit:
                    FeedbackForm { ticket in
                        submittedTicket = ticket
                    }
                case .tickets:
                    FeedbackTicketList()
                }
            }
            .padding(BNBUSpacing.screen)
        }
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: tab) { _, newValue in
            appState.errorMessage = nil
            if newValue == .tickets {
                Task { await appState.refreshFeedbackTickets() }
            }
        }
    }
}

private enum FeedbackTab: String, CaseIterable, Hashable {
    case submit
    case tickets

    var title: String {
        switch self {
        case .submit: return "提交问题"
        case .tickets: return "我的反馈"
        }
    }
}

private struct FeedbackForm: View {
    @EnvironmentObject private var appState: AppState
    let onSubmitted: (FeedbackTicket) -> Void

    @State private var category: FeedbackCategory = .bug
    @State private var description = ""
    @State private var submittedForm = false
    @FocusState private var descriptionFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
            if !appState.isWriteAllowed {
                ValidationPanel(message: BNBUL10n.text("系统当前为只读模式，暂时无法提交反馈。"))
                    .accessibilityIdentifier("feedback.readOnlyNotice")
            }

            SwissPanel {
                VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                    panelHeader(title: "问题内容", helper: "请选择问题类型并描述你遇到的情况。")
                    categoryPicker
                    descriptionField
                }
            }

            SwissPanel {
                VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                    Label("隐私边界", systemImage: "lock.shield")
                        .font(BNBUFont.titleMedium)
                        .foregroundStyle(BNBUTheme.primary)
                    Text("反馈会按当前登录账号关联。这里只提交问题类型、文字内容和允许的 App/系统版本信息；不会收集或发送邮箱、电话、截图、日志、Token 或设备标识。")
                        .font(BNBUFont.bodySmall)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityIdentifier("feedback.privacyBoundary")
            }

            PrimaryActionButton(
                title: appState.isSubmittingFeedback ? "正在提交…" : "提交问题",
                systemImage: "paperplane.fill",
                accessibilityIdentifier: "feedback.submit"
            ) {
                submit()
            }
            .disabled(!appState.isWriteAllowed || appState.isSubmittingFeedback)
            .opacity(appState.isWriteAllowed && !appState.isSubmittingFeedback ? 1 : 0.5)
        }
    }

    private func panelHeader(title: String, helper: String) -> some View {
        VStack(alignment: .leading, spacing: BNBUSpacing.space4) {
            Text(LocalizedStringKey(title))
                .font(BNBUFont.titleMedium)
                .foregroundStyle(BNBUTheme.onSurface)
            Text(LocalizedStringKey(helper))
                .font(BNBUFont.bodySmall)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var categoryPicker: some View {
        VStack(alignment: .leading, spacing: BNBUSpacing.space8) {
            Text("问题类型")
                .font(BNBUFont.labelMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)

            Menu {
                Picker("问题类型", selection: $category) {
                    ForEach(FeedbackCategory.allCases) { option in
                        Text(LocalizedStringKey(option.title)).tag(option)
                    }
                }
                .labelsHidden()
            } label: {
                HStack {
                    Text(LocalizedStringKey(category.title))
                        .font(BNBUFont.bodyLarge)
                        .foregroundStyle(BNBUTheme.onSurface)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: BNBUSpacing.touchTarget)
                .background(BNBUTheme.surface)
                .bnbuOutlinedSurface(lineWidth: 1)
            }
            .accessibilityIdentifier("feedback.category")
            .accessibilityLabel("问题类型")
            .accessibilityValue(Text(LocalizedStringKey(category.title)))
            .accessibilityHint("必填；双击后选择问题类型")
        }
    }

    private var descriptionField: some View {
        BNBUTextArea(
            label: "问题描述",
            text: $description,
            placeholder: "例如：操作步骤、预期结果和实际情况",
            required: true,
            helperText: "请勿填写密码、验证码、Token 或其他敏感凭据。",
            errorText: submittedForm && description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "请填写问题描述。"
                : nil,
            characterLimit: FeedbackRule.maximumDescriptionLength,
            enabled: !appState.isSubmittingFeedback,
            loading: appState.isSubmittingFeedback,
            focusBinding: $descriptionFocused,
            accessibilityIdentifier: "feedback.description"
        )
    }

    private func submit() {
        submittedForm = true
        dismissBNBUKeyboard()
        if description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            descriptionFocused = true
            return
        }
        Task {
            guard let ticket = await appState.submitFeedback(
                category: category,
                description: description
            ) else { return }
            description = ""
            submittedForm = false
            onSubmitted(ticket)
        }
    }
}

/// Up to three screenshots, listed as Android does: a 64pt square thumbnail per
/// row with its own delete control, and camera / library buttons beneath.
private struct FeedbackScreenshotPanel: View {
    @Binding var screenshots: [ProofAttachment]

    @State private var showCamera = false
    @State private var libraryItems: [PhotosPickerItem] = []
    @State private var notice: String?

    private var isFull: Bool { screenshots.count >= FeedbackRule.maximumScreenshots }

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                VStack(alignment: .leading, spacing: BNBUSpacing.space4) {
                    Text("截图（可选）")
                        .font(BNBUFont.titleMedium)
                        .foregroundStyle(BNBUTheme.onSurface)
                    Text(BNBUL10n.formatted(
                        "最多 %lld 张。截图可帮助我们更快定位问题。",
                        FeedbackRule.maximumScreenshots
                    ))
                    .font(BNBUFont.bodySmall)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)
                }

                ForEach(Array(screenshots.enumerated()), id: \.element.id) { index, shot in
                    screenshotRow(index: index, attachment: shot)
                }

                HStack(spacing: 10) {
                    OutlinedActionButton(
                        title: "拍摄",
                        systemImage: "camera.fill",
                        accessibilityIdentifier: "feedback.screenshot.camera"
                    ) {
                        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
                            notice = BNBUL10n.text("当前设备没有可用的相机。")
                            return
                        }
                        showCamera = true
                    }
                    .disabled(isFull)

                    PhotosPicker(
                        selection: $libraryItems,
                        maxSelectionCount: max(1, FeedbackRule.maximumScreenshots - screenshots.count),
                        matching: .images
                    ) {
                        HStack(spacing: BNBUSpacing.space8) {
                            Image(systemName: "photo")
                                .font(.system(size: 16, weight: .semibold))
                            Text("从相册选择")
                                .font(BNBUFont.labelLarge)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: BNBUSpacing.primaryControlHeight)
                        .foregroundStyle(BNBUTheme.onSurface)
                        .background(BNBUTheme.surface)
                        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous)
                                .stroke(BNBUTheme.outlineVariant, lineWidth: 1)
                        )
                    }
                    .disabled(isFull)
                    .accessibilityIdentifier("feedback.screenshot.library")
                }

                if let notice {
                    Text(verbatim: notice)
                        .font(BNBUFont.labelMedium)
                        .foregroundStyle(BNBUTheme.muted)
                }
            }
        }
        .sheet(isPresented: $showCamera) {
            CameraCapturePicker(initialCaptureMode: .photo) { attachment in
                append(attachment)
                showCamera = false
            }
            .ignoresSafeArea()
        }
        .onChange(of: libraryItems) { _, items in
            guard !items.isEmpty else { return }
            Task { await importFromLibrary(items) }
        }
    }

    private func screenshotRow(index: Int, attachment: ProofAttachment) -> some View {
        HStack(spacing: BNBUSpacing.space12) {
            thumbnail(for: attachment)
            Text(BNBUL10n.formatted("截图 %lld", index + 1))
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurface)
            Spacer(minLength: 0)
            Button {
                screenshots.removeAll { $0.id == attachment.id }
            } label: {
                Image(systemName: "trash")
                    .foregroundStyle(BNBUTheme.error)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("删除截图"))
            .accessibilityIdentifier("feedback.screenshot.remove.\(index)")
        }
    }

    private func thumbnail(for attachment: ProofAttachment) -> some View {
        Group {
            if let data = attachment.thumbnailData, let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "photo")
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
            }
        }
        .frame(width: 64, height: 64)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
    }

    private func append(_ attachment: ProofAttachment) {
        guard !isFull else { return }
        notice = nil
        screenshots.append(attachment)
    }

    private func importFromLibrary(_ items: [PhotosPickerItem]) async {
        for item in items {
            guard !isFull else { break }
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let thumbnail = ProofThumbnailRenderer.imageThumbnailData(from: data) else { continue }
            append(
                ProofAttachment(
                    id: UUID().uuidString,
                    type: .image,
                    fileName: "feedback_screenshot_\(screenshots.count + 1).jpg",
                    byteCount: data.count,
                    thumbnailData: thumbnail,
                    uploadData: data,
                    source: "library",
                    cosKey: nil,
                    mimeType: "image/jpeg",
                    contentDigest: nil
                )
            )
        }
        libraryItems = []
    }
}

private struct FeedbackField: View {
    let label: String
    let placeholder: String
    @Binding var text: String
    var required = false
    var helperText: String?
    var errorText: String?
    var keyboardType: UIKeyboardType = .default
    var textContentType: UITextContentType?
    var enabled = true
    var focusBinding: FocusState<Bool>.Binding?
    let identifier: String

    var body: some View {
        BNBUFormField(
            label: label,
            placeholder: placeholder,
            text: $text,
            required: required,
            helperText: helperText,
            errorText: errorText,
            keyboardType: keyboardType,
            textContentType: textContentType,
            enabled: enabled,
            focusBinding: focusBinding,
            accessibilityIdentifier: identifier
        )
    }
}

private struct FeedbackTicketList: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
            if appState.isLoadingFeedback, appState.feedbackTickets.isEmpty {
                ProgressView("正在加载反馈记录…")
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .accessibilityIdentifier("feedback.loading")
            } else if let notice = appState.feedbackNotice {
                ValidationPanel(message: notice)
            }

            if !appState.isLoadingFeedback || !appState.feedbackTickets.isEmpty {
                if appState.feedbackTickets.isEmpty {
                    EmptyPlaceholder(
                        title: "暂无已提交问题",
                        message: "提交问题后，可在这里查看处理状态。"
                    )
                } else {
                    ForEach(appState.feedbackTickets) { ticket in
                        FeedbackTicketCard(ticket: ticket)
                    }
                }
            }

            OutlinedActionButton(title: "刷新处理状态", systemImage: "arrow.clockwise") {
                Task { await appState.refreshFeedbackTickets() }
            }
            .disabled(appState.isLoadingFeedback)
            .opacity(appState.isLoadingFeedback ? 0.55 : 1)
            .accessibilityIdentifier("feedback.refresh")
        }
        .task { await appState.refreshFeedbackTickets() }
        .accessibilityIdentifier("feedback.tickets")
    }
}

private struct FeedbackTicketCard: View {
    let ticket: FeedbackTicket

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space8) {
                HStack(alignment: .top) {
                    Text(verbatim: ticket.displayNumber)
                        .font(BNBUFont.titleMedium)
                        .foregroundStyle(BNBUTheme.onSurface)
                    Spacer(minLength: BNBUSpacing.space8)
                    StatusBadge(text: ticket.status.rawValue, filled: true)
                }

                Text(verbatim: BNBUL10n.dynamicText(ticket.category))
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.primary)

                Text(verbatim: ticket.description)
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurface)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                if !ticket.createdAt.isEmpty {
                    Text(verbatim: BNBUL10n.text("提交时间：") + ticket.createdAt)
                        .font(BNBUFont.bodySmall)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                }

                if let reply = ticket.reply, !reply.isEmpty {
                    Text(verbatim: BNBUL10n.text("处理说明：") + reply)
                        .font(BNBUFont.bodySmall)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("feedback.ticket.\(ticket.id)")
    }
}

private struct FeedbackSubmittedView: View {
    let ticket: FeedbackTicket
    let onViewStatus: () -> Void
    let onBack: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                BNBUBackRow(action: onBack)
                SectionTitle(eyebrow: "SUPPORT", title: "问题已提交")

                SwissPanel {
                    VStack(alignment: .leading, spacing: BNBUSpacing.space12) {
                        Text("我们已收到你的问题。")
                            .font(BNBUFont.titleMedium)
                            .foregroundStyle(BNBUTheme.onSurface)
                        DetailFactRow(
                            label: "工单编号：",
                            value: ticket.displayNumber
                        )
                        DetailFactRow(
                            label: "当前状态：",
                            value: ticket.status.rawValue
                        )
                    }
                }

                PrimaryActionButton(
                    title: "查看处理状态",
                    systemImage: "arrow.right",
                    accessibilityIdentifier: "feedback.viewStatus"
                ) {
                    onViewStatus()
                }
            }
            .padding(BNBUSpacing.screen)
        }
        .accessibilityIdentifier("screen.feedbackSubmitted")
    }
}
