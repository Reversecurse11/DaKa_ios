import SwiftUI
import PhotosUI
import CoreTransferable
import UniformTypeIdentifiers
import AVFoundation
import UIKit

struct GridBackground: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 42
            let color = BNBUTheme.outline.opacity(0.06)
            var path = Path()

            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }

            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }

            context.stroke(path, with: .color(color), lineWidth: 1)
        }
        .background(BNBUTheme.background)
        .ignoresSafeArea()
    }
}

struct BNBUPageBackground: View {
    var body: some View {
        BNBUTheme.background
            .ignoresSafeArea()
    }
}

extension View {
    func bnbuOutlinedSurface(
        radius: CGFloat = BNBURadius.small,
        lineWidth: CGFloat = 1
    ) -> some View {
        clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .stroke(BNBUTheme.outline.opacity(lineWidth == 0 ? 0 : 0.45), lineWidth: lineWidth)
            }
    }
}

struct BNBUErrorPanel: View {
    let message: String
    var retryTitle = "重试"
    var retryAction: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BNBUTheme.error)
            Text(message)
                .font(.subheadline.weight(.regular))
                .foregroundStyle(BNBUTheme.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retryAction {
                Button(retryTitle, action: retryAction)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BNBUTheme.primary)
                    .buttonStyle(.plain)
            }
        }
        .padding(BNBUSpacing.panel)
        .background(BNBUTheme.errorContainer)
        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous))
        .accessibilityIdentifier("panel.error")
    }
}

struct BrandMark: View {
    var compact = false

    var body: some View {
        Image("bnbu_emblem")
            .resizable()
            .scaledToFit()
            .padding(compact ? 5 : 7)
            .background(BNBUTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous)
                    .stroke(BNBUTheme.outline.opacity(0.55), lineWidth: 1)
            }
        .frame(width: compact ? 44 : 64, height: compact ? 44 : 64)
        .accessibilityLabel("BNBU 校徽")
    }
}

struct SwissPanel<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(BNBUSpacing.panel)
            .background(BNBUTheme.surface)
            .clipShape(RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous))
            .shadow(color: BNBUTheme.onSurface.opacity(0.06), radius: 2, y: 1)
    }
}

struct SectionTitle: View {
    let eyebrow: String
    let title: String

    var body: some View {
        Text(title)
            .font(.title2.weight(.regular))
            .foregroundStyle(BNBUTheme.onSurface)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StatusBadge: View {
    let text: String
    var filled = false

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(filled ? BNBUTheme.onPrimaryContainer : BNBUTheme.onSurfaceVariant)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(filled ? BNBUTheme.primaryContainer : BNBUTheme.surfaceVariant)
            .clipShape(RoundedRectangle(cornerRadius: BNBURadius.extraSmall, style: .continuous))
    }
}

struct HourProgressBar: View {
    let value: Double
    let total: Double

    var ratio: Double {
        guard total > 0 else { return 0 }
        return min(max(value / total, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous)
                    .fill(BNBUTheme.surfaceVariant)
                RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous)
                    .fill(BNBUTheme.primary)
                    .frame(width: proxy.size.width * ratio)
            }
        }
        .frame(height: 12)
    }
}

struct MetricCell: View {
    let label: String
    let value: String
    let footnote: String

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 10) {
                Text(label.uppercased())
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                Text(value)
                    .font(.system(size: 34, weight: .regular, design: .default))
                    .foregroundStyle(BNBUTheme.onSurface)
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
                Text(footnote)
                    .font(.caption.weight(.regular))
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(BNBUTheme.onPrimary)
                .background(BNBUTheme.primary)
                .clipShape(RoundedRectangle(cornerRadius: BNBURadius.extraLarge, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(accessibilityIdentifier ?? title)
    }
}

struct SecondaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(BNBUTheme.onSurface)
                .background(BNBUTheme.surface)
                .bnbuOutlinedSurface(radius: BNBURadius.extraLarge, lineWidth: 1.5)
        }
        .buttonStyle(.plain)
    }
}

