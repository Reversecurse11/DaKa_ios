import CryptoKit
import Foundation

enum StudentGender: String, Hashable, Codable {
    case female
    case male
    case unknown

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = (try? container.decode(String.self))?.lowercased() ?? ""
        switch value {
        case "female", "f", "女", "女生": self = .female
        case "male", "m", "男", "男生": self = .male
        default: self = .unknown
        }
    }

    var title: String {
        switch self {
        case .female: return "女生"
        case .male: return "男生"
        case .unknown: return "性别待同步"
        }
    }

    var apiValue: String? {
        switch self {
        case .female: return "female"
        case .male: return "male"
        case .unknown: return nil
        }
    }
}

struct EnduranceScoreResult: Hashable, Codable {
    let score: Int
    let tier: String
    let timeSeconds: Int
    let gender: String
    let gradeLevel: String
    let gradeGroup: String

    var tierTitle: String {
        switch tier.lowercased() {
        case "excellent": return "优秀"
        case "good": return "良好"
        case "pass": return "及格"
        case "fail": return "不及格"
        default: return tier
        }
    }
}

struct StudentProfile: Identifiable, Hashable, Codable {
    let id: String
    /// Human-readable student number (e.g. "s1" / "22301142"); the server `id`
    /// may be an opaque UUID, so UI should display `displayStudentNumber`.
    let studentNumber: String?
    let name: String
    let email: String
    let college: String
    let className: String
    let status: String
    let enrollmentYear: Int?
    let birthDate: String?
    let gender: StudentGender
    let gradeLevel: String?

    var displayStudentNumber: String {
        if let studentNumber, !studentNumber.isEmpty {
            return studentNumber
        }
        return id
    }

    init(
        id: String,
        studentNumber: String? = nil,
        name: String,
        email: String,
        college: String,
        className: String,
        status: String,
        enrollmentYear: Int? = nil,
        birthDate: String? = nil,
        gender: StudentGender = .unknown,
        gradeLevel: String? = nil
    ) {
        self.id = id
        self.studentNumber = studentNumber
        self.name = name
        self.email = email
        self.college = college
        self.className = className
        self.status = status
        self.enrollmentYear = enrollmentYear
        self.birthDate = birthDate
        self.gender = gender
        self.gradeLevel = gradeLevel
    }

    enum CodingKeys: String, CodingKey {
        case id
        case studentId
        case studentNumber
        case studentNo
        case account
        case name
        case studentName
        case fullName
        case email
        case college
        case className
        case class_name
        case status
        case enrollmentYear
        case admissionYear
        case entryYear
        case enrollment_year
        case birthDate
        case birthday
        case gender
        case gradeLevel
        case currentGradeLevel
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedEmail = try container.decodeIfPresent(String.self, forKey: .email) ?? ""
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .studentId)
            ?? container.decodeIfPresent(String.self, forKey: .account)
            ?? decodedEmail
        studentNumber = try container.decodeIfPresent(String.self, forKey: .studentNumber)
            ?? container.decodeIfPresent(String.self, forKey: .studentNo)
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .studentName)
            ?? container.decodeIfPresent(String.self, forKey: .fullName)
            ?? "BNBU Student"
        email = decodedEmail
        college = try container.decodeIfPresent(String.self, forKey: .college) ?? "BNBU"
        className = try container.decodeIfPresent(String.self, forKey: .className)
            ?? container.decodeIfPresent(String.self, forKey: .class_name)
            ?? ""
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "正常"
        enrollmentYear = Self.decodeFlexibleInt(from: container, keys: [.enrollmentYear, .admissionYear, .entryYear, .enrollment_year])
        birthDate = try container.decodeIfPresent(String.self, forKey: .birthDate)
            ?? container.decodeIfPresent(String.self, forKey: .birthday)
        gender = try container.decodeIfPresent(StudentGender.self, forKey: .gender) ?? .unknown
        gradeLevel = try container.decodeIfPresent(String.self, forKey: .gradeLevel)
            ?? container.decodeIfPresent(String.self, forKey: .currentGradeLevel)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(studentNumber, forKey: .studentNumber)
        try container.encode(name, forKey: .name)
        try container.encode(email, forKey: .email)
        try container.encode(college, forKey: .college)
        try container.encode(className, forKey: .className)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(enrollmentYear, forKey: .enrollmentYear)
        try container.encodeIfPresent(birthDate, forKey: .birthDate)
        try container.encode(gender, forKey: .gender)
        try container.encodeIfPresent(gradeLevel, forKey: .gradeLevel)
    }

    private static func decodeFlexibleInt(
        from container: KeyedDecodingContainer<CodingKeys>,
        keys: [CodingKeys]
    ) -> Int? {
        for key in keys {
            if let value = try? container.decode(Int.self, forKey: key) {
                return value
            }
            if let value = try? container.decode(String.self, forKey: key), let year = Int(value) {
                return year
            }
        }
        return nil
    }
}

struct StudentAcademicProjection: Equatable {
    let academicYear: String
    let semester: String
    let grade: String
    let enrollmentYear: String
    let age: String
    let physicalStandard: String
    let usesConfirmedEnrollmentYear: Bool

    static func resolve(
        profile: StudentProfile,
        at date: Date = Date(),
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> StudentAcademicProjection {
        let year = calendar.component(.year, from: date)
        let month = calendar.component(.month, from: date)
        let academicStartYear = month >= 9 ? year : year - 1
        let fallbackGrade = gradeNumber(from: profile.gradeLevel)
        let projectedEnrollmentYear = profile.enrollmentYear ?? fallbackGrade.map { academicStartYear - $0 + 1 }
        let gradeNumber = projectedEnrollmentYear.map { max(academicStartYear - $0 + 1, 1) } ?? fallbackGrade
        let grade = gradeTitle(for: gradeNumber)
        let ageValue = age(from: profile.birthDate, at: date, calendar: calendar)
        let ageText = ageValue.map { "\($0) 岁" } ?? "年龄待同步"
        let semester = month >= 9 ? "秋季学期" : "春季学期"

        return StudentAcademicProjection(
            academicYear: "\(academicStartYear)–\(academicStartYear + 1) 学年",
            semester: semester,
            grade: grade,
            enrollmentYear: projectedEnrollmentYear.map { "\($0) 级" } ?? "入学年份待同步",
            age: ageText,
            physicalStandard: "\(profile.gender.title) · \(grade)体测标准",
            usesConfirmedEnrollmentYear: profile.enrollmentYear != nil
        )
    }

    private static func gradeNumber(from value: String?) -> Int? {
        switch value?.lowercased() {
        case "freshman", "year1", "grade1", "大一": return 1
        case "sophomore", "year2", "grade2", "大二": return 2
        case "junior", "year3", "grade3", "大三": return 3
        case "senior", "year4", "grade4", "大四": return 4
        default: return nil
        }
    }

    private static func gradeTitle(for number: Int?) -> String {
        switch number {
        case 1: return "大一"
        case 2: return "大二"
        case 3: return "大三"
        case 4: return "大四"
        case let value? where value > 4: return "大四及以上"
        default: return "年级待同步"
        }
    }

    private static func age(from value: String?, at date: Date, calendar: Calendar) -> Int? {
        guard let value else { return nil }
        let formats = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX", "yyyy-MM-dd'T'HH:mm:ssXXXXX"]
        let birthDate = formats.lazy.compactMap { format -> Date? in
            let formatter = DateFormatter()
            formatter.calendar = calendar
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter.date(from: value)
        }.first
        guard let birthDate else { return nil }
        return calendar.dateComponents([.year], from: birthDate, to: date).year
    }
}

enum ExerciseCategory: String, CaseIterable, Identifiable, Hashable, Codable {
    case courseRelated
    case general

    var id: String { rawValue }

    var title: String {
        switch self {
        case .courseRelated: return "课程相关运动"
        case .general: return "自主其他运动"
        }
    }
}

enum ExerciseSportType: String, CaseIterable, Identifiable, Hashable, Codable {
    case running
    case basketball
    case football
    case badminton
    case swimming
    case fitness
    case cycling
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .running: return "跑步"
        case .basketball: return "篮球"
        case .football: return "足球"
        case .badminton: return "羽毛球"
        case .swimming: return "游泳"
        case .fitness: return "健身"
        case .cycling: return "骑行"
        case .other: return "其他"
        }
    }
}

enum ExerciseSessionStatus: String, Hashable, Codable {
    case active
    case completed
}

enum ExerciseLocationStatus: String, Hashable, Codable {
    case available
    case unavailable
}

/// One pause window inside an exercise session. `resumedAt == nil` means the
/// pause is still open. Business rules require every pause/resume instant to
/// be recorded, so pauses are never merged or dropped.
struct ExercisePause: Hashable, Codable {
    let startedAt: Date
    var resumedAt: Date?

    /// Paused time that overlaps [rangeStart, rangeEnd]; an open pause is
    /// treated as lasting until rangeEnd.
    func overlap(from rangeStart: Date, to rangeEnd: Date) -> TimeInterval {
        let start = max(startedAt, rangeStart)
        let end = min(resumedAt ?? rangeEnd, rangeEnd)
        return max(end.timeIntervalSince(start), 0)
    }
}

