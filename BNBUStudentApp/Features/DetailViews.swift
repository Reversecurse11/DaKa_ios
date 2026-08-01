import SwiftUI

struct CourseDetailView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let course: Course

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    BNBUBackRow(title: "我的课程") { dismiss() }
                    courseHeader

                    SwissPanel {
                        VStack(alignment: .leading, spacing: 0) {
                            CourseDetailFactRow(label: "课程代码", value: course.code)
                            Divider().overlay(BNBUTheme.outlineVariant)
                            CourseDetailFactRow(label: "教学班", value: "Section \(course.section)")
                            Divider().overlay(BNBUTheme.outlineVariant)
                            CourseDetailFactRow(
                                label: "任课教师",
                                value: course.teacher.isEmpty ? BNBUL10n.text("待公布") : course.teacher
                            )
                            Divider().overlay(BNBUTheme.outlineVariant)
                            CourseDetailFactRow(label: "开课学期", value: offeringTerm)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            SectionTitle(eyebrow: "Trace", title: "相关记录")
                            Spacer()
                            Text(verbatim: recordCountLabel)
                                .font(BNBUFont.bodyMedium)
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        }
                        if appState.records(for: course).isEmpty {
                            EmptyPlaceholder(title: "暂无相关记录", message: "当前教学班还没有课程相关打卡记录。")
                        } else {
                            ForEach(appState.records(for: course)) { record in
                                NavigationLink {
                                    RecordDetailView(record: record)
                                } label: {
                                    RecordCard(record: record, courseTitle: course.displayTitle)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(BNBUSpacing.screen)
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
        .accessibilityIdentifier("screen.courseDetail")
    }

    private var courseHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(course.name)
                .font(BNBUFont.headlineMedium)
                .foregroundStyle(BNBUTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: course.displayTitle)
                .font(BNBUFont.bodyLarge)
                .foregroundStyle(BNBUTheme.muted)
            HStack(spacing: 10) {
                StatusBadge(text: course.isCurrent ? "修读中" : "已完成", filled: course.isCurrent)
                Text(verbatim: enrolmentTermSummary)
                    .font(BNBUFont.bodyMedium)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                Spacer(minLength: 0)
            }
        }
    }

    private var academicYear: String {
        appState.academicProjection.academicYear.replacingOccurrences(of: " 学年", with: "")
    }

    private var courseTerm: String {
        course.semester
            .replacingOccurrences(of: #"^\s*\d{4}[\s\-–/]*"#, with: "", options: .regularExpression)
            .bnbuLocalizedTerm
    }

    private var enrolmentTermSummary: String {
        BNBUL10n.locale.identifier.hasPrefix("zh")
            ? "\(academicYear) 学年\(courseTerm)"
            : "\(academicYear) · \(courseTerm)"
    }

    private var offeringTerm: String {
        "\(academicYear) · \(courseTerm)"
    }

    private var recordCountLabel: String {
        let count = appState.records(for: course).count
        if BNBUL10n.locale.identifier.hasPrefix("zh") {
            return "\(count) 条"
        }
        return count == 1 ? "1 record" : "\(count) records"
    }
}

private struct CourseDetailFactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(LocalizedStringKey(label))
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .frame(width: 76, alignment: .leading)
            Text(verbatim: value)
                .font(BNBUFont.bodyLarge)
                .foregroundStyle(BNBUTheme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 14)
    }
}

struct RecordDetailView: View {
    let record: CheckInRecord

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(eyebrow: record.creditType.rawValue, title: record.taskTitle)