struct DisabledAwareButton: View {
    let title: String
    let systemImage: String
    let isDisabled: Bool
    var accessibilityIdentifier: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline.weight(.medium))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(isDisabled ? BNBUTheme.onSurfaceVariant : BNBUTheme.onPrimaryContainer)
                .background(isDisabled ? BNBUTheme.surfaceVariant : BNBUTheme.primaryContainer)
                .clipShape(RoundedRectangle(cornerRadius: BNBURadius.large, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityIdentifier(accessibilityIdentifier ?? title)
    }
}

struct EmptyPlaceholder: View {
    let title: String
    let message: String

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.headline.weight(.medium))
                Text(message)
                    .font(.subheadline.weight(.regular))
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct BNBUInputTextModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.body.weight(.regular))
            .foregroundStyle(BNBUTheme.onSurface)
            .tint(BNBUTheme.primary)
    }
}

func dismissBNBUKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

private struct BNBUKeyboardToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("完成") {
                        dismissBNBUKeyboard()
                    }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(BNBUTheme.blue)
                }
            }
    }
}

extension View {
    func bnbuInputText() -> some View {
        modifier(BNBUInputTextModifier())
    }

    func bnbuKeyboardDismissToolbar() -> some View {
        modifier(BNBUKeyboardToolbarModifier())
    }
}

struct ProofAttachmentPanel: View {
    @Environment(\.openURL) private var openURL
    @Binding var attachments: [ProofAttachment]
    let maxAttachmentCount: Int
    let summaryText: String
    @State private var selectedItems: [PhotosPickerItem] = []
    @State private var isPhotoPickerPresented = false
    @State private var cameraPermission = CameraPermissionState.current
    @State private var activeCameraAlert: CameraAlert?
    @State private var isCameraPresented = false
    @State private var attachmentNotice: String?
    @State private var pendingDeletion: ProofAttachment?
    @State private var isDeletionConfirmationPresented = false

