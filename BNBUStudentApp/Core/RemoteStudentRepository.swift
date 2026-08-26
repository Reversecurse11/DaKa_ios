import Foundation
import OSLog

enum StudentServerConfig {
    static let testBaseURL = URL(string: "http://127.0.0.1:13000/api/v1")!
    static let productionBaseURL = URL(string: "https://configuration-required.invalid/api/v1")!
    static let localDevelopmentBaseURL = URL(string: "http://127.0.0.1:13000/api/v1")!
    static let requestTimeout: TimeInterval = 60

    #if DEBUG
    static let defaultBaseURL = localDevelopmentBaseURL
    #endif

    static func resolvedBaseURL(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleValue: String? = Bundle.main.object(forInfoDictionaryKey: "BNBUAPIBaseURL") as? String
    ) -> URL {
        #if DEBUG
        if let url = argumentValue(named: "-server-base-url", in: arguments).flatMap(URL.init(string:)).flatMap(validatedBaseURL) {
            return url
        }
        if let rawURL = environment["BNBU_API_BASE_URL"], let url = URL(string: rawURL).flatMap(validatedBaseURL) {
            return url
        }
        if let bundleValue, let url = URL(string: bundleValue).flatMap(validatedBaseURL) {
            return url
        }
        return defaultBaseURL
        #else
        guard let productionURL = validatedProductionBaseURL(bundleValue) else {
            preconditionFailure("Release BNBU_API_BASE_URL must be a non-placeholder HTTPS URL ending in /api/v1")
        }
        return productionURL
        #endif
    }

    static func validatedProductionBaseURL(_ rawValue: String?) -> URL? {
        guard let rawValue,
              let url = URL(string: rawValue),
              let validated = validatedBaseURL(url),
              validated.scheme == "https",
              let host = validated.host?.lowercased(),
              !host.hasSuffix(".invalid"),
              host != "localhost",
              host != "127.0.0.1" else {
            return nil
        }
        return validated
    }

    /// Organization scoping is explicit contract configuration. It must not be
    /// inferred from an email suffix or API hostname.
    static func resolvedOrganizationCode(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleValue: String? = Bundle.main.object(forInfoDictionaryKey: "BNBUOrganizationCode") as? String
    ) -> String? {
        let raw = argumentValue(named: "-organization-code", in: arguments)
            ?? environment["BNBU_ORGANIZATION_CODE"]
            ?? bundleValue
        guard let code = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              code.range(of: "^[A-Z0-9][A-Z0-9_-]{1,31}$", options: .regularExpression) != nil else {
            return nil
        }
        return code
    }

    private static func validatedBaseURL(_ url: URL) -> URL? {
        guard url.user == nil, url.password == nil, url.query == nil, url.fragment == nil,
              url.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression) == "/api/v1" else {
            return nil
        }
        #if DEBUG
        guard url.scheme == "http" || url.scheme == "https" else { return nil }
        #else
        guard url.scheme == "https" else { return nil }
        #endif
        return url
    }

    private static func argumentValue(named name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

/// Client-side half of the exercise test-tool gate. The Backend repeats the
/// environment/account decision and fails closed, so hiding this control is
/// never treated as the security boundary.
enum StudentTestToolsConfig {
    static let durationAdvanceCapability = "TEST_DURATION_ADVANCE"

    static func permits(
        appEnvironment: String?,
        enabledValue: String?,
        isDebugBuild: Bool
    ) -> Bool {
        guard isDebugBuild else { return false }
        let environment = appEnvironment?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let enabled = enabledValue?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return (environment == "local" || environment == "test" || environment == "staging") &&
            (enabled == "true" || enabled == "1")
    }

    static var isEnabled: Bool {
#if DEBUG
        let process = ProcessInfo.processInfo
        let environment = process.environment["APP_ENV"]
            ?? process.environment["BNBU_APP_ENV"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "BNBUAppEnvironment") as? String)
        let enabledValue = process.environment["TEST_TOOLS_ENABLED"]
            ?? process.environment["BNBU_TEST_TOOLS_ENABLED"]
            ?? bundleStringValue(for: "BNBUTestToolsEnabled")
        return permits(
            appEnvironment: environment,
            enabledValue: enabledValue,
            isDebugBuild: true
        )
#else
        return false
#endif
    }

    private static func bundleStringValue(for key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.boolValue ? "true" : "false" }
        return nil
    }
}

struct APIErrorResponse: Decodable {
    let code: String?
    let message: String
    let requestId: String?
    let timestamp: String?
}

struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: APIErrorResponse?
}

// MARK: - OpenAPI 2.0.13 transport models used by the P0 student mutations

struct ContractAuthSession: Codable, Sendable {
    let sessionId: String?
    /// The contract deliberately allows an authenticated student to have no
    /// enrollment selected yet. Mutation gateways resolve an ACTIVE enrollment
    /// when this value is nil; they never manufacture an enrollment identifier.
    let enrollmentId: String?
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let accessTokenExpiresAt: String
    let refreshTokenExpiresAt: String
    let user: ContractUser
}

/// A refresh token rotates on success, so losing the response is an ambiguous
/// mutation rather than proof that the credential is invalid. Persisting this
/// small intent before the request lets a relaunched app replay the exact same
/// Idempotency-Key without storing another copy of the refresh token.
private struct ContractRefreshIntent: Codable, Sendable {
    let sessionFingerprint: String
    let idempotencyKey: String
}

struct CourseJoinOutcome: @unchecked Sendable {
    let student: StudentProfile
    let userStatus: String
    let userVersion: Int

    var requiresFirstEmailBinding: Bool { userStatus == "PENDING_CONTACT_BINDING" }
}

struct ContractUser: Codable, Sendable {
    let id: String
    let organizationId: String
    let role: String
    let status: String
    let primaryEmailMasked: String?
    let emailVerified: Bool
    let version: Int
}

private struct ContractStudentSignInChallenge: Decodable {
    let challengeId: String
    let expiresAt: String
}

private struct ContractEmailVerificationChallenge: Decodable {
    let challengeId: String
    let mode: String
    let expiresAt: String
}

private struct ContractStudentProfile: Decodable {
    let id: String
    let studentNumber: String
    let fullName: String
    let gender: String
    let gradeYear: Int
    let collegeName: String?
    let majorName: String?
    let administrativeClassName: String?
    let status: String
}

private struct ContractCurrentUser: Decodable {
    let user: ContractUser
    let studentProfile: ContractStudentProfile?
}

private struct ContractCourse: Decodable, Sendable {
    let id: String
    let courseCode: String
    let courseName: String
    let status: String
}

private struct ContractClassSection: Decodable, Sendable {
    let id: String
    let courseId: String
    let semesterId: String
    let teacherId: String
    let classCode: String
    let displayName: String
    let status: String
    let isEnrollmentOpen: Bool
    let checkInWindowMode: String
    let checkInStartDate: String?
    let checkInEndDate: String?
    let dailyStartTime: String?
    let dailyEndTime: String?
    let submissionDeadlineAt: String?
    let excludedDates: [String]
}

private struct ContractSemester: Decodable {
    let id: String
    let displayName: String
    let isCurrent: Bool
}

private struct ContractCourseInvitePreview: Decodable {
    let classSectionId: String
    let displayName: String
    let courseCode: String
    let courseName: String
    let semesterDisplayName: String
    let teacherDisplayName: String
    let enrollmentOpen: Bool
    let expiresAt: String
}

private struct ContractJoinCapability: Decodable {
    let joinCapability: String
    let classSectionId: String
    let expiresAt: String
}

struct ContractExerciseSession: Decodable, Sendable {
    let id: String
    let studentId: String
    let enrollmentId: String
    let classSectionId: String
    let status: String
    let startedAt: String
    let endedAt: String?
    let actualDurationSeconds: Int
    let pausedDurationSeconds: Int
    let businessDate: String
    let version: Int
}

struct ContractAccountDeletionChallenge: Decodable, Sendable {
    let challengeId: String
    let mode: String
    let expiresAt: String
    let version: Int
}

struct ContractAccountDeletionResult: Decodable, Sendable {
    let status: String
    let deletedAt: String
    let allSessionsRevoked: Bool
    let newRegistrationRequired: Bool
}

struct ContractExerciseRecordAttemptContext: Decodable, Hashable, Sendable {
    let recordId: String
    let previousAttemptId: String?
    let rootAttemptId: String
    let attemptNumber: Int
}

private struct ContractExerciseRecordResubmission: Decodable, Sendable {
    let record: ContractExerciseRecord
    let attemptContext: ContractExerciseRecordAttemptContext
}

enum ExerciseSessionStartOutcome: Sendable {
    case created(session: ContractExerciseSession, requestId: String?)
    case recovered(session: ContractExerciseSession, requestId: String?)
    case alreadyActive(session: ContractExerciseSession, requestId: String?)
}

struct ContractExemptionSupplementPlan: Sendable {
    let applicationId: String
    let enrollmentId: String
    let expectedVersion: Int
    let mediaIds: [String]
}

private struct ContractEnrollment: Decodable, Sendable {
    let id: String
    let semesterId: String
    let classSectionId: String
    let studentId: String
    let status: String
}

private struct ContractJoinResult: Decodable {
    let studentProfile: ContractStudentProfile
    let enrollment: ContractEnrollment
    let course: ContractCourse
    let classSection: ContractClassSection
    let authSession: ContractAuthSession
}

private struct ContractCurrentReview: Decodable, Sendable {
    let result: String
    let reasonCode: String?
    let publicComment: String?
}

private struct ContractExerciseRecord: Decodable, Sendable {
    let id: String
    let enrollmentId: String
    let courseId: String
    let classSectionId: String
    let sessionId: String
    let businessDate: String
    let creditType: String
    let sportType: String
    let sportName: String?
    let description: String?
    let actualDurationSeconds: Int
    let pausedDurationSeconds: Int
    let creditedDurationSeconds: Int
    let status: String
    let submittedAt: String?
    let currentReview: ContractCurrentReview?
    let version: Int
}

private struct ContractStudentScore: Decodable, Sendable {
    let enrollmentId: String
    let validCourseDurationSeconds: Int
    let validGeneralDurationSeconds: Int
    let totalValidDurationSeconds: Int
    let qualificationStatus: String
    let status: String
}

private struct ContractActivityConversionPreview: Decodable, Sendable {
    let score: Int
    let tier: String
    let timeSeconds: Int
    let runType: String
    let ruleVersion: Int
}

private struct ContractMediaUploadSession: Decodable {
    let uploadSessionId: String
    let mediaId: String
    let uploadUrl: String
    let uploadMethod: String
    let requiredHeaders: [String: String]
}

private struct ContractMediaEvidence: Decodable {
    let id: String
    let sessionId: String?
    let enrollmentId: String?
    let businessPurpose: String
    let mediaType: String
    let declaredMimeType: String
    let verifiedMimeType: String?
    let uploadStatus: String
    let verifiedContentSha256: String?
    let version: Int
}

private struct ContractExemptionApplication: Decodable, Sendable {
    let id: String
    let studentId: String
    let enrollmentId: String
    let classSectionId: String
    let applicationType: String
    let applicationSubtype: String?
    let organizationName: String?
    let reason: String
    let mediaIds: [String]
    let status: String
    let publicComment: String?
    let submittedAt: String?
    let decidedAt: String?
    let version: Int
}

private struct ContractSuccessMeta: Decodable {
    let requestId: String
    let pagination: ContractPaginationMeta?
}

private struct ContractPaginationMeta: Decodable {
    let nextCursor: String?
}

private struct ContractEnvelope<Value: Decodable>: Decodable {
    let data: Value
    let meta: ContractSuccessMeta
}

struct SafeContractFieldError: Decodable, Equatable, Sendable {
    let field: String
    let code: String

    private enum CodingKeys: String, CodingKey { case field, code }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedField = try container.decode(String.self, forKey: .field)
        let decodedCode = try container.decode(String.self, forKey: .code)
        guard decodedField.range(
            of: "^[A-Za-z][A-Za-z0-9_.]{0,63}$",
            options: .regularExpression
        ) != nil,
              decodedCode.range(
                of: "^[A-Z][A-Z0-9_]{0,79}$",
                options: .regularExpression
              ) != nil else {
            throw DecodingError.dataCorruptedError(
                forKey: .field,
                in: container,
                debugDescription: "Unsafe field error metadata"
            )
        }
        field = decodedField
        code = decodedCode
    }
}

struct ContractExemptionDraftPlan: Sendable {
    let applicationId: String
    let enrollmentId: String
    let expectedVersion: Int
}

/// Strict allowlist from ADR-015 `details`. Unknown keys are ignored by
/// Decodable and arbitrary objects are never retained or logged.
struct SafeContractErrorDetails: Decodable, Equatable, Sendable {
    let retryable: Bool?
    let fieldErrors: [SafeContractFieldError]?
    let startedAt: String?
    let status: String?
    let startedOnCurrentAuthSession: Bool?

    private enum CodingKeys: String, CodingKey {
        case retryable
        case fieldErrors
        case startedAt
        case status
        case startedOnCurrentAuthSession
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        retryable = try? container.decodeIfPresent(Bool.self, forKey: .retryable)
        fieldErrors = try? container.decodeIfPresent([SafeContractFieldError].self, forKey: .fieldErrors)
        let decodedStartedAt = try? container.decodeIfPresent(String.self, forKey: .startedAt)
        startedAt = decodedStartedAt.flatMap(Self.safeRFC3339)
        let decodedStatus = try? container.decodeIfPresent(String.self, forKey: .status)
        status = decodedStatus.flatMap { ["IN_PROGRESS", "PAUSED"].contains($0) ? $0 : nil }
        startedOnCurrentAuthSession = try? container.decodeIfPresent(
            Bool.self,
            forKey: .startedOnCurrentAuthSession
        )
    }

    private static func safeRFC3339(_ value: String) -> String? {
        guard value.count <= 40 else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if fractional.date(from: value) != nil { return value }
        let standard = ISO8601DateFormatter()
        standard.formatOptions = [.withInternetDateTime]
        return standard.date(from: value) == nil ? nil : value
    }
}

private struct ContractErrorEnvelope: Decodable {
    let code: String
    let message: String
    let details: SafeContractErrorDetails?
    let requestId: String
    let timestamp: String

    private enum CodingKeys: String, CodingKey {
        case code
        case message
        case details
        case requestId
        case timestamp
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        code = try container.decode(String.self, forKey: .code)
        message = try container.decode(String.self, forKey: .message)
        details = try? container.decodeIfPresent(SafeContractErrorDetails.self, forKey: .details)
        requestId = try container.decode(String.self, forKey: .requestId)
        timestamp = try container.decode(String.self, forKey: .timestamp)
    }
}

struct WorkspacePayload: Decodable {
    let student: StudentProfile
    let courses: [Course]
    let progress: StudentProgress
    let records: [CheckInRecord]
    let grades: GradeRow?
    let memberships: [Membership]
    let notices: [StudentNotice]
    let exemptions: [ExemptionApplication]?
    let syncOperations: [SyncOperation]?

    func workspace() -> StudentWorkspace {
        StudentWorkspace(
            student: student,
            courses: courses,
            progress: progress,
            records: records,
            grades: grades ?? GradeRow(
                studentId: student.id,
                studentName: student.name,
                checkinScore: 0,
                exam: 0,
                attendance: 0,
                physical: 0,
                total: 0,
                sourceTrace: "server:grades-missing",
                missingItems: [BNBUL10n.text("成绩暂未返回")],
                state: .ruleUnpublished
            ),
            memberships: memberships,
            notices: notices,
            exemptions: exemptions ?? [],
            syncOperations: syncOperations ?? []
        )
    }
}

struct ServerLoginPayload: Decodable {
    let token: String?
    let accessToken: String?
    let user: StudentProfile?
    let defaultRoute: String?
}

struct DataWrapper<T: Decodable>: Decodable {
    let data: T
}

struct SportSummaryPayload: Decodable {
    let student: StudentProfile?
    let progress: StudentProgress?
    let courses: [Course]
    let records: [CheckInRecord]
    let grades: GradeRow?
    let memberships: [Membership]
    let notices: [StudentNotice]
    let exemptions: [ExemptionApplication]
    let hourRule: SportHourRule?

