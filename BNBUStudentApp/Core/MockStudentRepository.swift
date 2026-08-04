import Foundation

protocol StudentRepository {
    func loadWorkspace() -> StudentWorkspace
    /// Resolves a course invite code. Nil means the invite is unknown, expired
    /// or withdrawn, which the join flow reports before asking for details.
    func loadCourseInvite(code: String) -> CourseInvite?
    /// Accepts a contact verification code. The real check is server-side; this
    /// seam exists so the flow runs before the endpoint ships.
    func acceptsContactCode(_ code: String, channel: ContactChannel, value: String) -> Bool
    /// Problem reports the student has already filed.
    func loadFeedbackTickets() -> [FeedbackTicket]
    /// Availability policy the server publishes on its health endpoint. A missing
    /// field keeps the app in `normal` during the staged backend rollout.
    func loadSystemMode() -> SystemModeStatus
    /// Minimum supported build. Nil leaves the app usable, so a configuration or
    /// network failure never locks a student out.
    func loadUpdateRequirement() -> AppUpdateRequirement?
    /// Help articles an administrator published. An empty result means nothing
    /// has been published yet; a thrown error is the load failure the help
    /// centre offers to retry.
    func loadHelpArticles() throws -> [HelpArticle]
}

struct MockStudentRepository: StudentRepository {
    /// The endurance-run card has four server-driven states that demo data
    /// cannot show at once, so screenshot runs select one by launch argument.
    static var mockEnduranceStatus: EnduranceRunStatus {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing-endurance-exempt") { return .exempt }
        if arguments.contains("-ui-testing-endurance-absent") { return .absent }
        if arguments.contains("-ui-testing-endurance-unrecorded") { return .notRecorded }
        return .recorded
    }

