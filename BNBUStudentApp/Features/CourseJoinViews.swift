import AudioToolbox
import AVFoundation
import SwiftUI
import UIKit

/// Public preview followed by the OpenAPI 2.0.13 Join Capability and atomic
/// join. There is no client-side approval queue or locally fabricated course.
struct CourseJoinSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Set by a scan entry so tapping it goes straight to the camera instead of
    /// asking the student to pick an entry point twice.
    let autoPresentsScanner: Bool

    @State private var step: CourseJoinStep
    @State private var code = ""
    @State private var isScannerPresented = false
    @State private var activeAlert: CourseJoinScannerAlert?
    @State private var codeTouched = false

    init(autoPresentsScanner: Bool = false, startsWithFirstEmailBinding: Bool = false) {
        self.autoPresentsScanner = autoPresentsScanner
        _step = State(initialValue: startsWithFirstEmailBinding ? .firstEmailBinding : .entry)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                BNBUPageBackground()

                switch step {
                case .entry:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            scanPanel
                            codePanel
                        }
                        .padding(BNBUSpacing.screen)
                    }
                case let .confirm(invite):
                    CourseJoinConfirmView(
                        invite: invite,
                        onBack: {
                            appState.errorMessage = nil
                            step = .entry
                        },
                        onContinue: { name, studentNumber, gender, gradeYear in
                            Task {
                                guard let completion = await appState.joinCourseInvite(
                                    invite,
                                    name: name,
                                    studentNumber: studentNumber,
                                    gender: gender,
                                    gradeYear: gradeYear
                                ) else { return }
                                switch completion {
                                case .active:
                                    dismiss()
                                case .requiresFirstEmailBinding:
                                    step = .firstEmailBinding
                                }
                            }
                        }
                    )
                case .firstEmailBinding:
                    FirstEmailBindingView {
                        dismiss()
                    }
                }
            }
            .navigationTitle("加入课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !requiresFirstEmailBinding {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("关闭") { dismiss() }
                            .accessibilityIdentifier("course.join.close")
                    }
                }
            }
        }
        .accessibilityIdentifier("screen.courseJoin")
        .interactiveDismissDisabled(requiresFirstEmailBinding)
        .onAppear {
            if autoPresentsScanner {
                isScannerPresented = true
            }
        }
        .fullScreenCover(isPresented: $isScannerPresented) {
            CourseQRScannerView { payload in
                isScannerPresented = false
                handleScan(payload)
            } onCancel: {
                isScannerPresented = false
            }
            .ignoresSafeArea()
        }
        .alert(item: $activeAlert) { alert in
            alert.alert(openSettings: openSettings)
        }
    }

    private var requiresFirstEmailBinding: Bool {
        if case .firstEmailBinding = step { return true }
        return false
    }

    private var scanPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("扫描课程二维码")
                    .font(BNBUFont.titleMedium)
                Text("扫描任课老师提供的课程二维码，先读取服务器课程预览，再确认身份并直接加入。")
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .lineSpacing(3)
                PrimaryActionButton(
                    title: "扫描二维码",
                    systemImage: "qrcode.viewfinder",
                    accessibilityIdentifier: "course.join.scan"
                ) {
                    startScan()
                }
            }
        }
    }

    private var codePanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("输入邀请码")
                    .font(BNBUFont.titleMedium)
                BNBUFormField(
                    label: "课程邀请码",
                    placeholder: "输入老师提供的邀请码",
                    text: $code,
                    required: true,
                    helperText: "支持合同允许的长邀请码；不会在日志中记录邀请码明文。",
                    errorText: codeTouched ? CourseJoinCodeRule.validationMessage(for: code) : nil,
                    characterLimit: 512,
                    submitLabel: .done,
                    onSubmit: { lookUpInvite() },
                    onFocusChanged: { focused in if !focused { codeTouched = true } },
                    accessibilityIdentifier: "course.join.code.field"
                )

                if let message = appState.errorMessage {
                    Text(verbatim: message)
                        .font(BNBUFont.labelMedium)
                        .foregroundStyle(BNBUTheme.muted)
                        .accessibilityIdentifier("course.join.error")
                }

                DisabledAwareButton(
                    title: "下一步",
                    systemImage: "arrow.right",
                    isDisabled: CourseJoinCodeRule.validationMessage(for: code) != nil,
                    accessibilityIdentifier: "course.join.submit"
                ) {
                    lookUpInvite()
                }
            }
        }
    }

    private func lookUpInvite() {
        Task {
            codeTouched = true
            dismissBNBUKeyboard()
            appState.errorMessage = nil
            guard CourseJoinCodeRule.validationMessage(for: code) == nil else { return }
            guard let invite = await appState.previewCourseInvite(rawToken: code) else { return }
            step = .confirm(invite)
            code = ""
        }
    }

    private func startScan() {
        appState.errorMessage = nil
        guard CourseQRScannerView.isCameraAvailable else {
            activeAlert = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isScannerPresented = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        isScannerPresented = true
                    } else {
                        activeAlert = .denied
                    }
                }
            }
        case .denied:
            activeAlert = .denied
        case .restricted:
            activeAlert = .restricted
        @unknown default:
            activeAlert = .restricted
        }
    }

    private func handleScan(_ payload: String) {
        if let components = URLComponents(string: payload), components.scheme != nil,
           CourseInviteURLPolicy.resolvedAllowedHosts().isEmpty {
            activeAlert = .urlHostNotConfigured
            return
        }
        guard let scanned = CourseJoinCodeRule.code(fromScannedPayload: payload) else {
            activeAlert = .unrecognized
            return
        }
        code = scanned
        lookUpInvite()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private enum CourseJoinStep: Hashable {
    case entry
    case confirm(CourseInvite)
    case firstEmailBinding
}

/// Android's `CourseJoinConfirmScreen`: the invite's course is shown for
/// confirmation, then the student supplies the identity bound into the
/// one-time Join Capability.
struct CourseJoinConfirmView: View {
    @EnvironmentObject private var appState: AppState
    let invite: CourseInvite
    let onBack: () -> Void
    let onContinue: (_ name: String, _ studentNumber: String, _ gender: StudentGender, _ gradeYear: Int) -> Void

    @State private var name = ""
    @State private var studentNumber = ""
    @State private var gender: StudentGender = .unknown
    @State private var gradeYear = ""
    @State private var submittedIdentity = false
    @FocusState private var nameFocused: Bool
    @FocusState private var studentNumberFocused: Bool
    @FocusState private var gradeYearFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                BNBUBackRow(action: onBack)
                SectionTitle(eyebrow: "COURSE", title: "确认课程信息")
                coursePanel
                SectionTitle(eyebrow: "IDENTITY", title: "填写身份资料")
                identityPanel
            }
            .padding(BNBUSpacing.screen)
        }
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("screen.courseJoinConfirm")
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完成") {
                    nameFocused = false
                    studentNumberFocused = false
                    gradeYearFocused = false
                    dismissBNBUKeyboard()
                }
                .font(BNBUFont.titleSmall)
            }
        }
    }

    private var coursePanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 14) {
                CourseJoinFact(label: "课程名称", value: invite.courseName)
                CourseJoinFact(
                    label: "课程编号 / Section",
                    value: "\(invite.courseCode) / Section \(invite.section)"
                )
                CourseJoinFact(label: "授课老师", value: invite.teacherName)
                CourseJoinFact(label: "学期", value: invite.semester)
                Text("请确认以上课程信息无误后再加入")
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
            }
        }
    }

    private var identityPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 14) {
                if let message = appState.errorMessage {
                    BNBUErrorPanel(message: message)
                        .accessibilityIdentifier("courseJoinConfirm.error")
                }

                CourseJoinField(
                    label: "姓名",
                    text: $name,
                    limit: CourseJoinRequestRule.maximumNameLength,
                    errorText: submittedIdentity && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "请填写姓名。"
                        : nil,
                    focusBinding: $nameFocused,
                    identifier: "courseJoinConfirm.name"
                )

                CourseJoinField(
                    label: "学号",
                    text: $studentNumber,
                    limit: CourseJoinRequestRule.maximumStudentNumberLength,
                    errorText: submittedIdentity && studentNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "请填写学号。"
                        : nil,
                    focusBinding: $studentNumberFocused,
                    identifier: "courseJoinConfirm.studentNumber"
                )

                Picker("性别（必填）", selection: $gender) {
                    Text("请选择").tag(StudentGender.unknown)
                    Text("女").tag(StudentGender.female)
                    Text("男").tag(StudentGender.male)
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("courseJoinConfirm.gender")
                if submittedIdentity && gender == .unknown {
                    Label("请选择性别。", systemImage: "exclamationmark.circle.fill")
                        .font(BNBUFont.bodySmall)
                        .foregroundStyle(BNBUTheme.error)
                        .accessibilityIdentifier("courseJoinConfirm.gender.error")
                }

                BNBUFormField(
                    label: "入学年份",
                    placeholder: "例如：2026",
                    text: $gradeYear,
                    required: true,
                    helperText: "请输入四位入学年份。",
                    errorText: submittedIdentity && (gradeYear.count != 4 || Int(gradeYear) == nil)
                        ? "请输入有效的四位入学年份。"
                        : nil,
                    characterLimit: 4,
                    keyboardType: .numberPad,
                    submitLabel: .done,
                    focusBinding: $gradeYearFocused,
                    accessibilityIdentifier: "courseJoinConfirm.gradeYear"
                )
                .onChange(of: gradeYear) { _, value in
                    gradeYear = String(value.filter(\.isNumber).prefix(4))
                }

                PrimaryActionButton(
                    title: "确认并加入课程",
                    systemImage: "checkmark.circle.fill",
                    accessibilityIdentifier: "courseJoinConfirm.submit"
                ) {
                    submit()
                }
            }
        }
    }

    private func submit() {
        submittedIdentity = true
        nameFocused = false
        studentNumberFocused = false
        gradeYearFocused = false
        dismissBNBUKeyboard()
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            nameFocused = true
            return
        }
        if studentNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            studentNumberFocused = true
            return
        }
        if let validationMessage = CourseJoinRequestRule.validationMessage(
            name: name,
            studentNumber: studentNumber
        ) {
            appState.errorMessage = validationMessage
            return
        }
        guard gender.courseJoinAPIValue != nil,
              let parsedGradeYear = Int(gradeYear),
              (1000...9999).contains(parsedGradeYear) else {
            appState.errorMessage = BNBUL10n.text("请选择性别并填写四位入学年份。")
            if Int(gradeYear) == nil || gradeYear.count != 4 {
                gradeYearFocused = true
            }
            return
        }
        onContinue(name, studentNumber, gender, parsedGradeYear)
    }
}