struct ExerciseSession: Identifiable, Hashable, Codable {
    static let oneHour: TimeInterval = 60 * 60
    static let maximumDuration: TimeInterval = 2 * oneHour
    /// A pause left open this long auto-ends the session (business rule 3.2.1).
    static let maximumPauseBeforeAutoEnd: TimeInterval = 6 * oneHour

    let id: String
    let studentID: String
    let category: ExerciseCategory
    let sportType: ExerciseSportType
    let customSportName: String?
    let courseID: String?
    let startTime: Date
    var endTime: Date?
    var status: ExerciseSessionStatus
    var locationStatus: ExerciseLocationStatus
    var latitude: Double?
    var longitude: Double?
    var pauses: [ExercisePause]

    init(
        id: String,
        studentID: String,
        category: ExerciseCategory,
        sportType: ExerciseSportType,
        customSportName: String?,
        courseID: String?,
        startTime: Date,
        endTime: Date? = nil,
        status: ExerciseSessionStatus,
        locationStatus: ExerciseLocationStatus,
        latitude: Double? = nil,
        longitude: Double? = nil,
        pauses: [ExercisePause] = []
    ) {
        self.id = id
        self.studentID = studentID
        self.category = category
        self.sportType = sportType
        self.customSportName = customSportName
        self.courseID = courseID
        self.startTime = startTime
        self.endTime = endTime
        self.status = status
        self.locationStatus = locationStatus
        self.latitude = latitude
        self.longitude = longitude
        self.pauses = pauses
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        studentID = try container.decode(String.self, forKey: .studentID)
        category = try container.decode(ExerciseCategory.self, forKey: .category)
        sportType = try container.decode(ExerciseSportType.self, forKey: .sportType)
        customSportName = try container.decodeIfPresent(String.self, forKey: .customSportName)
        courseID = try container.decodeIfPresent(String.self, forKey: .courseID)
        startTime = try container.decode(Date.self, forKey: .startTime)
        endTime = try container.decodeIfPresent(Date.self, forKey: .endTime)
        status = try container.decode(ExerciseSessionStatus.self, forKey: .status)
        locationStatus = try container.decode(ExerciseLocationStatus.self, forKey: .locationStatus)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
        // Sessions persisted before the pause feature carry no pauses key.
        pauses = try container.decodeIfPresent([ExercisePause].self, forKey: .pauses) ?? []
    }

    var resolvedSportName: String {
        if sportType == .other {
            return customSportName ?? sportType.title
        }
        return sportType.title
    }

    /// The currently open pause, if the session is paused right now.
    var openPause: ExercisePause? {
        guard let last = pauses.last, last.resumedAt == nil else { return nil }
        return last
    }

    var isPaused: Bool {
        status == .active && openPause != nil
    }

    /// Actual exercise duration: wall-clock time minus accumulated pauses,
    /// capped at the 2-hour daily maximum.
    func elapsed(at date: Date = Date()) -> TimeInterval {
        let effectiveEnd = max(endTime ?? date, startTime)
        let wallClock = effectiveEnd.timeIntervalSince(startTime)
        let paused = pauses.reduce(0) { $0 + $1.overlap(from: startTime, to: effectiveEnd) }
        return min(max(wallClock - paused, 0), Self.maximumDuration)
    }

    /// Total paused time so far, for UI display.
    func pausedDuration(at date: Date = Date()) -> TimeInterval {
        let effectiveEnd = max(endTime ?? date, startTime)
        return pauses.reduce(0) { $0 + $1.overlap(from: startTime, to: effectiveEnd) }
    }

    func creditedHours(at date: Date = Date()) -> Double {
        let duration = elapsed(at: date)
        if duration >= Self.maximumDuration { return 2 }
        if duration >= Self.oneHour { return 1 }
        return 0
    }

    /// The wall-clock instant at which active exercise time reaches the
    /// 2-hour cap, walking the segments between pauses. Returns nil while an
    /// open pause exists and the cap was not reached before it started.
    func activeDurationCapInstant() -> Date? {
        var accumulated: TimeInterval = 0
        var cursor = startTime
        for pause in pauses {
            let segmentEnd = max(pause.startedAt, cursor)
            let segmentLength = segmentEnd.timeIntervalSince(cursor)
            if accumulated + segmentLength >= Self.maximumDuration {
                return cursor.addingTimeInterval(Self.maximumDuration - accumulated)
            }
            accumulated += segmentLength
            guard let resumedAt = pause.resumedAt else { return nil }
            cursor = max(resumedAt, segmentEnd)
        }
        return cursor.addingTimeInterval(Self.maximumDuration - accumulated)
    }

    /// Auto-completion: active time reached the 2-hour cap, or an open pause
    /// exceeded 6 hours (in which case the exercise ends at the pause start).
    func reconciled(at date: Date = Date()) -> ExerciseSession {
        guard status == .active else { return self }
        if let openPause {
            if date.timeIntervalSince(openPause.startedAt) >= Self.maximumPauseBeforeAutoEnd {
                return ended(at: openPause.startedAt)
            }
            return self
        }
        if let capInstant = activeDurationCapInstant(), date >= capInstant {
            return ended(at: capInstant)
        }
        return self
    }

    /// Whether reconciliation at `date` would auto-complete this session
    /// because the 2-hour active-time cap was reached (not the pause timeout).
    func reachedDailyCap(at date: Date = Date()) -> Bool {
        guard status == .active, openPause == nil else { return false }
        guard let capInstant = activeDurationCapInstant() else { return false }
        return date >= capInstant
    }

    /// Ends the session. Ending while paused stops the exercise at the pause
    /// start; the stop time never exceeds the active-time cap instant.
    func ended(at date: Date = Date()) -> ExerciseSession {
        var updated = self
        var stopTime = max(date, startTime)
        if let openPause {
            stopTime = min(stopTime, max(openPause.startedAt, startTime))
        }
        if let capInstant = activeDurationCapInstant(), capInstant < stopTime {
            stopTime = capInstant
        }
        updated.endTime = stopTime
        updated.status = .completed
        return updated
    }

    /// Opens a pause. Returns nil when the session is not active or already paused.
    func paused(at date: Date = Date()) -> ExerciseSession? {
        guard status == .active, openPause == nil else { return nil }
        let lastResume = pauses.last?.resumedAt ?? startTime
        var updated = self
        updated.pauses.append(ExercisePause(startedAt: max(date, lastResume), resumedAt: nil))
        return updated
    }

    /// Closes the open pause. Returns nil when the session is not paused.
    func resumed(at date: Date = Date()) -> ExerciseSession? {
        guard status == .active, let lastIndex = pauses.indices.last,
              pauses[lastIndex].resumedAt == nil else { return nil }
        var updated = self
        updated.pauses[lastIndex].resumedAt = max(date, pauses[lastIndex].startedAt)
        return updated
    }
}

enum ExerciseSessionInputRule {
    static let maximumCustomSportNameLength = 32

    static func validationMessage(sportType: ExerciseSportType?, customSportName: String) -> String? {
        guard let sportType else { return "请选择运动项目。" }
        guard sportType == .other else { return nil }
        let normalized = customSportName.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.isEmpty { return "请填写其他运动项目名称。" }
        if normalized.count > maximumCustomSportNameLength { return "其他运动项目名称不能超过 32 个字符。" }
        return nil
    }
}

/// Business rule 3.3: students may only *start* a session inside the daily
/// open window. A session started in the window may end and submit after it
/// closes. The window is admin-configured server-side; until the backend
/// exposes it, the documented default (06:00–22:00 Asia/Shanghai) applies.
enum CheckInTimeWindowRule {
    static let dailyStartHour = 6
    static let dailyEndHour = 22

    static var displayText: String {
        String(format: "%02d:00–%02d:00", dailyStartHour, dailyEndHour)
    }

    static func canStartExercise(at date: Date) -> Bool {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
        let hour = calendar.component(.hour, from: date)
        return hour >= dailyStartHour && hour < dailyEndHour
    }

    static var startBlockedMessage: String {
        "当前不在每日打卡开放时段（\(displayText)），暂时不能开始运动。"
    }
}

/// A camera capture taken during or right after an exercise session. Media
/// bytes live in a protected on-device file (or inline for small test
/// payloads); drafts never upload until the student selects them as proof.
struct ExerciseMediaDraft: Identifiable, Hashable, Codable {
    let id: String
    let studentID: String
    /// Session that produced this capture. Abandoning a session removes only
    /// its own drafts; drafts retained from an earlier <1h attempt survive.
    let sessionID: String
    let type: ProofMediaType
    let fileName: String
    /// File name inside the exercise-media draft directory. Nil when the
    /// bytes are stored inline (unit tests without file storage).
    let storedFileName: String?
    var inlineData: Data?
    var thumbnailData: Data?
    let byteCount: Int
    let durationSeconds: Double?
    let capturedAt: Date
}

enum ExerciseMediaDraftRule {
    /// Business rule 5.5/7: at most 6 photo drafts per check-in lifecycle.
    /// Video recordings do not count toward the photo cap.
    static let maximumPhotoDrafts = 6

    static func canAddPhoto(to drafts: [ExerciseMediaDraft]) -> Bool {
        drafts.filter { $0.type == .image }.count < maximumPhotoDrafts
    }
}

struct UserBrief: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let email: String
}