    enum CodingKeys: String, CodingKey {
        case student
        case profile
        case user
        case progress
        case summary
        case hourRule
        case hourRules
        case checkinSetting
        case requirement
        case courses
        case records
        case grades
        case memberships
        case organizationCredit
        case identity
        case notices
        case notifications
        case exemptions
        case exemptionApplications
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        student = try container.decodeIfPresent(StudentProfile.self, forKey: .student)
            ?? container.decodeIfPresent(StudentProfile.self, forKey: .profile)
            ?? container.decodeIfPresent(StudentProfile.self, forKey: .user)
        progress = try container.decodeIfPresent(StudentProgress.self, forKey: .progress)
            ?? container.decodeIfPresent(StudentProgress.self, forKey: .summary)
            ?? (try? StudentProgress(from: decoder))
        courses = (try? container.decodeIfPresent([Course].self, forKey: .courses)) ?? []
        records = (try? container.decodeIfPresent([CheckInRecord].self, forKey: .records)) ?? []
        grades = try container.decodeIfPresent(GradeRow.self, forKey: .grades)
        // Rule 4.4 targets may be published under the summary itself or under
        // the teacher's check-in setting; an absent block keeps the standard.
        var decodedHourRule: SportHourRule?
        for key in [CodingKeys.hourRule, .hourRules, .checkinSetting, .requirement] {
            guard decodedHourRule == nil else { break }
            decodedHourRule = try? container.decodeIfPresent(SportHourRule.self, forKey: key)
        }
        hourRule = decodedHourRule
        var decodedMemberships = (try? container.decodeIfPresent([Membership].self, forKey: .memberships)) ?? []
        if let organizationCredit = try container.decodeIfPresent(Membership.self, forKey: .organizationCredit) {
            decodedMemberships.append(organizationCredit)
        }
        if let identity = try? container.decodeIfPresent(SportIdentityPayload.self, forKey: .identity) {
            decodedMemberships.append(contentsOf: identity.memberships)
        }
        memberships = decodedMemberships
        notices = (try? container.decodeIfPresent([StudentNotice].self, forKey: .notices))
            ?? (try? container.decodeIfPresent([StudentNotice].self, forKey: .notifications))
            ?? []
        exemptions = (try? container.decodeIfPresent([ExemptionApplication].self, forKey: .exemptions))
            ?? (try? container.decodeIfPresent([ExemptionApplication].self, forKey: .exemptionApplications))
            ?? []
    }
}

struct SportRecordsPayload: Decodable {
    let records: [CheckInRecord]

    enum CodingKeys: String, CodingKey {
        case records
        case items
        case list
        case data
    }

    init(from decoder: Decoder) throws {
        if let records = try? [CheckInRecord](from: decoder) {
            self.records = records
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        records = (try? container.decodeIfPresent([CheckInRecord].self, forKey: .records))
            ?? (try? container.decodeIfPresent([CheckInRecord].self, forKey: .items))
            ?? (try? container.decodeIfPresent([CheckInRecord].self, forKey: .list))
            ?? (try? container.decodeIfPresent([CheckInRecord].self, forKey: .data))
            ?? []
    }
}

struct SportIdentityPayload: Decodable {
    let memberships: [Membership]

    enum CodingKeys: String, CodingKey {
        case memberships
        case organizationCredit
        case identity
        case data
    }

    init(from decoder: Decoder) throws {
        if let memberships = try? [Membership](from: decoder) {
            self.memberships = memberships
            return
        }
        if let membership = try? Membership(from: decoder) {
            memberships = [membership]
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        var decoded = (try? container.decodeIfPresent([Membership].self, forKey: .memberships)) ?? []
        if let organizationCredit = try container.decodeIfPresent(Membership.self, forKey: .organizationCredit) {
            decoded.append(organizationCredit)
        }
        if let identity = try? container.decodeIfPresent(Membership.self, forKey: .identity) {
            decoded.append(identity)
        }
        if decoded.isEmpty, let nested = try? container.decodeIfPresent(SportIdentityPayload.self, forKey: .data) {
            decoded = nested.memberships
        }
        memberships = decoded
    }
}

struct NoticesPayload: Decodable {
    let notices: [StudentNotice]

    enum CodingKeys: String, CodingKey {
        case notices
        case notifications
        case items
        case data
    }

    init(from decoder: Decoder) throws {
        if let notices = try? [StudentNotice](from: decoder) {
            self.notices = notices
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        notices = (try? container.decodeIfPresent([StudentNotice].self, forKey: .notices))
            ?? (try? container.decodeIfPresent([StudentNotice].self, forKey: .notifications))
            ?? (try? container.decodeIfPresent([StudentNotice].self, forKey: .items))
            ?? (try? container.decodeIfPresent([StudentNotice].self, forKey: .data))
            ?? []
    }
}

struct ExemptionsPayload: Decodable {
    let exemptions: [ExemptionApplication]

    enum CodingKeys: String, CodingKey {
        case exemptions
        case applications
        case items
        case list
        case data
    }

    init(from decoder: Decoder) throws {
        if let exemptions = try? [ExemptionApplication](from: decoder) {
            self.exemptions = exemptions
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        for key in [CodingKeys.exemptions, .applications, .items, .list, .data]
            where container.contains(key) {
            exemptions = try container.decodeIfPresent(
                [ExemptionApplication].self,
                forKey: key
            ) ?? []
            return
        }
        exemptions = []
    }
}

struct StudentCoursesPayload: Decodable {
    struct Semester: Decodable {
        let name: String
    }

    struct Item: Decodable {
        let id: String
        let code: String
        let section: String
        let name: String
        let teacherName: String?
        let isCurrent: Bool?
        let semester: Semester?
    }

    let courses: [Item]

    func models() -> [Course] {
        courses.map { item in
            Course(
                id: item.id,
                code: item.code,
                section: item.section,
                name: item.name,
                semester: item.semester?.name ?? "当前学期",
                students: 0,
                pending: 0,
                completion: 0,
                missing: 0,
                deadline: "",
                teacher: item.teacherName ?? "",
                isCurrent: item.isCurrent ?? true
            )
        }
    }
}

struct StudentGradesPayload: Decodable {
    struct Row: Decodable {
        let studentId: String?
        let studentName: String?
        let checkinScore: Int?
        let exam: Int?
        let attendance: Int?
        let physical: Int?
        let total: Int?
        let sourceTrace: String?
    }

    struct Summary: Decodable {
        let overallCheckinScore: Int?
        let overallExam: Int?
        let overallAttendance: Int?
        let overallPhysical: Int?
        let overallTotal: Int?
    }

    let grades: [Row]
    let summary: Summary

    func model(for student: StudentProfile) -> GradeRow {
        GradeRow(
            studentId: student.id,
            studentName: student.name,
            checkinScore: summary.overallCheckinScore ?? average(\.checkinScore),
            exam: summary.overallExam ?? average(\.exam),
            attendance: summary.overallAttendance ?? average(\.attendance),
            physical: summary.overallPhysical ?? average(\.physical),
            total: summary.overallTotal ?? average(\.total),
            sourceTrace: grades.compactMap(\.sourceTrace).first ?? "API: current grade projection",
            missingItems: grades.isEmpty ? [BNBUL10n.text("成绩尚未录入")] : []
        )
    }

    private func average(_ keyPath: KeyPath<Row, Int?>) -> Int {
        guard !grades.isEmpty else { return 0 }
        let total = grades.reduce(0) { $0 + ($1[keyPath: keyPath] ?? 0) }
        return Int((Double(total) / Double(grades.count)).rounded())
    }
}

struct ProofUploadPayload: Decodable {
    struct UploadedFile: Decodable {
        let url: String
        let cosKey: String
        let mediaType: ProofMediaType
        let mimeType: String
        let size: Int

        func attachment(fallback: ProofAttachment) -> ProofAttachment {
            ProofAttachment(
                id: cosKey,
                type: mediaType,
                fileName: fallback.fileName,
                byteCount: size,
                durationSeconds: fallback.durationSeconds,
                thumbnailData: fallback.thumbnailData,
                uploadData: nil,
                source: url,
                cosKey: cosKey,
                mimeType: mimeType,
                contentDigest: fallback.contentDigest
            )
        }
    }

    let id: String?
    let url: String?
    let urls: [String]?
    let path: String?
    let storagePath: String?
    let fileName: String?
    let type: ProofMediaType?
    let byteCount: Int?
    let files: [UploadedFile]?

    var remoteSource: String? {
        files?.first?.url ?? url ?? urls?.first ?? path ?? storagePath
    }

    func attachment(fallback: ProofAttachment) -> ProofAttachment {
        if let uploaded = files?.first {
            return uploaded.attachment(fallback: fallback)
        }
        return ProofAttachment(
            id: id ?? fallback.id,
            type: type ?? fallback.type,
            fileName: fileName ?? fallback.fileName,
            byteCount: byteCount ?? fallback.byteCount,
            durationSeconds: fallback.durationSeconds,
            thumbnailData: fallback.thumbnailData,
            uploadData: nil,
            source: remoteSource ?? fallback.source,
            cosKey: fallback.cosKey,
            mimeType: fallback.mimeType,
            contentDigest: fallback.contentDigest
        )
    }
}

/// Safe public projection returned by `GET /system-mode`.
struct SystemModePayload: Decodable {
    let mode: String
    let policyVersion: Int
    let updatedAt: String
}

/// One published entry returned by `GET /help-articles`.
struct HelpArticlePayload: Decodable {
    let id: String
    let category: String
    let locale: String
    let title: String
    let bodyMarkdown: String
    let publishedAt: String
    let version: Int
}

/// Privacy-bounded business projection from `GET/POST /feedback`. Contacts,
/// raw logs, tokens, device identifiers and internal notes are deliberately
/// absent because the public contract does not permit them.
private struct ContractFeedbackPayload: Decodable, Sendable {
    let id: String
    let category: String
    let content: String
    let status: String
    let publicReply: String?
    let createdAt: String
    let updatedAt: String
    let version: Int
}

private struct TestToolCapabilitiesPayload: Decodable {
    let capabilities: [String]
}

/// Platform policy returned by `GET /app-release-policy`.
struct AppReleasePolicyPayload: Decodable {
    let platform: String
    let minimumSupportedVersion: String
    let latestVersion: String
    let minimumSupportedBuildNumber: Int?
    let latestBuildNumber: Int?
    let enforcement: String
    let message: String?
    let downloadUrl: String?
    let effectiveAt: String
    let expiresAt: String?
    let policyVersion: String
}

struct RecordIdentifierPayload: Decodable {
    let id: String?
    let recordId: String?
}

struct ExemptionIdentifierPayload: Decodable {
    let id: String?
    let exemptionId: String?
    let applicationId: String?
}

private final class UploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let progressHandler: @Sendable (Double) -> Void