struct FirstEmailBindingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.locale) private var locale
    let onComplete: () -> Void

    @State private var email = ""
    @State private var code = ""
    @State private var codeSent = false
    @State private var emailTouched = false
    @State private var codeTouched = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(eyebrow: "ACCOUNT", title: "绑定学校邮箱")
                Text("课程已成功加入。完成首次邮箱验证后，账号才会变为 ACTIVE 并进入运动工作台。")
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)

                SwissPanel {
                    VStack(alignment: .leading, spacing: 14) {
                        BNBUFormField(
                            label: "学校邮箱",
                            placeholder: "name@bnbu.edu.cn",
                            text: $email,
                            required: true,
                            helperText: "完成验证后账号才会进入 ACTIVE 状态。",
                            errorText: emailTouched && !ContactBindingRule.isValid(email, for: .email)
                                ? "请输入有效的学校邮箱。"
                                : nil,
                            characterLimit: 254,
                            keyboardType: .emailAddress,
                            textContentType: .emailAddress,
                            enabled: !appState.isLoading,
                            submitLabel: .next,
                            onSubmit: { if ContactBindingRule.isValid(email, for: .email) { requestCode() } },
                            onFocusChanged: { focused in if !focused { emailTouched = true } },
                            accessibilityIdentifier: "courseJoin.emailBinding.email"
                        )

                        BNBUFormField(
                            label: "邮箱验证码",
                            placeholder: "4–10 位数字验证码",
                            text: $code,
                            required: true,
                            helperText: codeSent ? "验证码已发送，请查看邮箱。" : "请先发送验证码。",
                            errorText: codeTouched && !code.isEmpty && !ContactBindingRule.isValidStudentSignInCode(code)
                                ? "请输入 4–10 位数字验证码。"
                                : nil,
                            characterLimit: 10,
                            keyboardType: .numberPad,
                            textContentType: .oneTimeCode,
                            enabled: !appState.isLoading,
                            submitLabel: .done,
                            onSubmit: { if codeSent { verify() } },
                            onFocusChanged: { focused in if !focused { codeTouched = true } },
                            accessibilityIdentifier: "courseJoin.emailBinding.code"
                        )
                        .onChange(of: code) { _, value in
                            code = String(value.filter(\.isNumber).prefix(10))
                        }

                        Button(codeSent ? "重新发送" : "发送验证码") {
                            requestCode()
                        }
                        .frame(minHeight: BNBUSpacing.touchTarget)
                        .disabled(!ContactBindingRule.isValid(email, for: .email) || appState.isLoading)
                        .accessibilityIdentifier("courseJoin.emailBinding.send")

                        if let message = appState.errorMessage {
                            BNBUErrorPanel(message: message)
                        }

                        PrimaryActionButton(
                            title: "验证并进入",
                            systemImage: "envelope.badge.fill",
                            accessibilityIdentifier: "courseJoin.emailBinding.verify"
                        ) {
                            verify()
                        }
                        .disabled(!codeSent || !ContactBindingRule.isValidStudentSignInCode(code) || appState.isLoading)
                    }
                }
            }
            .padding(BNBUSpacing.screen)
        }
        .accessibilityIdentifier("screen.courseJoinEmailBinding")
    }

    private func requestCode() {
        emailTouched = true
        guard ContactBindingRule.isValid(email, for: .email) else { return }
        Task {
            let contractLocale = locale.identifier.hasPrefix("zh") ? "zh-CN" : "en"
            if await appState.requestFirstEmailBinding(email: email, locale: contractLocale) {
                codeSent = true
                code = ""
            }
        }
    }

    private func verify() {
        codeTouched = true
        guard codeSent, ContactBindingRule.isValidStudentSignInCode(code) else { return }
        Task {
            if await appState.verifyFirstEmailBinding(code: code) {
                onComplete()
            }
        }
    }
}