    init(
        attachments: Binding<[ProofAttachment]>,
        maxAttachmentCount: Int = ProofUploadRule.maxAttachmentCount,
        summaryText: String = ProofUploadRule.summaryText
    ) {
        _attachments = attachments
        self.maxAttachmentCount = max(maxAttachmentCount, 1)
        self.summaryText = summaryText
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("图片 / 视频凭证")
                        .font(.headline.weight(.medium))
                    Text("相册使用系统选择器，仅共享您选中的项目；拍摄时才会请求摄像头权限。")
                        .font(.caption.weight(.regular))
                        .foregroundStyle(BNBUTheme.muted)
                    Text(summaryText)
                        .font(.caption.weight(.regular))
                        .foregroundStyle(BNBUTheme.muted)
                }
                Spacer()
                Image(systemName: "photo.badge.plus")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(BNBUTheme.blue)
            }

            HStack(spacing: 10) {
                Button {
                    handlePhotoLibraryAction()
                } label: {
                    Label("从相册选择", systemImage: "photo.on.rectangle")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(isAtLimit ? BNBUTheme.muted : BNBUTheme.surface)
                        .background(isAtLimit ? BNBUTheme.surface : BNBUTheme.ink)
                        .bnbuOutlinedSurface(radius: BNBURadius.extraLarge, lineWidth: isAtLimit ? 1.5 : 0)
                }
                .buttonStyle(.plain)
                .disabled(isAtLimit)

                Button {
                    handleCameraAction()
                } label: {
                    Label("拍摄", systemImage: "camera.fill")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .foregroundStyle(isAtLimit ? BNBUTheme.muted : BNBUTheme.ink)
                        .background(BNBUTheme.surface)
                        .bnbuOutlinedSurface(radius: BNBURadius.extraLarge, lineWidth: 1.5)
                }
                .buttonStyle(.plain)
                .disabled(isAtLimit)
            }

            #if DEBUG
            Button {
                addDemoAttachment()
            } label: {
                Label("添加演示凭证", systemImage: "doc.badge.plus")
                    .font(.caption.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(isAtLimit ? BNBUTheme.muted : BNBUTheme.ink)
                    .background(BNBUTheme.surface)
                    .bnbuOutlinedSurface(radius: BNBURadius.extraLarge, lineWidth: 1.5)
            }
            .buttonStyle(.plain)
            .disabled(isAtLimit)
            .accessibilityIdentifier("proof.demo.add")
            #endif

            VStack(spacing: 8) {
                PermissionStatusLine(
                    title: "相册访问",
                    value: "仅所选项目",
                    systemImage: "photo.on.rectangle.angled",
                    filled: true
                )
                PermissionStatusLine(
                    title: "摄像头",
                    value: cameraPermission.title,
                    systemImage: cameraPermission.symbolName,
                    filled: cameraPermission == .authorized
                )
            }

            HStack(spacing: 8) {
                StatusBadge(text: "\(imageCount) 张图片")
                StatusBadge(text: "\(videoCount) 个视频")
                StatusBadge(text: "剩余 \(remainingSlots)")
                Spacer()
            }

            if let attachmentNotice {
                Text(attachmentNotice)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BNBUTheme.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(BNBUTheme.surface)
                    .bnbuOutlinedSurface()
                    .accessibilityLabel("凭证提示：\(attachmentNotice)")
            }

            if attachments.isEmpty {
                Text("尚未添加凭证")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BNBUTheme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(attachments) { attachment in
                        ProofAttachmentPreviewCard(attachment: attachment) {
                            pendingDeletion = attachment
                            isDeletionConfirmationPresented = true
                        }
                    }
                }
            }
        }
        .padding(16)
        .background(BNBUTheme.blueSoft)
        .overlay(
            Rectangle()
                .stroke(style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                .foregroundStyle(BNBUTheme.line)
        )
        .onChange(of: selectedItems) { _, newItems in
            guard !newItems.isEmpty else { return }
            Task {
                await importSelectedItems(newItems)
            }
        }
        .onAppear {
            cameraPermission = CameraPermissionState.current
        }
        .photosPicker(
            isPresented: $isPhotoPickerPresented,
            selection: $selectedItems,
            maxSelectionCount: max(remainingSlots, 1),
            matching: .any(of: [.images, .videos])
        )
        .sheet(isPresented: $isCameraPresented) {
            CameraCapturePicker { attachment in
                appendAttachment(attachment)
                cameraPermission = CameraPermissionState.current
            }
        }
        .confirmationDialog(
            "删除凭证",
            isPresented: $isDeletionConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                deletePendingAttachment()
            }
            Button("取消", role: .cancel) {
                pendingDeletion = nil
            }
        } message: {
            Text(pendingDeletion.map { "确认删除 \($0.fileName)？删除后提交前需要重新补充凭证。" } ?? "确认删除这个凭证？")
        }
        .alert(item: $activeCameraAlert) { alert in
            switch alert {
            case .unavailable:
                return Alert(
                    title: Text("当前设备无法拍摄"),
                    message: Text("模拟器或当前设备没有可用摄像头，可先添加占位凭证完成评审流程。"),
                    primaryButton: .default(Text("添加占位凭证")) {
                        addCameraPlaceholder()
                    },
                    secondaryButton: .cancel(Text("取消"))
                )
            case .denied:
                return Alert(
                    title: Text("摄像头权限未开启"),
                    message: Text("需要允许 BNBU Student 使用摄像头，才能直接拍摄打卡凭证。"),
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
                    message: Text("当前设备策略不允许使用摄像头，请联系设备管理员或改用相册选择。"),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private var imageCount: Int {
        attachments.filter { $0.type == .image }.count
    }

    private var videoCount: Int {
        attachments.filter { $0.type == .video }.count
    }

    private var remainingSlots: Int {
        max(maxAttachmentCount - attachments.count, 0)
    }

    private var isAtLimit: Bool {
        remainingSlots == 0 || (imageCount >= ProofUploadRule.maxImageCount && videoCount >= ProofUploadRule.maxVideoCount)
    }

    private func addCameraPlaceholder() {
        guard canAccept(.image) else {
            attachmentNotice = limitNotice(for: .image)
            return
        }
        attachments.append(
            ProofAttachment(
                id: UUID().uuidString,
                type: .image,
                fileName: "camera-proof-\(attachments.count + 1).jpg",
                byteCount: nil,
                thumbnailData: ProofThumbnailRenderer.demoThumbnailData(type: .image, index: attachments.count + 1),
                source: "拍摄占位"
            )
        )
        attachmentNotice = "已添加 1 个拍摄占位凭证。"
    }

    private func addDemoAttachment() {
        guard !isAtLimit else {
            attachmentNotice = "已达到凭证数量上限。"
            return
        }
        let nextIndex = attachments.count + 1
        let preferredType: ProofMediaType = nextIndex.isMultiple(of: 3) ? .video : .image
        let fallbackType: ProofMediaType = preferredType == .video ? .image : .video
        let type = canAccept(preferredType) ? preferredType : fallbackType
        guard canAccept(type) else {
            attachmentNotice = limitNotice(for: preferredType)
            return
        }
        let demoImageData = ProofThumbnailRenderer.demoThumbnailData(type: type, index: nextIndex)
        appendAttachment(
            ProofAttachment(
                id: UUID().uuidString,
                type: type,
                fileName: type == .video ? "demo-running-proof-\(nextIndex).mov" : "demo-running-proof-\(nextIndex).jpg",
                byteCount: type == .video ? 12_400_000 : (demoImageData?.count ?? 1_280_000),
                durationSeconds: type == .video ? 18 : nil,
                thumbnailData: demoImageData,
                // Demo images carry real bytes so the remote Debug flow can exercise
                // the full upload + submit chain; demo videos stay preview-only.
                uploadData: type == .image ? demoImageData : nil,
                source: "演示",
                mimeType: type == .image ? "image/jpeg" : nil
            )
        )
    }

    private func handlePhotoLibraryAction() {
        guard !isAtLimit else {
            attachmentNotice = "已达到凭证数量上限。"
            return
        }
        attachmentNotice = "系统选择器只会向 App 提供您本次选中的项目。"
        isPhotoPickerPresented = true
    }

    private func handleCameraAction() {
        guard canAccept(.image) else {
            attachmentNotice = limitNotice(for: .image)
            return
        }

        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            cameraPermission = .unavailable
            activeCameraAlert = .unavailable
            return
        }

        cameraPermission = CameraPermissionState.current
        switch cameraPermission {
        case .authorized:
            isCameraPresented = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    cameraPermission = granted ? .authorized : .denied
                    if granted {
                        isCameraPresented = true
                    } else {
                        activeCameraAlert = .denied
                    }
                }
            }
        case .denied:
            activeCameraAlert = .denied
        case .restricted:
            activeCameraAlert = .restricted
        case .unavailable:
            activeCameraAlert = .unavailable
        }
    }

    @MainActor
    private func importSelectedItems(_ items: [PhotosPickerItem]) async {
        guard !isAtLimit else {
            selectedItems = []
            attachmentNotice = "已达到凭证数量上限。"
            return
        }

        var importedCount = 0
        var oversizedCount = 0
        let importableItems = Array(items.prefix(remainingSlots))
        var skippedCount = max(items.count - importableItems.count, 0)

        for item in importableItems {
            let type: ProofMediaType = item.supportedContentTypes.contains {
                $0.conforms(to: .movie) || $0.conforms(to: .video)
            } ? .video : .image
            guard canAccept(type) else {
                skippedCount += 1
                continue
            }
            let fileExtension = type == .video ? "mov" : "jpg"
            let prefix = type == .video ? "video" : "image"
            let fileName = "\(prefix)-\(String(UUID().uuidString.prefix(6))).\(fileExtension)"
            let attachment: ProofAttachment?
            if type == .video,
               let importedFile = try? await item.loadTransferable(type: ImportedProofFile.self) {
                attachment = await makeFileBackedVideoAttachment(
                    fileName: fileName,
                    fileURL: importedFile.url,
                    source: "相册"
                )
            } else if type == .image,
                      let data = try? await item.loadTransferable(type: Data.self) {
                // Images are capped at 8 MB, so the small in-memory path remains
                // bounded. Videos never use this whole-file fallback.
                attachment = ProofAttachment(
                    id: UUID().uuidString,
                    type: type,
                    fileName: fileName,
                    byteCount: data.count,
                    thumbnailData: ProofThumbnailRenderer.imageThumbnailData(from: data),
                    uploadData: data,
                    source: "相册"
                )
            } else {
                attachment = nil
            }
            guard let attachment else {
                skippedCount += 1
                continue
            }
            attachments.append(attachment)
            importedCount += 1
            if !attachment.isValidForUpload {
                oversizedCount += 1
            }
        }

        var noticeParts: [String] = []
        if importedCount > 0 {
            noticeParts.append("已添加 \(importedCount) 个凭证")
        }
        if skippedCount > 0 {
            noticeParts.append("已忽略 \(skippedCount) 个超出数量上限的文件")
        }
        if oversizedCount > 0 {
            noticeParts.append("\(oversizedCount) 个文件超出大小限制，提交前请删除或替换")
        }
        attachmentNotice = noticeParts.isEmpty ? nil : noticeParts.joined(separator: "；")
        selectedItems = []
    }

    private func appendAttachment(_ attachment: ProofAttachment) {
        guard canAccept(attachment.type) else {
            attachmentNotice = limitNotice(for: attachment.type)
            return
        }
        attachments.append(attachment)
        attachmentNotice = attachment.isValidForUpload ? "已添加 1 个\(attachment.type.rawValue)凭证。" : "\(attachment.fileName) 超出大小限制，提交前请删除或替换。"
    }

    private func canAccept(_ type: ProofMediaType) -> Bool {
        switch type {
        case .image:
            return imageCount < ProofUploadRule.maxImageCount && attachments.count < maxAttachmentCount
        case .video:
            return videoCount < ProofUploadRule.maxVideoCount && attachments.count < maxAttachmentCount
        }
    }

    private func limitNotice(for type: ProofMediaType) -> String {
        if attachments.count >= maxAttachmentCount {
            return "最多只能添加 \(maxAttachmentCount) 个凭证。"
        }
        switch type {
        case .image:
            return "最多只能添加 \(ProofUploadRule.maxImageCount) 张图片。"
        case .video:
            return "最多只能添加 \(ProofUploadRule.maxVideoCount) 个视频。"
        }
    }

    private func deletePendingAttachment() {
        guard let pendingDeletion else { return }
        attachments.removeAll { $0.id == pendingDeletion.id }
        ProofTransientFileStore.removeManagedCopy(at: pendingDeletion.sourceFileURL)
        attachmentNotice = "已删除 \(pendingDeletion.fileName)。"
        self.pendingDeletion = nil
    }

    private func makeFileBackedVideoAttachment(
        fileName: String,
        fileURL: URL,
        source: String
    ) async -> ProofAttachment? {
        let fileDetails: (byteCount: Int, digest: String)? = try? await Task.detached(priority: .userInitiated) {
            let attributes = try FileManager.default.attributesOfItem(atPath: fileURL.path)
            let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
            let digest = try ProofContentDigest.sha256(fileURL: fileURL)
            return (byteCount, digest)
        }.value
        guard let fileDetails else {
            ProofTransientFileStore.removeManagedCopy(at: fileURL)
            return nil
        }
        return ProofAttachment(
            id: UUID().uuidString,
            type: .video,
            fileName: fileName,
            byteCount: fileDetails.byteCount,
            durationSeconds: await ProofThumbnailRenderer.videoDurationSeconds(from: fileURL),
            thumbnailData: ProofThumbnailRenderer.videoThumbnailData(from: fileURL),
            uploadData: nil,
            sourceFileURL: fileURL,
            source: source,
            contentDigest: fileDetails.digest
        )
    }
}

