import AudioToolbox
import AVFoundation
import SwiftUI
import UIKit

/// Course join application entry (business rule 4.2). Students scan the course
/// QR code or type the invite code; the teacher approves before the enrolment
/// becomes real, so this screen only submits an application.
struct CourseJoinSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""
    @State private var isScannerPresented = false
    @State private var activeAlert: CourseJoinScannerAlert?
    @State private var submittedCode: String?
    @FocusState private var isCodeFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                BNBUPageBackground()

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let submittedCode {
                            submittedPanel(code: submittedCode)
                        } else {
                            scanPanel
                            codePanel
                        }
                    }
                    .padding(BNBUSpacing.screen)
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
                Text("扫描任课老师提供的课程二维码后自动填入邀请码，提交后需要老师审核通过才能开始打卡。")
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
                    .onSubmit { submit() }
                    .accessibilityIdentifier("course.join.code.field")

                if let message = appState.errorMessage {
                    Text(verbatim: message)
                        .font(BNBUFont.labelMedium)
                        .foregroundStyle(BNBUTheme.muted)
                        .accessibilityIdentifier("course.join.error")
                }

                DisabledAwareButton(
                    title: "提交加入申请",
                    systemImage: "paperplane.fill",
                    isDisabled: CourseJoinCodeRule.validationMessage(for: code) != nil,
                    accessibilityIdentifier: "course.join.submit"
                ) {
                    submit()
                }
            }
        }
    }

    private func submittedPanel(code: String) -> some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 12) {
                Label("加入申请已提交", systemImage: "checkmark.seal")
                    .font(BNBUFont.titleMedium)
                    .foregroundStyle(BNBUTheme.primary)
                Text(verbatim: BNBUL10n.formatted("邀请码 %@ 的加入申请已提交，老师审核通过后即可开始打卡。", code))
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .lineSpacing(3)
                PrimaryActionButton(
                    title: "完成",
                    systemImage: "checkmark",
                    accessibilityIdentifier: "course.join.done"
                ) {
                    dismiss()
                }
            }
        }
    }

    private func submit() {
        isCodeFocused = false
        appState.errorMessage = nil
        let normalized = CourseJoinCodeRule.normalized(code)
        guard appState.submitCourseJoinRequest(rawCode: code) else { return }
        submittedCode = normalized
        code = ""
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
        submit()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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
