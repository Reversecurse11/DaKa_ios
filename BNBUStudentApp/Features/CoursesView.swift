import SwiftUI

struct CoursesView: View {
    @EnvironmentObject private var appState: AppState
    @State private var historyExpanded = false

    var body: some View {
        ZStack {
            BNBUPageBackground()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    Text("按课程代码和 Section 查看当前与历史教学班。")
                        .font(.subheadline)
                        .foregroundStyle(BNBUTheme.onSurfaceVariant)

                    if appState.workspace.courses.isEmpty {
                        EmptyPlaceholder(
                            title: "暂无课程",
                            message: "当前账号还没有可展示的体育教学班；课程同步后会按课程代码和 Section 显示。"
                        )
                    } else {
                        Text("当前学期课程")
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(BNBUTheme.onSurfaceVariant)

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
                                .bnbuGlassSurface(radius: BNBURadius.extraLarge, shadowOpacity: 0.04)
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
            .scrollIndicators(.hidden)
            .refreshable {
                await appState.refreshRemoteWorkspace()
            }
        }
        .navigationTitle("我的课程")
        .navigationBarTitleDisplayMode(.large)
        .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let course: Course
    let academicYear: String
    let term: String
    let isCurrent: Bool

    var body: some View {
        SwissPanel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    Image(systemName: "book.closed.fill")
                        .font(.title3.weight(.semibold))
                        .symbolRenderingMode(.monochrome)
                        .foregroundStyle(BNBUTheme.primary)
                        .frame(width: 42, height: 42)
                        .background(BNBUTheme.primary.opacity(0.1), in: Circle())

                    courseIdentity

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 8) {
                        StatusBadge(text: isCurrent ? "修读中" : "已完成", filled: isCurrent)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(BNBUTheme.onSurfaceVariant.opacity(0.7))
                    }
                }

                Divider()
                    .overlay(BNBUTheme.outline.opacity(0.2))

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) {
                        courseMeta(
                            systemImage: "person.fill",
                            value: course.teacher.isEmpty ? BNBUL10n.text("待公布") : course.teacher
                        )
                        Spacer(minLength: 8)
                        courseMeta(
                            systemImage: "calendar",
                            value: "\(academicYear.replacingOccurrences(of: " 学年", with: "")) · \(localizedTerm(term))"
                        )
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        courseMeta(
                            systemImage: "person.fill",
                            value: course.teacher.isEmpty ? BNBUL10n.text("待公布") : course.teacher
                        )
                        courseMeta(
                            systemImage: "calendar",
                            value: "\(academicYear.replacingOccurrences(of: " 学年", with: "")) · \(localizedTerm(term))"
                        )
                    }
                }
            }
        }
    }

    private var courseIdentity: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(course.displayTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(BNBUTheme.onSurface)
                .fixedSize(horizontal: false, vertical: true)
            Text(course.name)
                .font(.subheadline)
                .foregroundStyle(BNBUTheme.onSurfaceVariant)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func courseMeta(systemImage: String, value: String) -> some View {
        Label {
            Text(verbatim: value)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(BNBUTheme.primary)
        }
        .font(.subheadline)
        .foregroundStyle(BNBUTheme.onSurfaceVariant)
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
