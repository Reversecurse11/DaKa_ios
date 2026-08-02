import AudioToolbox
import AVFoundation
import SwiftUI
import UIKit

/// Course join application entry (business rule 4.2). A student joins before
/// signing in: scan the course QR code or type the invite code, confirm the
/// course the invite resolves to, then supply identity details for the teacher
/// to review. Only an approved application opens the main app.
struct CourseJoinSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Set by a scan entry so tapping it goes straight to the camera instead of
    /// asking the student to pick an entry point twice.
    var autoPresentsScanner = false

    @State private var step: CourseJoinStep = .entry
    @State private var code = ""
    @State private var isScannerPresented = false
    @State private var activeAlert: CourseJoinScannerAlert?
    @FocusState private var isCodeFocused: Bool

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
                        onContinue: { name, studentNumber in
                            appState.errorMessage = nil
                            step = .contactBinding(
                                invite,
                                name: name,
                                studentNumber: studentNumber
                            )
                        }
                    )
                case let .contactBinding(invite, name, studentNumber):
                    // Binding is not optional and has no way back: the student
                    // has to be reachable before a teacher sees the request.
                    ContactBindingView { phone, email in
                        guard appState.submitCourseJoinRequest(
                            invite: invite,
                            name: name,
                            studentNumber: studentNumber,
                            phone: phone,
                            email: email
                        ) else { return }
                        step = .submitted
                    }
                case .submitted:
                    JoinRequestStatusView(
                        request: appState.courseJoinRequest,
                        onBack: { dismiss() },
                        onContactTeacher: { dismiss() },
                        onEditAndResubmit: { _ in restartWithNewInvite() },
                        onUseNewInvite: { restartWithNewInvite() },
                        onApproved: { dismiss() }
                    )
                }
            }
            .navigationTitle("加入课程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .accessibilityIdentifier("course.join.close")
                }
            }
        }
        .accessibilityIdentifier("screen.courseJoin")
        .onAppear {
            // A student who already filed an application lands on its status
            // rather than being invited to file a second one.
            if let request = appState.courseJoinRequest, request.status != .active {
                step = .submitted
            } else if autoPresentsScanner {
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

    private var scanPanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 14) {
                Text("扫描课程二维码")
                    .font(BNBUFont.titleMedium)
                Text("扫描任课老师提供的课程二维码，核对课程信息后填写姓名和学号提交申请，老师审核通过后才能进入。")
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
                TextField("例如：BNBU2026", text: $code)
                    .bnbuInputText()
                    .accessibilityLabel("课程邀请码")
                    .accessibilityHint("填写老师提供的课程邀请码")
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(BNBUTheme.surface)
                    .bnbuOutlinedSurface(lineWidth: 1.5)
                    .focused($isCodeFocused)
                    .submitLabel(.done)
                    .onSubmit { lookUpInvite() }
                    .accessibilityIdentifier("course.join.code.field")

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
        isCodeFocused = false
        appState.errorMessage = nil
        guard let invite = appState.lookupCourseInvite(rawCode: code) else { return }
        step = .confirm(invite)
        code = ""
    }

    private func restartWithNewInvite() {
        appState.clearCourseJoinRequest()
        appState.errorMessage = nil
        step = .entry
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
    case contactBinding(CourseInvite, name: String, studentNumber: String)
    case submitted
}

/// Android's `CourseJoinConfirmScreen`: the invite's course is shown for
/// confirmation, then the student supplies the identity the teacher reviews.
struct CourseJoinConfirmView: View {
    @EnvironmentObject private var appState: AppState
    let invite: CourseInvite
    let onBack: () -> Void
    let onContinue: (_ name: String, _ studentNumber: String) -> Void

    @State private var name = ""
    @State private var studentNumber = ""
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case name
        case studentNumber
    }

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
                    focusedField = nil
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
                Text("请确认以上课程信息无误后再提交申请")
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
                    label: "姓名（必填）",
                    text: $name,
                    limit: CourseJoinRequestRule.maximumNameLength,
                    identifier: "courseJoinConfirm.name"
                )
                .focused($focusedField, equals: .name)

                CourseJoinField(
                    label: "学号（必填）",
                    text: $studentNumber,
                    limit: CourseJoinRequestRule.maximumStudentNumberLength,
                    identifier: "courseJoinConfirm.studentNumber"
                )
                .focused($focusedField, equals: .studentNumber)

                PrimaryActionButton(
                    title: "下一步：绑定联系方式",
                    systemImage: "arrow.right",
                    accessibilityIdentifier: "courseJoinConfirm.submit"
                ) {
                    submit()
                }
            }
        }
    }

    private func submit() {
        focusedField = nil
        dismissBNBUKeyboard()
        if let validationMessage = CourseJoinRequestRule.validationMessage(
            name: name,
            studentNumber: studentNumber
        ) {
            appState.errorMessage = validationMessage
            return
        }
        onContinue(name, studentNumber)
    }
}

/// Both contacts are bound before the application reaches the teacher: a
/// student who reinstalls the app signs back in with a code sent to one of
/// them, so registration is not complete until both are verified.
struct ContactBindingView: View {
    @EnvironmentObject private var appState: AppState
    let onBound: (_ phone: String, _ email: String) -> Void

    @State private var phone = ""
    @State private var email = ""
    @State private var verifiedPhone: String?
    @State private var verifiedEmail: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                SectionTitle(eyebrow: "ACCOUNT", title: "绑定手机号和邮箱")
                Text("退出登录或更换设备后，用这里绑定的手机号或邮箱接收验证码即可找回本账号。两项都验证通过后才能提交加入申请。")
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .lineSpacing(3)

                ContactChannelPanel(
                    channel: .phone,
                    value: $phone,
                    verifiedValue: $verifiedPhone
                )
                ContactChannelPanel(
                    channel: .email,
                    value: $email,
                    verifiedValue: $verifiedEmail
                )

                DisabledAwareButton(
                    title: "提交加入申请",
                    systemImage: "paperplane.fill",
                    isDisabled: verifiedPhone == nil || verifiedEmail == nil,
                    accessibilityIdentifier: "contactBinding.submit"
                ) {
                    guard let verifiedPhone, let verifiedEmail else { return }
                    onBound(verifiedPhone, verifiedEmail)
                }
            }
            .padding(BNBUSpacing.screen)
        }
        .scrollDismissesKeyboard(.immediately)
        .accessibilityIdentifier("screen.contactBinding")
    }
}

/// One contact: enter it, request a code, then verify. The send button waits
/// out the server's resend window before it can be used again.
private struct ContactChannelPanel: View {
    @EnvironmentObject private var appState: AppState
    let channel: ContactChannel
    @Binding var value: String
    @Binding var verifiedValue: String?

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
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(LocalizedStringKey(label))
                .font(BNBUFont.labelMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)

            TextField("", text: $text)
                .bnbuInputText()
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(BNBUTheme.surface)
                .bnbuOutlinedSurface(lineWidth: 1)
                .accessibilityLabel(Text(LocalizedStringKey(label)))
                .accessibilityIdentifier(identifier)
                .onChange(of: text) { _, value in
                    guard let limit, value.count > limit else { return }
                    text = String(value.prefix(limit))
                }

            if let limit {
                Text(verbatim: "\(text.count) / \(limit)")
                    .font(BNBUFont.labelSmall)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
    }
}

enum CourseJoinScannerAlert: String, Identifiable {
    case unavailable
    case denied
    case restricted
    case unrecognized

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
