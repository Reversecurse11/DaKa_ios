import SwiftUI

struct CourseDetailView: View {
    @EnvironmentObject private var appState: AppState
    let course: Course

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(eyebrow: course.semester, title: course.displayTitle)

                    SwissPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            DetailFactRow(label: "课程名称", value: course.name)
                            DetailFactRow(label: "Section", value: "Section \(course.section)")
                            DetailFactRow(label: "任课老师", value: course.teacher)
                            DetailFactRow(label: "下一截止", value: course.deadline)
                        }
                    }

                    SwissPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("我的课程相关进度")
                                .font(.headline.weight(.medium))
                            HourProgressBar(value: appState.workspace.progress.course, total: appState.hourRule.courseRequired)
                            DetailFactRow(label: "已完成", value: appState.workspace.progress.course.hourText)
                            DetailFactRow(label: "仍缺口", value: appState.courseRemaining.hourText)
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(eyebrow: "Class Tasks", title: "本教学班任务")
                        if appState.tasks(for: course).isEmpty {
                            EmptyPlaceholder(title: "暂无教学班任务", message: "当前教学班还没有可展示任务。老师发布后会在这里同步。")
                        } else {
                            ForEach(appState.tasks(for: course)) { task in
                                NavigationLink {
                                    TaskDetailView(task: task, course: course)
                                } label: {
                                    TaskRow(task: task)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        SectionTitle(eyebrow: "Trace", title: "相关记录")
                        if appState.records(for: course).isEmpty {
                            EmptyPlaceholder(title: "暂无相关记录", message: "当前教学班还没有课程相关打卡记录。")
                        } else {
                            ForEach(appState.records(for: course)) { record in
                                NavigationLink {
                                    RecordDetailView(record: record)
                                } label: {
                                    RecordCard(record: record)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(BNBUSpacing.screen)
            }
        }
        .navigationTitle("课程详情")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct TaskDetailView: View {
    let task: CourseTask
    let course: Course?

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(eyebrow: task.creditType.rawValue, title: task.title)

                    SwissPanel {
                        VStack(alignment: .leading, spacing: 14) {
                            DetailFactRow(label: "状态", value: task.status.rawValue)
                            DetailFactRow(label: "可获得小时", value: task.hours.hourText)
                            DetailFactRow(label: "截止时间", value: task.deadline)
                            DetailFactRow(label: "更新时间", value: task.updatedAt)
                            if let course {
                                DetailFactRow(label: "教学班", value: course.displayTitle)
                            }
                        }
                    }

                    SwissPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("证明要求")
                                .font(.headline.weight(.medium))
                            Text(task.proof)
                                .font(.subheadline.weight(.regular))
                                .foregroundStyle(BNBUTheme.muted)
                                .lineSpacing(3)
                        }
                    }

                    EmptyPlaceholder(
                        title: task.creditType == .courseRelated ? "计入课程相关学时" : "计入其他运动学时",
                        message: task.creditType == .courseRelated ? "这类任务不能被校队或社团认证完全替代。" : "其他运动不能替代课程相关学时，B 类最多计 10 小时。"
                    )
                }
                .padding(BNBUSpacing.screen)
            }
        }
        .navigationTitle("任务详情")
        .navigationBarTitleDisplayMode(.inline)
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
                                Spacer()
                                Text(record.hours.hourText)
                                    .font(.title2.weight(.medium))
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

                    SwissPanel {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("凭证文件")
                                .font(.headline.weight(.medium))

                            if record.proofFiles.isEmpty {
                                Text("该记录暂无可预览凭证文件。")
                                    .font(.subheadline.weight(.regular))
                                    .foregroundStyle(BNBUTheme.muted)
                            } else {
                                ForEach(record.proofFiles) { proof in
                                    HStack(spacing: 10) {
                                        Image(systemName: proof.type == .video ? "video.fill" : "photo.fill")
                                            .font(.headline.weight(.medium))
                                            .foregroundStyle(BNBUTheme.blue)
                                            .frame(width: 26, height: 26)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(proof.fileName)
                                                .font(.subheadline.weight(.medium))
                                                .foregroundStyle(BNBUTheme.ink)
                                                .lineLimit(1)
                                                .truncationMode(.middle)
                                            Text("\(proof.type.rawValue) · \(proof.displaySize) · \(proof.source)")
                                                .font(.caption.weight(.regular))
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
                                .font(.headline.weight(.medium))
                            Text(record.note)
                                .font(.subheadline.weight(.regular))
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
                                Label(currentNotice.category.rawValue, systemImage: currentNotice.category.symbolName)
                                    .font(.headline.weight(.medium))
                                    .foregroundStyle(BNBUTheme.blue)
                                Spacer()
                                StatusBadge(text: currentNotice.isUnread ? "未读" : "已读", filled: currentNotice.isUnread)
                            }

                            Text(currentNotice.message)
                                .font(.body.weight(.regular))
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

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(record.taskTitle)
                            .font(.headline.weight(.medium))
                        Text(record.submittedAt)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(BNBUTheme.muted)
                    }
                    Spacer()
                    StatusBadge(text: "已提交", filled: true)
                }

                HStack {
                    StatusBadge(text: record.creditType.rawValue)
                    Text(record.hours.hourText)
                        .font(.headline.weight(.medium))
                    Spacer()
                }

                if let sportType = record.sportType, !sportType.isEmpty {
                    Text("运动项目：\(sportType.bnbuSportTypeTitle)")
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                }

                Text("打卡照片 / 视频")
                    .font(.headline.weight(.medium))

                RecordMediaGrid(proofs: record.proofFiles)

                if !record.note.isEmpty && record.note != "学生未填写补充说明。" {
                    Text("备注：\(record.note)")
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                }

            }
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
                                .font(.title3.weight(.bold))
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
                .font(.title2.weight(.regular))
            Text("暂无打卡照片或视频")
                .font(.caption.weight(.medium))
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
                .font(.title2.weight(.regular))
            Text(proof.fileName.isEmpty ? "媒体文件" : proof.fileName)
                .font(.caption2.weight(.medium))
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
}
