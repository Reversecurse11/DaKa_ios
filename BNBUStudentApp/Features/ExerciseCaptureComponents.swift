import AVFoundation
import SwiftUI
import UIKit

/// Camera-only capture entry for the check-in flow (business rule 6.4: no
/// photo-library access for check-in proofs). Handles availability and
/// permission states, then hands the capture to `onCapture`.
struct ExerciseCameraCaptureButton: View {
    @Environment(\.openURL) private var openURL
    let title: String
    var systemImage = "camera.fill"
    var isDisabled = false
    var accessibilityIdentifier: String?
    let onCapture: (ProofAttachment) -> Void

    @State private var isCameraPresented = false
    @State private var activeAlert: ExerciseCameraAlert?

    var body: some View {
        Button {
            handleCameraAction()
        } label: {
            Label {
                Text(LocalizedStringKey(title))
            } icon: {
                Image(systemName: systemImage)
            }
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(isDisabled ? BNBUTheme.muted : BNBUTheme.ink)
                .background(BNBUTheme.surface)
                .bnbuOutlinedSurface(radius: BNBURadius.extraLarge, lineWidth: 1.5)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityIdentifier(accessibilityIdentifier ?? "checkin.capture.camera")
        .fullScreenCover(isPresented: $isCameraPresented) {
            CameraCapturePicker { attachment in
                onCapture(attachment)
            }
            .ignoresSafeArea()
        }
        .alert(item: $activeAlert) { alert in
            switch alert {
            case .unavailable:
                return Alert(
                    title: Text("当前设备无法拍摄"),
                    message: Text("打卡凭证只能通过相机实时拍摄。模拟器或当前设备没有可用摄像头。"),
                    dismissButton: .default(Text("好"))
                )
            case .denied:
                return Alert(
                    title: Text("摄像头权限未开启"),
                    message: Text("打卡凭证只能通过相机实时拍摄，需要允许 BNBU Student 使用摄像头。"),
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
            isCameraPresented = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    if granted {
                        isCameraPresented = true
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
}

private enum ExerciseCameraAlert: Identifiable {
    case unavailable
    case denied
    case restricted

    var id: String {
        switch self {
        case .unavailable: return "unavailable"
        case .denied: return "denied"
        case .restricted: return "restricted"
        }
    }
}

/// Draft picker shown in the evidence form: the student selects check-in
/// proofs from media captured during/after the exercise. Selection is capped
/// at 6 photos + 1 video (business rule 6.1).
struct ExerciseProofSelectionPanel: View {
    let drafts: [ExerciseMediaDraft]
    @Binding var selectedDraftIDs: Set<String>
    let onDelete: (ExerciseMediaDraft) -> Void
    @State private var notice: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if drafts.isEmpty {
                Text("尚无拍摄草稿。请使用上方按钮通过相机拍摄照片或录制视频。")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BNBUTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                HStack(spacing: 8) {
                    StatusBadge(text: "已选 \(selectedImageCount) 张照片")
                    StatusBadge(text: "已选 \(selectedVideoCount) 个视频")
                    Spacer()
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(drafts) { draft in
                        ExerciseMediaDraftCard(
                            draft: draft,
                            isSelected: selectedDraftIDs.contains(draft.id),
                            toggleAction: { toggle(draft) },
                            deleteAction: { onDelete(draft) }
                        )
                    }
                }
            }

            if let notice {
                Text(notice)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BNBUTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(BNBUTheme.surface)
                    .bnbuOutlinedSurface()
            }
        }
    }

    private var selectedDrafts: [ExerciseMediaDraft] {
        drafts.filter { selectedDraftIDs.contains($0.id) }
    }

    private var selectedImageCount: Int {
        selectedDrafts.filter { $0.type == .image }.count
    }

    private var selectedVideoCount: Int {
        selectedDrafts.filter { $0.type == .video }.count
    }

    private func toggle(_ draft: ExerciseMediaDraft) {
        if selectedDraftIDs.contains(draft.id) {
            selectedDraftIDs.remove(draft.id)
            notice = nil
            return
        }
        if draft.type == .image, selectedImageCount >= ProofUploadRule.maxImageCount {
            notice = "最多选择 \(ProofUploadRule.maxImageCount) 张照片作为凭证。"
            return
        }
        if draft.type == .video, selectedVideoCount >= ProofUploadRule.maxVideoCount {
            notice = "最多选择 \(ProofUploadRule.maxVideoCount) 个视频作为凭证。"
            return
        }
        selectedDraftIDs.insert(draft.id)
        notice = nil
    }
}

struct ExerciseMediaDraftCard: View {
    @Environment(\.locale) private var locale
    let draft: ExerciseMediaDraft
    let isSelected: Bool
    let toggleAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: toggleAction) {
                ZStack(alignment: .topLeading) {
                    thumbnail
                        .aspectRatio(1.25, contentMode: .fit)
                        .clipped()
                        .bnbuOutlinedSurface()

                    if draft.type == .video {
                        Image(systemName: "play.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BNBUTheme.surface)
                            .frame(width: 28, height: 28)
                            .background(BNBUTheme.ink)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    }

                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(isSelected ? BNBUTheme.primary : BNBUTheme.surface)
                        .background(
                            Circle().fill(isSelected ? BNBUTheme.surface : BNBUTheme.ink.opacity(0.35))
                        )
                        .padding(6)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("checkin.draft.toggle.\(draft.id)")
            .accessibilityLabel(isSelected ? "取消选择 \(draft.fileName)" : "选择 \(draft.fileName) 作为凭证")

            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(draft.fileName)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BNBUTheme.ink)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(metadataText)
                        .font(.caption.weight(.regular))
                        .foregroundStyle(BNBUTheme.muted)
                }
                Spacer()
                Button(action: deleteAction) {
                    Image(systemName: "trash")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BNBUTheme.muted)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("checkin.draft.delete.\(draft.id)")
                .accessibilityLabel("删除草稿 \(draft.fileName)")
            }
        }
        .padding(10)
        .background(BNBUTheme.surface)
        .overlay(
            Rectangle()
                .stroke(isSelected ? BNBUTheme.primary : BNBUTheme.line, lineWidth: isSelected ? 2 : 1)
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
                        .font(.title3.weight(.medium))
                        .foregroundStyle(BNBUTheme.blue)
                }
        }
    }
}
