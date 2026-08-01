import SwiftUI

struct CoursesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var historyExpanded = false

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        SectionTitle(eyebrow: "My Courses", title: "我的课程")
                        Text(verbatim: enrolmentHeadline)
                            .font(BNBUFont.bodyLarge)
                            .foregroundStyle(BNBUTheme.onSurface)
                        Text("每学期仅可选择一门课程")
                            .font(BNBUFont.bodyMedium)
                            .foregroundStyle(BNBUTheme.muted)
                    }

                    if !pendingCourses.isEmpty {
                        SectionTitle(eyebrow: "PENDING", title: "待审核课程")
                        ForEach(pendingCourses) { course in
                            PendingEnrollmentCard(course: course)
                        }
                    }

                    if appState.workspace.courses.isEmpty {
                        EmptyPlaceholder(
                            title: "暂无课程",
                            message: "当前账号还没有可展示的体育教学班；课程同步后会按课程代码和 Section 显示。"
                        )
                    } else {
                        HStack(alignment: .firstTextBaseline) {
                            SectionTitle(eyebrow: "CURRENT", title: "本学期")
                            Spacer()
                            Text(verbatim: currentCourseCountLabel)
                                .font(BNBUFont.bodyMedium)
                                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        }

                        if currentCourses.isEmpty {
                            EmptyPlaceholder(title: "当前学期暂无课程", message: "历史课程仍可在下方展开查看。")
                        } else {
                            ForEach(currentCourses) { course in
                                courseLink(course, isCurrent: true)
                            }
                        }

                        if !historyCourses.isEmpty {
                            Button {
                                withAnimation(.easeInOut(duration: 0.24)) {
                                    historyExpanded.toggle()
                                }
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "clock.arrow.circlepath")
                                        .foregroundStyle(BNBUTheme.primary)
                                    Text("历史课程（\(historyCourses.count)）")
                                        .font(BNBUFont.titleMedium)
                                        .foregroundStyle(BNBUTheme.onSurface)
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                                        .rotationEffect(.degrees(historyExpanded ? 180 : 0))
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 13)
                                .background(BNBUTheme.surfaceVariant)
                                .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            if historyExpanded {
                                ForEach(historyCourses) { course in
                                    courseLink(course, isCurrent: false)
                                }
                            }
                        }
                    }
                }
                .padding(BNBUSpacing.screen)
            }
            .refreshable {
                await appState.refreshRemoteWorkspace()
            }
        }
        .accessibilityIdentifier("screen.courses")
    }

    @ViewBuilder
    private func courseLink(_ course: Course, isCurrent: Bool) -> some View {
        NavigationLink {
            CourseDetailView(course: course)
        } label: {
            CourseCard(
                course: course,
                academicYear: appState.academicProjection.academicYear,
                term: appState.academicProjection.semester,
                isCurrent: isCurrent
            )
        }
        .buttonStyle(.plain)
    }

    /// Applications awaiting review get their own section so they are never
    /// mistaken for a course the student can already check in against.
    private var pendingCourses: [Course] {
        appState.pendingEnrollmentCourses
    }

    private var currentCourses: [Course] {
        appState.workspace.courses
            .filter { $0.isCurrent && !$0.isAwaitingEnrollmentReview }
            .sorted { $0.displayTitle < $1.displayTitle }
    }

    private var enrolmentHeadline: String {
        let count = currentCourses.count
        if BNBUL10n.locale.identifier.hasPrefix("zh") {
            return "\(count) 门课程正在修读"
        }
        return count == 1 ? "1 course in progress" : "\(count) courses in progress"
    }

    private var currentCourseCountLabel: String {
        let count = currentCourses.count
        if BNBUL10n.locale.identifier.hasPrefix("zh") {
            return "\(count) 门"
        }
        return count == 1 ? "1 course" : "\(count) courses"
    }

    private var historyCourses: [Course] {
        appState.workspace.courses
            .filter { !$0.isCurrent && !$0.isAwaitingEnrollmentReview }
            .sorted { $0.semester > $1.semester }
    }
}

private struct PendingEnrollmentCard: View {
    let course: Course

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(verbatim: course.code)
                            .font(BNBUFont.titleLarge)
                            .foregroundStyle(BNBUTheme.ink)
                        Text("等待任课老师审核")
                            .font(BNBUFont.titleSmall)
                            .foregroundStyle(BNBUTheme.muted)
                    }
                    Spacer(minLength: 8)
                    StatusBadge(text: course.enrollmentStatus.title)
                }

                Text("审核通过前不能开始运动打卡，本课程也不会产生有效学时。")
                    .font(BNBUFont.bodySmall)
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .lineSpacing(3)
            }
        }
    }
}

private struct CourseCard: View {
    let course: Course
    let academicYear: String
    let term: String
    let isCurrent: Bool

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 8) {
                    courseIdentity
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(BNBUFont.labelMedium)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                        .padding(.top, 4)
                }

                Divider()
                    .overlay(BNBUTheme.outlineVariant)

                VStack(alignment: .leading, spacing: 10) {
                    courseFactLine(
                        systemImage: "person",
                        text: course.teacher.isEmpty ? BNBUL10n.text("待公布") : course.teacher
                    )
                    courseFactLine(
                        systemImage: "calendar",
                        text: "\(academicYear.replacingOccurrences(of: " 学年", with: "")) · \(localizedTerm(term))"
                    )
                }

                HStack(spacing: 10) {
                    StatusBadge(text: isCurrent ? "修读中" : "已完成", filled: isCurrent)
                    Text(verbatim: enrolmentTermSummary)
                        .font(BNBUFont.bodySmall)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private var courseIdentity: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(course.name)
                .font(BNBUFont.titleLarge)
                .foregroundStyle(BNBUTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(course.displayTitle)
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func courseFactLine(systemImage: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .frame(width: 18, alignment: .leading)
            Text(verbatim: text)
                .font(BNBUFont.bodyMedium)
                .foregroundStyle(BNBUTheme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var enrolmentTermSummary: String {
        let year = academicYear.replacingOccurrences(of: " 学年", with: "")
        // Course semesters may arrive already prefixed with their own year
        // ("2026 春季学期"), which would otherwise read twice in one line.
        let term = localizedTerm(course.semester)
            .replacingOccurrences(of: #"^\s*\d{4}[\s\-–/]*"#, with: "", options: .regularExpression)
        if BNBUL10n.locale.identifier.hasPrefix("zh") {
            return "\(year) 学年\(term)"
        }
        return "\(year) · \(term)"
    }

    private func localizedTerm(_ value: String) -> String {
        value
            .replacingOccurrences(of: "春季学期", with: BNBUL10n.text("春季学期"))
            .replacingOccurrences(of: "秋季学期", with: BNBUL10n.text("秋季学期"))
            .replacingOccurrences(of: "SPRING", with: BNBUL10n.text("春季学期"))
            .replacingOccurrences(of: "FALL", with: BNBUL10n.text("秋季学期"))
    }
}