private struct ImportedProofFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            ImportedProofFile(url: try ProofTransientFileStore.makeProtectedCopy(from: received.file))
        }
    }
}

enum ProofThumbnailRenderer {
    private static let maxPixel: CGFloat = 420

    static func imageThumbnailData(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return imageThumbnailData(from: image)
    }

    static func imageThumbnailData(from image: UIImage) -> Data? {
        let size = fittedSize(for: image.size)
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumbnail = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return thumbnail.jpegData(compressionQuality: 0.72)
    }

    static func videoThumbnailData(from url: URL) -> Data? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixel, height: maxPixel)
        guard let cgImage = try? generator.copyCGImage(at: .zero, actualTime: nil) else {
            return nil
        }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.72)
    }

    static func videoDurationSeconds(from url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        guard let duration = try? await asset.load(.duration) else { return nil }
        let seconds = CMTimeGetSeconds(duration)
        return seconds.isFinite ? seconds : nil
    }

    static func demoThumbnailData(type: ProofMediaType, index: Int) -> Data? {
        let size = CGSize(width: maxPixel, height: maxPixel * 0.78)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            UIColor(red: 126 / 255, green: 190 / 255, blue: 251 / 255, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width, height: size.height * 0.32))

            UIColor(red: 11 / 255, green: 11 / 255, blue: 12 / 255, alpha: 1).setFill()
            context.fill(CGRect(x: 28, y: size.height - 58, width: size.width - 56, height: 8))
            context.fill(CGRect(x: 28, y: size.height - 36, width: size.width * 0.55, height: 8))

            let symbol = type == .video ? "VIDEO \(index)" : "PHOTO \(index)"
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.monospacedSystemFont(ofSize: 36, weight: .regular),
                .foregroundColor: UIColor(red: 11 / 255, green: 11 / 255, blue: 12 / 255, alpha: 1)
            ]
            symbol.draw(at: CGPoint(x: 28, y: 52), withAttributes: attributes)
        }
        return image.jpegData(compressionQuality: 0.72)
    }

    private static func fittedSize(for originalSize: CGSize) -> CGSize {
        guard originalSize.width > 0, originalSize.height > 0 else {
            return CGSize(width: maxPixel, height: maxPixel)
        }
        let ratio = min(maxPixel / originalSize.width, maxPixel / originalSize.height, 1)
        return CGSize(width: originalSize.width * ratio, height: originalSize.height * ratio)
    }
}