#if false // Retired phone/SMS and local verification presentation.
/// One contact: enter it, request a code, then verify. The send button waits
/// out the server's resend window before it can be used again.
struct ContactChannelPanel: View {
    @EnvironmentObject private var appState: AppState
    let channel: ContactChannel
    @Binding var value: String
    @Binding var verifiedValue: String?
    /// Settings lets a student swap an already-verified contact; registration
    /// does not, because the request has not been filed yet.
    var allowsReplacement = false

    @State private var code = ""
    @State private var codeSent = false
    @State private var resendSeconds = 0
    @State private var notice: String?
    @FocusState private var isFocused: Bool

    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text(LocalizedStringKey(channel.title))
                    .font(BNBUFont.titleMedium)

                if let verifiedValue {
                    verifiedRow(verifiedValue)
                } else {
                    contactRow
                    if codeSent { codeRow }
                    if let notice {
                        Text(verbatim: notice)
                            .font(BNBUFont.labelMedium)
                            .foregroundStyle(BNBUTheme.muted)
                    }
                }
            }
        }
        .onReceive(ticker) { _ in
            if resendSeconds > 0 { resendSeconds -= 1 }
        }
    }

    private func verifiedRow(_ verified: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(BNBUTheme.primary)
                Text(verbatim: BNBUL10n.formatted(
                    "%@已验证",
                    BNBUL10n.dynamicText(channel.title)
                ))
                .font(BNBUFont.titleSmall)
                .foregroundStyle(BNBUTheme.onSurface)
                Spacer(minLength: 0)
                Text(verbatim: ContactBindingRule.masked(verified, for: channel))
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("contactBinding.\(channel.rawValue).verified")

            if allowsReplacement {
                OutlinedActionButton(
                    title: channel == .phone ? "更换手机号" : "更换邮箱",
                    systemImage: "arrow.triangle.2.circlepath",
                    accessibilityIdentifier: "contactBinding.\(channel.rawValue).change"
                ) {
                    verifiedValue = nil
                    value = ""
                    code = ""
                    codeSent = false
                    notice = nil
                }
            }
        }
    }

    private var contactRow: some View {
        HStack(spacing: 10) {
            Image(systemName: channel.systemImage)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            if channel == .phone {
                Text(verbatim: "+86")
                    .font(BNBUFont.titleSmall)
                Divider().frame(height: 24)
            }
            TextField(placeholder, text: $value)
                .bnbuInputText()
                .keyboardType(channel == .phone ? .numberPad : .emailAddress)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($isFocused)
                .accessibilityLabel(Text(LocalizedStringKey(channel.title)))
                .accessibilityIdentifier("contactBinding.\(channel.rawValue).value")

            Button(sendTitle) { sendCode() }
                .font(BNBUFont.labelMedium)
                .foregroundStyle(canSend ? BNBUTheme.primary : BNBUTheme.onSurfaceVariant.opacity(0.55))
                .disabled(!canSend)
                .buttonStyle(.plain)
                .accessibilityIdentifier("contactBinding.\(channel.rawValue).sendCode")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: BNBUSpacing.touchTarget)
        .background(BNBUTheme.surface)
        .bnbuOutlinedSurface(lineWidth: 1)
    }

    private var codeRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            TextField(channel.codeTitle, text: $code)
                .bnbuInputText()
                .keyboardType(.numberPad)
                .onChange(of: code) { _, entered in
                    code = String(entered.filter(\.isNumber).prefix(ContactBindingRule.codeLength))
                }
                .accessibilityLabel(Text(LocalizedStringKey(channel.codeTitle)))
                .accessibilityIdentifier("contactBinding.\(channel.rawValue).code")

            Button("确认验证") { verify() }
                .font(BNBUFont.labelMedium)
                .foregroundStyle(
                    ContactBindingRule.isValidCode(code)
                        ? BNBUTheme.primary
                        : BNBUTheme.onSurfaceVariant.opacity(0.55)
                )
                .disabled(!ContactBindingRule.isValidCode(code))
                .buttonStyle(.plain)
                .accessibilityIdentifier("contactBinding.\(channel.rawValue).verify")
        }
        .padding(.horizontal, 14)
        .frame(minHeight: BNBUSpacing.touchTarget)
        .background(BNBUTheme.surface)
        .bnbuOutlinedSurface(lineWidth: 1)
    }

    private var placeholder: String {
        channel == .phone ? BNBUL10n.text("请输入 11 位手机号") : "name@bnbu.edu.cn"
    }

    private var sendTitle: String {
        resendSeconds > 0
            ? BNBUL10n.formatted("%lld 秒后可重发", resendSeconds)
            : BNBUL10n.text("获取验证码")
    }

    private var canSend: Bool {
        resendSeconds == 0 && ContactBindingRule.isValid(value, for: channel)
    }

    private func sendCode() {
        isFocused = false
        guard appState.sendContactVerificationCode(to: value, channel: channel) else {
            notice = appState.errorMessage
            return
        }
        codeSent = true
        resendSeconds = ContactBindingRule.resendInterval
        notice = BNBUL10n.text("验证码已发送，10 分钟内有效。")
    }

    private func verify() {
        guard appState.verifyContactCode(code, for: value, channel: channel) else {
            notice = appState.errorMessage
            return
        }
        verifiedValue = value
        notice = nil
    }
}
#endif

