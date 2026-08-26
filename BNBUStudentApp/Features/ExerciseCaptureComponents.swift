import AVFoundation
import SwiftUI
import UIKit

enum ExerciseCameraCapturePurpose {
    case checkIn
    case exemption

    var videoMaximumDuration: TimeInterval {
        switch self {
        case .checkIn:
            return ExerciseMediaDraftRule.maximumVideoDurationSeconds
        case .exemption:
            return 30
        }
    }

    func requiresMicrophone(
        for initialCaptureMode: UIImagePickerController.CameraCaptureMode?
    ) -> Bool {
        guard initialCaptureMode != .photo else { return false }
        switch self {
        case .checkIn:
            return true
        case .exemption:
            return false
        }
    }

    var unavailableMessage: String {
        switch self {
        case .checkIn:
            return BNBUL10n.text("打卡凭证只能通过相机实时拍摄。模拟器或当前设备没有可用摄像头。")
        case .exemption:
            return BNBUL10n.locale.identifier.hasPrefix("zh")
                ? "免测证明只能通过相机现场拍摄。模拟器或当前设备没有可用摄像头。"
                : "Exemption proof must be captured live with the camera. This simulator or device has no available camera."
        }
    }

    var deniedMessage: String {
        switch self {
        case .checkIn:
            return BNBUL10n.text("打卡凭证只能通过相机实时拍摄，需要允许 BNBU Student 使用摄像头。")
        case .exemption:
            return BNBUL10n.locale.identifier.hasPrefix("zh")
                ? "免测证明只能通过相机现场拍摄，需要允许 BNBU Student 使用摄像头。"
                : "Exemption proof must be captured live. Allow BNBU Student to use the camera."
        }
    }
}

/// Camera-only capture entry for the check-in flow (business rule 6.4: no
/// photo-library access for check-in proofs). Handles availability and
/// permission states, then hands the capture to `onCapture`.
struct ExerciseCameraCaptureButton: View {
    @Environment(\.openURL) private var openURL
    let title: String
    var systemImage = "camera.fill"
    var purpose: ExerciseCameraCapturePurpose = .checkIn
    var initialCaptureMode: UIImagePickerController.CameraCaptureMode? = nil
    var isDisabled = false
    var accessibilityIdentifier: String?
    let onCapture: (ProofAttachment) -> Void

    @State private var isCameraPresented = false
    @State private var activeAlert: ExerciseCameraAlert?
    @State private var pendingAttachment: ProofAttachment?
    @State private var retakesAfterConfirmation = false

