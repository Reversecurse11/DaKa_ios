import Foundation

protocol StudentRepository {
    func loadWorkspace() -> StudentWorkspace
}

struct MockStudentRepository: StudentRepository {
    func loadWorkspace() -> StudentWorkspace {
        let student = StudentProfile(
            id: "demo-student-001",
            name: "演示学生",
            email: "demo.student@example.invalid",
            college: "工商管理学院",
            className: "2026A",
            status: "正常",
            enrollmentYear: 2024,
            birthDate: "2000-01-01",
            gender: .female,
            gradeLevel: "sophomore"
        )

        let teamCredit = Membership(
            id: "m1",
            type: "team",
            organization: "羽毛球队",
            studentId: student.id,
            studentName: student.name,
            status: "认证有效",
            validUntil: "2026-09-01",
            offset: "可抵扣",
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
            offset: "待确认",
            comment: "社团负责人尚未确认本学期名单",
            updatedBy: "跑步社负责人",
            updatedAt: "2026.06.08 18:00"
        )

        let courses = [
            Course(
                id: "gepe-1004",
                code: "GEPE101",
                section: "1004",
                name: "全人教育体育模块",
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
                name: "全人教育体育模块",
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
            rawGeneral: 0,
            exam: 86,
            attendance: 90,
            physical: 78,
            status: "差课程 4h",
            source: "seed",
            organizationCredit: teamCredit
        )

        let tasks = [
            CourseTask(
                id: "t1",
                courseId: "gepe-1004",
                creditType: .courseRelated,
                title: "课外跑步训练 Week 08",
                hours: 2,
                deadline: "第 8 周周日 23:59",
                proof: "运动 App 截图 + 场地照片",
                status: .active,
                updatedAt: "2026.06.10 09:30"
            ),
            CourseTask(
                id: "t2",
                courseId: "gepe-1004",
                creditType: .courseRelated,
                title: "体能练习补交任务",
                hours: 1.5,
                deadline: "第 9 周周三 18:00",
                proof: "训练视频 10 秒 + 运动记录截图",
                status: .active,
                updatedAt: "2026.06.11 15:20"
            ),
            CourseTask(
                id: "t3",
                courseId: "self-general",
                creditType: .general,
                title: "自主运动打卡",
                hours: 2,
                deadline: "学期统一截止：第 16 周周日 23:59",
                proof: "运动 App 截图 / 手环记录 / 场地照片",
                status: .active,
                updatedAt: "2026.06.01 08:00"
            ),
            CourseTask(
                id: "t4",
                courseId: "gepe-1005",
                creditType: .courseRelated,
                title: "Section 1005 Week 03 已关闭任务",
                hours: 2,
                deadline: "第 3 周周日 23:59",
                proof: "运动 App 截图 + 场地照片",
                status: .closed,
                updatedAt: "2026.05.12 09:00"
            )
        ]

        let records = [
            CheckInRecord(
                id: "r1",
                courseId: "gepe-1004",
                taskTitle: "课外跑步训练 Week 06",
                creditType: .courseRelated,
                hours: 2,
                submittedAt: "2026.06.08 20:10",
                status: .supplement,
                proofSummary: "2 张图片，1 个短视频",
                proofPhotoCount: 2,
                proofVideoCount: 1,
                proofFiles: [
                    ProofAttachment(id: "pf-r1-1", type: .image, fileName: "run-week06-photo-1.jpg", byteCount: 842_000, source: "mock"),
                    ProofAttachment(id: "pf-r1-2", type: .image, fileName: "run-week06-photo-2.jpg", byteCount: 790_000, source: "mock"),
                    ProofAttachment(id: "pf-r1-3", type: .video, fileName: "run-week06-video.mov", byteCount: 5_800_000, source: "mock")
                ],
                teacherFeedback: "视频时长不足，请补充包含完整运动过程的短视频。",
                note: "操场跑步 40 分钟，配速截图已上传。"
            ),
            CheckInRecord(
                id: "r2",
                courseId: "gepe-1004",
                taskTitle: "课外跑步训练 Week 05",
                creditType: .courseRelated,
                hours: 2,
                submittedAt: "2026.06.01 19:40",
                status: .approved,
                proofSummary: "运动截图 + 场地照片",
                proofPhotoCount: 2,
                proofVideoCount: 0,
                proofFiles: [
                    ProofAttachment(id: "pf-r2-1", type: .image, fileName: "gym-workout-screen.jpg", byteCount: 680_000, source: "mock"),
                    ProofAttachment(id: "pf-r2-2", type: .image, fileName: "gym-location.jpg", byteCount: 730_000, source: "mock")
                ],
                teacherFeedback: "凭证通过，按 2 小时计入。",
                note: "体育馆力量训练。"
            ),
            CheckInRecord(
                id: "r3",
                courseId: nil,
                taskTitle: "校队身份抵扣",
                creditType: .organizationOffset,
                hours: 10,
                submittedAt: "2026.06.01 10:30",
                status: .offset,
                proofSummary: "羽毛球队官方名单",
                proofPhotoCount: 0,
                proofVideoCount: 0,
                proofFiles: [],
                teacherFeedback: "系统已自动计入其他运动 10 小时。",
                note: "组织认证抵扣，B 类最多计 10 小时。"
            ),
            CheckInRecord(
                id: "r4",
                courseId: "gepe-1004",
                taskTitle: "课外跑步训练 Week 04",
                creditType: .courseRelated,
                hours: 2,
                submittedAt: "2026.05.25 20:20",
                status: .rejected,
                proofSummary: "运动截图",
                proofPhotoCount: 1,
                proofVideoCount: 0,
                proofFiles: [
                    ProofAttachment(id: "pf-r4-1", type: .image, fileName: "duplicate-run-screen.jpg", byteCount: 640_000, source: "mock")
                ],
                teacherFeedback: "图片哈希命中历史记录，本次不计入有效学时。",
                note: "补交跑步记录。"
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
            missingItems: ["打卡未满：课程相关还差 4h"]
        )

        let notices = [
            StudentNotice(
                id: "n1",
                title: "课程相关任务即将截止",
                message: "GEPE101 / Section 1004 的 Week 08 任务将在第 8 周周日 23:59 截止。",
                time: "今天 09:00",
                category: .deadline,
                isUnread: true
            ),
            StudentNotice(
                id: "n2",
                title: "运动记录已提交",
                message: "课外跑步训练 Week 06 已成功提交，可在打卡记录中查看。",
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
            tasks: tasks,
            records: records,
            grades: grades,
            memberships: [teamCredit, clubPending],
            notices: notices,
            exemptions: exemptions,
            syncOperations: syncOperations
        )
    }
}

struct EmptyStudentRepository: StudentRepository {
    func loadWorkspace() -> StudentWorkspace {
        let student = StudentProfile(
            id: "demo-student-001",
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
                rawGeneral: 0,
                exam: 0,
                attendance: 0,
                physical: 0,
                status: "暂无数据",
                source: "empty-ui-test",
                organizationCredit: nil
            ),
            tasks: [],
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