struct StudentWorkspace: Codable {
    var student: StudentProfile
    var courses: [Course]
    var progress: StudentProgress
    var records: [CheckInRecord]
    var grades: GradeRow
    var memberships: [Membership]
    var notices: [StudentNotice]
    var exemptions: [ExemptionApplication]
    var syncOperations: [SyncOperation]

    init(
        student: StudentProfile,
        courses: [Course],
        progress: StudentProgress,
        records: [CheckInRecord],
        grades: GradeRow,
        memberships: [Membership],
        notices: [StudentNotice],
        exemptions: [ExemptionApplication] = [],
        syncOperations: [SyncOperation] = []
    ) {
        self.student = student
        self.courses = courses
        self.progress = progress
        self.records = records
        self.grades = grades
        self.memberships = memberships
        self.notices = notices
        self.exemptions = exemptions
        self.syncOperations = syncOperations
    }

    enum CodingKeys: String, CodingKey {
        case student
        case courses
        case progress
        case records
        case grades
        case memberships
        case notices
        case exemptions
        case syncOperations
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        student = try container.decode(StudentProfile.self, forKey: .student)
        courses = try container.decode([Course].self, forKey: .courses)
        progress = try container.decode(StudentProgress.self, forKey: .progress)
        records = try container.decode([CheckInRecord].self, forKey: .records)
        grades = try container.decode(GradeRow.self, forKey: .grades)
        memberships = try container.decode([Membership].self, forKey: .memberships)
        notices = try container.decode([StudentNotice].self, forKey: .notices)
        exemptions = try container.decodeIfPresent([ExemptionApplication].self, forKey: .exemptions) ?? []
        syncOperations = try container.decodeIfPresent([SyncOperation].self, forKey: .syncOperations) ?? []
    }
}

enum SyncOperationType: String, CaseIterable, Identifiable, Hashable, Codable {
    case submitRecord = "提交打卡"
    case submitExemption = "提交免测申请"
    case supplementExemption = "补充免测材料"
    case markNoticeRead = "通知已读"
    case resetLocalData = "重置数据"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .submitRecord:
            return "paperplane.fill"
        case .submitExemption:
            return "cross.case.fill"
        case .supplementExemption:
            return "doc.badge.plus"
        case .markNoticeRead:
            return "checkmark.circle"
        case .resetLocalData:
            return "arrow.counterclockwise"
        }
    }
}

enum SyncOperationStatus: String, CaseIterable, Identifiable, Hashable, Codable {
    case queued = "待同步"
    case localOnly = "本地完成"
    case synced = "已同步"

    var id: String { rawValue }
}

struct SyncOperation: Identifiable, Hashable, Codable {
    let id: String
    let type: SyncOperationType
    let title: String
    let detail: String
    let createdAt: String
    var status: SyncOperationStatus
}

struct Course: Identifiable, Hashable, Codable {
    let id: String
    let code: String
    let section: String
    let name: String
    let semester: String
    let students: Int
    let pending: Int
    let completion: Int
    let missing: Int
    var deadline: String
    var teacher: String
    let isCurrent: Bool

    init(
        id: String,
        code: String,
        section: String,
        name: String,
        semester: String,
        students: Int,
        pending: Int,
        completion: Int,
        missing: Int,
        deadline: String,
        teacher: String,
        isCurrent: Bool = true
    ) {
        self.id = id
        self.code = code
        self.section = section
        self.name = name
        self.semester = semester
        self.students = students
        self.pending = pending
        self.completion = completion
        self.missing = missing
        self.deadline = deadline
        self.teacher = teacher
        self.isCurrent = isCurrent
    }

    enum CodingKeys: String, CodingKey {
        case id
        case courseId
        case code
        case courseCode
        case section
        case name
        case courseName
        case semester
        case students
        case studentCount
        case pending
        case pendingCount
        case completion
        case missing
        case missingCount
        case deadline
        case teacher
        case teacherName
        case isCurrent
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedCode = try container.decodeIfPresent(String.self, forKey: .code)
            ?? container.decodeIfPresent(String.self, forKey: .courseCode)
            ?? "GEPE101"
        let decodedSection = try container.decodeIfPresent(String.self, forKey: .section) ?? "0000"
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .courseId)
            ?? "\(decodedCode)-\(decodedSection)"
        code = decodedCode
        section = decodedSection
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .courseName)
            ?? "体育课程"
        semester = try container.decodeIfPresent(String.self, forKey: .semester) ?? "当前学期"
        students = try container.decodeIfPresent(Int.self, forKey: .students)
            ?? container.decodeIfPresent(Int.self, forKey: .studentCount)
            ?? 0
        pending = try container.decodeIfPresent(Int.self, forKey: .pending)
            ?? container.decodeIfPresent(Int.self, forKey: .pendingCount)
            ?? 0
        completion = try container.decodeIfPresent(Int.self, forKey: .completion) ?? 0
        missing = try container.decodeIfPresent(Int.self, forKey: .missing)
            ?? container.decodeIfPresent(Int.self, forKey: .missingCount)
            ?? 0
        deadline = try container.decodeIfPresent(String.self, forKey: .deadline) ?? ""
        if let teacherName = try? container.decode(String.self, forKey: .teacher) {
            teacher = teacherName
        } else {
            teacher = (try? container.decode(UserBrief.self, forKey: .teacher).name)
                ?? (try? container.decode(String.self, forKey: .teacherName))
                ?? ""
        }
        isCurrent = try container.decodeIfPresent(Bool.self, forKey: .isCurrent) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(code, forKey: .code)
        try container.encode(section, forKey: .section)
        try container.encode(name, forKey: .name)
        try container.encode(semester, forKey: .semester)
        try container.encode(students, forKey: .students)
        try container.encode(pending, forKey: .pending)
        try container.encode(completion, forKey: .completion)
        try container.encode(missing, forKey: .missing)
        try container.encode(deadline, forKey: .deadline)
        try container.encode(teacher, forKey: .teacher)
        try container.encode(isCurrent, forKey: .isCurrent)
    }

    var displayTitle: String {
        "\(code) / Section \(section)"
    }
}

struct StudentProgress: Identifiable, Hashable, Codable {
    let id: String
    let name: String
    let college: String
    let className: String
    var course: Double
    var general: Double
    var rawGeneral: Double
    let exam: Int
    let attendance: Int
    let physical: Int
    var status: String
    let source: String
    var organizationCredit: Membership?

    init(
        id: String,
        name: String,
        college: String,
        className: String,
        course: Double,
        general: Double,
        rawGeneral: Double,
        exam: Int,
        attendance: Int,
        physical: Int,
        status: String,
        source: String,
        organizationCredit: Membership?
    ) {
        self.id = id
        self.name = name
        self.college = college
        self.className = className
        self.course = course
        self.general = general
        self.rawGeneral = rawGeneral
        self.exam = exam
        self.attendance = attendance
        self.physical = physical
        self.status = status
        self.source = source
        self.organizationCredit = organizationCredit
    }

    enum CodingKeys: String, CodingKey {
        case id
        case studentId
        case name
        case studentName
        case college
        case className
        case course
        case courseHours
        case courseCompleted
        case general
        case generalHours
        case otherHours
        case rawGeneral
        case rawGeneralHours
        case exam
        case examScore
        case attendance
        case attendanceScore
        case physical
        case physicalScore
        case status
        case source
        case organizationCredit
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .studentId)
            ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name)
            ?? container.decodeIfPresent(String.self, forKey: .studentName)
            ?? "BNBU Student"
        college = try container.decodeIfPresent(String.self, forKey: .college) ?? "BNBU"
        className = try container.decodeIfPresent(String.self, forKey: .className) ?? ""
        course = try container.decodeIfPresent(Double.self, forKey: .course)
            ?? container.decodeIfPresent(Double.self, forKey: .courseHours)
            ?? container.decodeIfPresent(Double.self, forKey: .courseCompleted)
            ?? 0
        general = try container.decodeIfPresent(Double.self, forKey: .general)
            ?? container.decodeIfPresent(Double.self, forKey: .generalHours)
            ?? container.decodeIfPresent(Double.self, forKey: .otherHours)
            ?? 0
        rawGeneral = try container.decodeIfPresent(Double.self, forKey: .rawGeneral)
            ?? container.decodeIfPresent(Double.self, forKey: .rawGeneralHours)
            ?? general
        exam = try container.decodeIfPresent(Int.self, forKey: .exam)
            ?? container.decodeIfPresent(Int.self, forKey: .examScore)
            ?? 0
        attendance = try container.decodeIfPresent(Int.self, forKey: .attendance)
            ?? container.decodeIfPresent(Int.self, forKey: .attendanceScore)
            ?? 0
        physical = try container.decodeIfPresent(Int.self, forKey: .physical)
            ?? container.decodeIfPresent(Int.self, forKey: .physicalScore)
            ?? 0
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "暂无风险"
        source = try container.decodeIfPresent(String.self, forKey: .source) ?? "server"
        organizationCredit = try container.decodeIfPresent(Membership.self, forKey: .organizationCredit)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(college, forKey: .college)
        try container.encode(className, forKey: .className)
        try container.encode(course, forKey: .course)
        try container.encode(general, forKey: .general)
        try container.encode(rawGeneral, forKey: .rawGeneral)
        try container.encode(exam, forKey: .exam)
        try container.encode(attendance, forKey: .attendance)
        try container.encode(physical, forKey: .physical)
        try container.encode(status, forKey: .status)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(organizationCredit, forKey: .organizationCredit)
    }
}