private enum CameraPermissionState: Equatable {
    case unavailable
    case notDetermined
    case authorized
    case denied
    case restricted

    static var current: CameraPermissionState {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return .unavailable
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            return .notDetermined
        case .authorized:
            return .authorized
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .restricted
        }
    }

    var title: String {
        switch self {
        case .unavailable:
            return "设备不可用"
        case .notDetermined:
            return "待授权"
        case .authorized:
            return "已允许"
        case .denied:
            return "已拒绝"
        case .restricted:
            return "系统限制"
        }
    }

    var symbolName: String {
        switch self {
        case .authorized:
            return "camera.fill"
        case .notDetermined:
            return "camera.badge.clock"
        case .denied:
            return "camera.badge.ellipsis"
        case .restricted:
            return "lock.fill"
        case .unavailable:
            return "camera.slash"
        }
    }
}

private enum CameraAlert: Identifiable {
    case unavailable
    case denied
    case restricted

    var id: String {
        switch self {
        case .unavailable:
            return "unavailable"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        }
    }
}

private struct PermissionStatusLine: View {
    let title: String
    let value: String
    let systemImage: String
    var filled = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.caption.weight(.medium))
                .foregroundStyle(BNBUTheme.blue)
                .frame(width: 20)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(BNBUTheme.ink)
            Spacer()
            StatusBadge(text: value, filled: filled)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title)：\(value)")
    }
}