    init(progressHandler: @escaping @Sendable (Double) -> Void) {
        self.progressHandler = progressHandler
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        progressHandler(min(max(fraction, 0), 1))
    }
}

actor RemoteStudentRepository {
    private static let uploadDirectoryName = "BNBUStudentUploads"
    private let baseURL: URL
    nonisolated let serverIdentity: String
    private let credentialStore: any SecureCredentialStoring
    private let urlSession: URLSession
    private let exerciseTestToolsEnabled: Bool
    private var accessToken: String?
    private var contractSession: ContractAuthSession?
    private var currentUser: StudentProfile?
    private var lastContractRequestId: String?
    private var authenticationEpoch: UInt64 = 0
    private var refreshTask: Task<Void, Error>?

    private let accessTokenStorageKey: String
    private let contractSessionStorageKey: String
    private let refreshIntentStorageKey: String
    private let deviceIDStorageKey = "bnbu.auth.deviceId.v1"

    private static func tokenStorageSuffix(for baseURL: URL) -> String {
        baseURL.absoluteString
            .replacingOccurrences(of: "://", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
    }

    static func accessTokenKey(for baseURL: URL) -> String {
        "bnbu.remote.accessToken.v2.\(tokenStorageSuffix(for: baseURL))"
    }

    static func contractSessionKey(for baseURL: URL) -> String {
        "bnbu.contract.authSession.v2.\(tokenStorageSuffix(for: baseURL))"
    }

    static func refreshIntentKey(for baseURL: URL) -> String {
        "bnbu.contract.refreshIntent.v1.\(tokenStorageSuffix(for: baseURL))"
    }

    static func legacyAccessTokenDefaultsKey(for baseURL: URL) -> String {
        "bnbu.remote.accessToken.v1.\(tokenStorageSuffix(for: baseURL))"
    }

    init(
        baseURL: URL = StudentServerConfig.resolvedBaseURL(),
        credentialStore: any SecureCredentialStoring = KeychainCredentialStore(),
        urlSession: URLSession = .shared,
        legacyDefaults: UserDefaults = .standard,
        exerciseTestToolsEnabled: Bool = StudentTestToolsConfig.isEnabled
    ) {
        Self.removeStaleUploadFiles()
        ProofTransientFileStore.removeStaleCopies()
        self.baseURL = baseURL
        self.serverIdentity = baseURL.absoluteString
        self.credentialStore = credentialStore
        self.urlSession = urlSession
        self.exerciseTestToolsEnabled = exerciseTestToolsEnabled
        let storageKey = Self.accessTokenKey(for: baseURL)
        accessTokenStorageKey = storageKey
        let sessionStorageKey = Self.contractSessionKey(for: baseURL)
        contractSessionStorageKey = sessionStorageKey
        refreshIntentStorageKey = Self.refreshIntentKey(for: baseURL)

        if let sessionData = try? credentialStore.data(forKey: sessionStorageKey),
           let restored = try? JSONDecoder().decode(ContractAuthSession.self, from: sessionData),
           restored.tokenType == "Bearer",
           !restored.accessToken.isEmpty,
           !restored.refreshToken.isEmpty {
            contractSession = restored
            accessToken = restored.accessToken
        }

        let storedCredential: Data?
        do {
            storedCredential = try credentialStore.data(forKey: storageKey)
        } catch {
            storedCredential = nil
        }
        if contractSession != nil {
            // The complete rotating AuthSession is authoritative over the
            // access-token-only compatibility entry.
        } else if let secureData = storedCredential,
           let token = String(data: secureData, encoding: .utf8),
           !token.isEmpty {
            accessToken = token
        } else {
            let legacyKey = Self.legacyAccessTokenDefaultsKey(for: baseURL)
            let legacyToken = legacyDefaults.string(forKey: legacyKey)
            if let legacyToken, !legacyToken.isEmpty,
               (try? credentialStore.set(Data(legacyToken.utf8), forKey: storageKey)) != nil {
                accessToken = legacyToken
                legacyDefaults.removeObject(forKey: legacyKey)
            } else {
                accessToken = nil
            }
        }

        // Frozen v1 never defined refresh tokens. Remove any credentials left by
        // older development builds so a logout is strictly local and deterministic.
        let suffix = Self.tokenStorageSuffix(for: baseURL)
        legacyDefaults.removeObject(forKey: "bnbu.remote.refreshToken.v1.\(suffix)")
    }

    var isAuthenticated: Bool {
        accessToken != nil
    }

    var authEnrollmentId: String? {
        contractSession?.enrollmentId
    }

    /// Rehydrates the persisted rotating AuthSession without guessing a local
    /// user state. `/me` is explicitly allowed for both ACTIVE and
    /// PENDING_CONTACT_BINDING students.
    func restoreStudentSession() async throws -> CourseJoinOutcome? {
        guard contractSession != nil else { return nil }
        let data = try await get("me")
        let current = try decodeContract(ContractCurrentUser.self, from: data)
        guard current.user.role == "STUDENT",
              current.user.status == "ACTIVE" || current.user.status == "PENDING_CONTACT_BINDING",
              let student = current.studentProfile,
              let currentSession = contractSession else {
            throw RepositoryError.apiError("持久化会话未返回受支持的学生投影。")
        }
        let refreshedSession = ContractAuthSession(
            sessionId: currentSession.sessionId,
            enrollmentId: currentSession.enrollmentId,
            accessToken: currentSession.accessToken,
            refreshToken: currentSession.refreshToken,
            tokenType: currentSession.tokenType,
            accessTokenExpiresAt: currentSession.accessTokenExpiresAt,
            refreshTokenExpiresAt: currentSession.refreshTokenExpiresAt,
            user: current.user
        )
        try installContractSession(refreshedSession)
        let profile = Self.studentProfile(from: student, user: current.user)
        currentUser = profile
        return CourseJoinOutcome(
            student: profile,
            userStatus: current.user.status,
            userVersion: current.user.version
        )
    }

    func requestStudentSignInCode(
        account: String,
        organizationCode: String,
        locale: String
    ) async throws -> (challengeId: String, expiresAt: String) {
        let normalizedAccount = account.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard ContactBindingRule.isValid(normalizedAccount, for: .email) else {
            throw RepositoryError.apiError("请输入有效的学校邮箱。")
        }
        guard StudentServerConfig.resolvedOrganizationCode(
            arguments: ["-organization-code", organizationCode],
            environment: [:],
            bundleValue: nil
        ) == organizationCode else {
            throw RepositoryError.apiError("CONTRACT DECISION REQUIRED：请显式配置有效的 BNBU organizationCode。")
        }
        guard locale == "zh-CN" || locale == "en" else {
            throw RepositoryError.apiError("登录语言参数不受合同支持。")
        }
        let data = try await post(
            "auth/student-sign-in-codes",
            body: try Self.jsonData([
                "organizationCode": organizationCode,
                "account": normalizedAccount,
                "channel": "EMAIL",
                "locale": locale
            ]),
            authenticated: false,
            idempotencyKey: IdempotencyKeyPolicy.make()
        )
        let challenge = try decodeContract(ContractStudentSignInChallenge.self, from: data)
        return (challenge.challengeId, challenge.expiresAt)
    }

    func verifyStudentSignInCode(
        challengeId: String,
        code: String
    ) async throws -> StudentProfile {
        guard !challengeId.isEmpty,
              code.range(of: "^\\d{4,10}$", options: .regularExpression) != nil else {
            throw RepositoryError.apiError("请输入 4 到 10 位数字验证码。")
        }
        authenticationEpoch &+= 1
        let loginEpoch = authenticationEpoch
        let data = try await post(
            "auth/student-sign-in-codes/verify",
            body: try Self.jsonData([
                "challengeId": challengeId,
                "code": code,
                "deviceId": try persistentDeviceID()
            ]),
            authenticated: false,
            idempotencyKey: IdempotencyKeyPolicy.make()
        )
        guard loginEpoch == authenticationEpoch else {
            throw RepositoryError.sessionChanged
        }
        let session = try decodeContract(ContractAuthSession.self, from: data)
        guard session.user.role == "STUDENT", session.user.status == "ACTIVE" else {
            throw RepositoryError.apiError("当前学生账号尚未处于 ACTIVE 状态。")
        }
        try installContractSession(session)
        do {
            return try await loadCurrentStudentProfile()
        } catch {
            _ = clearSession()
            throw error
        }
    }

    func previewCourseInvite(token rawToken: String) async throws -> CourseInvite {
        let token = try Self.validInviteToken(rawToken)
        let tokenPath = try Self.percentEncodedPathComponent(token)
        let data = try await get(
            "course-invites/\(tokenPath)/preview",
            authenticated: false
        )
        let preview = try decodeContract(ContractCourseInvitePreview.self, from: data)
        guard preview.enrollmentOpen else {
            throw RepositoryError.apiError("该课程当前未开放加入。")
        }
        return CourseInvite(
            code: token,
            classSectionID: preview.classSectionId,
            courseName: preview.courseName,
            courseCode: preview.courseCode,
            section: preview.displayName,
            teacherName: preview.teacherDisplayName,
            semester: preview.semesterDisplayName,
            enrollmentOpen: preview.enrollmentOpen,
            expiresAt: preview.expiresAt
        )
    }

    func joinCourseInvite(
        _ invite: CourseInvite,
        fullName: String,
        studentNumber: String,
        gender: StudentGender,
        gradeYear: Int
    ) async throws -> CourseJoinOutcome {
        let token = try Self.validInviteToken(invite.code)
        let tokenPath = try Self.percentEncodedPathComponent(token)
        guard let previewClassSectionID = invite.classSectionID,
              !previewClassSectionID.isEmpty,
              invite.enrollmentOpen,
              let joinGender = gender.courseJoinAPIValue,
              (1000...9999).contains(gradeYear) else {
            throw RepositoryError.apiError("课程邀请或学生资料不符合加入合同。")
        }
        let capabilityData = try await post(
            "course-invites/\(tokenPath)/join-capabilities",
            body: try Self.jsonData([
                "fullName": fullName.trimmingCharacters(in: .whitespacesAndNewlines),
                "studentNumber": studentNumber.trimmingCharacters(in: .whitespacesAndNewlines),
                "gender": joinGender,
                "gradeYear": gradeYear
            ]),
            authenticated: false,
            idempotencyKey: IdempotencyKeyPolicy.make()
        )
        let capability = try decodeContract(ContractJoinCapability.self, from: capabilityData)
        guard capability.classSectionId == previewClassSectionID else {
            throw RepositoryError.apiError("加入凭证与已预览课程不一致，已停止加入。")
        }
        let joinData = try await post(
            "course-invites/\(tokenPath)/join",
            body: nil,
            authenticated: false,
            idempotencyKey: IdempotencyKeyPolicy.make(),
            headers: ["X-Join-Capability": capability.joinCapability]
        )
        let result = try decodeContract(ContractJoinResult.self, from: joinData)
        guard result.enrollment.status == "ACTIVE",
              result.enrollment.classSectionId == previewClassSectionID,
              result.classSection.id == previewClassSectionID,
              result.authSession.user.role == "STUDENT" else {
            throw RepositoryError.apiError("服务器未返回目标课程的 ACTIVE Enrollment，已停止本地登录。")
        }
        guard result.authSession.user.status == "ACTIVE" ||
                result.authSession.user.status == "PENDING_CONTACT_BINDING" else {
            throw RepositoryError.apiError("课程已加入，但账号状态不受学生端合同支持。")
        }
        try installContractSession(result.authSession)
        let profile = Self.studentProfile(from: result.studentProfile, user: result.authSession.user)
        currentUser = profile
        return CourseJoinOutcome(
            student: profile,
            userStatus: result.authSession.user.status,
            userVersion: result.authSession.user.version
        )
    }

    func requestFirstEmailBinding(
        email: String,
        locale: String,
        expectedVersion: Int
    ) async throws -> (challengeId: String, expiresAt: String) {
        guard contractSession?.user.status == "PENDING_CONTACT_BINDING",
              expectedVersion > 0,
              ContactBindingRule.isValid(email, for: .email),
              locale == "zh-CN" || locale == "en" else {
            throw RepositoryError.apiError("首次邮箱绑定参数不符合合同。")
        }
        let data = try await post(
            "me/email-verification-challenges",
            body: try Self.jsonData([
                "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
                "locale": locale,
                "expectedVersion": expectedVersion
            ]),
            idempotencyKey: IdempotencyKeyPolicy.make()
        )
        let challenge = try decodeContract(ContractEmailVerificationChallenge.self, from: data)
        guard challenge.mode == "FIRST_BIND" else {
            throw RepositoryError.apiError("服务器返回的邮箱验证模式不是 FIRST_BIND。")
        }
        return (challenge.challengeId, challenge.expiresAt)
    }

    func verifyFirstEmailBinding(
        challengeId: String,
        newEmailCode: String
    ) async throws -> StudentProfile {
        let challengeID = try Self.pathComponent(challengeId)
        guard ContactBindingRule.isValidStudentSignInCode(newEmailCode) else {
            throw RepositoryError.apiError("请输入 4 到 10 位数字验证码。")
        }
        let data = try await post(
            "me/email-verification-challenges/\(challengeID)/verify",
            body: try Self.jsonData(["newEmailCode": newEmailCode]),
            idempotencyKey: IdempotencyKeyPolicy.make()
        )
        let current = try decodeContract(ContractCurrentUser.self, from: data)
        guard current.user.role == "STUDENT",
              current.user.status == "ACTIVE",
              current.user.emailVerified,
              let student = current.studentProfile,
              let existingSession = contractSession else {
            throw RepositoryError.apiError("邮箱验证完成后未返回 ACTIVE 学生投影。")
        }
        let updatedSession = ContractAuthSession(
            sessionId: existingSession.sessionId,
            enrollmentId: existingSession.enrollmentId,
            accessToken: existingSession.accessToken,
            refreshToken: existingSession.refreshToken,
            tokenType: existingSession.tokenType,
            accessTokenExpiresAt: existingSession.accessTokenExpiresAt,
            refreshTokenExpiresAt: existingSession.refreshTokenExpiresAt,
            user: current.user
        )
        try installContractSession(updatedSession)
        let profile = Self.studentProfile(from: student, user: current.user)
        currentUser = profile
        return profile
    }

    @discardableResult
    func logout() async -> Bool {
        let current = contractSession
        var remotelyRevoked = true
        if let current {
            do {
                _ = try await post(
                    "auth/logout",
                    body: try Self.jsonData(["refreshToken": current.refreshToken]),
                    idempotencyKey: IdempotencyKeyPolicy.make()
                )
            } catch RepositoryError.unauthorized {
                // An already-expired/revoked session is equivalent to logout.
            } catch {
                remotelyRevoked = false
            }
        }
        invalidateInMemorySession()
        return clearPersistedAccessToken() && remotelyRevoked
    }

    @discardableResult
    func clearSession() -> Bool {
        invalidateInMemorySession()
        return clearPersistedAccessToken()
    }

    func loadWorkspace() async throws -> StudentWorkspace {
        try await loadContractWorkspace()
    }

    // MARK: OpenAPI 2.0.13 P0 mutation gateways

    /// AuthSession.enrollmentId is optional by contract. When absent, resolve
    /// the student's ACTIVE enrollment from the authoritative list. Multiple
    /// unmatched enrollments are not guessed; the caller must provide the
    /// ClassSection represented by the current course.
    func resolveActiveEnrollmentID(preferredClassSectionId: String?) async throws -> String {
        if let enrollmentId = contractSession?.enrollmentId, !enrollmentId.isEmpty {
            return enrollmentId
        }
        let enrollments = try await getAllContractPages(
            ContractEnrollment.self,
            path: "enrollments",
            queryItems: [
            URLQueryItem(name: "status", value: "ACTIVE"),
            URLQueryItem(name: "limit", value: "100"),
            URLQueryItem(name: "sort", value: "-joinedAt")
            ]
        )
            .filter { $0.status == "ACTIVE" }
        if let preferredClassSectionId,
           let exact = enrollments.first(where: { $0.classSectionId == preferredClassSectionId }) {
            return exact.id
        }
        guard enrollments.count == 1, let only = enrollments.first else {
            throw RepositoryError.apiError("无法唯一确定当前 ACTIVE Enrollment，请刷新课程后重试。")
        }
        return only.id
    }

    /// Recover first, create second. A local UUID is never sent as sessionId.
    func startOrRecoverExerciseSession(
        preferredClassSectionId: String?,
        recoverableLocalSessionId: String?,
        clientObservedAt: Date
    ) async throws -> ExerciseSessionStartOutcome {
        let enrollmentId = try await resolveActiveEnrollmentID(
            preferredClassSectionId: preferredClassSectionId
        )
        if let active = try await activeExerciseSession(enrollmentId: enrollmentId) {
            guard active.enrollmentId == enrollmentId else {
                throw RepositoryError.apiError("服务器返回了不属于当前 Enrollment 的运动会话。")
            }
            if active.id == recoverableLocalSessionId {
                return .recovered(session: active, requestId: lastContractRequestId)
            }
            return .alreadyActive(session: active, requestId: lastContractRequestId)
        }
        let body: [String: Any] = [
            "enrollmentId": enrollmentId,
            "clientObservedAt": Self.rfc3339(clientObservedAt)
        ]
        do {
            let data = try await post(
                "exercise-sessions",
                body: try Self.jsonData(body),
                idempotencyKey: IdempotencyKeyPolicy.make()
            )
            let created = try decodeContract(ContractExerciseSession.self, from: data)
            return .created(session: created, requestId: lastContractRequestId)
        } catch let error as RepositoryError {
            // A concurrent device may have created the one allowed active
            // session after our read. Return it as a non-controlling conflict;
            // the caller must never install it as this device's local session.
            if case .contractError(let status, _, _, let requestId, _, _) = error,
               status == 409,
               let active = try await activeExerciseSession(enrollmentId: enrollmentId) {
                if active.id == recoverableLocalSessionId {
                    return .recovered(session: active, requestId: requestId)
                }
                return .alreadyActive(session: active, requestId: requestId)
            }
            throw error
        }
    }

    func requestAccountDeletionChallenge(
        locale: String
    ) async throws -> ContractAccountDeletionChallenge {
        guard locale == "zh-CN" || locale == "en" else {
            throw RepositoryError.apiError("账户注销语言参数不符合合同。")
        }
        let currentData = try await get("me")
        let current = try decodeContract(ContractCurrentUser.self, from: currentData)
        guard current.user.role == "STUDENT",
              current.user.status == "ACTIVE",
              current.user.version > 0 else {
            throw RepositoryError.apiError("当前账号状态不能发起注销。")
        }
        let data = try await post(
            "me/account-deletion-challenges",
            body: try Self.jsonData([
                "expectedVersion": current.user.version,
                "locale": locale
            ]),
            idempotencyKey: IdempotencyKeyPolicy.make()
        )
        let challenge = try decodeContract(ContractAccountDeletionChallenge.self, from: data)
        guard challenge.mode == "STUDENT_EMAIL_OTP",
              challenge.version > 0,
              !challenge.challengeId.isEmpty else {
            throw RepositoryError.apiError("服务器返回的注销验证方式无效。")
        }
        return challenge
    }

    func confirmAccountDeletion(
        challengeId: String,
        expectedVersion: Int,
        verificationCode: String
    ) async throws -> (result: ContractAccountDeletionResult, credentialsCleared: Bool) {
        let challengeId = try Self.pathComponent(challengeId)
        guard expectedVersion > 0,
              ContactBindingRule.isValidStudentSignInCode(verificationCode) else {
            throw RepositoryError.apiError("请输入 4 到 10 位数字验证码。")
        }
        let data = try await post(
            "me/account-deletion-challenges/\(challengeId)/confirm",
            body: try Self.jsonData([
                "expectedVersion": expectedVersion,
                "verificationCode": verificationCode
            ]),
            idempotencyKey: IdempotencyKeyPolicy.make()
        )
        let result = try decodeContract(ContractAccountDeletionResult.self, from: data)
        guard result.status == "DELETED",
              result.allSessionsRevoked,
              result.newRegistrationRequired else {
            throw RepositoryError.apiError("服务器未确认账户注销与全部会话失效。")
        }
        invalidateInMemorySession()
        let credentialsCleared = clearPersistedAccessToken()
        return (result, credentialsCleared)
    }

    /// Read-only refresh for the cross-device blocking state. This operation
    /// never creates, cancels, transfers or controls a Session.
    func readActiveExerciseSession(
        preferredClassSectionId: String?
    ) async throws -> ExerciseSessionStartOutcome? {
        let enrollmentId = try await resolveActiveEnrollmentID(
            preferredClassSectionId: preferredClassSectionId
        )
        guard let active = try await activeExerciseSession(enrollmentId: enrollmentId) else {
            return nil
        }
        guard active.enrollmentId == enrollmentId else {
            throw RepositoryError.apiError("服务器返回了不属于当前 Enrollment 的运动会话。")
        }
        return .alreadyActive(session: active, requestId: lastContractRequestId)
    }

    func controlExerciseSession(
        sessionId: String,
        action: String,
        clientObservedAt: Date
    ) async throws -> ContractExerciseSession {
        guard ["pause", "resume", "finish"].contains(action) else {
            throw RepositoryError.apiError("不支持的运动会话操作。")
        }
        let current = try await getExerciseSession(sessionId: sessionId)
        let terminalOrMatching = current.status == "COMPLETED" ||
            (action == "pause" && current.status == "PAUSED") ||
            (action == "resume" && current.status == "IN_PROGRESS")
        if terminalOrMatching { return current }
        let body: [String: Any] = [
            "expectedVersion": current.version,
            "clientObservedAt": Self.rfc3339(clientObservedAt)
        ]
        let data = try await post(
            "exercise-sessions/\(try Self.pathComponent(sessionId))/\(action)",
            body: try Self.jsonData(body),
            idempotencyKey: IdempotencyKeyPolicy.make()
        )
        return try decodeContract(ContractExerciseSession.self, from: data)
    }

    /// Cancel is deliberately separate from pause/resume/finish because its
    /// contract body is VersionedReasonRequest rather than SessionControlRequest.
    /// Reading first supplies the exact optimistic-lock version; a repeated
    /// call after an ambiguous response safely recognizes CANCELLED.
    func cancelExerciseSession(
        sessionId: String,
        reason: String
    ) async throws -> ContractExerciseSession {
        let current = try await getExerciseSession(sessionId: sessionId)
        if current.status == "CANCELLED" { return current }
        guard current.status == "IN_PROGRESS" || current.status == "PAUSED" else {
            throw RepositoryError.apiError("当前运动会话状态不允许放弃。")
        }
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedReason.isEmpty else {
            throw RepositoryError.apiError("放弃运动必须提供原因。")
        }
        let data = try await post(
            "exercise-sessions/\(try Self.pathComponent(sessionId))/cancel",
            body: try Self.jsonData([
                "reason": String(normalizedReason.prefix(1000)),
                "expectedVersion": current.version
            ]),
            idempotencyKey: IdempotencyKeyPolicy.make()
        )
        return try decodeContract(ContractExerciseSession.self, from: data)
    }

    func getExerciseSession(sessionId: String) async throws -> ContractExerciseSession {
        let data = try await get("exercise-sessions/\(try Self.pathComponent(sessionId))")
        return try decodeContract(ContractExerciseSession.self, from: data)
    }

    func getExerciseRecordAttemptContext(
        recordId: String
    ) async throws -> ContractExerciseRecordAttemptContext {
        let recordId = try Self.pathComponent(recordId)
        let data = try await get("exercise-records/\(recordId)/attempt-context")
        let context = try decodeContract(ContractExerciseRecordAttemptContext.self, from: data)
        guard context.recordId == recordId, context.attemptNumber >= 1 else {
            throw RepositoryError.apiError("服务器返回了不属于当前记录的补交历史。")
        }
        return context
    }

    /// Authenticated capability read. Hidden routes and missing enum values
    /// fail closed without exposing whether the internal endpoint exists.
    func exerciseTestToolCapabilities() async throws -> Set<String> {
        guard exerciseTestToolsEnabled else { return [] }
        do {
            let data = try await get("internal/test-tools/capabilities")
            let payload = try decodeContract(TestToolCapabilitiesPayload.self, from: data)
            return Set(payload.capabilities.filter {
                $0 == StudentTestToolsConfig.durationAdvanceCapability
            })
        } catch let error as RepositoryError where Self.isNotFound(error) {
            return []
        }
    }

    /// Formal 60-minute operation. Callers install only the authoritative
    /// Session returned by the Backend and never edit a local timestamp.
    func addSixtyMinutesToExerciseSession(
        sessionId: String,
        expectedVersion: Int
    ) async throws -> ContractExerciseSession {
        let sessionId = try Self.pathComponent(sessionId)
        guard expectedVersion > 0 else {
            throw RepositoryError.apiError("运动会话缺少有效的服务端版本。")
        }
        _ = try await post(
            "exercise-sessions/\(sessionId)/add-sixty-minutes",
            body: try Self.jsonData([
                "expectedVersion": expectedVersion,
                "clientObservedAt": ISO8601DateFormatter().string(from: Date())
            ]),
            idempotencyKey: IdempotencyKeyPolicy.make()
        )
        return try await getExerciseSession(sessionId: sessionId)
    }

    func uploadExerciseEvidence(
        attachment: ProofAttachment,
        sessionId: String,
        idempotencyKey: String
    ) async throws -> ProofAttachment {
        try await uploadContractEvidence(
            attachment: attachment,
            businessPurpose: "EXERCISE_RECORD",
            sessionId: sessionId,
            enrollmentId: nil,
            captureSource: "IN_APP_CAMERA",
            idempotencyKey: idempotencyKey,
            bindToSession: true
        )
    }

    func uploadExemptionEvidence(
        attachment: ProofAttachment,
        applicationId: String,
        enrollmentId: String,
        idempotencyKey: String
    ) async throws -> ProofAttachment {
        try await uploadContractEvidence(
            attachment: attachment,
            businessPurpose: "EXEMPTION_APPLICATION",
            sessionId: nil,
            enrollmentId: enrollmentId,
            exemptionApplicationId: applicationId,
            captureSource: attachment.source == "相册" ? "FILE_PICKER" : "IN_APP_CAMERA",
            idempotencyKey: idempotencyKey,
            bindToSession: false
        )
    }

    func submitExerciseRecord(
        sessionId: String,
        previousRecordId: String? = nil,
        creditType: CreditType,
        sportType: ExerciseSportType,
        customSportName: String?,
        description: String,
        mediaIds: [String],
        clientRequestId: String,
        idempotencyKey: String
    ) async throws -> CheckInRecord {
        let session = try await getExerciseSession(sessionId: sessionId)
        guard session.id == sessionId, session.status == "COMPLETED" else {
            throw RepositoryError.apiError("服务端运动会话尚未完成，不能创建打卡记录。")
        }
        guard !mediaIds.isEmpty, Set(mediaIds).count == mediaIds.count else {
            throw RepositoryError.apiError("打卡凭证缺少有效 mediaId。")
        }
        let canonicalSport = Self.contractSport(sportType)
        let normalizedName = customSportName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body: [String: Any] = [
            "sessionId": session.id,
            "creditType": creditType == .courseRelated ? "COURSE_RELATED" : "GENERAL",
            "sportType": canonicalSport,
            "sportName": sportType == .other && normalizedName?.isEmpty == false ? normalizedName! : NSNull(),
            "description": description,
            "clientRequestId": String(clientRequestId.prefix(64))
        ]
        let attemptContext: ContractExerciseRecordAttemptContext?
        var record: ContractExerciseRecord
        if let previousRecordId {
            let previousRecordId = try Self.pathComponent(previousRecordId)
            let previousData = try await get("exercise-records/\(previousRecordId)")
            let previous = try decodeContract(ContractExerciseRecord.self, from: previousData)
            guard previous.id == previousRecordId,
                  previous.status == "REVIEWED",
                  previous.currentReview?.result == "INVALID" else {
                throw RepositoryError.serverError(
                    statusCode: 409,
                    code: "EXERCISE_RECORD_RESUBMISSION_NOT_ALLOWED",
                    message: "Only the latest INVALID attempt can be resubmitted."
                )
            }
            var resubmissionBody = body
            resubmissionBody["expectedVersion"] = previous.version
            let createdData = try await post(
                "exercise-records/\(previousRecordId)/resubmissions",
                body: try Self.jsonData(resubmissionBody),
                idempotencyKey: Self.phaseKey(idempotencyKey, "record-resubmit-create")
            )
            let resubmission = try decodeContract(
                ContractExerciseRecordResubmission.self,
                from: createdData
            )
            guard resubmission.record.sessionId == session.id,
                  resubmission.attemptContext.recordId == resubmission.record.id,
                  resubmission.attemptContext.previousAttemptId == previousRecordId else {
                throw RepositoryError.apiError("服务器返回的补交尝试链与原记录不一致。")
            }
            record = resubmission.record
            attemptContext = resubmission.attemptContext
        } else {
            let createdData = try await post(
                "exercise-records",
                body: try Self.jsonData(body),
                idempotencyKey: Self.phaseKey(idempotencyKey, "record-create")
            )
            record = try decodeContract(ContractExerciseRecord.self, from: createdData)
            attemptContext = nil
        }
        guard record.sessionId == session.id else {
            throw RepositoryError.apiError("服务器返回了不属于当前运动会话的记录。")
        }
        if record.status == "DRAFT" {
            let submitBody: [String: Any] = [
                "mediaIds": mediaIds,
                "expectedVersion": record.version
            ]
            let submittedData = try await post(
                "exercise-records/\(try Self.pathComponent(record.id))/submit",
                body: try Self.jsonData(submitBody),
                idempotencyKey: Self.phaseKey(idempotencyKey, "record-submit")
            )
            record = try decodeContract(ContractExerciseRecord.self, from: submittedData)
        }
        guard record.status == "REVIEWED",
              let reviewResult = record.currentReview?.result,
              ["VALID", "INVALID"].contains(reviewResult) else {
            throw RepositoryError.apiError("服务端未返回已提交的打卡记录。")
        }
        return Self.checkInRecord(
            from: record,
            session: session,
            creditType: creditType,
            attemptContext: attemptContext
        )
    }

    func createExemptionDraft(
        enrollmentId: String,
        item: ExemptionItem,
        reason: String,
        detail: String,
        organization: String,
        idempotencyKey: String
    ) async throws -> ContractExemptionDraftPlan {
        let mapping = try Self.contractExemptionMapping(item)
        let body: [String: Any] = [
            "enrollmentId": enrollmentId,
            "applicationType": mapping.type,
            "applicationSubtype": mapping.subtype,
            "organizationName": mapping.requiresOrganization ? organization : NSNull(),
            "reason": ExemptionInputRule.combinedReason(reason: reason, detail: detail),
            "mediaIds": []
        ]
        let createdData = try await post(
            "exemption-applications",
            body: try Self.jsonData(body),
            idempotencyKey: Self.phaseKey(idempotencyKey, "exemption-create")
        )
        let draft = try decodeContract(ContractExemptionApplication.self, from: createdData)
        guard draft.enrollmentId == enrollmentId, draft.status == "DRAFT" else {
            throw RepositoryError.apiError("服务器未返回当前 Enrollment 的免测草稿。")
        }
        return ContractExemptionDraftPlan(
            applicationId: draft.id,
            enrollmentId: draft.enrollmentId,
            expectedVersion: draft.version
        )
    }

    func updateAndSubmitCreatedExemption(
        applicationId: String,
        item: ExemptionItem,
        reason: String,
        detail: String,
        organization: String,
        preparedExpectedVersion: Int,
        mediaIds: [String],
        idempotencyKey: String
    ) async throws -> ExemptionApplication {
        let applicationId = try Self.pathComponent(applicationId)
        guard preparedExpectedVersion > 0,
              !mediaIds.isEmpty,
              mediaIds.count <= 20,
              Set(mediaIds).count == mediaIds.count else {
            throw RepositoryError.apiError("免测草稿的版本或材料目标不完整。")
        }
        let expectedReason = ExemptionInputRule.combinedReason(reason: reason, detail: detail)
        let currentData = try await get("exemption-applications/\(applicationId)")
        var current = try decodeContract(ContractExemptionApplication.self, from: currentData)
        if current.status == "SUBMITTED" {
            guard current.reason == expectedReason, current.mediaIds == mediaIds else {
                throw RepositoryError.apiError("服务器中的已提交免测申请与本地重试目标不一致。")
            }
            return Self.exemptionApplication(
                from: current,
                item: item,
                reason: reason,
                detail: detail,
                organization: organization
            )
        }
        guard current.status == "DRAFT" else {
            throw RepositoryError.apiError("当前免测申请已不再是可提交草稿。")
        }
        if current.mediaIds != mediaIds || current.reason != expectedReason {
            guard current.version == preparedExpectedVersion else {
                throw RepositoryError.serverError(
                    statusCode: 409,
                    code: "CONFLICT_VERSION_MISMATCH",
                    message: "The exemption draft changed before submission."
                )
            }
            let updatedData = try await patch(
                "exemption-applications/\(applicationId)",
                body: try Self.jsonData([
                    "reason": expectedReason,
                    "mediaIds": mediaIds,
                    "expectedVersion": preparedExpectedVersion
                ]),
                idempotencyKey: Self.phaseKey(idempotencyKey, "exemption-associate-media")
            )
            current = try decodeContract(ContractExemptionApplication.self, from: updatedData)
        }
        guard current.reason == expectedReason, current.mediaIds == mediaIds else {
            throw RepositoryError.apiError("服务器返回的免测草稿与材料目标不一致。")
        }
        try await waitForAvailableMedia(ids: current.mediaIds)
        let submitted = try await submitContractExemption(
            applicationId: current.id,
            expectedVersion: current.version,
            idempotencyKey: Self.phaseKey(idempotencyKey, "exemption-submit")
        )
        return Self.exemptionApplication(
            from: submitted,
            item: item,
            reason: reason,
            detail: detail,
            organization: organization
        )
    }

    func prepareExemptionSupplement(
        applicationId: String,
        newMediaIds: [String]
    ) async throws -> ContractExemptionSupplementPlan {
        let applicationId = try Self.pathComponent(applicationId)
        guard Set(newMediaIds).count == newMediaIds.count else {
            throw RepositoryError.apiError("补充材料包含重复 mediaId。")
        }
        let currentData = try await get("exemption-applications/\(applicationId)")
        let current = try decodeContract(ContractExemptionApplication.self, from: currentData)
        guard current.status == "SUPPLEMENT_REQUIRED" || current.status == "DRAFT" else {
            throw RepositoryError.apiError("当前免测申请状态不允许补充材料。")
        }
        let targetMediaIds = Array(Set(current.mediaIds + newMediaIds)).sorted()
        guard targetMediaIds.count <= 20 else {
            throw RepositoryError.apiError("免测材料数量超过合同上限。")
        }
        return ContractExemptionSupplementPlan(
            applicationId: current.id,
            enrollmentId: current.enrollmentId,
            expectedVersion: current.version,
            mediaIds: targetMediaIds
        )
    }

    func updateAndSubmitExemption(
        application: ExemptionApplication,
        reason: String,
        detail: String,
        preparedExpectedVersion: Int,
        preparedMediaIds: [String],
        idempotencyKey: String
    ) async throws -> ExemptionApplication {
        let applicationId = try Self.pathComponent(application.id)
        guard preparedExpectedVersion > 0,
              !preparedMediaIds.isEmpty,
              preparedMediaIds == Array(Set(preparedMediaIds)).sorted(),
              preparedMediaIds.count <= 20 else {
            throw RepositoryError.apiError("免测补充重试目标不完整，已停止提交。")
        }
        let expectedReason = ExemptionInputRule.combinedReason(reason: reason, detail: detail)
        let currentData = try await get("exemption-applications/\(applicationId)")
        let current = try decodeContract(ContractExemptionApplication.self, from: currentData)

        // The submit response may have been lost after the server committed it.
        // Only an exact projection match can close that journal entry; any other
        // terminal state remains a conflict for the user to inspect.
        if current.status == "SUBMITTED" {
            guard current.reason == expectedReason,
                  current.mediaIds == preparedMediaIds else {
                throw RepositoryError.apiError("服务器中的已提交免测申请与本地重试目标不一致，已停止重复提交。")
            }
            return Self.exemptionApplication(
                from: current,
                item: application.item,
                reason: application.reason,
                detail: expectedReason,
                organization: application.organization
            )
        }
        guard current.status == "SUPPLEMENT_REQUIRED" || current.status == "DRAFT" else {
            throw RepositoryError.apiError("当前免测申请状态不允许补充材料。")
        }
        let body: [String: Any] = [
            "reason": expectedReason,
            "mediaIds": preparedMediaIds,
            "expectedVersion": preparedExpectedVersion
        ]
        let updatedData = try await patch(
            "exemption-applications/\(applicationId)",
            body: try Self.jsonData(body),
            idempotencyKey: Self.phaseKey(idempotencyKey, "exemption-update")
        )
        let updated = try decodeContract(ContractExemptionApplication.self, from: updatedData)
        guard updated.id == current.id,
              updated.reason == expectedReason,
              updated.mediaIds == preparedMediaIds,
              updated.status == "SUPPLEMENT_REQUIRED" || updated.status == "DRAFT" else {
            throw RepositoryError.apiError("服务器返回的免测补充结果与已保存目标不一致。")
        }
        try await waitForAvailableMedia(ids: updated.mediaIds)
        let submitted = try await submitContractExemption(
            applicationId: updated.id,
            expectedVersion: updated.version,
            idempotencyKey: Self.phaseKey(idempotencyKey, "exemption-resubmit")
        )
        guard submitted.status == "SUBMITTED",
              submitted.reason == expectedReason,
              submitted.mediaIds == preparedMediaIds else {
            throw RepositoryError.apiError("服务器未确认完全一致的免测补充提交结果。")
        }
        return Self.exemptionApplication(
            from: submitted,
            item: application.item,
            reason: application.reason,
            detail: ExemptionInputRule.combinedReason(reason: reason, detail: detail),
            organization: application.organization
        )
    }

    func exemptionEnrollmentID(applicationId: String) async throws -> String {
        let applicationId = try Self.pathComponent(applicationId)
        let data = try await get("exemption-applications/\(applicationId)")
        return try decodeContract(ContractExemptionApplication.self, from: data).enrollmentId
    }

    private func activeExerciseSession(enrollmentId: String) async throws -> ContractExerciseSession? {
        let data = try await get(
            "exercise-sessions/active",
            queryItems: [URLQueryItem(name: "enrollmentId", value: enrollmentId)]
        )
        return try decodeContract(ContractExerciseSession?.self, from: data)
    }

    private func decodeContract<Value: Decodable>(
        _ type: Value.Type,
        from data: Data
    ) throws -> Value {
        let envelope = try makeDecoder().decode(ContractEnvelope<Value>.self, from: data)
        lastContractRequestId = envelope.meta.requestId
        return envelope.data
    }

    /// Drains the canonical cursor contract and fails closed if the server
    /// repeats a cursor or exceeds the defensive page ceiling.
    private func getAllContractPages<Value: Decodable & Sendable>(
        _ type: Value.Type,
        path: String,
        queryItems: [URLQueryItem]
    ) async throws -> [Value] {
        let baseQueryItems = queryItems.filter { $0.name != "cursor" }
        var values: [Value] = []
        var cursor: String?
        var seenCursors = Set<String>()

        for _ in 0..<100 {
            var pageQueryItems = baseQueryItems
            if let cursor {
                pageQueryItems.append(URLQueryItem(name: "cursor", value: cursor))
            }
            let data = try await get(path, queryItems: pageQueryItems)
            let envelope = try makeDecoder().decode(ContractEnvelope<[Value]>.self, from: data)
            lastContractRequestId = envelope.meta.requestId
            values.append(contentsOf: envelope.data)

            guard let nextCursor = envelope.meta.pagination?.nextCursor?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !nextCursor.isEmpty else {
                return values
            }
            guard seenCursors.insert(nextCursor).inserted else {
                throw RepositoryError.apiError("服务端返回了重复分页游标，已停止同步。")
            }
            cursor = nextCursor
        }
        throw RepositoryError.apiError("服务端分页超过 100 页安全上限，已停止同步。")
    }

    private func uploadContractEvidence(
        attachment: ProofAttachment,
        businessPurpose: String,
        sessionId: String?,
        enrollmentId: String?,
        exemptionApplicationId: String? = nil,
        captureSource: String,
        idempotencyKey: String,
        bindToSession: Bool
    ) async throws -> ProofAttachment {
        guard attachment.isValidForUpload else {
            throw RepositoryError.apiError("原始凭证文件已不可用，请重新选择。")
        }
        let byteCount: Int
        if let fileURL = attachment.sourceFileURL,
           let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
           values.isRegularFile == true,
           let fileSize = values.fileSize,
           fileSize > 0 {
            byteCount = fileSize
        } else if let bytes = attachment.uploadData, !bytes.isEmpty {
            byteCount = bytes.count
        } else {
            throw RepositoryError.apiError("原始凭证文件已不可用，请重新选择。")
        }

        let mediaType = attachment.type == .video ? "VIDEO" : "IMAGE"
        let declaredMimeType = attachment.mimeType ?? mimeType(for: attachment)
        var initiateBody: [String: Any] = [
            "mediaType": mediaType,
            "mimeType": declaredMimeType,
            "fileSizeBytes": byteCount,
            "captureSource": captureSource
        ]
        if exemptionApplicationId == nil {
            initiateBody["businessPurpose"] = businessPurpose
            if let sessionId { initiateBody["sessionId"] = try Self.pathComponent(sessionId) }
            if let enrollmentId { initiateBody["enrollmentId"] = try Self.pathComponent(enrollmentId) }
        }
        if let digest = attachment.contentDigest,
           digest.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil {
            initiateBody["declaredContentSha256"] = digest.lowercased()
        }
        if attachment.type == .video {
            guard let duration = attachment.durationSeconds, duration > 0 else {
                throw RepositoryError.apiError("视频凭证缺少有效时长。")
            }
            initiateBody["durationSeconds"] = Int(ceil(duration))
        }

        let initiatePath: String
        if let exemptionApplicationId {
            initiatePath = "exemption-applications/\(try Self.pathComponent(exemptionApplicationId))/media-uploads"
        } else {
            initiatePath = "media-uploads"
        }
        let initiatedData = try await post(
            initiatePath,
            body: try Self.jsonData(initiateBody),
            idempotencyKey: Self.phaseKey(idempotencyKey, "media-initiate")
        )
        let initiated = try decodeContract(ContractMediaUploadSession.self, from: initiatedData)
        guard initiated.uploadMethod == "PUT" || initiated.uploadMethod == "POST",
              let uploadURL = URL(string: initiated.uploadUrl),
              Self.isAllowedSignedUploadURL(uploadURL, relativeTo: baseURL) else {
            throw RepositoryError.apiError("服务器返回了无效的私有上传地址。")
        }

        var signedRequest = URLRequest(url: uploadURL, timeoutInterval: StudentServerConfig.requestTimeout)
        signedRequest.httpMethod = initiated.uploadMethod
        initiated.requiredHeaders.forEach {
            signedRequest.setValue($0.value, forHTTPHeaderField: $0.key)
        }
        let signedResponse: URLResponse
        do {
            if let fileURL = attachment.sourceFileURL {
                (_, signedResponse) = try await urlSession.upload(for: signedRequest, fromFile: fileURL)
            } else if let bytes = attachment.uploadData {
                (_, signedResponse) = try await urlSession.upload(for: signedRequest, from: bytes)
            } else {
                throw RepositoryError.apiError("原始凭证文件已不可用，请重新选择。")
            }
        } catch let error as URLError {
            throw mappedNetworkError(error)
        }
        guard let httpResponse = signedResponse as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode),
              let etag = httpResponse.value(forHTTPHeaderField: "ETag"),
              !etag.isEmpty else {
            throw RepositoryError.networkError("凭证上传未得到有效 ETag，请刷新后重试。")
        }

        let uploadSessionId = try Self.pathComponent(initiated.uploadSessionId)
        let confirmedData = try await post(
            "media-uploads/\(uploadSessionId)/confirm",
            body: try Self.jsonData(["etag": etag]),
            idempotencyKey: Self.phaseKey(idempotencyKey, "media-confirm")
        )
        var media = try decodeContract(ContractMediaEvidence.self, from: confirmedData)
        guard media.id == initiated.mediaId,
              media.businessPurpose == businessPurpose,
              media.sessionId == sessionId,
              media.enrollmentId == enrollmentId else {
            throw RepositoryError.apiError("服务器返回了不属于当前业务对象的凭证。")
        }
        if bindToSession {
            guard let sessionId else {
                throw RepositoryError.apiError("运动凭证缺少服务端 sessionId。")
            }
            let boundData = try await post(
                "media/\(try Self.pathComponent(media.id))/bind",
                body: try Self.jsonData([
                    "sessionId": sessionId,
                    "expectedVersion": media.version
                ]),
                idempotencyKey: Self.phaseKey(idempotencyKey, "media-bind")
            )
            media = try decodeContract(ContractMediaEvidence.self, from: boundData)
            media = try await waitForAvailableMedia(id: media.id)
        } else {
            guard ["UPLOADED", "BOUND", "PROCESSING", "AVAILABLE"].contains(media.uploadStatus) else {
                throw RepositoryError.apiError("免测凭证未进入可关联状态，请稍后安全重试。")
            }
        }
        return ProofAttachment(
            id: attachment.id,
            type: attachment.type,
            fileName: attachment.fileName,
            byteCount: byteCount,
            durationSeconds: attachment.durationSeconds,
            thumbnailData: attachment.thumbnailData,
            source: "Backend 2.0.13 media",
            cosKey: media.id,
            mimeType: media.verifiedMimeType ?? media.declaredMimeType,
            contentDigest: media.verifiedContentSha256 ?? attachment.contentDigest
        )
    }

    private func waitForAvailableMedia(ids: [String]) async throws {
        for mediaId in ids {
            _ = try await waitForAvailableMedia(id: mediaId)
        }
    }

    private func waitForAvailableMedia(id: String) async throws -> ContractMediaEvidence {
        let mediaId = try Self.pathComponent(id)
        for attempt in 0..<20 {
            let data = try await get("media/\(mediaId)")
            let media = try decodeContract(ContractMediaEvidence.self, from: data)
            if media.uploadStatus == "AVAILABLE" { return media }
            if media.uploadStatus == "FAILED" {
                throw RepositoryError.serverError(
                    statusCode: 409,
                    code: "MEDIA_NOT_AVAILABLE",
                    message: "Retained media processing failed."
                )
            }
            guard ["UPLOADED", "BOUND", "PROCESSING"].contains(media.uploadStatus) else {
                throw RepositoryError.apiError("凭证状态异常，不能继续提交。")
            }
            if attempt < 19 {
                try await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        throw RepositoryError.serverError(
            statusCode: 409,
            code: "MEDIA_PROCESSING_INCOMPLETE",
            message: "Retained media processing is incomplete."
        )
    }

    private func submitContractExemption(
        applicationId: String,
        expectedVersion: Int,
        idempotencyKey: String
    ) async throws -> ContractExemptionApplication {
        let applicationId = try Self.pathComponent(applicationId)
        let data = try await post(
            "exemption-applications/\(applicationId)/submit",
            body: try Self.jsonData(["expectedVersion": expectedVersion]),
            idempotencyKey: idempotencyKey
        )
        return try decodeContract(ContractExemptionApplication.self, from: data)
    }

    private static func contractSport(_ sport: ExerciseSportType) -> String {
        switch sport {
        case .running: return "RUNNING"
        case .basketball: return "BASKETBALL"
        case .football: return "FOOTBALL"
        case .badminton: return "BADMINTON"
        case .tableTennis: return "TABLE_TENNIS"
        case .swimming: return "SWIMMING"
        case .fitness: return "FITNESS"
        case .cycling: return "CYCLING"
        case .other: return "OTHER"
        }
    }

    private static func contractExemptionMapping(
        _ item: ExemptionItem
    ) throws -> (type: String, subtype: String, requiresOrganization: Bool) {
        switch item {
        case .run800m: return ("PHYSICAL_TEST", "RUN_800M", false)
        case .run1000m: return ("PHYSICAL_TEST", "RUN_1000M", false)
        case .team: return ("EXERCISE_CHECK_IN", "SCHOOL_TEAM", true)
        case .club: return ("EXERCISE_CHECK_IN", "STUDENT_CLUB", true)
        case .enduranceRun, .physicalTest, .singlePhysicalItem:
            throw RepositoryError.apiError("旧免测类型无法唯一映射到 2.0.13 合同，请重新选择具体项目。")
        }
    }

    private static func checkInRecord(
        from record: ContractExerciseRecord,
        session: ContractExerciseSession,
        creditType: CreditType,
        attemptContext: ContractExerciseRecordAttemptContext? = nil
    ) -> CheckInRecord {
        let invalid = record.currentReview?.result == "INVALID"
        return CheckInRecord(
            id: record.id,
            courseId: creditType == .courseRelated ? record.courseId : nil,
            taskTitle: creditType == .courseRelated ? BNBUL10n.text("课程相关运动") : BNBUL10n.text("自主运动"),
            creditType: creditType,
            hours: Double(record.creditedDurationSeconds) / 3600,
            submittedAt: record.submittedAt ?? RecentTimestamp.justNow,
            validity: invalid ? .invalid : .valid,
            invalidReason: invalid ? (record.currentReview?.publicComment ?? record.currentReview?.reasonCode) : nil,
            proofSummary: BNBUL10n.text("凭证已由服务器保存"),
            proofPhotoCount: 0,
            proofVideoCount: 0,
            proofFiles: [],
            note: record.description ?? BNBUL10n.text("学生未填写补充说明。"),
            sportType: record.sportName ?? record.sportType,
            startedAt: session.startedAt,
            endedAt: session.endedAt,
            activeDuration: "\(record.creditedDurationSeconds)",
            attemptContext: attemptContext.map(Self.attemptContext),
            serverVersion: record.version
        )
    }

    /// List projections do not embed ExerciseSession. Preserve only facts the
    /// record contract actually returns instead of manufacturing coordinates or
    /// client-observed timestamps.
    private static func checkInRecord(
        from record: ContractExerciseRecord,
        creditType: CreditType,
        attemptContext: ContractExerciseRecordAttemptContext? = nil
    ) -> CheckInRecord? {
        guard let result = record.currentReview?.result,
              ["VALID", "INVALID"].contains(result) else { return nil }
        let invalid = record.currentReview?.result == "INVALID"
        return CheckInRecord(
            id: record.id,
            courseId: creditType == .courseRelated ? record.courseId : nil,
            taskTitle: creditType == .courseRelated ? BNBUL10n.text("课程相关运动") : BNBUL10n.text("自主运动"),
            creditType: creditType,
            hours: Double(record.creditedDurationSeconds) / 3600,
            submittedAt: record.submittedAt ?? record.businessDate,
            validity: invalid ? .invalid : .valid,
            invalidReason: invalid ? (record.currentReview?.publicComment ?? record.currentReview?.reasonCode) : nil,
            proofSummary: BNBUL10n.text("凭证已由服务器保存"),
            proofPhotoCount: 0,
            proofVideoCount: 0,
            proofFiles: [],
            note: record.description ?? BNBUL10n.text("学生未填写补充说明。"),
            sportType: record.sportName ?? record.sportType,
            startedAt: record.businessDate,
            endedAt: record.submittedAt,
            activeDuration: "\(record.creditedDurationSeconds)",
            attemptContext: attemptContext.map(Self.attemptContext),
            serverVersion: record.version
        )
    }

    private static func attemptContext(
        _ context: ContractExerciseRecordAttemptContext
    ) -> ExerciseRecordAttemptContext {
        ExerciseRecordAttemptContext(
            recordId: context.recordId,
            previousAttemptId: context.previousAttemptId,
            rootAttemptId: context.rootAttemptId,
            attemptNumber: context.attemptNumber
        )
    }

    private static func exemptionItem(
        from application: ContractExemptionApplication
    ) -> ExemptionItem? {
        switch (application.applicationType, application.applicationSubtype) {
        case ("PHYSICAL_TEST", "RUN_800M"): return .run800m
        case ("PHYSICAL_TEST", "RUN_1000M"): return .run1000m
        case ("EXERCISE_CHECK_IN", "SCHOOL_TEAM"): return .team
        case ("EXERCISE_CHECK_IN", "STUDENT_CLUB"): return .club
        default: return nil
        }
    }

    private static func exemptionApplication(
        from application: ContractExemptionApplication,
        item: ExemptionItem,
        reason: String,
        detail: String,
        organization: String
    ) -> ExemptionApplication {
        let status: ExemptionStatus
        switch application.status {
        case "APPROVED": status = .approved
        case "REJECTED": status = .rejected
        case "SUPPLEMENT_REQUIRED": status = .supplementRequired
        default: status = .pending
        }
        let proofs = application.mediaIds.enumerated().map { index, mediaId in
            ProofAttachment(
                id: "server-media-\(index)-\(mediaId)",
                type: .image,
                fileName: "media-\(index + 1)",
                byteCount: nil,
                source: "Backend 2.0.13 media",
                cosKey: mediaId
            )
        }
        return ExemptionApplication(
            id: application.id,
            studentId: application.studentId,
            item: item,
            reason: reason,
            detail: detail,
            organization: application.organizationName ?? organization,
            submittedAt: application.submittedAt ?? RecentTimestamp.justNow,
            status: status,
            proofFiles: proofs,
            teacherFeedback: application.publicComment ?? "",
            updatedAt: application.decidedAt ?? application.submittedAt ?? RecentTimestamp.justNow
        )
    }

    private static func phaseKey(_ base: String, _ phase: String) -> String {
        let suffix = ".\(phase)"
        return String(base.prefix(max(8, 128 - suffix.count))) + suffix
    }

    private static func pathComponent(_ value: String) throws -> String {
        guard value.range(
            of: "^[A-Za-z0-9._:-]{1,64}$",
            options: .regularExpression
        ) != nil else {
            throw RepositoryError.apiError("服务端资源 ID 格式不正确。")
        }
        return value
    }

    private static func percentEncodedPathComponent(_ value: String) throws -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        guard !value.isEmpty,
              let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed),
              !encoded.isEmpty else {
            throw RepositoryError.apiError("课程邀请 token 无法安全写入 URL。")
        }
        return encoded
    }

    private static func jsonData(_ value: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
    }

    private static func rfc3339(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func isAllowedSignedUploadURL(_ url: URL, relativeTo apiURL: URL) -> Bool {
        guard url.user == nil, url.password == nil else { return false }
        if url.scheme?.lowercased() == "https" { return true }
        guard url.scheme?.lowercased() == "http",
              apiURL.scheme?.lowercased() == "http",
              let uploadHost = url.host?.lowercased(),
              let apiHost = apiURL.host?.lowercased() else { return false }
        let loopback = Set(["localhost", "127.0.0.1", "::1"])
        return uploadHost == apiHost || (loopback.contains(uploadHost) && loopback.contains(apiHost))
    }

    func convertEndurance(
        timeSeconds: Int,
        gender: String,
        gradeLevel: String
    ) async throws -> EnduranceScoreResult {
        let normalizedGender = gender.uppercased()
        let normalizedGrade = gradeLevel.uppercased()
        let data = try await post(
            "activity-conversion-rules/preview",
            body: try Self.jsonData([
                "timeSeconds": timeSeconds,
                "gender": normalizedGender,
                "gradeLevel": normalizedGrade
            ]),
            idempotencyKey: nil
        )
        let preview = try decodeContract(ContractActivityConversionPreview.self, from: data)
        return EnduranceScoreResult(
            score: preview.score,
            tier: preview.tier.lowercased(),
            timeSeconds: preview.timeSeconds,
            gender: normalizedGender.lowercased(),
            gradeLevel: normalizedGrade.lowercased(),
            gradeGroup: ["JUNIOR", "SENIOR"].contains(normalizedGrade)
                ? "junior_senior"
                : "freshman_sophomore"
        )
    }

    /// Retained only for internal automated coverage. No student-facing control
    /// calls this endpoint; the production UI uses the formal operation below.
    func advanceExerciseSessionTestDuration(
        sessionId: String,
        expectedVersion: Int
    ) async throws -> ContractExerciseSession {
        let sessionId = try Self.pathComponent(sessionId)
        guard expectedVersion > 0 else {
            throw RepositoryError.apiError("运动会话缺少有效的服务端版本。")
        }
        _ = try await post(
            "internal/test-tools/exercise-sessions/\(sessionId)/advance-duration",
            body: try Self.jsonData(["expectedVersion": expectedVersion]),
            idempotencyKey: IdempotencyKeyPolicy.make()
        )
        return try await getExerciseSession(sessionId: sessionId)
    }

    func markNoticeRead(noticeId: String) async throws {
        let notificationID = try Self.pathComponent(noticeId)
        _ = try await post(
            "notifications/\(notificationID)/read",
            body: nil,
            idempotencyKey: IdempotencyKeyPolicy.make()
        )
    }

    func listCourses() async throws -> [Course] {
        try await loadContractWorkspace().courses
    }

    func listExemptions(
        fallback: [ExemptionApplication] = []
    ) async throws -> [ExemptionApplication] {
        let applications = try await getAllContractPages(
            ContractExemptionApplication.self,
            path: "exemption-applications",
            queryItems: [URLQueryItem(name: "limit", value: "100")]
        )
        return applications.compactMap { application in
                guard let item = Self.exemptionItem(from: application) else { return nil }
                return Self.exemptionApplication(
                    from: application,
                    item: item,
                    reason: application.reason,
                    detail: "",
                    organization: application.organizationName ?? ""
                )
            }
    }

    /// Server release r19 returns explicit business-state errors while the
    /// teacher/admin side has not finished configuring a course. These states
    /// must degrade to an empty module instead of failing the whole workspace.
    private static let notReadyBusinessCodes: Set<String> = [
        "CHECKIN_SETTING_REQUIRED",
        "PUBLISHED_GRADE_RULE_REQUIRED",
        "LEGACY_BUSINESS_REMOVED"
    ]

    private static func isNotFound(_ error: RepositoryError) -> Bool {
        switch error {
        case .httpError(let statusCode):
            return statusCode == 404
        case .serverError(let statusCode, _, _):
            return statusCode == 404
        case .contractError(let statusCode, _, _, _, _, _):
            return statusCode == 404
        default:
            return false
        }
    }

    private func getIfBusinessReady(_ path: String) async throws -> Data? {
        do {
            return try await get(path)
        } catch let error as RepositoryError {
            if case .serverError(_, let code, _) = error,
               let code,
               Self.notReadyBusinessCodes.contains(code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()) {
                return nil
            }
            throw error
        }
    }

    private func loadContractWorkspace() async throws -> StudentWorkspace {
        async let currentUserRequest = get("me")
        async let enrollmentRequest = getAllContractPages(
            ContractEnrollment.self,
            path: "enrollments",
            queryItems: [
                URLQueryItem(name: "status", value: "ACTIVE"),
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "sort", value: "-joinedAt")
            ]
        )
        async let courseRequest = getAllContractPages(
            ContractCourse.self,
            path: "courses",
            queryItems: [URLQueryItem(name: "limit", value: "100")]
        )
        async let sectionRequest = getAllContractPages(
            ContractClassSection.self,
            path: "class-sections",
            queryItems: [URLQueryItem(name: "limit", value: "100")]
        )
        async let semesterRequest = get("semesters/current")
        async let recordRequest = getAllContractPages(
            ContractExerciseRecord.self,
            path: "exercise-records",
            queryItems: [
                URLQueryItem(name: "limit", value: "100"),
                URLQueryItem(name: "sort", value: "-businessDate")
            ]
        )
        let (currentUserData, enrollmentData, courseData, sectionData, semesterData, recordData) = try await (
            currentUserRequest,
            enrollmentRequest,
            courseRequest,
            sectionRequest,
            semesterRequest,
            recordRequest
        )
        let current = try decodeContract(ContractCurrentUser.self, from: currentUserData)
        guard current.user.role == "STUDENT",
              current.user.status == "ACTIVE",
              let contractStudent = current.studentProfile else {
            throw RepositoryError.apiError("当前会话没有 ACTIVE 学生资料。")
        }
        let student = Self.studentProfile(from: contractStudent, user: current.user)
        currentUser = student

        let enrollments = enrollmentData.filter { $0.status == "ACTIVE" }
        let contractCourses = courseData
        let sections = sectionData
        let semester = try decodeContract(ContractSemester.self, from: semesterData)
        let contractRecords = recordData

        let enrollmentSectionIDs = Set(enrollments.map(\.classSectionId))
        let coursesByID = Dictionary(uniqueKeysWithValues: contractCourses.map { ($0.id, $0) })
        let courses = sections
            .filter { enrollmentSectionIDs.contains($0.id) }
            .compactMap { section -> Course? in
                guard let course = coursesByID[section.courseId] else { return nil }
                return Course(
                    id: section.id,
                    code: course.courseCode,
                    section: section.classCode,
                    name: course.courseName,
                    semester: section.semesterId == semester.id ? semester.displayName : section.semesterId,
                    students: 0,
                    pending: 0,
                    completion: 0,
                    missing: 0,
                    deadline: section.submissionDeadlineAt ?? "",
                    teacher: BNBUL10n.text("任课教师"),
                    isCurrent: section.status == "ACTIVE" && section.semesterId == semester.id,
                    enrollmentStatus: .approved,
                    checkInTimeWindow: CheckInTimeWindowPolicy(
                        mode: section.checkInWindowMode,
                        startDate: section.checkInStartDate,
                        endDate: section.checkInEndDate,
                        dailyStartTime: section.dailyStartTime,
                        dailyEndTime: section.dailyEndTime,
                        excludedDates: section.excludedDates,
                        submissionDeadlineAt: section.submissionDeadlineAt
                    )
                )
            }
            .sorted { $0.displayTitle < $1.displayTitle }

        let records = contractRecords.compactMap { record -> CheckInRecord? in
            guard let creditType = CreditType(contractValue: record.creditType) else { return nil }
            return Self.checkInRecord(from: record, creditType: creditType)
        }
        let currentSectionIDs = Set(
            sections
                .filter { $0.semesterId == semester.id }
                .map(\.id)
        )
        let currentEnrollment = enrollments.first { currentSectionIDs.contains($0.classSectionId) }
        // All clients derive the displayed hour progress from the same public
        // fact: current-enrollment records whose latest review is VALID.
        let validRecords = contractRecords.filter {
            $0.enrollmentId == currentEnrollment?.id && $0.currentReview?.result == "VALID"
        }
        let courseSeconds = validRecords
            .filter { CreditType(contractValue: $0.creditType) == .courseRelated }
            .reduce(0) { $0 + $1.creditedDurationSeconds }
        let generalSeconds = validRecords
            .filter { CreditType(contractValue: $0.creditType) == .general }
            .reduce(0) { $0 + $1.creditedDurationSeconds }
        let progress = StudentProgress(
            id: student.id,
            name: student.name,
            college: student.college,
            className: student.className,
            course: Double(courseSeconds) / 3600,
            general: Double(generalSeconds) / 3600,
            rawCourse: Double(courseSeconds) / 3600,
            rawGeneral: Double(generalSeconds) / 3600,
            exam: 0,
            attendance: 0,
            physical: 0,
            status: BNBUL10n.text("已按有效打卡累计"),
            source: "OpenAPI /exercise-records:VALID_SUM",
            organizationCredit: nil,
            authoritativeTotalHours: Double(courseSeconds + generalSeconds) / 3600,
            authoritativeQualificationStatus: nil
        )
        let grades = GradeRow(
            studentId: student.id,
            studentName: student.name,
            checkinScore: 0,
            exam: 0,
            attendance: 0,
            physical: 0,
            total: 0,
            sourceTrace: "OpenAPI 2.0.13：成绩投影未在本次 workspace 合同内",
            missingItems: [BNBUL10n.text("成绩暂未返回")],
            state: .ruleUnpublished
        )
        let exemptions = (try? await listExemptions()) ?? []
        return StudentWorkspace(
            student: student,
            courses: courses,
            progress: progress,
            records: records,
            grades: grades,
            memberships: [],
            notices: [],
            exemptions: exemptions,
            syncOperations: [
                SyncOperation(
                    id: "sync-openapi-2.0.13",
                    type: .resetLocalData,
                    title: BNBUL10n.text("Backend API 同步"),
                    detail: BNBUL10n.text("已读取当前学生、课程关系和运动记录。"),
                    createdAt: RecentTimestamp.justNow,
                    status: .synced
                )
            ],
            hourRule: .unavailable
        )
    }

    private func workspace(
        summary: SportSummaryPayload?,
        student: StudentProfile,
        courses: [Course],
        grades: GradeRow,
        records: [CheckInRecord],
        memberships: [Membership],
        notices: [StudentNotice],
        exemptions: [ExemptionApplication]
    ) -> StudentWorkspace {
        let progressSeed = summary?.progress
        let summaryProgress = progressSeed ?? StudentProgress(
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
            status: summary == nil ? BNBUL10n.text("打卡规则待老师发布") : BNBUL10n.text("等待服务器返回进度"),
            source: summary == nil ? "server:checkin-setting-required" : "server:progress-missing",
            organizationCredit: nil
        )
        var progress = StudentProgress(
            id: student.id,
            name: student.name,
            college: student.college,
            className: student.className,
            course: summaryProgress.course,
            general: summaryProgress.general,
            rawCourse: summaryProgress.rawCourse,
            rawGeneral: summaryProgress.rawGeneral,
            exam: summaryProgress.exam,
            attendance: summaryProgress.attendance,
            physical: summaryProgress.physical,
            status: summaryProgress.status,
            source: summaryProgress.source,
            organizationCredit: summaryProgress.organizationCredit
        )
        if progress.organizationCredit == nil {
            progress.organizationCredit = memberships.first { $0.offset.contains("抵扣") || $0.status.contains("有效") }
        }

        return StudentWorkspace(
            student: student,
            courses: courses,
            progress: progress,
            records: records,
            grades: grades,
            memberships: memberships,
            notices: notices,
            exemptions: exemptions,
            syncOperations: [
                SyncOperation(
                    id: "sync-tencent-cloud-api",
                    type: .resetLocalData,
                    title: "腾讯云 API 同步",
                    detail: "已从 \(baseURL.absoluteString) 聚合学生端数据。",
                    createdAt: RecentTimestamp.justNow,
                    status: .synced
                )
            ],
            hourRule: summary?.hourRule ?? .unavailable
        )
    }

    /// Availability policy from the public `GET /system-mode` projection. A
    /// transient failure keeps the existing fail-open startup behaviour.
    func loadSystemMode() async -> SystemModeStatus {
        guard let data = try? await get("system-mode", authenticated: false) else {
            return SystemModeStatus()
        }
        guard let payload = try? decodeContract(SystemModePayload.self, from: data) else {
            return SystemModeStatus()
        }
        return SystemModeStatus(
            mode: SystemMode.parse(payload.mode)
        )
    }

    /// The Backend compares the numeric iOS build and returns its authoritative
    /// enforcement decision. A missing policy or transient failure remains
    /// fail-open and never invents a client-side version rule.
    func loadUpdateRequirement(
        currentVersion: String = BNBUAppVersion.current,
        currentBuildNumber: Int? = BNBUAppVersion.currentBuildNumber
    ) async -> AppUpdateRequirement? {
        guard let currentBuildNumber, currentBuildNumber > 0 else { return nil }
        guard let data = try? await get(
            "app-release-policy",
            queryItems: [
                URLQueryItem(name: "platform", value: "IOS"),
                URLQueryItem(name: "currentVersion", value: currentVersion),
                URLQueryItem(name: "currentBuildNumber", value: String(currentBuildNumber))
            ],
            authenticated: false
        ),
              let payload = try? decodeContract(AppReleasePolicyPayload.self, from: data),
              payload.platform == "IOS",
              payload.enforcement == "REQUIRED" else {
            return nil
        }
        return AppUpdateRequirement(
            minimumVersion: payload.minimumSupportedVersion,
            downloadURL: payload.downloadUrl ?? "",
            updateMessage: payload.message ?? ""
        )
    }

    /// Help articles an administrator published, in public `GET /help-articles`.
    /// Failures propagate so the help centre can fall back to its cached copy or
    /// offer a retry.
    func loadHelpArticles(
        locale: String = Locale.current.identifier.lowercased().hasPrefix("en") ? "en" : "zh-CN"
    ) async throws -> [HelpArticle] {
        let contractLocale = locale == "en" ? "en" : "zh-CN"
        let data = try await get(
            "help-articles",
            queryItems: [URLQueryItem(name: "locale", value: contractLocale)],
            authenticated: false
        )
        let payload = try decodeContract([HelpArticlePayload].self, from: data)
        return HelpArticle.displayOrdered(
            payload.enumerated().map { index, entry in
                HelpArticle(
                    id: entry.id,
                    title: entry.title,
                    category: entry.category,
                    content: entry.bodyMarkdown,
                    sortOrder: index,
                    updatedAt: entry.publishedAt
                )
            }
        )
    }

    /// Lists the signed-in student's own persisted feedback. Pagination is
    /// drained through the canonical cursor helper, so a repeated cursor fails
    /// closed instead of silently returning a partial list.
    func listFeedback() async throws -> [FeedbackTicket] {
        let payloads = try await getAllContractPages(
            ContractFeedbackPayload.self,
            path: "feedback",
            queryItems: [URLQueryItem(name: "limit", value: "100")]
        )
        return payloads.map(Self.feedbackTicket)
    }

    /// Creates one privacy-bounded feedback item. The request includes only
    /// the fields allowlisted by `CreateFeedbackRequest`; email, phone, logs,
    /// tokens, screenshots and device identifiers are never serialized.
    func createFeedback(
        category: FeedbackCategory,
        content: String
    ) async throws -> FeedbackTicket {
        let normalizedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let validationMessage = FeedbackRule.validationMessage(description: normalizedContent) {
            throw RepositoryError.apiError(validationMessage)
        }
        let body: [String: Any] = [
            "category": category.apiValue,
            "content": normalizedContent,
            "clientContext": [
                "platform": "IOS",
                "appVersion": String(BNBUAppVersion.current.prefix(64)),
                "osVersion": String(ProcessInfo.processInfo.operatingSystemVersionString.prefix(64)),
            ],
        ]
        let data = try await post(
            "feedback",
            body: try Self.jsonData(body),
            idempotencyKey: IdempotencyKeyPolicy.make()
        )
        return Self.feedbackTicket(
            try decodeContract(ContractFeedbackPayload.self, from: data)
        )
    }

    private static func feedbackTicket(_ payload: ContractFeedbackPayload) -> FeedbackTicket {
        FeedbackTicket(
            id: payload.id,
            ticketNumber: "",
            category: FeedbackCategory.title(forAPIValue: payload.category),
            description: payload.content,
            status: FeedbackTicketStatus.parsed(payload.status),
            createdAt: payload.createdAt,
            reply: payload.publicReply
        )
    }

    private func get(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        authenticated: Bool = true
    ) async throws -> Data {
        var request = URLRequest(url: url(for: path, queryItems: queryItems), timeoutInterval: StudentServerConfig.requestTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(Self.makeRequestId(), forHTTPHeaderField: "X-Request-ID")
        if authenticated {
            setAuth(&request)
        }
        return try await perform(request)
    }

    private func post(
        _ path: String,
        body: Data?,
        authenticated: Bool = true,
        idempotencyKey: String? = nil,
        headers: [String: String] = [:]
    ) async throws -> Data {
        var request = URLRequest(url: url(for: path), timeoutInterval: StudentServerConfig.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.makeRequestId(), forHTTPHeaderField: "X-Request-ID")
        request.httpBody = body
        if let idempotencyKey {
            guard IdempotencyKeyPolicy.isValid(idempotencyKey) else {
                throw RepositoryError.apiError("Idempotency-Key 格式不正确。")
            }
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        for (name, value) in headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        if authenticated {
            setAuth(&request)
        }
        return try await perform(request)
    }

    private func patch(
        _ path: String,
        body: Data?,
        idempotencyKey: String? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url(for: path), timeoutInterval: StudentServerConfig.requestTimeout)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.makeRequestId(), forHTTPHeaderField: "X-Request-ID")
        request.httpBody = body
        if let idempotencyKey {
            guard IdempotencyKeyPolicy.isValid(idempotencyKey) else {
                throw RepositoryError.apiError("Idempotency-Key 格式不正确。")
            }
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        setAuth(&request)
        return try await perform(request)
    }

    private func put(_ path: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: url(for: path), timeoutInterval: StudentServerConfig.requestTimeout)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.makeRequestId(), forHTTPHeaderField: "X-Request-ID")
        request.httpBody = body
        setAuth(&request)
        return try await perform(request)
    }