    func loadWorkspace() -> StudentWorkspace {
        let student = StudentProfile(
            id: "demo-student-001",
            studentNumber: "2400123456",
            name: "演示学生",
            email: "demo.student@example.invalid",
            college: "工商管理学院",
            className: "2026A",
            status: "正常",
            enrollmentYear: 2024,
            birthDate: "2000-01-01",
            gender: .female,
            gradeLevel: "sophomore",
            gradeCalculatedAt: "2026-07-29T14:32:07Z"
        )

        let teamCredit = Membership(
            id: "m1",
            type: "team",
            organization: "羽毛球队",
            studentId: student.id,
            studentName: student.name,
            status: "有效",
            validUntil: "2026-09-01",
            offset: "其他运动时长抵扣 10 小时",
            comment: "校队名单已确认，抵扣其他运动 10 小时",
            updatedBy: "体育部管理员",
            updatedAt: "2026.06.01 10:30"
        )

        let clubPending = Membership(
            id: "m2",
            type: "club",
            organization: "跑步社",
            studentId: student.id,
            studentName: student.name,
            status: "待确认",
            validUntil: "2026-09-01",
            offset: "名单确认后生效",
            comment: "社团负责人尚未确认本学期名单",
            updatedBy: "跑步社负责人",
            updatedAt: "2026.06.08 18:00"
        )

        let courses = [
            Course(
                id: "gepe-1004",
                code: "GEPE101",
                section: "1004",
                name: "全人教育体育模块（羽毛球）",
                semester: "2026 SPRING",
                students: 82,
                pending: 24,
                completion: 63,
                missing: 19,
                deadline: "第 8 周周日 23:59",
                teacher: "王老师"
            ),
            Course(
                id: "gepe-1005",
                code: "GEPE101",
                section: "1005",
                name: "全人教育体育模块（篮球）",
                semester: "2026 SPRING",
                students: 78,
                pending: 12,
                completion: 71,
                missing: 11,
                deadline: "第 8 周周日 23:59",
                teacher: "李老师"
            )
        ]

        let progress = StudentProgress(
            id: student.id,
            name: student.name,
            college: student.college,
            className: student.className,
            course: 6,
            general: 10,
            rawCourse: 6,
            rawGeneral: 0,
            exam: 86,
            attendance: 90,
            physical: 78,
            status: "差课程 4 小时",
            source: "seed",
            organizationCredit: teamCredit
        )

        let records = [
            CheckInRecord(
                id: "r1",
                courseId: "gepe-1004",
                taskTitle: "课程相关运动打卡",
                creditType: .courseRelated,
                hours: 2,
                submittedAt: "2026.06.08 20:10",
                validity: .valid,
                proofSummary: "2 张图片，1 个短视频",
                proofPhotoCount: 2,
                proofVideoCount: 1,
                proofFiles: [
                    ProofAttachment(id: "pf-r1-1", type: .image, fileName: "run-week06-photo-1.jpg", byteCount: 842_000, source: "mock"),
                    ProofAttachment(id: "pf-r1-2", type: .image, fileName: "run-week06-photo-2.jpg", byteCount: 790_000, source: "mock"),
                    ProofAttachment(id: "pf-r1-3", type: .video, fileName: "run-week06-video.mov", byteCount: 5_800_000, source: "mock")
                ],
                note: "操场跑步，全程计时 2 小时。",
                sportType: "running"
            ),
            CheckInRecord(
                id: "r2",
                courseId: "gepe-1004",
                taskTitle: "课程相关运动打卡",
                creditType: .courseRelated,
                hours: 2,
                submittedAt: "2026.06.01 19:40",
                validity: .valid,
                proofSummary: "2 张现场照片",
                proofPhotoCount: 2,
                proofVideoCount: 0,
                proofFiles: [
                    ProofAttachment(id: "pf-r2-1", type: .image, fileName: "gym-training-photo.jpg", byteCount: 680_000, source: "mock"),
                    ProofAttachment(id: "pf-r2-2", type: .image, fileName: "gym-location-photo.jpg", byteCount: 730_000, source: "mock")
                ],
                note: "体育馆力量训练。",
                sportType: "fitness"
            ),
            CheckInRecord(
                id: "r3",
                courseId: nil,
                taskTitle: "校队身份抵扣",
                creditType: .organizationOffset,
                hours: 10,
                submittedAt: "2026.06.01 10:30",
                validity: .valid,
                proofSummary: "羽毛球队官方名单",
                proofPhotoCount: 0,
                proofVideoCount: 0,
                proofFiles: [],
                note: "组织认证抵扣，B 类最多计 10 小时。"
            ),
            CheckInRecord(
                id: "r4",
                courseId: "gepe-1004",
                taskTitle: "课程相关运动打卡",
                creditType: .courseRelated,
                hours: 2,
                submittedAt: "2026.05.25 20:20",
                validity: .invalid,
                invalidReason: "图片哈希命中历史记录，本次不计入有效学时。",
                proofSummary: "1 张现场照片",
                proofPhotoCount: 1,
                proofVideoCount: 0,
                proofFiles: [
                    ProofAttachment(id: "pf-r4-1", type: .image, fileName: "run-repeat-photo.jpg", byteCount: 640_000, source: "mock")
                ],
                note: "操场跑步记录。",
                sportType: "running"
            )
        ]

        let exemptions = [
            ExemptionApplication(
                id: "ex1",
                studentId: student.id,
                item: .run800m,
                reason: "膝关节运动损伤",
                detail: "近期医生建议避免长距离耐力跑，申请本学期 800 米耐力跑免测。",
                submittedAt: "2026.06.09 14:20",
                status: .rejected,
                proofFiles: [
                    ProofAttachment(id: "ex-pf-1", type: .image, fileName: "hospital-note.jpg", byteCount: 920_000, source: "mock")
                ],
                teacherFeedback: "老师已驳回：证明材料不足。如需再次申请，请重新提交新申请。",
                reviewer: "王老师",
                updatedAt: "2026.06.10 11:30"
            )
        ]

        let grades = GradeRow(
            studentId: student.id,
            studentName: student.name,
            checkinScore: 80,
            exam: 86,
            attendance: 90,
            physical: 78,
            total: 83,
            sourceTrace: "名单:课程初始名单; 打卡:组织抵扣:羽毛球队; 专项:已录入; 平时:已保存; 体测:已保存",
            missingItems: ["打卡未满：课程相关还差 4h"],
            enduranceRunTimeSeconds: Self.mockEnduranceStatus == .recorded ? 245 : nil,
            enduranceRunStatus: Self.mockEnduranceStatus,
            enduranceRunScore: Self.mockEnduranceStatus == .exempt ? 85 : nil
        )

        let notices = [
            StudentNotice(
                id: "n1",
                title: "本学期学时提醒",
                message: "课程相关学时还差 4 小时，请尽早安排运动打卡。",
                time: "今天 09:00",
                category: .deadline,
                isUnread: true
            ),
            StudentNotice(
                id: "n2",
                title: "运动记录已提交",
                message: "课程相关运动打卡已成功提交，可在打卡记录中查看。",
                time: "昨天 18:20",
                category: .system,
                isUnread: true
            ),
            StudentNotice(
                id: "n3",
                title: "组织抵扣已生效",
                message: "羽毛球队认证有效，其他运动 10 小时已自动完成。",
                time: "06.01 10:30",
                category: .organization,
                isUnread: false
            ),
            StudentNotice(
                id: "n4",
                title: "免测申请需补材料",
                message: "800m 免测申请需要补充校医室证明，请在申请详情中补交后重新提交。",
                time: "07.30 15:40",
                category: .review,
                isUnread: true
            )
        ]

        let syncOperations = [
            SyncOperation(
                id: "sync-seed",
                type: .resetLocalData,
                title: "加载 Mock 工作台",
                detail: "学生端当前使用本地 mock 数据，后续可替换为 API repository。",
                createdAt: "启动时",
                status: .localOnly
            )
        ]

        return StudentWorkspace(
            student: student,
            courses: courses,
            progress: progress,
            records: records,
            grades: grades,
            memberships: [teamCredit, clubPending],
            notices: notices,
            exemptions: exemptions,
            syncOperations: syncOperations
        )
    }