struct CameraCapturePicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let completion: (ProofAttachment) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.videoMaximumDuration = 30
        picker.videoQuality = .typeMedium

        let availableTypes = UIImagePickerController.availableMediaTypes(for: .camera) ?? []
        let preferredTypes = [UTType.image.identifier, UTType.movie.identifier].filter { availableTypes.contains($0) }
        picker.mediaTypes = preferredTypes.isEmpty ? availableTypes : preferredTypes
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    @MainActor
    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraCapturePicker

        init(parent: CameraCapturePicker) {
            self.parent = parent
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let mediaType = info[.mediaType] as? String
            if mediaType == UTType.movie.identifier,
               let sourceURL = info[.mediaURL] as? URL {
                Task {
                    if let attachment = await makeVideoAttachment(from: sourceURL) {
                        parent.completion(attachment)
                    }
                    parent.dismiss()
                }
                return
            }

            parent.completion(makeImageAttachment(from: info))
            parent.dismiss()
        }

        private func makeImageAttachment(from info: [UIImagePickerController.InfoKey: Any]) -> ProofAttachment {
            let image = info[.originalImage] as? UIImage
            let uploadData = image?.jpegData(compressionQuality: 0.82)
            let byteCount = uploadData?.count
            return ProofAttachment(
                id: UUID().uuidString,
                type: .image,
                fileName: "camera-photo-\(String(UUID().uuidString.prefix(6))).jpg",
                byteCount: byteCount,
                thumbnailData: image.flatMap { ProofThumbnailRenderer.imageThumbnailData(from: $0) },
                uploadData: uploadData,
                source: "摄像头"
            )
        }

        private func makeVideoAttachment(from sourceURL: URL) async -> ProofAttachment? {
            let prepared: (url: URL, byteCount: Int, digest: String)? = try? await Task.detached(priority: .userInitiated) {
                let protectedURL = try ProofTransientFileStore.makeProtectedCopy(from: sourceURL)
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: protectedURL.path)
                    let byteCount = (attributes[.size] as? NSNumber)?.intValue ?? 0
                    let digest = try ProofContentDigest.sha256(fileURL: protectedURL)
                    return (protectedURL, byteCount, digest)
                } catch {
                    ProofTransientFileStore.removeManagedCopy(at: protectedURL)
                    throw error
                }
            }.value
            guard let prepared else { return nil }
            return ProofAttachment(
                id: UUID().uuidString,
                type: .video,
                fileName: "camera-video-\(String(UUID().uuidString.prefix(6))).mov",
                byteCount: prepared.byteCount,
                durationSeconds: await ProofThumbnailRenderer.videoDurationSeconds(from: prepared.url),
                thumbnailData: ProofThumbnailRenderer.videoThumbnailData(from: prepared.url),
                uploadData: nil,
                sourceFileURL: prepared.url,
                source: "摄像头",
                contentDigest: prepared.digest
            )
        }
    }
}

