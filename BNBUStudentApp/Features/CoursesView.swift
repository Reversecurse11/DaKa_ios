import SwiftUI

struct CoursesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var historyExpanded = false

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

    private var currentCourses: [Course] {
        appState.workspace.courses
            .filter(\.isCurrent)
            .sorted { $0.displayTitle < $1.displayTitle }
    }

    private var historyCourses: [Course] {
        appState.workspace.courses
            .filter { !$0.isCurrent }
            .sorted { $0.semester > $1.semester }
    }
}

private struct CourseCard: View {
    let course: Course
    let academicYear: String
    let term: String
    let isCurrent: Bool

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(course.displayTitle)
                            .font(.title3.weight(.medium))
                            .foregroundStyle(BNBUTheme.ink)
                        Text(course.name)
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(BNBUTheme.muted)
                    }
                    Spacer()
                    StatusBadge(text: course.semester)
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    CourseFact(label: "任课老师", value: course.teacher.isEmpty ? "待公布" : course.teacher)
                    CourseFact(label: "学年", value: academicYear.replacingOccurrences(of: " 学年", with: ""))
                    CourseFact(label: "学期", value: term)
                    CourseFact(label: "选课状态", value: isCurrent ? "修读中" : "已完成")
                }

                HStack {
                    Text(isCurrent ? "当前教学班" : "历史学期")
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
}

private struct CourseFact: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.caption2.weight(.medium))
                .foregroundStyle(BNBUTheme.muted)
            Text(value)
                .font(.headline.weight(.medium))
                .foregroundStyle(BNBUTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(BNBUTheme.surfaceVariant)
        .clipShape(RoundedRectangle(cornerRadius: BNBURadius.small, style: .continuous))
    }
}