    private func url(for path: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let basePath = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.percentEncodedPath = "/" + [basePath, endpointPath].filter { !$0.isEmpty }.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }

    private func setAuth(_ request: inout URLRequest) {
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
    }

    private static func makeRequestId() -> String {
        "ios-req-\(UUID().uuidString.lowercased())"
    }

    private func perform(_ request: URLRequest, mayRefresh: Bool = true) async throws -> Data {
        let (data, response) = try await networkData(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RepositoryError.networkError("无效的服务器响应")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let failure = try apiError(from: data, statusCode: httpResponse.statusCode)
            let isAuthenticatedRequest = request.value(forHTTPHeaderField: "Authorization") != nil
            if isAuthenticatedRequest,
               mayRefresh,
               contractSession != nil,
               failure.isAccessTokenExpired {
                try await refreshContractSession()
                var retried = request
                setAuth(&retried)
                return try await perform(retried, mayRefresh: false)
            }
            if isAuthenticatedRequest, failure.isTerminalAuthenticationFailure {
                _ = clearSession()
            }
            throw failure
        }

        return data
    }

    private func refreshContractSession() async throws {
        if let refreshTask {
            return try await refreshTask.value
        }
        guard let current = contractSession else { throw RepositoryError.unauthorized }
        let intent = try refreshIntent(for: current)
        let refreshEpoch = authenticationEpoch
        let task = Task {
            try await self.rotateContractSession(
                current,
                intent: intent,
                expectedEpoch: refreshEpoch
            )
        }
        refreshTask = task
        do {
            try await task.value
            refreshTask = nil
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private func rotateContractSession(
        _ current: ContractAuthSession,
        intent: ContractRefreshIntent,
        expectedEpoch: UInt64
    ) async throws {
        var request = URLRequest(
            url: url(for: "auth/refresh"),
            timeoutInterval: StudentServerConfig.requestTimeout
        )
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.makeRequestId(), forHTTPHeaderField: "X-Request-ID")
        request.setValue(intent.idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        request.httpBody = try Self.jsonData(["refreshToken": current.refreshToken])
        let (data, response) = try await networkData(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RepositoryError.networkError("无效的服务器响应")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            let failure = try apiError(from: data, statusCode: httpResponse.statusCode)
            if failure.isTerminalAuthenticationFailure {
                _ = clearSession()
            }
            throw failure
        }
        let rotated = try decodeContract(ContractAuthSession.self, from: data)
        guard expectedEpoch == authenticationEpoch else {
            throw RepositoryError.sessionChanged
        }
        try installContractSession(rotated)
    }

    private func refreshIntent(for current: ContractAuthSession) throws -> ContractRefreshIntent {
        let fingerprint = refreshSessionFingerprint(current)
        do {
            if let persisted = try credentialStore.data(forKey: refreshIntentStorageKey) {
                guard let existing = try? JSONDecoder().decode(ContractRefreshIntent.self, from: persisted),
                      IdempotencyKeyPolicy.isValid(existing.idempotencyKey) else {
                    // A malformed recovery record could represent an already
                    // accepted rotation. Never invent a second key for it.
                    throw RepositoryError.secureStorageUnavailable
                }
                if existing.sessionFingerprint == fingerprint {
                    return existing
                }
                // A successful/new login installed a different refresh token;
                // an intent for that older credential can no longer be replayed.
                try credentialStore.removeData(forKey: refreshIntentStorageKey)
            }
            let intent = ContractRefreshIntent(
                sessionFingerprint: fingerprint,
                idempotencyKey: IdempotencyKeyPolicy.make()
            )
            try credentialStore.set(
                JSONEncoder().encode(intent),
                forKey: refreshIntentStorageKey
            )
            return intent
        } catch let error as RepositoryError {
            throw error
        } catch {
            throw RepositoryError.secureStorageUnavailable
        }
    }

    private func refreshSessionFingerprint(_ session: ContractAuthSession) -> String {
        RemoteMutationFingerprint.make(
            scope: "auth-refresh",
            fields: [
                "serverIdentity": serverIdentity,
                "sessionId": session.sessionId ?? "",
                "organizationId": session.user.organizationId,
                "userId": session.user.id,
                "refreshTokenSha256": ProofContentDigest.sha256(data: Data(session.refreshToken.utf8)),
            ],
            attachments: []
        )
    }

    private func performUpload(
        _ request: URLRequest,
        bodyFileURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> Data {
        let (data, response) = try await networkUpload(
            for: request,
            bodyFileURL: bodyFileURL,
            progressHandler: progressHandler
        )
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RepositoryError.networkError("无效的服务器响应")
        }

        if !(200...299).contains(httpResponse.statusCode) {
            let failure = try apiError(from: data, statusCode: httpResponse.statusCode)
            if request.value(forHTTPHeaderField: "Authorization") != nil,
               failure.isTerminalAuthenticationFailure {
                _ = clearSession()
            }
            throw failure
        }

        return data
    }

    private func decodeEnvelope<T: Decodable>(_ type: T.Type, from data: Data) throws -> APIEnvelope<T> {
        try makeDecoder().decode(APIEnvelope<T>.self, from: data)
    }

    private func decodeFlexible<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        let decoder = makeDecoder()
        if let envelope = try? decoder.decode(APIEnvelope<T>.self, from: data) {
            if envelope.success, let payload = envelope.data {
                return payload
            }
            throw RepositoryError.apiError(envelope.error?.message ?? "服务器返回失败")
        }
        if let wrapper = try? decoder.decode(DataWrapper<T>.self, from: data) {
            return wrapper.data
        }
        return try decoder.decode(T.self, from: data)
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private func apiError(from data: Data, statusCode: Int) throws -> RepositoryError {
        let decoder = makeDecoder()
        if let error = try? decoder.decode(ContractErrorEnvelope.self, from: data) {
            return .contractError(
                statusCode: statusCode,
                code: error.code,
                message: error.message,
                requestId: error.requestId,
                timestamp: error.timestamp,
                details: error.details
            )
        }
        if let envelope = try? decoder.decode(APIEnvelope<EmptyPayload>.self, from: data),
           let error = envelope.error {
            return .serverError(statusCode: statusCode, code: error.code, message: error.message)
        }
        if let error = try? decoder.decode(APIErrorResponse.self, from: data) {
            return .serverError(statusCode: statusCode, code: error.code, message: error.message)
        }
        return .httpError(statusCode)
    }

    private func networkData(for request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch let error as URLError {
            throw mappedNetworkError(error)
        }
    }

    private func networkUpload(
        for request: URLRequest,
        bodyFileURL: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> (Data, URLResponse) {
        let delegate = UploadProgressDelegate(progressHandler: progressHandler)
        do {
            return try await urlSession.upload(
                for: request,
                fromFile: bodyFileURL,
                delegate: delegate
            )
        } catch let error as URLError {
            throw mappedNetworkError(error)
        }
    }

    private func mappedNetworkError(_ error: URLError) -> RepositoryError {
        let message: String
        switch error.code {
        case .timedOut:
            message = BNBUL10n.text("连接服务器超时，请稍后重试")
        case .notConnectedToInternet:
            message = BNBUL10n.text("当前网络不可用，请检查网络连接")
        case .networkConnectionLost:
            message = BNBUL10n.text("网络连接已中断，请先刷新记录确认提交状态")
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            message = BNBUL10n.text("暂时无法连接校园体育服务")
        default:
            // System descriptions can contain host names or local paths. Keep
            // the internal classification generic; the user mapper never
            // exposes the original NSError text.
            message = "NETWORK_OTHER"
        }
        return RepositoryError.networkError(message)
    }

    private func mimeType(for attachment: ProofAttachment) -> String {
        switch attachment.type {
        case .image:
            return "image/jpeg"
        case .video:
            return "video/quicktime"
        }
    }

    private func makeProtectedMultipartBodyFile(
        boundary: String,
        attachment: ProofAttachment
    ) throws -> URL {
        let fileManager = FileManager.default
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(Self.uploadDirectoryName, isDirectory: true)
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete]
        )
        try fileManager.setAttributes(
            [.protectionKey: FileProtectionType.complete],
            ofItemAtPath: directoryURL.path
        )

        let fileURL = directoryURL.appendingPathComponent("multipart-\(UUID().uuidString).body")
        guard fileManager.createFile(
            atPath: fileURL.path,
            contents: nil,
            attributes: [.protectionKey: FileProtectionType.complete]
        ) else {
            throw RepositoryError.networkError("无法准备受保护的上传文件")
        }

        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            let safeFileName = attachment.fileName
                .replacingOccurrences(of: "\r", with: "_")
                .replacingOccurrences(of: "\n", with: "_")
                .replacingOccurrences(of: "\"", with: "_")
                .prefix(160)
            let header = "--\(boundary)\r\n"
                + "Content-Disposition: form-data; name=\"files\"; filename=\"\(safeFileName)\"\r\n"
                + "Content-Type: \(mimeType(for: attachment))\r\n\r\n"
            try handle.write(contentsOf: Data(header.utf8))
            if let sourceFileURL = attachment.sourceFileURL {
                let sourceHandle = try FileHandle(forReadingFrom: sourceFileURL)
                defer { try? sourceHandle.close() }
                while true {
                    let chunk = try sourceHandle.read(upToCount: ProofContentDigest.streamingChunkBytes) ?? Data()
                    guard !chunk.isEmpty else { break }
                    try handle.write(contentsOf: chunk)
                }
            } else if let payload = attachment.uploadData {
                try handle.write(contentsOf: payload)
            } else {
                throw RepositoryError.apiError("原始凭证文件已不可用，请删除该凭证后重新选择。")
            }
            try handle.write(contentsOf: Data("\r\n--\(boundary)--\r\n".utf8))
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: fileURL.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableFileURL = fileURL
            try mutableFileURL.setResourceValues(values)
            return fileURL
        } catch {
            try? fileManager.removeItem(at: fileURL)
            throw error
        }
    }