enum CreditType: String, CaseIterable, Identifiable, Hashable, Codable {
    case courseRelated = "课程相关"
    case general = "其他运动"
    case organizationOffset = "系统抵扣"

    var id: String { rawValue }

    var apiValue: String {
        switch self {
        case .courseRelated:
            return "course"
        case .general:
            return "general"
        case .organizationOffset:
            return "organization"
        }
    }

    var symbolName: String {
        switch self {
        case .courseRelated: return "book.closed"
        case .general: return "figure.run"
        case .organizationOffset: return "checkmark.seal"
        }
    }

    init?(contractValue value: String) {
        switch value {
        case "courseRelated", "course_related", "COURSE_RELATED", "course", "COURSE", "课程相关", "A类", "A 类":
            self = .courseRelated
        case "general", "GENERAL", "other", "OTHER", "other_sport", "其他运动", "B类", "B 类":
            self = .general
        case "organizationOffset", "organization_offset", "ORGANIZATION_OFFSET", "系统抵扣":
            self = .organizationOffset
        default:
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        self = CreditType(contractValue: value) ?? .general
    }
}

/// New business model: a submitted record is immediately valid. Teachers can
/// only mark a record invalid afterwards; there is no pending-review,
/// rejected-resubmit or supplement-material state anymore.
enum RecordValidity: String, CaseIterable, Identifiable, Hashable, Codable {
    case valid = "有效"
    case invalid = "无效"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "invalid", "INVALID", "无效", "rejected", "REJECTED", "被驳回", "已驳回":
            self = .invalid
        default:
            // Legacy pending/approved/supplement/offset states and any unknown
            // value all map to valid; only an explicit server invalidation
            // downgrades a record.
            self = .valid
        }
    }
}

struct CheckInRecord: Identifiable, Hashable, Codable {
    let id: String
    let courseId: String?
    let taskTitle: String
    let creditType: CreditType
    var hours: Double
    var submittedAt: String
    var validity: RecordValidity
    var invalidReason: String?
    var proofSummary: String
    var proofPhotoCount: Int
    var proofVideoCount: Int
    var proofFiles: [ProofAttachment]
    var note: String
    var sportType: String?

    var representsCompleteServerRecord: Bool {
        hours == 1 || hours == 2
    }

    init(
        id: String,
        courseId: String?,
        taskTitle: String,
        creditType: CreditType,
        hours: Double,
        submittedAt: String,
        validity: RecordValidity = .valid,
        invalidReason: String? = nil,
        proofSummary: String,
        proofPhotoCount: Int,
        proofVideoCount: Int,
        proofFiles: [ProofAttachment],
        note: String,
        sportType: String? = nil
    ) {
        self.id = id
        self.courseId = courseId
        self.taskTitle = taskTitle
        self.creditType = creditType
        self.hours = hours
        self.submittedAt = submittedAt
        self.validity = validity
        self.invalidReason = invalidReason
        self.proofSummary = proofSummary
        self.proofPhotoCount = proofPhotoCount
        self.proofVideoCount = proofVideoCount
        self.proofFiles = proofFiles
        self.note = note
        self.sportType = sportType
    }

    enum CodingKeys: String, CodingKey {
        case id
        case recordId
        case courseId
        case taskTitle
        case title
        case sportType
        case creditType
        case type
        case hours
        case submittedAt
        case createdAt
        case updatedAt
        case validity
        case status
        case reviewStatus
        case invalidReason
        case teacherFeedback
        case feedback
        case comment
        case reviewComment
        case proofSummary
        case proofPhotoCount
        case proofVideoCount
        case proofFiles
        case note
        case description
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .recordId)
            ?? UUID().uuidString
        courseId = try container.decodeIfPresent(String.self, forKey: .courseId)
        taskTitle = try container.decodeIfPresent(String.self, forKey: .taskTitle)
            ?? container.decodeIfPresent(String.self, forKey: .title)
            ?? container.decodeIfPresent(String.self, forKey: .sportType)
            ?? container.decodeIfPresent(String.self, forKey: .description)
            ?? "体育打卡"
        creditType = try container.decodeIfPresent(CreditType.self, forKey: .creditType)
            ?? container.decodeIfPresent(CreditType.self, forKey: .type)
            ?? .general
        hours = CheckInRecord.decodeDouble(from: container, forKey: .hours) ?? 0
        submittedAt = try container.decodeIfPresent(String.self, forKey: .submittedAt)
            ?? container.decodeIfPresent(String.self, forKey: .createdAt)
            ?? container.decodeIfPresent(String.self, forKey: .updatedAt)
            ?? ""
        // Legacy caches / older servers may still send review states under
        // `status`; RecordValidity's decoder maps them onto valid/invalid.
        validity = try container.decodeIfPresent(RecordValidity.self, forKey: .validity)
            ?? container.decodeIfPresent(RecordValidity.self, forKey: .status)
            ?? container.decodeIfPresent(RecordValidity.self, forKey: .reviewStatus)
            ?? .valid
        var decodedInvalidReason = try container.decodeIfPresent(String.self, forKey: .invalidReason)
        if decodedInvalidReason == nil {
            decodedInvalidReason = try container.decodeIfPresent(String.self, forKey: .teacherFeedback)
        }
        if decodedInvalidReason == nil {
            decodedInvalidReason = try container.decodeIfPresent(String.self, forKey: .feedback)
        }
        if decodedInvalidReason == nil {
            decodedInvalidReason = try container.decodeIfPresent(String.self, forKey: .comment)
        }
        if decodedInvalidReason == nil {
            decodedInvalidReason = try container.decodeIfPresent(String.self, forKey: .reviewComment)
        }
        proofFiles = (try? container.decodeIfPresent([ProofAttachment].self, forKey: .proofFiles))
            ?? proofAttachments(from: ((try? container.decodeIfPresent([String].self, forKey: .proofFiles)) ?? []))
        proofSummary = try container.decodeIfPresent(String.self, forKey: .proofSummary)
            ?? CheckInRecord.proofSummary(for: proofFiles)
        proofPhotoCount = try container.decodeIfPresent(Int.self, forKey: .proofPhotoCount) ?? proofFiles.filter { $0.type == .image }.count
        proofVideoCount = try container.decodeIfPresent(Int.self, forKey: .proofVideoCount) ?? proofFiles.filter { $0.type == .video }.count
        note = try container.decodeIfPresent(String.self, forKey: .note)
            ?? container.decodeIfPresent(String.self, forKey: .description)
            ?? ""
        sportType = try container.decodeIfPresent(String.self, forKey: .sportType)
        invalidReason = decodedInvalidReason?.isEmpty == false ? decodedInvalidReason : nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(courseId, forKey: .courseId)
        try container.encode(taskTitle, forKey: .taskTitle)
        try container.encode(creditType, forKey: .creditType)
        try container.encode(hours, forKey: .hours)
        try container.encode(submittedAt, forKey: .submittedAt)
        try container.encode(validity, forKey: .validity)
        try container.encodeIfPresent(invalidReason, forKey: .invalidReason)
        try container.encode(proofSummary, forKey: .proofSummary)
        try container.encode(proofPhotoCount, forKey: .proofPhotoCount)
        try container.encode(proofVideoCount, forKey: .proofVideoCount)
        try container.encode(proofFiles, forKey: .proofFiles)
        try container.encode(note, forKey: .note)
        try container.encodeIfPresent(sportType, forKey: .sportType)
    }

    private static func proofSummary(for proofFiles: [ProofAttachment]) -> String {
        guard !proofFiles.isEmpty else { return "未添加凭证" }
        let photoCount = proofFiles.filter { $0.type == .image }.count
        let videoCount = proofFiles.filter { $0.type == .video }.count
        var parts: [String] = []
        if photoCount > 0 {
            parts.append("\(photoCount) 张图片")
        }
        if videoCount > 0 {
            parts.append("\(videoCount) 个视频")
        }
        return parts.joined(separator: "，")
    }

    private static func decodeDouble(from container: KeyedDecodingContainer<CodingKeys>, forKey key: CodingKeys) -> Double? {
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        if let value = try? container.decodeIfPresent(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }
}

enum ProofMediaType: String, CaseIterable, Identifiable, Hashable, Codable {
    case image = "图片"
    case video = "视频"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "image", "IMAGE", "图片":
            self = .image
        case "video", "VIDEO", "视频":
            self = .video
        default:
            self = .image
        }
    }
}

enum ProofUploadRule {
    static let maxImageCount = 6
    static let maxVideoCount = 1
    static let maxAttachmentCount = maxImageCount + maxVideoCount
    static let maxImageBytes = 8_000_000
    static let maxVideoBytes = 100_000_000
    static let maxRequestBytes = 120_000_000

    static var summaryText: String {
        "最多 \(maxImageCount) 张照片 + \(maxVideoCount) 个视频；图片不超过 8MB，视频不超过 100MB。"
    }

    static func accepts(_ attachments: [ProofAttachment]) -> Bool {
        acceptsAttachmentCounts(attachments) &&
            totalByteCount(in: attachments) <= maxRequestBytes
    }

    static func acceptsAttachmentCounts(_ attachments: [ProofAttachment]) -> Bool {
        attachments.count <= maxAttachmentCount &&
            imageCount(in: attachments) <= maxImageCount &&
            videoCount(in: attachments) <= maxVideoCount
    }