    /// One resolved and one in-flight ticket, so the list, the status badges and
    /// the reply row all have something to show before the endpoint ships.
    /// Demo and screenshot runs need to reach the maintenance surfaces without a
    /// server, so the availability policy is selected by launch argument.
    func loadSystemMode() -> SystemModeStatus {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing-maintenance") {
            return SystemModeStatus(
                mode: .maintenance,
                message: "",
                estimatedRecoveryTime: "2026-08-04 22:00"
            )
        }
        if arguments.contains("-ui-testing-read-only") {
            return SystemModeStatus(mode: .readOnly)
        }
        if arguments.contains("-ui-testing-planned-maintenance") {
            return SystemModeStatus(
                mode: .normal,
                message: "",
                plannedMaintenanceAt: "2026-08-06 23:00"
            )
        }
        return SystemModeStatus()
    }

    func loadUpdateRequirement() -> AppUpdateRequirement? {
        guard ProcessInfo.processInfo.arguments.contains("-ui-testing-update-required") else {
            return nil
        }
        return AppUpdateRequirement(
            minimumVersion: "99.0",
            downloadURL: "https://example.invalid/bnbu-sports",
            updateMessage: "本次更新修复了打卡凭证上传失败的问题。"
        )
    }

    /// Stands in for the administrator-managed article list. Screenshot runs pick
    /// the failure and empty states, which demo data cannot produce on its own.
    func loadHelpArticles() throws -> [HelpArticle] {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("-ui-testing-help-error") {
            throw RepositoryError.networkError("演示：帮助内容加载失败")
        }
        if arguments.contains("-ui-testing-help-empty") {
            return []
        }

        return [
            HelpArticle(
                id: "help-checkin-flow",
                title: "如何完成一次运动打卡？",
                category: "运动打卡",
                content: "在首页或“运动”页选择打卡类型和运动项目后开始计时。运动中可暂停后继续；结束时确认时长，选择至少 1 张现场照片或 1 个现场视频作为凭证，再提交。",
                sortOrder: 10,
                updatedAt: "2026-07-28T09:12:00Z"
            ),
            HelpArticle(
                id: "help-checkin-evidence",
                title: "照片和视频凭证有什么限制？",
                category: "运动打卡",
                content: "凭证必须在运动过程中或提交环节用相机现场拍摄，不能从相册选择。每次最多 6 张照片和 1 个视频，且至少选择其中 1 项。",
                sortOrder: 20,
                updatedAt: "2026-07-28T09:12:00Z"
            ),
            HelpArticle(
                id: "help-location-denied",
                title: "为什么获取不到定位？",
                category: "定位与权限",
                content: "请在 iPhone“设置 → 隐私与安全性 → 定位服务”中允许本 App 使用定位。定位失败不会阻止计时和提交，记录会显示为“未获取位置”。",
                sortOrder: 30,
                updatedAt: "2026-07-20T02:00:00Z"
            ),
            HelpArticle(
                id: "help-exemption-apply",
                title: "如何提交体测免测申请？",
                category: "申请与审核",
                content: "从个人页进入申请中心，选择免测类型，填写申请信息并上传证明材料后提交。提交后可查看审核状态，被退回时可补充材料重新提交。",
                sortOrder: 40,
                updatedAt: "2026-07-15T06:30:00Z"
            ),
            HelpArticle(
                id: "help-grade-publish",
                title: "成绩什么时候公示？",
                category: "课程与成绩",
                content: "成绩由任课教师录入并公示。公示前显示为“未录入”，公示后可在成绩页查看各项得分与总评。对成绩有疑问请先联系任课教师。",
                sortOrder: 50,
                updatedAt: "2026-07-15T06:30:00Z"
            ),
            HelpArticle(
                id: "help-maintenance",
                title: "维护期间可以做什么？",
                category: "系统与账号",
                content: "维护公告会说明影响范围和预计恢复时间。服务暂时不可用时可继续查看已缓存内容，提交类操作请在恢复后重试；未提交的运动会保留在本机草稿中。",
                sortOrder: 60,
                updatedAt: "2026-07-01T11:00:00Z"
            )
        ]
    }

    func loadFeedbackTickets() -> [FeedbackTicket] {
        [
            FeedbackTicket(
                id: "fb-2026-0043",
                ticketNumber: "FB-2026-0043",
                category: FeedbackCategory.checkIn.title,
                description: "结束运动后提交打卡，凭证上传到一半就停住了，重试两次才成功。",
                status: .processing,
                createdAt: "2026 年 7 月 30 日 19:24",
                reply: nil
            ),
            FeedbackTicket(
                id: "fb-2026-0031",
                ticketNumber: "FB-2026-0031",
                category: FeedbackCategory.grades.title,
                description: "耐力跑成绩换算结果和老师给的分数差 1 分。",
                status: .resolved,
                createdAt: "2026 年 7 月 21 日 10:05",
                reply: "已核对评分表，差异来自年级组别取值，本周已修正。"
            )
        ]
    }

    /// Demo data has no mailbox or handset to deliver to, so any well-formed
    /// code is accepted until the contact endpoints ship.
    func acceptsContactCode(_ code: String, channel: ContactChannel, value: String) -> Bool {
        ContactBindingRule.isValidCode(code)
    }

    /// Demo invites resolve to a course the demo student has not joined, so the
    /// confirmation page has something to show before the lookup endpoint ships.
    func loadCourseInvite(code: String) -> CourseInvite? {
        guard CourseJoinCodeRule.validationMessage(for: code) == nil else { return nil }
        return CourseInvite(
            code: CourseJoinCodeRule.normalized(code),
            courseName: "大学体育（篮球）",
            courseCode: "PE1024",
            section: "S02",
            teacherName: "陈老师",
            semester: "2026-2027 学年第一学期"
        )
    }
}