private struct ProofAttachmentPreviewCard: View {
    let attachment: ProofAttachment
    let removeAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ZStack(alignment: .topTrailing) {
                thumbnail
                    .aspectRatio(1.25, contentMode: .fit)
                    .clipped()
                    .bnbuOutlinedSurface()

                if attachment.type == .video {
                    Image(systemName: "play.fill")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BNBUTheme.surface)
                        .frame(width: 28, height: 28)
                        .background(BNBUTheme.ink)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }

                Button(action: removeAction) {
                    Image(systemName: "xmark")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BNBUTheme.surface)
                        .frame(width: 26, height: 26)
                        .background(BNBUTheme.ink)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("proof.remove.\(attachment.id)")
                .accessibilityLabel("删除凭证 \(attachment.fileName)")
                .accessibilityHint("需要确认后才会删除")
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(attachment.fileName)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(BNBUTheme.ink)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(metadataText)
                    .font(.caption.weight(.regular))
                    .foregroundStyle(BNBUTheme.muted)

                StatusBadge(
                    text: attachment.validationMessage ?? "可提交",
                    filled: attachment.isValidForUpload
                )
            }
        }
        .padding(10)
        .background(BNBUTheme.surface)
        .overlay(
            Rectangle()
                .stroke(attachment.isValidForUpload ? BNBUTheme.line : BNBUTheme.ink, lineWidth: attachment.isValidForUpload ? 1 : 2)
        )
        .accessibilityIdentifier("proof.card.\(attachment.id)")
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let thumbnailData = attachment.thumbnailData,
           let image = UIImage(data: thumbnailData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Rectangle()
                .fill(BNBUTheme.pale)
                .overlay {
                    Image(systemName: attachment.type == .video ? "video.fill" : "photo.fill")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(BNBUTheme.blue)
                }
        }
    }

    private var metadataText: String {
        [
            attachment.type.rawValue,
            attachment.displaySize,
            attachment.displayDuration,
            attachment.source
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

struct DetailFactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BNBUTheme.ink)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.regular))
                .foregroundStyle(BNBUTheme.muted)
                .multilineTextAlignment(.trailing)
        }
    }
}