    static func validationMessage(for attachments: [ProofAttachment]) -> String? {
        if imageCount(in: attachments) > maxImageCount {
            return "最多只能添加 \(maxImageCount) 张图片。"
        }
        if videoCount(in: attachments) > maxVideoCount {
            return "最多只能添加 \(maxVideoCount) 个视频。"
        }
        if attachments.count > maxAttachmentCount {
            return "最多只能添加 \(maxAttachmentCount) 个凭证。"
        }
        if totalByteCount(in: attachments) > maxRequestBytes {
            return "全部凭证总大小不能超过 120MB。"
        }
        return nil
    }

    static func imageCount(in attachments: [ProofAttachment]) -> Int {
        attachments.filter { $0.type == .image }.count
    }

    static func videoCount(in attachments: [ProofAttachment]) -> Int {
        attachments.filter { $0.type == .video }.count
    }

    static func totalByteCount(in attachments: [ProofAttachment]) -> Int {
        attachments.reduce(0) { partialResult, attachment in
            partialResult + max(attachment.byteCount ?? 0, 0)
        }
    }
}

enum ExemptionProofRule {
    static let maxAttachmentCount = 5

    static var summaryText: String {
        "免测证明最多 \(maxAttachmentCount) 个；图片不超过 8MB，视频不超过 100MB。"
    }

    static func accepts(_ attachments: [ProofAttachment]) -> Bool {
        !attachments.isEmpty &&
            attachments.count <= maxAttachmentCount &&
            ProofUploadRule.accepts(attachments)
    }

    static func validationMessage(for attachments: [ProofAttachment]) -> String? {
        if attachments.count > maxAttachmentCount {
            return "免测申请最多只能添加 \(maxAttachmentCount) 个证明材料。"
        }
        return ProofUploadRule.validationMessage(for: attachments)
    }
}

enum CheckInInputRule {
    /// Q&A 7/23 (Q5): the sport note is required for both course-related and
    /// general exercise. The 200-character cap stays until the final field
    /// spec is published with the OpenAPI document.
    static let maximumDescriptionLength = 200

    static func normalizedDescription(_ note: String, for category: ExerciseCategory) -> String {
        _ = category
        return note.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func validationMessage(note: String) -> String? {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return "请填写运动说明。"
        }
        if trimmed.count > maximumDescriptionLength {
            return "运动说明不能超过 \(maximumDescriptionLength) 个字符。"
        }
        return nil
    }
}

enum CheckInSubmissionPhase: Equatable {
    case idle
    case uploading(fileName: String, completedFiles: Int, totalFiles: Int, fileProgress: Double)
    case submitting
    case syncing

    var isActive: Bool {
        self != .idle
    }

    var overallProgress: Double? {
        switch self {
        case .idle:
            return nil
        case .uploading(_, let completedFiles, let totalFiles, let fileProgress):
            guard totalFiles > 0 else { return 0 }
            let clampedFileProgress = min(max(fileProgress, 0), 1)
            return min((Double(completedFiles) + clampedFileProgress) / Double(totalFiles), 1)
        case .submitting, .syncing:
            return 1
        }
    }

    var canRetryWithoutDuplicateRisk: Bool {
        if case .uploading = self {
            return true
        }
        return false
    }
}

enum ProofContentDigest {
    /// The largest buffer held while hashing a file-backed proof. A 100 MB
    /// video therefore never has to be materialized as one `Data` value just
    /// to establish mutation identity.
    static let streamingChunkBytes = 1_048_576

    static func sha256(data: Data) -> String {
        SHA256.hash(data: data).hexString
    }

    static func sha256(
        fileURL: URL,
        chunkSize: Int = streamingChunkBytes,
        onChunkRead: ((Int) -> Void)? = nil
    ) throws -> String {
        guard fileURL.isFileURL else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        guard chunkSize > 0 else {
            throw CocoaError(.fileReadInvalidFileName)
        }

        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: chunkSize) ?? Data()
            guard !chunk.isEmpty else { break }
            onChunkRead?(chunk.count)
            hasher.update(data: chunk)
        }
        return hasher.finalize().hexString
    }
}

/// App-owned temporary source files are protected at rest and are deliberately
/// never encoded into drafts or the pending-mutation journal.
enum ProofTransientFileStore {
    static let directoryName = "bnbu-proof-sources"

    static func makeProtectedCopy(from sourceURL: URL) throws -> URL {
        guard sourceURL.isFileURL else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: directoryURL.path
        )

        let suffix = sourceURL.pathExtension.isEmpty ? "bin" : sourceURL.pathExtension
        let destinationURL = directoryURL
            .appendingPathComponent("proof-\(UUID().uuidString).\(suffix)")
        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: destinationURL.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = destinationURL
            try mutableURL.setResourceValues(values)
            return destinationURL
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            throw error
        }
    }

    static func removeManagedCopy(at fileURL: URL?) {
        guard let fileURL, isManagedCopy(fileURL) else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }

    static func removeStaleCopies(fileManager: FileManager = .default) {
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
        try? fileManager.removeItem(at: directoryURL)
    }

    private static func isManagedCopy(_ fileURL: URL) -> Bool {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(directoryName, isDirectory: true)
            .standardizedFileURL
        let candidate = fileURL.standardizedFileURL
        return candidate.deletingLastPathComponent() == directoryURL
    }
}

struct ProofAttachment: Identifiable, Hashable, Codable {
    let id: String
    let type: ProofMediaType
    let fileName: String
    let byteCount: Int?
    var durationSeconds: Double? = nil
    var thumbnailData: Data? = nil
    var uploadData: Data? = nil
    /// A transient app-owned file used for large uploads and streaming SHA-256.
    /// It is intentionally absent from `CodingKeys`, so persistence never
    /// captures a local URL or the original bytes.
    var sourceFileURL: URL? = nil
    let source: String
    let cosKey: String?
    let mimeType: String?
    let contentDigest: String?

    init(
        id: String,
        type: ProofMediaType,
        fileName: String,
        byteCount: Int?,
        durationSeconds: Double? = nil,
        thumbnailData: Data? = nil,
        uploadData: Data? = nil,
        sourceFileURL: URL? = nil,
        source: String,
        cosKey: String? = nil,
        mimeType: String? = nil,
        contentDigest: String? = nil
    ) {
        self.id = id
        self.type = type
        self.fileName = fileName
        self.byteCount = byteCount
        self.durationSeconds = durationSeconds
        self.thumbnailData = thumbnailData
        self.uploadData = uploadData
        self.sourceFileURL = sourceFileURL
        self.source = source
        self.cosKey = cosKey
        self.mimeType = mimeType
        self.contentDigest = contentDigest
            ?? uploadData.map(ProofContentDigest.sha256)
            ?? sourceFileURL.flatMap { try? ProofContentDigest.sha256(fileURL: $0) }
    }

    enum CodingKeys: String, CodingKey {
        case id
        case fileId
        case type
        case mediaType
        case fileName
        case name
        case url
        case path
        case byteCount
        case size
        case durationSeconds
        case thumbnailData
        case source
        case storagePath
        case cosKey
        case mimeType
        case contentDigest
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedCosKey = try container.decodeIfPresent(String.self, forKey: .cosKey)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .fileId)
            ?? decodedCosKey
            ?? UUID().uuidString
        type = try container.decodeIfPresent(ProofMediaType.self, forKey: .type)
            ?? container.decodeIfPresent(ProofMediaType.self, forKey: .mediaType)
            ?? .image
        let remotePath = try container.decodeIfPresent(String.self, forKey: .source)
            ?? container.decodeIfPresent(String.self, forKey: .storagePath)
            ?? container.decodeIfPresent(String.self, forKey: .url)
            ?? container.decodeIfPresent(String.self, forKey: .path)
        fileName = try container.decodeIfPresent(String.self, forKey: .fileName)
            ?? container.decodeIfPresent(String.self, forKey: .name)
            ?? remotePath?.split(separator: "/").last.map(String.init)
            ?? "proof-file"
        byteCount = try container.decodeIfPresent(Int.self, forKey: .byteCount)
            ?? container.decodeIfPresent(Int.self, forKey: .size)
        durationSeconds = try container.decodeIfPresent(Double.self, forKey: .durationSeconds)
        thumbnailData = try container.decodeIfPresent(Data.self, forKey: .thumbnailData)
        uploadData = nil
        sourceFileURL = nil
        source = remotePath ?? "服务器"
        cosKey = decodedCosKey
        mimeType = try container.decodeIfPresent(String.self, forKey: .mimeType)
        contentDigest = try container.decodeIfPresent(String.self, forKey: .contentDigest)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(fileName, forKey: .fileName)
        try container.encodeIfPresent(byteCount, forKey: .byteCount)
        try container.encodeIfPresent(durationSeconds, forKey: .durationSeconds)
        try container.encodeIfPresent(thumbnailData, forKey: .thumbnailData)
        try container.encode(source, forKey: .source)
        try container.encodeIfPresent(cosKey, forKey: .cosKey)
        try container.encodeIfPresent(mimeType, forKey: .mimeType)
        try container.encodeIfPresent(contentDigest, forKey: .contentDigest)
    }

    var displaySize: String {
        guard let byteCount else { return "本地占位" }
        if byteCount >= 1_000_000 {
            return String(format: "%.1f MB", Double(byteCount) / 1_000_000)
        }
        return "\(max(byteCount / 1_000, 1)) KB"
    }

    var displayDuration: String? {
        guard let durationSeconds else { return nil }
        let totalSeconds = max(Int(durationSeconds.rounded()), 0)
        if totalSeconds >= 60 {
            return "\(totalSeconds / 60)分\(totalSeconds % 60)秒"
        }
        return "\(totalSeconds)秒"
    }

    var validationMessage: String? {
        if needsOriginalFileReselection {
            return "原始文件已不在内存中，请删除后重新选择"
        }
        if let byteCount {
            switch type {
            case .image where byteCount > ProofUploadRule.maxImageBytes:
                return "图片超过 8MB"
            case .video where byteCount > ProofUploadRule.maxVideoBytes:
                return "视频超过 100MB"
            default:
                break
            }
        }

        return nil
    }

    var isValidForUpload: Bool {
        validationMessage == nil
    }

    private var needsOriginalFileReselection: Bool {
        let isLocalSelection = source == "相册" || source == "摄像头" || source == "拍摄占位"
        return isLocalSelection && uploadData == nil && sourceFileURL == nil && cosKey == nil
    }
}