struct EmptyStudentRepository: StudentRepository {
    func loadCourseInvite(code: String) -> CourseInvite? { nil }

    func acceptsContactCode(_ code: String, channel: ContactChannel, value: String) -> Bool {
        ContactBindingRule.isValidCode(code)
    }

    func loadFeedbackTickets() -> [FeedbackTicket] { [] }

    func loadSystemMode() -> SystemModeStatus { SystemModeStatus() }

    func loadUpdateRequirement() -> AppUpdateRequirement? { nil }

    func loadHelpArticles() throws -> [HelpArticle] { [] }

    func loadWorkspace() -> StudentWorkspace {
        let student = StudentProfile(
            id: "demo-student-001",
            studentNumber: "2400123456",
            name: "演示学生",
            email: "demo.student@example.invalid",
            college: "工商管理学院",
            className: "2026A",
            status: "正常"
        )

        return StudentWorkspace(
            student: student,
            courses: [],
            progress: StudentProgress(
                id: student.id,
                name: student.name,
                college: student.college,
                className: student.className,
                course: 0,
                general: 0,
                rawCourse: 0,
                rawGeneral: 0,
                exam: 0,
                attendance: 0,
                physical: 0,
                status: "暂无数据",
                source: "empty-ui-test",
                organizationCredit: nil
            ),
            records: [],
            grades: GradeRow(
                studentId: student.id,
                studentName: student.name,
                checkinScore: 0,
                exam: 0,
                attendance: 0,
                physical: 0,
                total: 0,
                sourceTrace: "空状态测试数据",
                missingItems: ["暂无成绩来源"]
            ),
            memberships: [],
            notices: [],
            syncOperations: []
        )
    }
}