    var body: some View {
        Button {
            handleCameraAction()
        } label: {
            Label {
                Text(LocalizedStringKey(title))
            } icon: {
                Image(systemName: systemImage)
            }
                .font(BNBUFont.titleSmall)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(isDisabled ? BNBUTheme.muted : BNBUTheme.primary)
                .background(BNBUTheme.surface)
                .bnbuOutlinedSurface(radius: BNBURadius.extraLarge, lineWidth: 1.5)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityIdentifier(accessibilityIdentifier ?? "checkin.capture.camera")
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraCapturePicker(
                initialCaptureMode: initialCaptureMode,
                videoMaximumDuration: purpose.videoMaximumDuration
            ) { attachment in
                // A camera result is not Session evidence yet. The student can
                // still cancel or retake here; only the explicit keep action
                // moves it into the retained evidence collection.
                pendingAttachment = attachment
            }
            .ignoresSafeArea()
        }
        .sheet(item: $pendingAttachment, onDismiss: {
            guard retakesAfterConfirmation else { return }
            retakesAfterConfirmation = false
            isCameraPresented = true
        }) { attachment in
            ExerciseCaptureConfirmationSheet(
                attachment: attachment,
                cancelAction: {
                    discardPendingAttachment(attachment)
                    pendingAttachment = nil
                },
                retakeAction: {
                    discardPendingAttachment(attachment)
                    retakesAfterConfirmation = true
                    pendingAttachment = nil
                },
                keepAction: {
                    pendingAttachment = nil
                    onCapture(attachment)
                }
            )
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .unavailable:
                return Alert(
                    title: Text("当前设备无法拍摄"),
                    message: Text(purpose.unavailableMessage),
                    dismissButton: .default(Text("好"))
                )
            case .denied:
                return Alert(
                    title: Text("摄像头权限未开启"),
                    message: Text(purpose.deniedMessage),
                    primaryButton: .default(Text("去设置")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .restricted:
                return Alert(
                    title: Text("摄像头受系统限制"),
                    message: Text("当前设备策略不允许使用摄像头，请联系设备管理员。"),
                    dismissButton: .default(Text("好"))
                )
            case .microphoneDenied:
                return Alert(
                    title: Text("麦克风权限未开启"),
                    message: Text("现场录像必须包含声音，需要允许 BNBU Student 使用麦克风。"),
                    primaryButton: .default(Text("去设置")) {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            openURL(url)
                        }
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .microphoneRestricted:
                return Alert(
                    title: Text("麦克风受系统限制"),
                    message: Text("现场录像必须包含声音，但当前设备策略不允许使用麦克风。"),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private func handleCameraAction() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            activeAlert = .unavailable
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            presentCameraAfterMicrophoneCheck()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        presentCameraAfterMicrophoneCheck()
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

    private func discardPendingAttachment(_ attachment: ProofAttachment) {
        guard attachment.type == .video else { return }
        ProofTransientFileStore.removeManagedCopy(at: attachment.sourceFileURL)
    }

    @MainActor
    private func presentCameraAfterMicrophoneCheck() {
        guard purpose.requiresMicrophone(for: initialCaptureMode) else {
            isCameraPresented = true
            return
        }
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            isCameraPresented = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                Task { @MainActor in
                    if granted {
                        isCameraPresented = true
                    } else {
                        activeAlert = .microphoneDenied
                    }
                }
            }
        case .denied:
            activeAlert = .microphoneDenied
        case .restricted:
            activeAlert = .microphoneRestricted
        @unknown default:
            activeAlert = .microphoneRestricted
        }
    }
}

/// The only editable step in the check-in evidence lifecycle. Once the
/// student confirms retention, the attachment is persisted as Session
/// evidence and later screens intentionally expose no exclude/delete action.
private struct ExerciseCaptureConfirmationSheet: View {
    let attachment: ProofAttachment
    let cancelAction: () -> Void
    let retakeAction: () -> Void
    let keepAction: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: BNBUSpacing.space20) {
                Text("确认保留现场凭证")
                    .font(BNBUFont.headlineSmall)
                    .foregroundStyle(BNBUTheme.onSurface)

                Text("确认保留后，这份素材会进入本次运动的完整凭证集合，提交前不能再取消选择或删除。")
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .fixedSize(horizontal: false, vertical: true)

                preview
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .background(BNBUTheme.surfaceVariant)
                    .clipShape(RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous))

                Spacer(minLength: BNBUSpacing.space8)

                DisabledAwareButton(
                    title: "确认保留",
                    systemImage: "checkmark.shield.fill",
                    isDisabled: false,
                    accessibilityIdentifier: "checkin.capture.keep"
                ) {
                    keepAction()
                }

                HStack(spacing: BNBUSpacing.space12) {
                    SecondaryActionButton(title: "重拍", systemImage: "arrow.clockwise") {
                        retakeAction()
                    }
                    .accessibilityIdentifier("checkin.capture.retake")

                    SecondaryActionButton(title: "放弃", systemImage: "xmark") {
                        cancelAction()
                    }
                    .accessibilityIdentifier("checkin.capture.discard")
                }
            }
            .padding(BNBUSpacing.screen)
            .background(BNBUPageBackground())
            .interactiveDismissDisabled()
        }
        .accessibilityIdentifier("checkin.capture.confirmation")
    }

    @ViewBuilder
    private var preview: some View {
        if let thumbnailData = attachment.thumbnailData,
           let image = UIImage(data: thumbnailData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Image(systemName: attachment.type == .video ? "video.fill" : "photo.fill")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(BNBUTheme.primary)
        }
    }
}

private enum ExerciseCameraAlert: Identifiable {
    case unavailable
    case denied
    case restricted
    case microphoneDenied
    case microphoneRestricted

    var id: String {
        switch self {
        case .unavailable: return "unavailable"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .microphoneDenied: return "microphone-denied"
        case .microphoneRestricted: return "microphone-restricted"
        }
    }
}

/// Small tinted capsule used for the session lifecycle state and capture
/// result, matching the pills Android puts on the trailing edge of each card.
struct SessionStatePill: View {
    let text: String
    let tint: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(tint)
                .frame(width: 6, height: 6)
            Text(verbatim: text)
                .font(BNBUFont.labelMedium)
                .foregroundStyle(tint)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }
}