                    SwissPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                StatusBadge(text: "已提交", filled: true)
                                StatusBadge(text: record.validity.rawValue, filled: record.validity == .valid)
                                Spacer()
                                Text(record.hours.localizedHourText)
                                    .font(BNBUFont.headlineSmall)
                            }
                            DetailFactRow(label: "提交时间", value: record.submittedAt)
                            if let sportType = record.sportType, !sportType.isEmpty {
                                DetailFactRow(label: "运动项目", value: sportType.bnbuSportTypeTitle)
                            }
                            DetailFactRow(label: "图片凭证", value: "\(record.proofPhotoCount)")
                            DetailFactRow(label: "视频凭证", value: "\(record.proofVideoCount)")
                            DetailFactRow(label: "凭证摘要", value: record.proofSummary)
                        }
                    }

                    if record.validity == .invalid {
                        SwissPanel {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("记录已被判定无效")
                                    .font(BNBUFont.titleMedium)
                                Text(record.invalidReason ?? "老师已将该记录标记为无效，本次学时不计入。")
                                    .font(BNBUFont.bodyMedium)
                                    .foregroundStyle(BNBUTheme.muted)
                                    .lineSpacing(3)
                            }
                        }
                    }

                    SwissPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("凭证文件")
                                .font(BNBUFont.titleMedium)

                            if record.proofFiles.isEmpty {
                                Text("该记录暂无可预览凭证文件。")
                                    .font(BNBUFont.bodyMedium)
                                    .foregroundStyle(BNBUTheme.muted)
                            } else {
                                RecordMediaGrid(proofs: record.proofFiles)

                                ForEach(record.proofFiles) { proof in
                                    HStack(spacing: 10) {
                                        Image(systemName: proof.type == .video ? "video.fill" : "photo.fill")
                                            .font(BNBUFont.titleMedium)
                                            .foregroundStyle(BNBUTheme.blue)
                                            .frame(width: 26, height: 26)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(proof.fileName)
                                                .font(BNBUFont.titleSmall)
                                                .foregroundStyle(BNBUTheme.ink)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Text("\(proof.type.rawValue) · \(proof.displaySize) · \(proof.source)")
                                                .font(BNBUFont.bodySmall)
                                                .foregroundStyle(BNBUTheme.muted)
                                        }
                                        Spacer()
                                    }
                                    .padding(.vertical, 6)
                                }
                            }
                        }
                    }

                    SwissPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("学生说明")
                                .font(BNBUFont.titleMedium)
                            Text(record.note)
                                .font(BNBUFont.bodyMedium)
                                .foregroundStyle(BNBUTheme.muted)
                                .lineSpacing(3)
                        }
                    }
                }
                .padding(BNBUSpacing.screen)
            }
        }
        .navigationTitle("记录详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct NoticeDetailView: View {
    @EnvironmentObject private var appState: AppState
    let notice: StudentNotice

    private var currentNotice: StudentNotice {
        appState.workspace.notices.first { $0.id == notice.id } ?? notice
    }

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(eyebrow: currentNotice.time, title: currentNotice.title)

                    SwissPanel {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Label {
                                    Text(LocalizedStringKey(currentNotice.category.rawValue))
                                } icon: {
                                    Image(systemName: currentNotice.category.symbolName)
                                }
                                    .font(BNBUFont.titleMedium)
                                    .foregroundStyle(BNBUTheme.blue)
                                Spacer()
                                StatusBadge(text: currentNotice.isUnread ? "未读" : "已读", filled: currentNotice.isUnread)
                            }

                            Text(currentNotice.message)
                                .font(BNBUFont.bodyLarge)
                                .foregroundStyle(BNBUTheme.ink)
                                .lineSpacing(5)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    if let errorMessage = appState.errorMessage {
                        BNBUErrorPanel(message: errorMessage)
                    }

                    DisabledAwareButton(title: appState.isLoading ? "同步中..." : "标记为已读", systemImage: appState.isLoading ? "hourglass" : "checkmark.circle", isDisabled: !currentNotice.isUnread || appState.isLoading) {
                        appState.markNoticeRead(id: currentNotice.id)
                    }
                }
                .padding(BNBUSpacing.screen)
            }
        }
        .navigationTitle("通知详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RecordCard: View {
    let record: CheckInRecord
    /// Android names the linked class rather than echoing its identifier.
    var courseTitle: String? = nil

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.taskTitle)
                            .font(BNBUFont.titleMedium)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(verbatim: sportAndDate)
                            .font(BNBUFont.bodyMedium)
                            .foregroundStyle(BNBUTheme.muted)
                        Text(LocalizedStringKey(record.creditType.rawValue))
                            .font(BNBUFont.bodyMedium)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    }
                    Spacer(minLength: 8)
                    VStack(alignment: .trailing, spacing: 6) {
                        Text(record.hours.localizedHourText)
                            .font(BNBUFont.titleMedium)
                            .foregroundStyle(BNBUTheme.primary)
                        if record.validity == .invalid {
                            StatusBadge(text: "无效")
                        }
                    }
                }

                Divider().overlay(BNBUTheme.outlineVariant)

                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    RecordFact(systemImage: "calendar", label: "开始时间", value: record.startedAt)
                    RecordFact(systemImage: "stopwatch", label: "结束时间", value: record.endedAt)
                    RecordFact(systemImage: "stopwatch", label: "实际运动时长", value: record.activeDuration)
                    RecordFact(
                        systemImage: "checkmark.circle",
                        label: "计入学时",
                        value: record.hours.localizedHourText
                    )
                }

                if let linkedCourse = courseTitle ?? record.courseId, !linkedCourse.isEmpty {
                    RecordInlineFact(systemImage: "checkmark.circle", label: "关联课程", value: linkedCourse)
                }
                RecordInlineFact(systemImage: "paperclip", label: "运动凭证", value: record.proofSummary)

                if !record.note.isEmpty && record.note != "学生未填写补充说明。" {
                    Text("运动说明：\(record.note)")
                        .font(BNBUFont.bodyMedium)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var sportAndDate: String {
        let sport = record.sportType?.bnbuSportTypeTitle ?? ""
        return [sport, record.submittedAt]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }
}