private struct CourseJoinFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(LocalizedStringKey(label))
                .font(BNBUFont.labelMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            Text(verbatim: BNBUL10n.dynamicText(value))
                .font(BNBUFont.bodyLarge)
                .foregroundStyle(BNBUTheme.onSurface)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CourseJoinField: View {
    let label: String
    @Binding var text: String
    var limit: Int?
    var keyboardType: UIKeyboardType = .default
    var errorText: String?
    var focusBinding: FocusState<Bool>.Binding?
    let identifier: String

    var body: some View {
        BNBUFormField(
            label: label,
            placeholder: "",
            text: $text,
            required: true,
            errorText: errorText,
            characterLimit: limit,
            keyboardType: keyboardType,
            focusBinding: focusBinding,
            accessibilityIdentifier: identifier
        )
    }
}

enum CourseJoinScannerAlert: String, Identifiable {
    case unavailable
    case denied
    case restricted
    case unrecognized
    case urlHostNotConfigured

    var id: String { rawValue }

    func alert(openSettings: @escaping () -> Void) -> Alert {
        switch self {
        case .unavailable:
            return Alert(
                title: Text("当前设备无法扫码"),
                message: Text("模拟器或当前设备没有可用摄像头，请改用邀请码加入课程。"),
                dismissButton: .default(Text("好"))
            )
        case .denied:
            return Alert(
                title: Text("摄像头权限未开启"),
                message: Text("扫描课程二维码需要允许 BNBU Student 使用摄像头，也可以改用邀请码加入课程。"),
                primaryButton: .default(Text("去设置")) { openSettings() },
                secondaryButton: .cancel(Text("取消"))
            )
        case .restricted:
            return Alert(
                title: Text("摄像头受系统限制"),
                message: Text("当前设备策略不允许使用摄像头，请改用邀请码加入课程。"),
                dismissButton: .default(Text("好"))
            )
        case .unrecognized:
            return Alert(
                title: Text("二维码无法识别"),
                message: Text("这不是有效的课程二维码，请向老师确认或改用邀请码加入课程。"),
                dismissButton: .default(Text("好"))
            )
        case .urlHostNotConfigured:
            return Alert(
                title: Text("课程链接域名尚未配置"),
                message: Text("CONTRACT DECISION REQUIRED：本地环境没有显式配置课程邀请 URL allowlist。请手动输入邀请码；App 不会猜测正式域名。"),
                dismissButton: .default(Text("好"))
            )
        }
    }
}

/// Live QR capture. Availability and permission are resolved by the caller, so
/// this view only runs the session and reports the first payload it reads.
struct CourseQRScannerView: UIViewControllerRepresentable {
    static var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
            && AVCaptureDevice.default(for: .video) != nil
    }

    let onScan: (String) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> CourseQRScannerViewController {
        let controller = CourseQRScannerViewController()
        controller.onScan = onScan
        controller.onCancel = onCancel
        return controller
    }

    func updateUIViewController(_ uiViewController: CourseQRScannerViewController, context: Context) {}
}

