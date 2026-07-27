import SwiftUI

struct CoursesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var historyExpanded = false
    @State private var isJoinSheetPresented = false

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    SectionTitle(eyebrow: "My Courses", title: "我的课程")

                    Text("教学班以课程代码 + Section 区分；同一课程代码的不同 Section 会作为不同教学班展示。")
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(BNBUTheme.muted)
                        .lineSpacing(3)

                    joinEntry

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
                        SectionTitle(eyebrow: "CURRENT", title: "当前学期课程")

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
                                        .font(.headline.weight(.medium))
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
        .sheet(isPresented: $isJoinSheetPresented) {
            CourseJoinSheet()
                .environmentObject(appState)
        }
    }

    private var joinEntry: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("加入新课程")
                    .font(.headline.weight(.medium))
                Text("扫描老师提供的课程二维码或输入邀请码提交申请，老师审核通过后才会建立正式课程关系。")
                    .font(.subheadline.weight(.regular))
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .lineSpacing(3)
                PrimaryActionButton(
                    title: "扫码 / 邀请码加入",
                    systemImage: "qrcode.viewfinder",
                    accessibilityIdentifier: "courses.join.entry"
                ) {
                    appState.errorMessage = nil
                    isJoinSheetPresented = true
                }
            }
        }
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
                            .font(.title3.weight(.medium))
                            .foregroundStyle(BNBUTheme.ink)
                        Text("等待任课老师审核")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(BNBUTheme.muted)
                    }
                    Spacer(minLength: 8)
                    StatusBadge(text: course.enrollmentStatus.title)
                }

                Text("审核通过前不能开始运动打卡，本课程也不会产生有效学时。")
                    .font(.caption.weight(.regular))
                    .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    .lineSpacing(3)
            }
        }
    }
}

private struct CourseCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let course: Course
    let academicYear: String
    let term: String
    let isCurrent: Bool

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 16) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top) {
                        courseIdentity
                        Spacer(minLength: 8)
                        StatusBadge(text: localizedTerm(course.semester))
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        courseIdentity
                        StatusBadge(text: localizedTerm(course.semester))
                    }
                }

                LazyVGrid(columns: factColumns, spacing: 10) {
                    CourseFact(
                        label: "任课老师",
                        value: course.teacher.isEmpty ? BNBUL10n.text("待公布") : course.teacher
                    )
                    CourseFact(label: "学年", value: academicYear.replacingOccurrences(of: " 学年", with: ""))
                    CourseFact(label: "学期", value: localizedTerm(term))
                    CourseFact(
                        label: "选课状态",
                        value: isCurrent ? BNBUL10n.text("修读中") : BNBUL10n.text("已完成")
                    )
                }

                HStack {
                    Text(LocalizedStringKey(isCurrent ? "当前教学班" : "历史学期"))
                        .font(.subheadline.weight(.regular))
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)
                    Spacer()
                    Label("查看课程详情", systemImage: "chevron.right")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(BNBUTheme.primary)
                }
            }
        }
    }

    private var courseIdentity: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(course.displayTitle)
                .font(.title3.weight(.medium))
                .foregroundStyle(BNBUTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(course.name)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(BNBUTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var factColumns: [GridItem] {
        if dynamicTypeSize.isAccessibilitySize {
            return [GridItem(.flexible())]
        }
        return [GridItem(.flexible()), GridItem(.flexible())]
    }

    private func localizedTerm(_ value: String) -> String {
        value
            .replacingOccurrences(of: "春季学期", with: BNBUL10n.text("春季学期"))
            .replacingOccurrences(of: "秋季学期", with: BNBUL10n.text("秋季学期"))
            .replacingOccurrences(of: "SPRING", with: BNBUL10n.text("春季学期"))
            .replacingOccurrences(of: "FALL", with: BNBUL10n.text("秋季学期"))
    }
}

private struct CourseFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocalizedStringKey(label))
                .font(.caption2.weight(.medium))
                .foregroundStyle(BNBUTheme.muted)
            Text(verbatim: value)
                .font(.headline.weight(.medium))
                .foregroundStyle(BNBUTheme.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(BNBUTheme.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
    }
}