private struct RecordFact: View {
    let systemImage: String
    let label: String
    let value: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(label))
                    .font(BNBUFont.bodySmall)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                Text(verbatim: value?.isEmpty == false ? value! : BNBUL10n.text("未提供"))
                    .font(BNBUFont.titleSmall)
                    .foregroundStyle(BNBUTheme.onSurface)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }
}

private struct RecordInlineFact: View {
    let systemImage: String
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .frame(width: 18)
            Text(LocalizedStringKey(label))
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            Text(verbatim: value)
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }
}

private struct RecordMediaGrid: View {
    let proofs: [ProofAttachment]

    var body: some View {
        switch proofs.count {
        case 0:
            mediaPlaceholder
                .frame(maxWidth: .infinity)
                .frame(height: 96)
        case 1:
            RecordProofThumbnail(proof: proofs[0])
                .aspectRatio(16 / 9, contentMode: .fit)
        case 2:
            HStack(spacing: 8) {
                ForEach(proofs.prefix(2)) { proof in
                    RecordProofThumbnail(proof: proof)
                        .aspectRatio(1, contentMode: .fit)
                }
            }
        default:
            HStack(spacing: 8) {
                RecordProofThumbnail(proof: proofs[0])
                VStack(spacing: 8) {
                    RecordProofThumbnail(proof: proofs[1])
                    ZStack {
                        RecordProofThumbnail(proof: proofs[2])
                        if proofs.count > 3 {
                            Color.black.opacity(0.48)
                            Text("+\(proofs.count - 3)")
                                .font(BNBUFont.titleLarge)
                                .foregroundStyle(.white)
                        }
                    }
                }
            }
            .frame(height: 190)
        }
    }

    private var mediaPlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "photo")
                .font(BNBUFont.headlineSmall)
            Text("暂无打卡照片或视频")
                .font(BNBUFont.labelMedium)
        }
        .foregroundStyle(BNBUTheme.onSurfaceVariant)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(BNBUTheme.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous))
    }
}

private struct RecordProofThumbnail: View {
    let proof: ProofAttachment

    var body: some View {
        ZStack {
            BNBUTheme.surfaceVariant
            if let data = proof.thumbnailData ?? proof.uploadData,
               let image = UIImage(data: data) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else if let url = URL(string: proof.source), url.scheme == "http" || url.scheme == "https" {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else if phase.error != nil {
                        placeholder
                    } else {
                        ProgressView()
                    }
                }
            } else {
                placeholder
            }

            if proof.type == .video {
                Image(systemName: "play.circle.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.white)
                    .shadow(radius: 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous))
    }

    private var placeholder: some View {
        VStack(spacing: 6) {
            Image(systemName: proof.type == .video ? "video" : "photo")
                .font(BNBUFont.headlineSmall)
            Text(proof.fileName.isEmpty ? "媒体文件" : proof.fileName)
                .font(BNBUFont.labelSmall)
                .lineLimit(2)
        }
        .foregroundStyle(BNBUTheme.onSurfaceVariant)
        .padding(8)
    }
}

private extension String {
    var bnbuSportTypeTitle: String {
        switch self {
        case "running": return "跑步"
        case "basketball": return "篮球"
        case "football": return "足球"
        case "badminton": return "羽毛球"
        case "swimming": return "游泳"
        case "fitness": return "健身"
        case "cycling": return "骑行"
        default: return self
        }
    }

    var bnbuLocalizedTerm: String {
        replacingOccurrences(of: "春季学期", with: BNBUL10n.text("春季学期"))
            .replacingOccurrences(of: "秋季学期", with: BNBUL10n.text("秋季学期"))
            .replacingOccurrences(of: "SPRING", with: BNBUL10n.text("春季学期"))
            .replacingOccurrences(of: "FALL", with: BNBUL10n.text("秋季学期"))
    }
}