    private static func removeStaleUploadFiles(fileManager: FileManager = .default) {
        let directoryURL = fileManager.temporaryDirectory
            .appendingPathComponent(uploadDirectoryName, isDirectory: true)
        guard let children = try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }
        for child in children where child.lastPathComponent.hasPrefix("multipart-") {
            try? fileManager.removeItem(at: child)
        }
    }

    private func resolvedCreditType(from value: String) -> CreditType {
        switch value {
        case "course", "courseRelated", "course_related", "课程相关":
            return .courseRelated
        case "organization", "organizationOffset", "organization_offset", "系统抵扣":
            return .organizationOffset
        default:
            return .general
        }
    }

    private func resolvedExemptionItem(from value: String) -> ExemptionItem {
        switch value {
        case "800m", "800M", "800 米", "800米":
            return .run800m
        case "1000m", "1000M", "1000 米", "1000米":
            return .run1000m
        case "endurance_run", "enduranceRun", "800/1000 米耐力跑", "耐力跑免测":
            return .enduranceRun
        case "single_physical_item", "singlePhysicalItem", "体测单项免测", "单项免测":
            return .singlePhysicalItem
        default:
            return .physicalTest
        }
    }

    private func remoteProofAttachments(from proofFiles: [String]) -> [ProofAttachment] {
        proofFiles.enumerated().map { index, source in
            let fileName = source.split(separator: "/").last.map(String.init) ?? "proof-\(index + 1)"
            let lowercased = fileName.lowercased()
            let type: ProofMediaType = lowercased.hasSuffix(".mov") || lowercased.hasSuffix(".mp4") || lowercased.hasSuffix(".m4v") ? .video : .image
            return ProofAttachment(
                id: "remote-proof-\(index)-\(abs(source.hashValue))",
                type: type,
                fileName: fileName,
                byteCount: nil,
                source: source
            )
        }
    }