private func proofAttachments(from sources: [String]) -> [ProofAttachment] {
    sources.enumerated().map { index, source in
        let fileName = source.split(separator: "/").last.map(String.init) ?? "proof-\(index + 1)"
        let lowercased = fileName.lowercased()
        let mediaType: ProofMediaType = lowercased.hasSuffix(".mov") ||
            lowercased.hasSuffix(".mp4") ||
            lowercased.hasSuffix(".m4v") ? .video : .image
        return ProofAttachment(
            id: "\(source)-\(index)",
            type: mediaType,
            fileName: fileName,
            byteCount: nil,
            source: source
        )
    }
}

enum IdempotencyKeyPolicy {
    private static let allowedCharacters = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:-")

    static func make() -> String {
        "ios-\(UUID().uuidString.lowercased())"
    }

    static func isValid(_ value: String) -> Bool {
        let scalars = value.unicodeScalars
        return (8...128).contains(scalars.count) && scalars.allSatisfy(allowedCharacters.contains)
    }
}

enum RemoteMutationFingerprint {
    static func make(
        scope: String,
        fields: [String: String],
        attachments: [ProofAttachment]
    ) -> String {
        var input = Data()
        append(scope, to: &input)
        for key in fields.keys.sorted() {
            append(key, to: &input)
            append(fields[key] ?? "", to: &input)
        }
        // Attachment identity is intentionally order + content only. Renames,
        // media metadata changes, local/remote source transitions and COS refs
        // must not rotate the idempotency key for the same logical bytes.
        for (position, attachment) in attachments.enumerated() {
            append(String(position), to: &input)
            append(attachment.contentDigest ?? "", to: &input)
        }
        return SHA256.hash(data: input).hexString
    }

    private static func append(_ value: String, to data: inout Data) {
        let bytes = Data(value.utf8)
        data.append(Data("\(bytes.count):".utf8))
        data.append(bytes)
    }
}

enum PendingRemoteMutationPhase: String, Hashable, Codable {
    case uploading
    case finalMutationPrepared
    case serverConfirmed
}

struct PendingRemoteMutationAttempt: Hashable, Codable {
    let scope: String
    let fingerprint: String
    let idempotencyKey: String
    let serverIdentity: String
    let studentID: String
    /// Canonical values used to build the mutation body. Keeping these beside
    /// the key makes a restart recovery self-describing instead of depending on
    /// transient SwiftUI form state.
    let requestFields: [String: String]
    /// Stable attachment identity only. Its persisted representation excludes
    /// original bytes, thumbnails, local paths and remote signed URLs.
    let sourceProofs: [ProofAttachment]
    var uploadedProofs: [ProofAttachment]
    var phase: PendingRemoteMutationPhase
    var serverResultID: String?

    init(
        scope: String,
        fingerprint: String,
        idempotencyKey: String,
        serverIdentity: String,
        studentID: String,
        requestFields: [String: String] = [:],
        sourceProofs: [ProofAttachment] = [],
        uploadedProofs: [ProofAttachment],
        phase: PendingRemoteMutationPhase = .uploading,
        serverResultID: String? = nil
    ) {
        self.scope = scope
        self.fingerprint = fingerprint
        self.idempotencyKey = idempotencyKey
        self.serverIdentity = serverIdentity
        self.studentID = studentID
        self.requestFields = requestFields
        self.sourceProofs = sourceProofs
        self.uploadedProofs = uploadedProofs
        self.phase = phase
        self.serverResultID = serverResultID
    }

    static func create(
        scope: String,
        fingerprint: String,
        serverIdentity: String,
        studentID: String,
        requestFields: [String: String] = [:],
        sourceProofs: [ProofAttachment] = []
    ) -> PendingRemoteMutationAttempt {
        PendingRemoteMutationAttempt(
            scope: scope,
            fingerprint: fingerprint,
            idempotencyKey: IdempotencyKeyPolicy.make(),
            serverIdentity: serverIdentity,
            studentID: studentID,
            requestFields: requestFields,
            sourceProofs: sourceProofs,
            uploadedProofs: [],
            phase: .uploading,
            serverResultID: nil
        )
    }

    mutating func markFinalMutationPrepared() {
        phase = .finalMutationPrepared
        serverResultID = nil
    }

    mutating func markServerConfirmed(resultID: String?) {
        phase = .serverConfirmed
        let normalized = resultID?.trimmingCharacters(in: .whitespacesAndNewlines)
        serverResultID = normalized?.isEmpty == false ? normalized : nil
    }

    var isServerConfirmed: Bool {
        phase == .serverConfirmed
    }

    func matches(
        scope: String,
        fingerprint: String,
        serverIdentity: String,
        studentID: String
    ) -> Bool {
        self.scope == scope &&
            self.fingerprint == fingerprint &&
            self.serverIdentity == serverIdentity &&
            self.studentID == studentID &&
            IdempotencyKeyPolicy.isValid(idempotencyKey)
    }

    private enum CodingKeys: String, CodingKey {
        case scope
        case fingerprint
        case idempotencyKey
        case serverIdentity
        case studentID
        case requestFields
        case sourceProofs
        case uploadedProofs
        case phase
        case serverResultID
    }

    private struct PersistedSourceProof: Hashable, Codable {
        let id: String
        let type: ProofMediaType
        let fileName: String
        let byteCount: Int?
        let durationSeconds: Double?
        let sourceLabel: String
        let mimeType: String?
        let contentDigest: String?

        init(_ attachment: ProofAttachment) {
            id = attachment.id
            type = attachment.type
            fileName = attachment.fileName
            byteCount = attachment.byteCount
            durationSeconds = attachment.durationSeconds
            sourceLabel = Self.safeSourceLabel(attachment.source)
            mimeType = attachment.mimeType
            contentDigest = attachment.contentDigest
        }

        func attachment() -> ProofAttachment {
            ProofAttachment(
                id: id,
                type: type,
                fileName: fileName,
                byteCount: byteCount,
                durationSeconds: durationSeconds,
                thumbnailData: nil,
                uploadData: nil,
                source: sourceLabel,
                cosKey: nil,
                mimeType: mimeType,
                contentDigest: contentDigest
            )
        }

        private static func safeSourceLabel(_ source: String) -> String {
            let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty,
                  !trimmed.contains("://"),
                  !trimmed.hasPrefix("/"),
                  !trimmed.hasPrefix("\\\\") else {
                return "本地凭证"
            }
            return String(trimmed.prefix(64))
        }
    }

    /// Only the canonical COS reference is persisted for a completed upload.
    /// In particular, this representation excludes original bytes, thumbnails
    /// and short-lived signed URLs from the restart-recovery journal.
    private struct PersistedUploadedProof: Hashable, Codable {
        let type: ProofMediaType
        let fileName: String
        let byteCount: Int?
        let durationSeconds: Double?
        let cosKey: String?
        let mimeType: String?
        let contentDigest: String?

        init(_ attachment: ProofAttachment) {
            type = attachment.type
            fileName = attachment.fileName
            byteCount = attachment.byteCount
            durationSeconds = attachment.durationSeconds
            cosKey = attachment.cosKey
            mimeType = attachment.mimeType
            contentDigest = attachment.contentDigest
        }