final class CourseQRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onScan: ((String) -> Void)?
    var onCancel: (() -> Void)?

    private let session = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var hasReportedScan = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configureSession()
        configureOverlay()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        startSessionIfNeeded()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else { return }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.frame = view.bounds
        view.layer.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    private func configureOverlay() {
        let hint = UILabel()
        hint.text = BNBUL10n.text("将课程二维码放入取景框")
        hint.textColor = .white
        hint.font = .preferredFont(forTextStyle: .subheadline)
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false

        let cancel = UIButton(type: .system)
        cancel.setTitle(BNBUL10n.text("取消"), for: .normal)
        cancel.tintColor = .white
        cancel.titleLabel?.font = .preferredFont(forTextStyle: .headline)
        cancel.accessibilityIdentifier = "course.join.scanner.cancel"
        cancel.addTarget(self, action: #selector(cancelTapped), for: .touchUpInside)
        cancel.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(hint)
        view.addSubview(cancel)
        NSLayoutConstraint.activate([
            hint.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            hint.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -24),
            hint.bottomAnchor.constraint(equalTo: cancel.topAnchor, constant: -20),
            cancel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cancel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24)
        ])
    }

    private func startSessionIfNeeded() {
        guard !session.isRunning else { return }
        // Session start blocks; keeping it off the main thread avoids a hitch
        // while the camera warms up.
        Task.detached(priority: .userInitiated) { [session] in
            session.startRunning()
        }
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard !hasReportedScan,
              let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              object.type == .qr,
              let payload = object.stringValue else { return }
        hasReportedScan = true
        session.stopRunning()
        AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
        onScan?(payload)
    }
}