    private func canonicalProofReference(_ attachment: ProofAttachment) throws -> [String: Any] {
        guard let cosKey = attachment.cosKey, !cosKey.isEmpty else {
            throw RepositoryError.apiError("上传凭证缺少 cosKey，请重新上传后再提交。")
        }
        return [
            "cosKey": cosKey,
            "mediaType": attachment.type == .video ? "video" : "image",
            "mimeType": attachment.mimeType ?? mimeType(for: attachment),
            "size": attachment.byteCount ?? 0
        ]
    }

    private func installSession(accessToken: String, user: StudentProfile) throws {
        guard !accessToken.isEmpty else {
            throw RepositoryError.apiError("登录响应缺少 token")
        }
        do {
            try credentialStore.set(Data(accessToken.utf8), forKey: accessTokenStorageKey)
        } catch {
            self.accessToken = nil
            currentUser = nil
            throw RepositoryError.secureStorageUnavailable
        }
        self.accessToken = accessToken
        currentUser = user
    }

    private func persistentDeviceID() throws -> String {
        if let data = try credentialStore.data(forKey: deviceIDStorageKey),
           let existing = String(data: data, encoding: .utf8),
           !existing.isEmpty,
           existing.count <= 128 {
            return existing
        }
        let generated = "ios-\(UUID().uuidString.lowercased())"
        do {
            try credentialStore.set(Data(generated.utf8), forKey: deviceIDStorageKey)
        } catch {
            throw RepositoryError.secureStorageUnavailable
        }
        return generated
    }