/// Read-only strip of what has been captured so far. The evidence form still
/// owns selection; this only mirrors Android's "已拍摄素材" preview.
struct ExerciseDraftThumbnailStrip: View {
    let drafts: [ExerciseMediaDraft]

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
            ForEach(drafts) { draft in
                VStack(alignment: .leading, spacing: 6) {
                    // A filled rectangle owns the cell size; the thumbnail rides
                    // in an overlay so a short or oversized capture cannot drag
                    // the row height around.
                    Rectangle()
                        .fill(BNBUTheme.surfaceVariant)
                        .frame(height: 78)
                        .overlay {
                            thumbnail(for: draft)
                        }
                        .overlay {
                            if draft.type == .video {
                                Image(systemName: "play.fill")
                                    .font(BNBUFont.labelMedium)
                                    .foregroundStyle(BNBUTheme.surface)
                                    .frame(width: 30, height: 30)
                                    .background(BNBUTheme.overlayBlack.opacity(0.55))
                                    .clipShape(Circle())
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.extraSmall, style: .continuous))

                    HStack(spacing: 4) {
                        Text(draft.type == .video ? "现场视频" : "现场照片")
                            .font(BNBUFont.labelSmall)
                            .foregroundStyle(BNBUTheme.onSurface)
                        Spacer(minLength: 0)
                        Image(systemName: "checkmark.shield.fill")
                            .font(BNBUFont.labelSmall)
                            .foregroundStyle(BNBUTheme.tertiary)
                            .accessibilityLabel("已确认保留")
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private func thumbnail(for draft: ExerciseMediaDraft) -> some View {
        if let data = draft.thumbnailData, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Image(systemName: draft.type == .video ? "video.fill" : "photo.fill")
                .font(BNBUFont.titleMedium)
                .foregroundStyle(BNBUTheme.primary)
        }
    }
}

/// Read-only retained evidence shown in the final form. Capture confirmation
/// is the last point where a student may cancel or retake; every draft in this
/// collection is submitted and cannot be excluded here.
struct ExerciseProofSelectionPanel: View {
    let drafts: [ExerciseMediaDraft]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if drafts.isEmpty {
                Text("尚无拍摄草稿。请使用上方按钮通过相机拍摄照片或录制视频。")
                    .font(BNBUFont.labelMedium)
                    .foregroundStyle(BNBUTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                HStack(spacing: 8) {
                    StatusBadge(text: "已保留 \(imageCount) 张照片")
                    StatusBadge(text: "已保留 \(videoCount) 个视频")
                    Spacer()
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(drafts) { draft in
                        ExerciseMediaDraftCard(draft: draft)
                    }
                }
            }
        }
    }

    private var imageCount: Int {
        drafts.filter { $0.type == .image }.count
    }

    private var videoCount: Int {
        drafts.filter { $0.type == .video }.count
    }
}

struct ExerciseMediaDraftCard: View {
    @Environment(\.locale) private var locale
    let draft: ExerciseMediaDraft

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topLeading) {
                thumbnail
                    .aspectRatio(1.25, contentMode: .fit)
                    .clipped()
                    .bnbuOutlinedSurface()

                if draft.type == .video {
                    Image(systemName: "play.fill")
                        .font(BNBUFont.labelMedium)
                        .foregroundStyle(BNBUTheme.surface)
                        .frame(width: 28, height: 28)
                        .background(BNBUTheme.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                Image(systemName: "checkmark.shield.fill")
                    .font(BNBUFont.titleLarge)
                    .foregroundStyle(BNBUTheme.tertiary)
                    .background(Circle().fill(BNBUTheme.surface))
                    .padding(6)
                    .accessibilityLabel("已确认保留")
            }

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.fileName)
                        .font(BNBUFont.labelMedium)
                        .foregroundStyle(BNBUTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(metadataText)
                        .font(BNBUFont.bodySmall)
                        .foregroundStyle(BNBUTheme.muted)
                }
                Spacer()
                Text("已保留")
                    .font(BNBUFont.labelSmall)
                    .foregroundStyle(BNBUTheme.tertiary)
            }
        }
        .padding(10)
        .background(BNBUTheme.surface)
        .overlay(
            Rectangle()
                .stroke(BNBUTheme.tertiary, lineWidth: 1.5)
        )
        .accessibilityElement(children: .contain)
    }

    private var metadataText: String {
        var parts: [String] = [
            draft.capturedAt.formatted(
                Date.FormatStyle()
                    .hour()
                    .minute()
                    .locale(locale)
            )
        ]
        if let durationSeconds = draft.durationSeconds {
            parts.append("\(Int(durationSeconds.rounded())) 秒")
        }
        let megabytes = Double(draft.byteCount) / 1_000_000
        parts.append(String(format: "%.1fMB", megabytes))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbnailData = draft.thumbnailData,
           let image = UIImage(data: thumbnailData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(BNBUTheme.pale)
                .overlay {
                    Image(systemName: draft.type == .video ? "video.fill" : "photo.fill")
                        .font(BNBUFont.titleLarge)
                        .foregroundStyle(BNBUTheme.blue)
                }
        }
    }
}