        func attachment(at index: Int) -> ProofAttachment {
            let stableReference = cosKey ?? "persisted-upload-\(index)"
            return ProofAttachment(
                id: stableReference,
                type: type,
                fileName: fileName,
                byteCount: byteCount,
                durationSeconds: durationSeconds,
                thumbnailData: nil,
                uploadData: nil,
                source: cosKey ?? "",
                cosKey: cosKey,
                mimeType: mimeType,
                contentDigest: contentDigest
            )
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        scope = try container.decode(String.self, forKey: .scope)
        fingerprint = try container.decode(String.self, forKey: .fingerprint)
        idempotencyKey = try container.decode(String.self, forKey: .idempotencyKey)
        serverIdentity = try container.decode(String.self, forKey: .serverIdentity)
        studentID = try container.decode(String.self, forKey: .studentID)
        requestFields = try container.decodeIfPresent(
            [String: String].self,
            forKey: .requestFields
        ) ?? [:]
        let sourceReferences = try container.decodeIfPresent(
            [PersistedSourceProof].self,
            forKey: .sourceProofs
        ) ?? []
        sourceProofs = sourceReferences.map { $0.attachment() }
        let references = try container.decodeIfPresent(
            [PersistedUploadedProof].self,
            forKey: .uploadedProofs
        ) ?? []
        uploadedProofs = references.enumerated().map { index, reference in
            reference.attachment(at: index)
        }
        phase = try container.decodeIfPresent(PendingRemoteMutationPhase.self, forKey: .phase) ?? .uploading
        serverResultID = try container.decodeIfPresent(String.self, forKey: .serverResultID)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(scope, forKey: .scope)
        try container.encode(fingerprint, forKey: .fingerprint)
        try container.encode(idempotencyKey, forKey: .idempotencyKey)
        try container.encode(serverIdentity, forKey: .serverIdentity)
        try container.encode(studentID, forKey: .studentID)
        try container.encode(requestFields, forKey: .requestFields)
        try container.encode(sourceProofs.map(PersistedSourceProof.init), forKey: .sourceProofs)
        try container.encode(uploadedProofs.map(PersistedUploadedProof.init), forKey: .uploadedProofs)
        try container.encode(phase, forKey: .phase)
        try container.encodeIfPresent(serverResultID, forKey: .serverResultID)
    }
}

struct PendingRemoteMutationSummary: Identifiable, Hashable {
    let scope: String
    let title: String
    let target: String?
    let uploadedProofCount: Int
    let isServerConfirmed: Bool

    var id: String { scope }

    init(attempt: PendingRemoteMutationAttempt) {
        scope = attempt.scope
        uploadedProofCount = attempt.uploadedProofs.count
        isServerConfirmed = attempt.isServerConfirmed
        if attempt.scope == "sport-record:create" {
            title = attempt.isServerConfirmed ? "打卡记录已提交，待本地清理" : "打卡记录待重试"
            target = attempt.requestFields["taskTitle"]
        } else if attempt.scope == "exemption:create:physical-test" {
            title = attempt.isServerConfirmed ? "免测申请已提交，待本地清理" : "免测申请待重试"
            target = attempt.requestFields["type"]
        } else if attempt.scope.hasPrefix("exemption:supplement:") {
            title = attempt.isServerConfirmed ? "免测补充材料已提交，待本地清理" : "免测补充材料待重试"
            target = attempt.requestFields["exemptionId"]
        } else {
            title = "未完成操作"
            target = nil
        }
    }
}

struct PendingExemptionFormRecovery: Hashable {
    let scope: String
    let item: ExemptionItem
    let reason: String
    let detail: String
    let sourceProofs: [ProofAttachment]
    let uploadedProofCount: Int

    var isReadyToRetryWithoutOriginalBytes: Bool {
        !sourceProofs.isEmpty && uploadedProofCount == sourceProofs.count
    }
}

private extension Digest {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

/// A validated, ready-to-send check-in under the new exercise-session model.
struct CheckInSubmission: Hashable {
    let creditType: CreditType
    let courseId: String?
    let hours: Double

    var title: String {
        creditType == .courseRelated ? "课程相关运动打卡" : "自主运动打卡"
    }
}

struct CheckInDraft: Identifiable, Hashable, Codable {
    let id: String
    /// The credit bucket this draft belongs to. Replaces the legacy `taskId`;
    /// old persisted drafts fail decode and are cleared by the store-health path.
    var creditType: CreditType
    var courseId: String?
    var hours: Double
    var note: String
    var proofAttachments: [ProofAttachment]
    var updatedAt: String
    var sportType: String? = nil
    var customSportType: String? = nil
    var pendingRemoteMutation: PendingRemoteMutationAttempt? = nil
}

enum ExemptionItem: String, CaseIterable, Identifiable, Hashable, Codable {
    case run800m = "800 米耐力跑免测"
    case run1000m = "1000 米耐力跑免测"
    case enduranceRun = "800/1000 米耐力跑"
    case physicalTest = "体测免测"
    case singlePhysicalItem = "体测单项免测"

    static var allCases: [ExemptionItem] {
        [.run800m, .run1000m]
    }

    var id: String { rawValue }

    var apiValue: String {
        switch self {
        case .run800m, .enduranceRun:
            return "800m"
        case .run1000m:
            return "1000m"
        case .physicalTest:
            return "physical_test"
        case .singlePhysicalItem:
            return "single_physical_item"
        }
    }

    var symbolName: String {
        switch self {
        case .run800m, .run1000m, .enduranceRun:
            return "figure.run"
        case .physicalTest:
            return "heart.text.square"
        case .singlePhysicalItem:
            return "list.clipboard"
        }
    }