    private static func validInviteToken(_ raw: String) throws -> String {
        let token = CourseJoinCodeRule.normalized(raw)
        if let validationMessage = CourseJoinCodeRule.validationMessage(for: token) {
            throw RepositoryError.apiError(validationMessage)
        }
        return token
    }

    private func loadCurrentStudentProfile() async throws -> StudentProfile {
        let data = try await get("me")
        let current = try decodeContract(ContractCurrentUser.self, from: data)
        guard current.user.role == "STUDENT",
              let student = current.studentProfile else {
            throw RepositoryError.apiError("当前会话没有学生资料。")
        }
        let profile = Self.studentProfile(from: student, user: current.user)
        currentUser = profile
        return profile
    }

    private static func studentProfile(
        from profile: ContractStudentProfile,
        user: ContractUser
    ) -> StudentProfile {
        let gender: StudentGender
        switch profile.gender {
        case "FEMALE": gender = .female
        case "MALE": gender = .male
        default: gender = .unknown
        }
        return StudentProfile(
            id: profile.id,
            studentNumber: profile.studentNumber,
            name: profile.fullName,
            email: user.primaryEmailMasked ?? "",
            college: profile.collegeName ?? "",
            className: profile.administrativeClassName ?? "",
            status: profile.status,
            enrollmentYear: profile.gradeYear,
            gender: gender
        )
    }

    private func installContractSession(_ session: ContractAuthSession) throws {
        guard session.tokenType == "Bearer",
              !session.accessToken.isEmpty,
              !session.refreshToken.isEmpty else {
            throw RepositoryError.apiError("登录响应缺少完整 AuthSession")
        }
        do {
            let encoded = try JSONEncoder().encode(session)
            try credentialStore.set(encoded, forKey: contractSessionStorageKey)
            try credentialStore.set(Data(session.accessToken.utf8), forKey: accessTokenStorageKey)
            try credentialStore.removeData(forKey: refreshIntentStorageKey)
        } catch {
            throw RepositoryError.secureStorageUnavailable
        }
        contractSession = session
        accessToken = session.accessToken
    }

    private func invalidateInMemorySession() {
        authenticationEpoch &+= 1
        refreshTask?.cancel()
        refreshTask = nil
        accessToken = nil
        contractSession = nil
        currentUser = nil
    }

    private func clearPersistedAccessToken() -> Bool {
        do {
            try credentialStore.removeData(forKey: accessTokenStorageKey)
            try credentialStore.removeData(forKey: contractSessionStorageKey)
            try credentialStore.removeData(forKey: refreshIntentStorageKey)
            return true
        } catch {
            return false
        }
    }
}

private struct EmptyPayload: Decodable {}

enum ClientErrorContext: String {
    case login
    case otp
    case join
    case session
    case media
    case record
    case exemption
    case feedback
    case accountDeletion
    case network
    case generic
}

struct UserFacingError: Equatable {
    let code: String
    let title: String
    let message: String
    let action: String
    let requestId: String?
    let retryable: Bool
    var fieldErrors: [String: String] = [:]
    var safeStartedAt: String? = nil
    var safeStatus: String? = nil
    var startedOnCurrentAuthSession: Bool? = nil

