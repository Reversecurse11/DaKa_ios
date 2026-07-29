import SwiftUI

/// Android's `JoinRequestStatusScreen`. An approved request belongs in the
/// normal course experience, so this page reports it and closes instead of
/// rendering a fifth state.
struct JoinRequestStatusView: View {
    let request: CourseJoinRequest?
    var inviteUnavailable = false
    let onBack: () -> Void
    var onContactTeacher: () -> Void = {}
    var onEditAndResubmit: (CourseJoinRequest) -> Void = { _ in }
    var onUseNewInvite: () -> Void = {}
    var onApproved: () -> Void = {}

    var body: some View {
        ZStack {
            BNBUPageBackground()
            ScrollView {
                VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                    header
                    panel
                }
                .padding(BNBUSpacing.screen)
            }
        }
        .onAppear {
            if request?.status == .active { onApproved() }
        }
        .accessibilityIdentifier("screen.joinRequestStatus")
    }

    private var header: some View {
        HStack(spacing: 4) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(BNBUFont.titleMedium)
                    .foregroundStyle(BNBUTheme.onSurface)
                    .frame(width: BNBUSpacing.touchTarget, height: BNBUSpacing.touchTarget)
            }
            .buttonStyle(BNBUPressStyle())
            .accessibilityLabel("返回")
            .accessibilityIdentifier("nav.back")
            SectionTitle(eyebrow: "COURSE JOIN", title: "加入申请")
        }
    }

    @ViewBuilder
    private var panel: some View {
        if inviteUnavailable {
            inviteUnavailablePanel
        } else if let request {
            switch request.status {
            case .pending:
                pendingPanel(request)
            case .needsCorrection:
                correctionPanel(request)
            case .rejected:
                rejectedPanel(request)
            case .active:
                EmptyView()
            }
        } else {
            requestUnavailablePanel
        }
    }

    private func pendingPanel(_ request: CourseJoinRequest) -> some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                JoinRequestStatusHeading(
                    title: "申请状态：待教师审核",
                    systemImage: "exclamationmark.circle"
                )
                VStack(alignment: .leading, spacing: 10) {
                    JoinRequestFact(label: "课程", value: "\(request.courseCode) / Section \(request.section)")
                    JoinRequestFact(label: "班级", value: request.courseName)
                    JoinRequestFact(label: "教师", value: request.teacherName)
                    JoinRequestFact(label: "学期", value: request.semester)
                    JoinRequestFact(label: "提交时间", value: request.submittedAt)
                }
                JoinRequestActionButton(
                    title: "联系教师",
                    systemImage: "envelope",
                    filled: false,
                    identifier: "joinRequest.contactTeacher",
                    action: onContactTeacher
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func correctionPanel(_ request: CourseJoinRequest) -> some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                JoinRequestStatusHeading(
                    title: "申请状态：需补正资料",
                    systemImage: "square.and.pencil"
                )
                JoinRequestReviewComment(label: "教师原因", comment: request.reviewComment)
                JoinRequestActionButton(
                    title: "修改并重新提交",
                    systemImage: "square.and.pencil",
                    filled: true,
                    identifier: "joinRequest.resubmit"
                ) {
                    onEditAndResubmit(request)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func rejectedPanel(_ request: CourseJoinRequest) -> some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                JoinRequestStatusHeading(
                    title: "申请状态：已拒绝",
                    systemImage: "exclamationmark.circle"
                )
                JoinRequestReviewComment(label: "拒绝原因", comment: request.reviewComment)
                JoinRequestActionButton(
                    title: "联系教师",
                    systemImage: "envelope",
                    filled: false,
                    identifier: "joinRequest.contactTeacher",
                    action: onContactTeacher
                )
                JoinRequestActionButton(
                    title: "使用新邀请码重新申请",
                    systemImage: "arrow.clockwise",
                    filled: true,
                    identifier: "joinRequest.newInvite",
                    action: onUseNewInvite
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var inviteUnavailablePanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                JoinRequestStatusHeading(
                    title: "该邀请已过期或已被教师撤销",
                    systemImage: "exclamationmark.circle"
                )
                Text("请联系教师获取新的二维码或邀请码")
                    .font(BNBUFont.bodyLarge)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                JoinRequestActionButton(
                    title: "联系教师",
                    systemImage: "envelope",
                    filled: true,
                    identifier: "joinRequest.contactTeacher",
                    action: onContactTeacher
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var requestUnavailablePanel: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: BNBUSpacing.space16) {
                JoinRequestStatusHeading(
                    title: "暂时无法获取申请状态",
                    systemImage: "exclamationmark.circle"
                )
                Text("请返回后刷新页面，或联系教师确认申请情况。")
                    .font(BNBUFont.bodyLarge)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                JoinRequestActionButton(
                    title: "返回",
                    systemImage: "arrow.left",
                    filled: false,
                    identifier: "joinRequest.back",
                    action: onBack
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// Compact entry card shared by the dashboard and the courses tab.
struct JoinRequestEntryPanel: View {
    let request: CourseJoinRequest
    var identifier = "joinRequest.entry"
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            SwissPanel {
                HStack(spacing: BNBUSpacing.space12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("加入申请")
                            .font(BNBUFont.titleMedium)
                            .foregroundStyle(BNBUTheme.onSurface)
                        Text(verbatim: "\(request.courseCode) / Section \(request.section) · \(BNBUL10n.dynamicText(request.status.title))")
                            .font(BNBUFont.bodyMedium)
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    StatusBadge(text: request.status.title, filled: request.status == .pending)
                }
            }
        }
        .buttonStyle(BNBUPressStyle())
        .accessibilityIdentifier(identifier)
    }
}

private struct JoinRequestStatusHeading: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(BNBUFont.titleLarge)
                .foregroundStyle(BNBUTheme.primary)
                .frame(width: 24, height: 24)
            Text(LocalizedStringKey(title))
                .font(BNBUFont.titleLarge)
                .foregroundStyle(BNBUTheme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct JoinRequestFact: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Text(verbatim: "\(BNBUL10n.dynamicText(label))：")
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .frame(width: 76, alignment: .leading)
            Text(verbatim: value.isEmpty ? BNBUL10n.text("待公布") : value)
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurface)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct JoinRequestReviewComment: View {
    let label: String
    let comment: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: "\(BNBUL10n.dynamicText(label))：")
                .font(BNBUFont.labelLarge)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
            // A teacher's note is entered data, so it is shown verbatim; only
            // the empty-state fallback is translated.
            Text(verbatim: comment.isEmpty
                ? BNBUL10n.text("教师暂未填写说明，请联系教师确认。")
                : comment)
                .font(BNBUFont.bodyLarge)
                .foregroundStyle(BNBUTheme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct JoinRequestActionButton: View {
    let title: String
    let systemImage: String
    let filled: Bool
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: BNBUSpacing.space8) {
                Image(systemName: systemImage)
                Text(LocalizedStringKey(title))
            }
            .font(BNBUFont.labelLarge)
            .frame(maxWidth: .infinity)
            .frame(height: BNBUSpacing.primaryControlHeight)
            .foregroundStyle(filled ? BNBUTheme.onPrimary : BNBUTheme.primary)
            .background(filled ? BNBUTheme.primary : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous))
            .overlay {
                if !filled {
                    RoundedRectangle(cornerRadius: BNBURadius.medium, style: .continuous)
                        .stroke(BNBUTheme.outline.opacity(0.45), lineWidth: 1)
                }
            }
        }
        .buttonStyle(BNBUPressStyle())
        .accessibilityIdentifier(identifier)
    }
}