    var proofHint: String {
        switch self {
        case .run800m:
            return "建议上传医院证明或校医室证明，说明不适合参加 800 米耐力跑测试。"
        case .run1000m:
            return "建议上传医院证明或校医室证明，说明不适合参加 1000 米耐力跑测试。"
        case .enduranceRun:
            return "建议上传医院证明或校医室证明，说明不适合参加耐力跑测试。"
        case .physicalTest:
            return "建议上传医院证明，说明本学期体测整体免测原因。"
        case .singlePhysicalItem:
            return "请在说明中写明申请免测的具体项目，并上传证明。"
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "800m", "800M", "800 米耐力跑免测", "800米耐力跑免测", "800 米", "800米":
            self = .run800m
        case "1000m", "1000M", "1000 米耐力跑免测", "1000米耐力跑免测", "1000 米", "1000米":
            self = .run1000m
        case "enduranceRun", "endurance_run", "ENDURANCE_RUN", "800/1000 米耐力跑", "800/1000米耐力跑", "耐力跑免测":
            self = .enduranceRun
        case "physicalTest", "physical_test", "PHYSICAL_TEST", "体测免测", "体测整体免测":
            self = .physicalTest
        case "singlePhysicalItem", "single_physical_item", "SINGLE_PHYSICAL_ITEM", "体测单项免测", "单项免测":
            self = .singlePhysicalItem
        default:
            self = .physicalTest
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

enum ExemptionInputRule {
    static let minimumReasonLength = 2
    static let maximumCombinedReasonLength = 2_000

    static func combinedReason(reason: String, detail: String) -> String {
        [reason, detail]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func validationMessage(reason: String, detail: String) -> String? {
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedDetail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalizedReason.count < minimumReasonLength {
            return "申请原因至少需要 2 个字符。"
        }
        if normalizedDetail.isEmpty {
            return "请填写情况说明。"
        }
        if combinedReason(reason: normalizedReason, detail: normalizedDetail).count > maximumCombinedReasonLength {
            return "申请原因和情况说明合计不能超过 2000 个字符。"
        }
        return nil
    }
}

enum ExemptionStatus: String, CaseIterable, Identifiable, Hashable, Codable {
    case pending = "待审核"
    case approved = "已通过"
    case rejected = "已驳回"
    case supplementRequired = "需补材料"
    case expired = "已过期"

    var id: String { rawValue }

    var apiValue: String {
        switch self {
        case .pending:
            return "pending"
        case .approved:
            return "approved"
        case .rejected:
            return "rejected"
        case .supplementRequired:
            return "supplement_required"
        case .expired:
            return "expired"
        }
    }

    var symbolName: String {
        switch self {
        case .pending:
            return "clock"
        case .approved:
            return "checkmark.seal"
        case .rejected:
            return "xmark.octagon"
        case .supplementRequired:
            return "arrow.up.doc"
        case .expired:
            return "calendar.badge.exclamationmark"
        }
    }

    var canSupplement: Bool {
        self == .rejected || self == .supplementRequired
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "pending", "PENDING", "reviewing", "REVIEWING", "待审核", "审核中":
            self = .pending
        case "approved", "APPROVED", "pass", "PASSED", "已通过", "通过":
            self = .approved
        case "rejected", "REJECTED", "reject", "FAILED", "被驳回", "已驳回", "驳回":
            self = .rejected
        case "supplement", "SUPPLEMENT", "needsSupplement", "needs_supplement", "NEEDS_SUPPLEMENT", "supplement_required", "SUPPLEMENT_REQUIRED", "补材料", "需补材料", "要求补充材料":
            self = .supplementRequired
        case "expired", "EXPIRED", "已过期":
            self = .expired
        default:
            self = .pending
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct ExemptionApplication: Identifiable, Hashable, Codable {
    let id: String
    let studentId: String
    var item: ExemptionItem
    var reason: String
    var detail: String
    var submittedAt: String
    var status: ExemptionStatus
    var proofFiles: [ProofAttachment]
    var teacherFeedback: String
    var reviewer: String?
    var updatedAt: String

    var representsCompleteServerApplication: Bool {
        !studentId.isEmpty
    }

    init(
        id: String,
        studentId: String,
        item: ExemptionItem,
        reason: String,
        detail: String,
        submittedAt: String,
        status: ExemptionStatus,
        proofFiles: [ProofAttachment],
        teacherFeedback: String,
        reviewer: String? = nil,
        updatedAt: String
    ) {
        self.id = id
        self.studentId = studentId
        self.item = item
        self.reason = reason
        self.detail = detail
        self.submittedAt = submittedAt
        self.status = status
        self.proofFiles = proofFiles
        self.teacherFeedback = teacherFeedback
        self.reviewer = reviewer
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case exemptionId
        case applicationId
        case studentId
        case item
        case exemptionItem
        case type
        case exemptionType
        case reason
        case detail
        case description
        case submittedAt
        case createdAt
        case status
        case reviewStatus
        case proofFiles
        case proofs
        case attachments
        case teacherFeedback
        case feedback
        case comment
        case reviewComment
        case reviewer
        case reviewedBy
        case reviewerName
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id)
            ?? container.decodeIfPresent(String.self, forKey: .exemptionId)
            ?? container.decodeIfPresent(String.self, forKey: .applicationId)
            ?? UUID().uuidString
        studentId = try container.decodeIfPresent(String.self, forKey: .studentId) ?? ""
        item = try container.decodeIfPresent(ExemptionItem.self, forKey: .item)
            ?? container.decodeIfPresent(ExemptionItem.self, forKey: .exemptionItem)
            ?? container.decodeIfPresent(ExemptionItem.self, forKey: .type)
            ?? container.decodeIfPresent(ExemptionItem.self, forKey: .exemptionType)
            ?? .physicalTest
        reason = try container.decodeIfPresent(String.self, forKey: .reason) ?? "未填写原因"
        detail = try container.decodeIfPresent(String.self, forKey: .detail)
            ?? container.decodeIfPresent(String.self, forKey: .description)
            ?? ""
        submittedAt = try container.decodeIfPresent(String.self, forKey: .submittedAt)
            ?? container.decodeIfPresent(String.self, forKey: .createdAt)
            ?? ""
        status = try container.decodeIfPresent(ExemptionStatus.self, forKey: .status)
            ?? container.decodeIfPresent(ExemptionStatus.self, forKey: .reviewStatus)
            ?? .pending
        proofFiles = Self.decodeProofFiles(from: container)
        teacherFeedback = try container.decodeIfPresent(String.self, forKey: .teacherFeedback)
            ?? container.decodeIfPresent(String.self, forKey: .feedback)
            ?? container.decodeIfPresent(String.self, forKey: .comment)
            ?? container.decodeIfPresent(String.self, forKey: .reviewComment)
            ?? "等待老师审核。"
        reviewer = try container.decodeIfPresent(String.self, forKey: .reviewer)
            ?? container.decodeIfPresent(String.self, forKey: .reviewedBy)
            ?? container.decodeIfPresent(String.self, forKey: .reviewerName)
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? submittedAt
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(studentId, forKey: .studentId)
        try container.encode(item, forKey: .item)
        try container.encode(reason, forKey: .reason)
        try container.encode(detail, forKey: .detail)
        try container.encode(submittedAt, forKey: .submittedAt)
        try container.encode(status, forKey: .status)
        try container.encode(proofFiles, forKey: .proofFiles)
        try container.encode(teacherFeedback, forKey: .teacherFeedback)
        try container.encodeIfPresent(reviewer, forKey: .reviewer)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var proofSummary: String {
        let photoCount = proofFiles.filter { $0.type == .image }.count
        let videoCount = proofFiles.filter { $0.type == .video }.count
        var parts: [String] = []
        if photoCount > 0 {
            parts.append("\(photoCount) 张图片")
        }
        if videoCount > 0 {
            parts.append("\(videoCount) 个视频")
        }
        return parts.isEmpty ? "未添加证明材料" : parts.joined(separator: "，")
    }

    private static func decodeProofFiles(from container: KeyedDecodingContainer<CodingKeys>) -> [ProofAttachment] {
        for key in [CodingKeys.proofFiles, .proofs, .attachments] {
            if let attachments = try? container.decodeIfPresent([ProofAttachment].self, forKey: key) {
                return attachments
            }
            if let sources = try? container.decodeIfPresent([String].self, forKey: key) {
                return proofAttachments(from: sources)
            }
        }
        return []
    }
}

struct Membership: Identifiable, Hashable, Codable {
    let id: String
    let type: String
    let organization: String
    let studentId: String
    let studentName: String
    let status: String
    let validUntil: String
    let offset: String
    let comment: String
    let updatedBy: String
    let updatedAt: String

    init(
        id: String,
        type: String,
        organization: String,
        studentId: String,
        studentName: String,
        status: String,
        validUntil: String,
        offset: String,
        comment: String,
        updatedBy: String,
        updatedAt: String
    ) {
        self.id = id
        self.type = type
        self.organization = organization
        self.studentId = studentId
        self.studentName = studentName
        self.status = status
        self.validUntil = validUntil
        self.offset = offset
        self.comment = comment
        self.updatedBy = updatedBy
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case organization
        case studentId
        case studentName
        case status
        case validUntil
        case offset
        case comment
        case updatedBy
        case updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        type = try container.decode(String.self, forKey: .type)
        organization = try container.decode(String.self, forKey: .organization)
        studentId = try container.decode(String.self, forKey: .studentId)
        studentName = try container.decodeIfPresent(String.self, forKey: .studentName) ?? ""
        status = try container.decode(String.self, forKey: .status)
        validUntil = try container.decodeIfPresent(String.self, forKey: .validUntil) ?? ""
        offset = try container.decode(String.self, forKey: .offset)
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        updatedBy = try container.decodeIfPresent(String.self, forKey: .updatedBy) ?? ""
        updatedAt = try container.decodeIfPresent(String.self, forKey: .updatedAt) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(organization, forKey: .organization)
        try container.encode(studentId, forKey: .studentId)
        try container.encode(studentName, forKey: .studentName)
        try container.encode(status, forKey: .status)
        try container.encode(validUntil, forKey: .validUntil)
        try container.encode(offset, forKey: .offset)
        try container.encode(comment, forKey: .comment)
        try container.encode(updatedBy, forKey: .updatedBy)
        try container.encode(updatedAt, forKey: .updatedAt)
    }

    var typeTitle: String {
        type == "team" ? "校队" : "社团"
    }
}

struct GradeRow: Identifiable, Hashable, Codable {
    var id: String { studentId }
    let studentId: String
    let studentName: String
    let checkinScore: Int
    let exam: Int
    let attendance: Int
    let physical: Int
    let total: Int
    let sourceTrace: String
    let missingItems: [String]
}

enum NoticeCategory: String, CaseIterable, Identifiable, Hashable, Codable {
    case deadline = "截止提醒"
    case review = "审核反馈"
    case organization = "组织认证"
    case system = "系统通知"

    var id: String { rawValue }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "deadline", "DEADLINE", "截止提醒":
            self = .deadline
        case "review", "REVIEW", "审核反馈":
            self = .review
        case "organization", "ORGANIZATION", "组织认证":
            self = .organization
        case "system", "SYSTEM", "系统通知":
            self = .system
        default:
            self = .system
        }
    }

    var symbolName: String {
        switch self {
        case .deadline:
            return "calendar.badge.clock"
        case .review:
            return "doc.text.magnifyingglass"
        case .organization:
            return "person.3.sequence"
        case .system:
            return "bell"
        }
    }
}

struct StudentNotice: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let message: String
    let time: String
    let category: NoticeCategory
    var isUnread: Bool

    init(
        id: String,
        title: String,
        message: String,
        time: String,
        category: NoticeCategory = .system,
        isUnread: Bool
    ) {
        self.id = id
        self.title = title
        self.message = message
        self.time = time
        self.category = category
        self.isUnread = isUnread
    }

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case message
        case time
        case createdAt
        case category
        case isUnread
        case isRead
        case read
        case readAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        message = try container.decode(String.self, forKey: .message)
        time = try container.decodeIfPresent(String.self, forKey: .time)
            ?? container.decodeIfPresent(String.self, forKey: .createdAt)
            ?? ""
        category = try container.decodeIfPresent(NoticeCategory.self, forKey: .category) ?? Self.inferCategory(title: title, message: message)
        if let unread = try container.decodeIfPresent(Bool.self, forKey: .isUnread) {
            isUnread = unread
        } else if let read = try container.decodeIfPresent(Bool.self, forKey: .isRead)
            ?? container.decodeIfPresent(Bool.self, forKey: .read) {
            isUnread = !read
        } else if (try container.decodeIfPresent(String.self, forKey: .readAt)) != nil {
            isUnread = false
        } else {
            isUnread = true
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(title, forKey: .title)
        try container.encode(message, forKey: .message)
        try container.encode(time, forKey: .time)
        try container.encode(category, forKey: .category)
        try container.encode(isUnread, forKey: .isUnread)
    }

    private static func inferCategory(title: String, message: String) -> NoticeCategory {
        let text = title + message
        if text.contains("截止") || text.localizedCaseInsensitiveContains("deadline") {
            return .deadline
        }
        if text.contains("补材料") || text.contains("补充材料") || text.contains("审核") || text.contains("驳回") || text.localizedCaseInsensitiveContains("review") {
            return .review
        }
        if text.contains("校队") || text.contains("社团") || text.contains("组织") || text.contains("认证") || text.localizedCaseInsensitiveContains("organization") {
            return .organization
        }
        return .system
    }
}

struct SportHourRule: Hashable, Codable {
    let total: Double
    let courseRequired: Double
    let generalRequired: Double
    let dailyLimit: Double

    static let standard = SportHourRule(total: 20, courseRequired: 10, generalRequired: 10, dailyLimit: 2)
}