    var displayText: String {
        var values = [title, message, action]
        if let requestId {
            values.append(BNBUL10n.text("诊断编号：\(requestId)"))
        }
        return values.joined(separator: "\n")
    }
}

enum ClientErrorMapper {
    static func map(_ error: Error, context: ClientErrorContext = .generic) -> UserFacingError {
        if error is RemoteMutationJournalError {
            return make(
                code: "CLIENT_MUTATION_JOURNAL_WRITE_FAILED",
                title: BNBUL10n.text("无法安全保存待提交操作"),
                message: BNBUL10n.text("设备未能写入本地受保护的重试记录，因此网络提交已停止。"),
                action: BNBUL10n.text("请确认设备已解锁且存储空间充足，然后重试。"),
                retryable: true
            )
        }
        if error is DecodingError {
            return make(
                code: "CLIENT_CONTRACT_DECODE_FAILED",
                title: BNBUL10n.text("暂时无法读取服务器数据"),
                message: BNBUL10n.text("服务器数据格式与当前 App 不一致。"),
                action: BNBUL10n.text("请稍后重试；持续出现时请联系技术支持。"),
                retryable: true
            )
        }
        guard let repositoryError = error as? RepositoryError else {
            return make(
                code: "CLIENT_UNEXPECTED_ERROR",
                title: BNBUL10n.text("操作未完成"),
                message: BNBUL10n.text("App 暂时无法完成这项操作。"),
                action: BNBUL10n.text("请返回后重试；持续出现时请联系技术支持。"),
                retryable: true
            )
        }

        let metadata = metadata(for: repositoryError)
        let code = safeErrorCode(metadata.code, statusCode: metadata.statusCode)
        let requestId = safeRequestId(metadata.requestId)
        let normalizedCode = code

        if normalizedCode == "SESSION_ALREADY_ACTIVE" {
            return applyingSafeDetails(make(
                code: normalizedCode,
                title: BNBUL10n.text("无法开始运动"),
                message: BNBUL10n.text("账号已有一条正在进行中的运动，可能是在另一台设备上创建的。"),
                action: BNBUL10n.text("请回原设备继续或结束运动，然后刷新状态。"),
                requestId: requestId,
                retryable: true
            ), details: metadata.details)
        }
        if normalizedCode == "ACCOUNT_DELETION_ACTIVE_SESSION" {
            return applyingSafeDetails(make(
                code: normalizedCode,
                title: BNBUL10n.text("暂时无法注销账户"),
                message: BNBUL10n.text("账号还有一条正在进行或暂停中的运动。"),
                action: BNBUL10n.text("请先结束或明确放弃该运动，再重新发起注销。"),
                requestId: requestId,
                retryable: true
            ), details: metadata.details)
        }
        if normalizedCode == "ACCOUNT_DELETION_PENDING_REVIEW" {
            return applyingSafeDetails(make(
                code: normalizedCode,
                title: BNBUL10n.text("暂时无法注销账户"),
                message: BNBUL10n.text("账号仍有等待处理的审核事项。"),
                action: BNBUL10n.text("请等待审核完成或联系课程老师后再试。"),
                requestId: requestId,
                retryable: false
            ), details: metadata.details)
        }
        if normalizedCode == "ACCOUNT_DELETION_REAUTH_REQUIRED" {
            return applyingSafeDetails(make(
                code: normalizedCode,
                title: BNBUL10n.text("需要重新验证身份"),
                message: BNBUL10n.text("本次注销验证已过期或不再有效。"),
                action: BNBUL10n.text("请返回并重新获取邮箱验证码。"),
                requestId: requestId,
                retryable: true
            ), details: metadata.details)
        }
        if normalizedCode.contains("MEDIA") &&
            (normalizedCode.contains("PROCESSING") ||
                normalizedCode.contains("NOT_READY") ||
                normalizedCode.contains("INCOMPLETE")) {
            return applyingSafeDetails(make(
                code: normalizedCode,
                title: BNBUL10n.text("凭证仍在处理中"),
                message: BNBUL10n.text("至少一份已保留凭证尚未完成安全校验，当前不能提交记录。"),
                action: BNBUL10n.text("请保留全部凭证并稍后刷新状态。"),
                requestId: requestId,
                retryable: true
            ), details: metadata.details)
        }
        if normalizedCode == "MEDIA_NOT_AVAILABLE" ||
            (normalizedCode.contains("MEDIA") && normalizedCode.contains("FAILED")) {
            return applyingSafeDetails(make(
                code: normalizedCode,
                title: BNBUL10n.text("凭证处理失败"),
                message: BNBUL10n.text("至少一份已保留凭证未能通过处理，记录不能提交。"),
                action: BNBUL10n.text("请保留现场并联系技术支持，提供诊断编号。"),
                requestId: requestId,
                retryable: false
            ), details: metadata.details)
        }
        if normalizedCode.contains("OTP") || normalizedCode.contains("CHALLENGE") {
            return applyingSafeDetails(make(
                code: normalizedCode,
                title: BNBUL10n.text("验证码未通过"),
                message: BNBUL10n.text("验证码无效、已过期或与当前验证请求不匹配。"),
                action: BNBUL10n.text("请重新获取验证码后再试。"),
                requestId: requestId,
                retryable: true
            ), details: metadata.details)
        }

        switch repositoryError {
        case .unauthorized:
            return authenticationError(code: "AUTH_SESSION_REQUIRED", requestId: requestId)
        case .sessionChanged:
            return make(
                code: "CLIENT_SESSION_CHANGED",
                title: BNBUL10n.text("操作已取消"),
                message: BNBUL10n.text("登录账号已发生变化，本次操作没有继续执行。"),
                action: BNBUL10n.text("请确认当前账号后重新操作。"),
                retryable: true
            )
        case .secureStorageUnavailable:
            return make(
                code: "CLIENT_SECURE_STORAGE_UNAVAILABLE",
                title: BNBUL10n.text("无法安全保存登录状态"),
                message: BNBUL10n.text("设备安全存储当前不可用。"),
                action: BNBUL10n.text("请解锁设备并重试。"),
                retryable: true
            )
        case .networkError(let diagnostic):
            let timedOut = diagnostic.localizedCaseInsensitiveContains("timeout") || diagnostic.contains("超时")
            return make(
                code: timedOut ? "NETWORK_TIMEOUT" : "NETWORK_UNAVAILABLE",
                title: timedOut ? BNBUL10n.text("请求超时") : BNBUL10n.text("网络连接失败"),
                message: timedOut
                    ? BNBUL10n.text("服务器没有在限定时间内响应。")
                    : BNBUL10n.text("当前无法连接校园体育服务。"),
                action: BNBUL10n.text("请检查网络后重试；提交类操作请先刷新状态。"),
                retryable: true
            )
        case .httpError, .serverError, .contractError:
            return httpError(
                statusCode: metadata.statusCode ?? 0,
                code: normalizedCode,
                requestId: requestId,
                context: context,
                details: metadata.details
            )
        case .apiError:
            return contextualValidationError(context: context)
        }
    }

    static func safeRequestId(_ value: String?) -> String? {
        guard let value,
              value.range(of: "^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$", options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    static func safeErrorCode(_ value: String?, statusCode: Int?) -> String {
        if let value,
           value.range(of: "^[A-Z][A-Z0-9_]{0,79}$", options: .regularExpression) != nil {
            return value
        }
        if let statusCode, (100...599).contains(statusCode) {
            return "HTTP_\(statusCode)"
        }
        return "UNKNOWN_ERROR"
    }

    private static func metadata(for error: RepositoryError) -> (
        statusCode: Int?, code: String?, requestId: String?, details: SafeContractErrorDetails?
    ) {
        switch error {
        case .httpError(let status): return (status, nil, nil, nil)
        case .serverError(let status, let code, _): return (status, code, nil, nil)
        case .contractError(let status, let code, _, let requestId, _, let details):
            return (status, code, requestId, details)
        default: return (nil, nil, error.requestId, nil)
        }
    }

    private static func httpError(
        statusCode: Int,
        code: String,
        requestId: String?,
        context: ClientErrorContext,
        details: SafeContractErrorDetails?
    ) -> UserFacingError {
        let mapped: UserFacingError
        switch statusCode {
        case 401:
            mapped = authenticationError(code: code, requestId: requestId)
        case 403:
            mapped = make(
                code: code,
                title: BNBUL10n.text("当前操作不被允许"),
                message: BNBUL10n.text("当前账号、角色或资源状态没有执行这项操作的权限。"),
                action: BNBUL10n.text("请刷新状态；如有疑问请联系课程老师。"),
                requestId: requestId,
                retryable: false
            )
        case 408:
            mapped = make(
                code: code,
                title: BNBUL10n.text("请求超时"),
                message: BNBUL10n.text("服务器没有在限定时间内响应。"),
                action: BNBUL10n.text("请先刷新状态，再决定是否重试。"),
                requestId: requestId,
                retryable: true
            )
        case 409:
            mapped = make(
                code: code,
                title: BNBUL10n.text("当前状态已发生变化"),
                message: BNBUL10n.text("服务器上的最新状态与本次操作不一致。"),
                action: BNBUL10n.text("请刷新页面，确认最新状态后再操作。"),
                requestId: requestId,
                retryable: true
            )
        case 422:
            mapped = contextualValidationError(context: context, code: code, requestId: requestId)
        case 429:
            mapped = make(
                code: code,
                title: BNBUL10n.text("操作过于频繁"),
                message: BNBUL10n.text("服务器暂时限制了重复请求。"),
                action: BNBUL10n.text("请稍后再试，不要连续点击提交。"),
                requestId: requestId,
                retryable: true
            )
        case 500...599:
            mapped = make(
                code: code,
                title: BNBUL10n.text("校园体育服务暂时异常"),
                message: BNBUL10n.text("服务端暂时无法完成这项操作。"),
                action: BNBUL10n.text("请稍后重试；提交类操作请先刷新状态。"),
                requestId: requestId,
                retryable: true
            )
        default:
            mapped = make(
                code: code,
                title: BNBUL10n.text("操作未完成"),
                message: BNBUL10n.text("服务器未能接受本次请求。"),
                action: BNBUL10n.text("请检查输入并刷新状态后重试。"),
                requestId: requestId,
                retryable: true
            )
        }
        return applyingSafeDetails(mapped, details: details)
    }

    private static func applyingSafeDetails(
        _ error: UserFacingError,
        details: SafeContractErrorDetails?
    ) -> UserFacingError {
        guard let details else { return error }
        let safeFieldErrors = (details.fieldErrors ?? []).reduce(into: [String: String]()) {
            values, fieldError in
            values[fieldError.field] = BNBUL10n.text("该字段未通过校验，请检查后重试。")
        }
        return UserFacingError(
            code: error.code,
            title: error.title,
            message: error.message,
            action: error.action,
            requestId: error.requestId,
            retryable: details.retryable ?? error.retryable,
            fieldErrors: safeFieldErrors,
            safeStartedAt: details.startedAt,
            safeStatus: details.status,
            startedOnCurrentAuthSession: details.startedOnCurrentAuthSession
        )
    }

    private static func authenticationError(code: String, requestId: String?) -> UserFacingError {
        make(
            code: code,
            title: BNBUL10n.text("需要重新登录"),
            message: BNBUL10n.text("当前登录状态已过期或已失效。"),
            action: BNBUL10n.text("请重新登录后继续。"),
            requestId: requestId,
            retryable: false
        )
    }

    private static func contextualValidationError(
        context: ClientErrorContext,
        code: String = "VALIDATION_FAILED",
        requestId: String? = nil
    ) -> UserFacingError {
        let subject: String
        switch context {
        case .login, .otp: subject = BNBUL10n.text("登录信息")
        case .join: subject = BNBUL10n.text("入班信息")
        case .session: subject = BNBUL10n.text("运动状态")
        case .media: subject = BNBUL10n.text("凭证")
        case .record: subject = BNBUL10n.text("运动记录")
        case .exemption: subject = BNBUL10n.text("免测申请")
        case .feedback: subject = BNBUL10n.text("反馈内容")
        case .accountDeletion: subject = BNBUL10n.text("账户注销信息")
        case .network, .generic: subject = BNBUL10n.text("提交内容")
        }
        return make(
            code: code,
            title: BNBUL10n.text("请检查\(subject)"),
            message: BNBUL10n.text("\(subject)未通过服务器校验。"),
            action: BNBUL10n.text("请检查页面提示和最新状态后重试。"),
            requestId: requestId,
            retryable: false
        )
    }

    private static func make(
        code: String,
        title: String,
        message: String,
        action: String,
        requestId: String? = nil,
        retryable: Bool
    ) -> UserFacingError {
        UserFacingError(
            code: code,
            title: title,
            message: message,
            action: action,
            requestId: requestId,
            retryable: retryable
        )
    }
}

enum SafeClientLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "edu.bnbu.student.mvp",
        category: "client-error"
    )

    /// Logs only an allowlist of diagnostic metadata. Error descriptions,
    /// tokens, OTP values, passwords, email addresses, student numbers and
    /// local file paths are deliberately excluded.
    static func record(
        _ error: Error,
        context: ClientErrorContext,
        userError: UserFacingError
    ) {
        let errorType = String(describing: type(of: error))
        let requestId = userError.requestId ?? "none"
        logger.error(
            "category=\(context.rawValue, privacy: .public) code=\(userError.code, privacy: .public) requestId=\(requestId, privacy: .public) retryable=\(userError.retryable, privacy: .public) errorType=\(errorType, privacy: .public)"
        )
    }
}

enum RepositoryError: Error, LocalizedError {
    case unauthorized
    case sessionChanged
    case secureStorageUnavailable
    case networkError(String)
    case httpError(Int)
    case apiError(String)
    case serverError(statusCode: Int, code: String?, message: String)
    case contractError(
        statusCode: Int,
        code: String,
        message: String,
        requestId: String,
        timestamp: String,
        details: SafeContractErrorDetails?
    )

    var requestId: String? {
        if case .contractError(_, _, _, let requestId, _, _) = self { return requestId }
        return nil
    }

    /// A protected request may refresh only for this exact contract signal.
    /// Other 401 responses can describe malformed credentials, revoked
    /// sessions, verification challenges, or an incomplete proxy response.
    var isAccessTokenExpired: Bool {
        switch self {
        case .contractError(let statusCode, let code, _, _, _, _):
            return statusCode == 401 && code == "AUTH_TOKEN_EXPIRED"
        case .serverError(let statusCode, let code, _):
            return statusCode == 401 && code == "AUTH_TOKEN_EXPIRED"
        default:
            return false
        }
    }

    /// Only explicit canonical auth failures are allowed to destroy a local
    /// session. Transport failures, response loss, throttling, conflicts and
    /// server errors all retain both the session and its refresh intent.
    var isTerminalAuthenticationFailure: Bool {
        switch self {
        case .unauthorized:
            return true
        case .contractError(let statusCode, let code, _, _, _, _):
            return Self.isTerminalAuthenticationFailure(statusCode: statusCode, code: code)
        case .serverError(let statusCode, let code, _):
            return Self.isTerminalAuthenticationFailure(statusCode: statusCode, code: code)
        default:
            return false
        }
    }

    private static func isTerminalAuthenticationFailure(statusCode: Int, code: String?) -> Bool {
        let normalizedCode = code?.uppercased() ?? ""
        if statusCode == 403 {
            return normalizedCode == "AUTH_ACCOUNT_DISABLED"
        }
        guard statusCode == 401 else { return false }
        return [
            "AUTH_CREDENTIAL_INVALID",
            "AUTH_TOKEN_INVALID",
            "AUTH_SESSION_REVOKED",
        ].contains(normalizedCode)
    }

    var isAmbiguousMutationFailure: Bool {
        switch self {
        case .networkError:
            return true
        case .httpError(let statusCode):
            return (500...599).contains(statusCode) || [408, 425, 429].contains(statusCode)
        case .serverError(let statusCode, let code, _):
            let normalizedCode = code?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased() ?? ""
            return (500...599).contains(statusCode) ||
                [408, 425, 429].contains(statusCode) ||
                (statusCode == 409 && normalizedCode.hasPrefix("IDEMPOTENCY_"))
        case .contractError(let statusCode, let code, _, _, _, _):
            return (500...599).contains(statusCode) ||
                [408, 425, 429].contains(statusCode) ||
                (statusCode == 409 && code.uppercased().hasPrefix("IDEMPOTENCY_"))
        case .apiError(let message):
            return message.localizedCaseInsensitiveContains("processing") ||
                message.localizedCaseInsensitiveContains("idempotency conflict") ||
                message.contains("处理中")
        case .unauthorized, .sessionChanged, .secureStorageUnavailable:
            return false
        }
    }

    var errorDescription: String? {
        ClientErrorMapper.map(self).displayText
    }
}
