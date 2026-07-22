import Foundation

enum StudentServerConfig {
    static let testBaseURL = URL(string: "http://123.207.5.70:82/api/v1")!
    static let productionBaseURL = URL(string: "https://configuration-required.invalid/api/v1")!
    static let localDevelopmentBaseURL = URL(string: "http://127.0.0.1:8080/api/v1")!
    static let requestTimeout: TimeInterval = 60

    #if DEBUG
    static let defaultBaseURL = testBaseURL
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

struct APIErrorResponse: Decodable {
    let code: String?
    let message: String
}

struct APIEnvelope<T: Decodable>: Decodable {
    let success: Bool
    let data: T?
    let error: APIErrorResponse?
}

struct LoginPayload: Decodable {
    let accessToken: String
    let user: StudentProfile
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
                missingItems: ["成绩暂未返回"]
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

    enum CodingKeys: String, CodingKey {
        case student
        case profile
        case user
        case progress
        case summary
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
        exemptions = (try? container.decodeIfPresent([ExemptionApplication].self, forKey: .exemptions))
            ?? (try? container.decodeIfPresent([ExemptionApplication].self, forKey: .applications))
            ?? (try? container.decodeIfPresent([ExemptionApplication].self, forKey: .items))
            ?? (try? container.decodeIfPresent([ExemptionApplication].self, forKey: .list))
            ?? (try? container.decodeIfPresent([ExemptionApplication].self, forKey: .data))
            ?? []
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
            sourceTrace: grades.compactMap(\.sourceTrace).first ?? "API: /student/grades",
            missingItems: grades.isEmpty ? ["成绩尚未录入"] : []
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
    private var accessToken: String?
    private var currentUser: StudentProfile?
    private var authenticationEpoch: UInt64 = 0

    private let accessTokenStorageKey: String

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

    static func legacyAccessTokenDefaultsKey(for baseURL: URL) -> String {
        "bnbu.remote.accessToken.v1.\(tokenStorageSuffix(for: baseURL))"
    }

    init(
        baseURL: URL = StudentServerConfig.resolvedBaseURL(),
        credentialStore: any SecureCredentialStoring = KeychainCredentialStore(),
        urlSession: URLSession = .shared,
        legacyDefaults: UserDefaults = .standard
    ) {
        Self.removeStaleUploadFiles()
        ProofTransientFileStore.removeStaleCopies()
        self.baseURL = baseURL
        self.serverIdentity = baseURL.absoluteString
        self.credentialStore = credentialStore
        self.urlSession = urlSession
        let storageKey = Self.accessTokenKey(for: baseURL)
        accessTokenStorageKey = storageKey

        let storedCredential: Data?
        do {
            storedCredential = try credentialStore.data(forKey: storageKey)
        } catch {
            storedCredential = nil
        }
        if let secureData = storedCredential,
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

    func login(account: String, password: String) async throws -> StudentProfile {
        authenticationEpoch &+= 1
        let loginEpoch = authenticationEpoch
        let body = try JSONSerialization.data(withJSONObject: [
            "account": account,
            "password": password,
            "role": "student",
            "clientType": "mobile"
        ])
        let data = try await post("auth/login", body: body, authenticated: false)
        guard loginEpoch == authenticationEpoch else {
            throw RepositoryError.sessionChanged
        }

        if let payload = try? decodeFlexible(LoginPayload.self, from: data) {
            try installSession(accessToken: payload.accessToken, user: payload.user)
            return payload.user
        }

        let payload = try decodeFlexible(ServerLoginPayload.self, from: data)
        guard let token = payload.accessToken ?? payload.token else {
            throw RepositoryError.apiError("登录响应缺少 token")
        }
        let user = payload.user ?? StudentProfile(
            id: account,
            name: "BNBU Student",
            email: account.contains("@") ? account : "",
            college: "BNBU",
            className: "",
            status: payload.defaultRoute ?? "正常"
        )
        try installSession(accessToken: token, user: user)
        return user
    }

    /// Frozen API v1 issues a short-lived access token and has no server-side
    /// session/revocation endpoint. Logout therefore performs no network request.
    @discardableResult
    func logout() -> Bool {
        invalidateInMemorySession()
        return clearPersistedAccessToken()
    }

    @discardableResult
    func clearSession() -> Bool {
        invalidateInMemorySession()
        return clearPersistedAccessToken()
    }

    func loadWorkspace() async throws -> StudentWorkspace {
        do {
            return try await loadSportsWorkspace()
        } catch RepositoryError.httpError(let code) where code == 404 {
            return try await loadLegacyWorkspace()
        } catch RepositoryError.serverError(let statusCode, _, let message)
            where statusCode == 404 && (
                message.localizedCaseInsensitiveContains("not found") ||
                message.contains("未找到") ||
                message.contains("不存在")
            ) {
            return try await loadLegacyWorkspace()
        } catch RepositoryError.apiError(let message)
            where message.localizedCaseInsensitiveContains("not found") ||
                message.contains("未找到") ||
                message.contains("不存在") {
            return try await loadLegacyWorkspace()
        } catch {
            throw error
        }
    }

    func submitCheckIn(
        courseId: String?,
        creditType: String,
        taskTitle: String,
        hours: Double,
        note: String,
        sportType: String? = nil,
        proofFiles: [ProofAttachment] = [],
        idempotencyKey: String? = nil
    ) async throws -> CheckInRecord {
        if let inputMessage = CheckInInputRule.validationMessage(note: note) {
            throw RepositoryError.apiError(inputMessage)
        }
        let proofReferences = try proofFiles.map(canonicalProofReference)
        var body: [String: Any] = [
            "creditType": creditType,
            "hours": hours,
            "description": note,
            "proofFiles": proofReferences
        ]
        if let courseId, !courseId.isEmpty {
            body["courseId"] = courseId
        }
        if let sportType, !sportType.isEmpty {
            body["sportType"] = sportType
        }
        let data = try await post(
            "sport/records",
            body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
            idempotencyKey: idempotencyKey
        )
        if let record = try? decodeFlexible(CheckInRecord.self, from: data),
           record.representsCompleteServerRecord {
            return record
        }
        let identifier = try? decodeFlexible(RecordIdentifierPayload.self, from: data)
        return CheckInRecord(
            id: identifier?.id ?? identifier?.recordId ?? UUID().uuidString,
            courseId: courseId,
            taskTitle: taskTitle,
            creditType: resolvedCreditType(from: creditType),
            hours: hours,
            submittedAt: "刚刚",
            validity: .valid,
            proofSummary: proofFiles.isEmpty ? "未添加凭证" : "\(proofFiles.count) 个凭证",
            proofPhotoCount: 0,
            proofVideoCount: 0,
            proofFiles: [],
            note: note,
            sportType: sportType
        )
    }

    func convertEndurance(
        timeSeconds: Int,
        gender: String,
        gradeLevel: String
    ) async throws -> EnduranceScoreResult {
        let body: [String: Any] = [
            "timeSeconds": timeSeconds,
            "gender": gender,
            "gradeLevel": gradeLevel
        ]
        let data = try await post(
            "scoring/convert-endurance",
            body: try JSONSerialization.data(withJSONObject: body)
        )
        return try decodeFlexible(EnduranceScoreResult.self, from: data)
    }

    func uploadProof(
        attachment: ProofAttachment,
        progressHandler: @escaping @Sendable (Double) -> Void = { _ in }
    ) async throws -> ProofAttachment? {
        guard attachment.uploadData != nil || attachment.sourceFileURL != nil else {
            throw RepositoryError.apiError("原始凭证文件已不可用，请删除该凭证后重新选择。")
        }

        return try await uploadProof(
            path: "upload/proof",
            attachment: attachment,
            progressHandler: progressHandler
        )
    }

    private func uploadProof(
        path: String,
        attachment: ProofAttachment,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> ProofAttachment? {
        let boundary = UUID().uuidString
        var request = URLRequest(url: url(for: path), timeoutInterval: StudentServerConfig.requestTimeout)
        request.httpMethod = "POST"
        setAuth(&request)
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        let bodyFileURL = try makeProtectedMultipartBodyFile(
            boundary: boundary,
            attachment: attachment
        )
        defer { try? FileManager.default.removeItem(at: bodyFileURL) }

        let data = try await performUpload(request, bodyFileURL: bodyFileURL, progressHandler: progressHandler)
        if let upload = try? decodeFlexible(ProofUploadPayload.self, from: data),
           upload.remoteSource != nil {
            return upload.attachment(fallback: attachment)
        }
        if let uploadedAttachment = try? decodeFlexible(ProofAttachment.self, from: data),
           uploadedAttachment.source != "服务器" {
            return uploadedAttachment
        }
        throw RepositoryError.apiError("服务器上传响应缺少文件 URL")
    }

    func submitExemption(
        item: String,
        reason: String,
        detail: String,
        proofFiles: [String] = [],
        idempotencyKey: String? = nil
    ) async throws -> ExemptionApplication {
        if let inputMessage = ExemptionInputRule.validationMessage(reason: reason, detail: detail) {
            throw RepositoryError.apiError(inputMessage)
        }
        let combinedReason = ExemptionInputRule.combinedReason(reason: reason, detail: detail)
        let body: [String: Any] = [
            "type": item,
            "reason": combinedReason,
            "proofFiles": proofFiles,
            "organization": NSNull()
        ]
        let data = try await post(
            "student/physical-test-exemptions",
            body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
            idempotencyKey: idempotencyKey
        )
        if let application = try? decodeFlexible(ExemptionApplication.self, from: data),
           application.representsCompleteServerApplication {
            return application
        }
        let identifier = try? decodeFlexible(ExemptionIdentifierPayload.self, from: data)
        return ExemptionApplication(
            id: identifier?.id ?? identifier?.exemptionId ?? identifier?.applicationId ?? UUID().uuidString,
            studentId: "",
            item: resolvedExemptionItem(from: item),
            reason: reason,
            detail: detail,
            submittedAt: "刚刚",
            status: .pending,
            proofFiles: remoteProofAttachments(from: proofFiles),
            teacherFeedback: "免测申请已提交到服务器，等待老师审核。",
            updatedAt: "刚刚"
        )
    }

    func supplementExemption(
        application: ExemptionApplication,
        reason: String,
        proofFiles: [String] = [],
        idempotencyKey: String? = nil
    ) async throws -> ExemptionApplication {
        let normalizedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedReason.count >= ExemptionInputRule.minimumReasonLength,
              normalizedReason.count <= ExemptionInputRule.maximumCombinedReasonLength else {
            throw RepositoryError.apiError("补充说明需要 2 到 2000 个字符。")
        }
        let body: [String: Any] = [
            "reason": normalizedReason,
            "proofFiles": proofFiles,
            "organization": NSNull()
        ]
        let data = try await post(
            "student/physical-test-exemptions/\(application.id)/supplements",
            body: try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]),
            idempotencyKey: idempotencyKey
        )
        if let supplemented = try? decodeFlexible(ExemptionApplication.self, from: data),
           supplemented.representsCompleteServerApplication {
            return supplemented
        }
        let identifier = try? decodeFlexible(ExemptionIdentifierPayload.self, from: data)
        return ExemptionApplication(
            id: identifier?.id ?? identifier?.exemptionId ?? identifier?.applicationId ?? application.id,
            studentId: application.studentId,
            item: application.item,
            reason: application.reason,
            detail: normalizedReason,
            submittedAt: application.submittedAt,
            status: .pending,
            proofFiles: remoteProofAttachments(from: proofFiles),
            teacherFeedback: "补充材料已提交到服务器，等待老师复审。",
            reviewer: application.reviewer,
            updatedAt: "刚刚"
        )
    }

    func markNoticeRead(noticeId: String) async throws {
        _ = try await put("common/notifications/\(noticeId)/read", body: nil)
    }

    func listCourses() async throws -> [Course] {
        let data = try await get("student/courses")
        return try decodeFlexible(StudentCoursesPayload.self, from: data).models()
    }

    /// Server release r19 returns explicit business-state errors while the
    /// teacher/admin side has not finished configuring a course. These states
    /// must degrade to an empty module instead of failing the whole workspace.
    private static let notReadyBusinessCodes: Set<String> = [
        "CHECKIN_SETTING_REQUIRED",
        "PUBLISHED_GRADE_RULE_REQUIRED",
        "LEGACY_BUSINESS_REMOVED"
    ]

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

    private func loadSportsWorkspace() async throws -> StudentWorkspace {
        async let summaryRequest = getIfBusinessReady("sport/summary")
        async let profileRequest = get("student/profile")
        async let coursesRequest = get("student/courses")
        async let gradesRequest = getIfBusinessReady("student/grades")
        async let recordsRequest = get("sport/records")

        let (summaryData, profileData, coursesData, gradesData, recordsData) = try await (
            summaryRequest,
            profileRequest,
            coursesRequest,
            gradesRequest,
            recordsRequest
        )
        let summary = try summaryData.map { try decodeFlexible(SportSummaryPayload.self, from: $0) }
        let student = try decodeFlexible(StudentProfile.self, from: profileData)
        var courses = try decodeFlexible(StudentCoursesPayload.self, from: coursesData).models()
        let grades = try gradesData.map { try decodeFlexible(StudentGradesPayload.self, from: $0).model(for: student) }
            ?? GradeRow(
                studentId: student.id,
                studentName: student.name,
                checkinScore: 0,
                exam: 0,
                attendance: 0,
                physical: 0,
                total: 0,
                sourceTrace: "服务器：成绩规则尚未发布",
                missingItems: ["成绩规则尚未发布"]
            )
        let records = try decodeFlexible(SportRecordsPayload.self, from: recordsData).records

        for index in courses.indices {
            if courses[index].teacher.isEmpty,
               let summaryCourse = summary?.courses.first(where: { $0.id == courses[index].id }) {
                courses[index].teacher = summaryCourse.teacher
            }
        }

        var memberships = summary?.memberships ?? []
        if let identityData = try? await get("sport/identity"),
           let identityPayload = try? decodeFlexible(SportIdentityPayload.self, from: identityData) {
            memberships = identityPayload.memberships
        }

        var notices = summary?.notices ?? []
        if let noticesData = try? await get("common/notifications"),
           let noticesPayload = try? decodeFlexible(NoticesPayload.self, from: noticesData) {
            notices = noticesPayload.notices
        }

        var exemptions = summary?.exemptions ?? []
        if let exemptionsData = try? await get("student/physical-test-exemptions"),
           let exemptionsPayload = try? decodeFlexible(ExemptionsPayload.self, from: exemptionsData) {
            exemptions = exemptionsPayload.exemptions
        }

        return workspace(
            summary: summary,
            student: student,
            courses: courses,
            grades: grades,
            records: records,
            memberships: memberships,
            notices: notices,
            exemptions: exemptions
        )
    }

    private func loadLegacyWorkspace() async throws -> StudentWorkspace {
        let data = try await get("student/workspace")
        let payload = try decodeFlexible(WorkspacePayload.self, from: data)
        return payload.workspace()
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
            rawGeneral: 0,
            exam: 0,
            attendance: 0,
            physical: 0,
            status: summary == nil ? "打卡规则待老师发布" : "等待服务器返回进度",
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
                    createdAt: "刚刚",
                    status: .synced
                )
            ]
        )
    }

    private func get(_ path: String, queryItems: [URLQueryItem] = []) async throws -> Data {
        var request = URLRequest(url: url(for: path, queryItems: queryItems), timeoutInterval: StudentServerConfig.requestTimeout)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        setAuth(&request)
        return try await perform(request)
    }

    private func post(
        _ path: String,
        body: Data?,
        authenticated: Bool = true,
        idempotencyKey: String? = nil
    ) async throws -> Data {
        var request = URLRequest(url: url(for: path), timeoutInterval: StudentServerConfig.requestTimeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        if let idempotencyKey {
            guard IdempotencyKeyPolicy.isValid(idempotencyKey) else {
                throw RepositoryError.apiError("Idempotency-Key 格式不正确。")
            }
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if authenticated {
            setAuth(&request)
        }
        return try await perform(request)
    }

    private func patch(_ path: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: url(for: path), timeoutInterval: StudentServerConfig.requestTimeout)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        setAuth(&request)
        return try await perform(request)
    }

    private func put(_ path: String, body: Data?) async throws -> Data {
        var request = URLRequest(url: url(for: path), timeoutInterval: StudentServerConfig.requestTimeout)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        setAuth(&request)
        return try await perform(request)
    }

    private func url(for path: String, queryItems: [URLQueryItem] = []) -> URL {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)!
        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components.path = "/" + [basePath, endpointPath].filter { !$0.isEmpty }.joined(separator: "/")
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        return components.url!
    }

    private func setAuth(_ request: inout URLRequest) {
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await networkData(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw RepositoryError.networkError("无效的服务器响应")
        }

        if httpResponse.statusCode == 401, request.value(forHTTPHeaderField: "Authorization") != nil {
            _ = clearSession()
            throw RepositoryError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw try apiError(from: data, statusCode: httpResponse.statusCode)
        }

        return data
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

        if httpResponse.statusCode == 401, request.value(forHTTPHeaderField: "Authorization") != nil {
            _ = clearSession()
            throw RepositoryError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw try apiError(from: data, statusCode: httpResponse.statusCode)
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
            message = "连接服务器超时，请稍后重试"
        case .notConnectedToInternet:
            message = "当前网络不可用，请检查网络连接"
        case .networkConnectionLost:
            message = "网络连接已中断，请先刷新记录确认提交状态"
        case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            message = "暂时无法连接校园体育服务"
        default:
            message = error.localizedDescription
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

    private func invalidateInMemorySession() {
        authenticationEpoch &+= 1
        accessToken = nil
        currentUser = nil
    }

    private func clearPersistedAccessToken() -> Bool {
        do {
            try credentialStore.removeData(forKey: accessTokenStorageKey)
            return true
        } catch {
            return false
        }
    }
}

private struct EmptyPayload: Decodable {}

enum RepositoryError: Error, LocalizedError {
    case unauthorized
    case sessionChanged
    case secureStorageUnavailable
    case networkError(String)
    case httpError(Int)
    case apiError(String)
    case serverError(statusCode: Int, code: String?, message: String)

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
        case .apiError(let message):
            return message.localizedCaseInsensitiveContains("processing") ||
                message.localizedCaseInsensitiveContains("idempotency conflict") ||
                message.contains("处理中")
        case .unauthorized, .sessionChanged, .secureStorageUnavailable:
            return false
        }
    }

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "登录已过期，请重新登录"
        case .sessionChanged:
            return "登录操作已取消"
        case .secureStorageUnavailable:
            return "无法安全保存登录状态，请解锁设备并重试。"
        case .networkError(let message):
            return "网络错误：\(message)"
        case .httpError(let code):
            return StudentFacingErrorMessage.httpStatus(code)
        case .apiError(let message):
            return StudentFacingErrorMessage.api(message)
        case .serverError(_, _, let message):
            return StudentFacingErrorMessage.api(message)
        }
    }
}

private enum StudentFacingErrorMessage {
    static func httpStatus(_ code: Int) -> String {
        switch code {
        case 400:
            return "提交内容不完整或格式不正确，请检查后重试。"
        case 401:
            return "登录已过期，请重新登录。"
        case 403:
            return "当前账号无权执行此操作，请联系课程老师。"
        case 404:
            return "请求的数据或服务暂不可用，请刷新后重试。"
        case 408:
            return "请求超时，请检查网络后重试。"
        case 409:
            return duplicateSubmission
        case 413:
            return oversizedFile
        case 422:
            return "提交内容未通过校验，请确认任务状态、时间范围和凭证要求。"
        case 429:
            return "操作过于频繁，请稍后再试。"
        case 500...599:
            return "校园体育服务暂时异常，请稍后重试。"
        default:
            return "服务器错误（\(code)），请稍后重试。"
        }
    }

    static func api(_ message: String) -> String {
        let normalized = message.lowercased()

        if containsAny(normalized, values: [
            "duplicate", "already submitted", "once per day", "重复", "已提交过", "每天一次", "每日一次"
        ]) {
            return duplicateSubmission
        }
        if containsAny(normalized, values: [
            "not started", "outside", "expired", "deadline", "date range", "未开始", "已结束", "已截止", "时间范围", "超出打卡"
        ]) {
            return "当前不在任务允许的打卡时间内，请刷新任务并确认开始和截止时间。"
        }
        if containsAny(normalized, values: [
            "payload too large", "file too large", "exceeds", "文件过大", "超过文件", "超过上传"
        ]) {
            return oversizedFile
        }
        if containsAny(normalized, values: [
            "unauthorized", "token expired", "未授权", "登录过期"
        ]) {
            return "登录已过期，请重新登录。"
        }
        return "服务器未能处理该请求，请检查提交内容或稍后重试。"
    }

    private static let duplicateSubmission = "今天已提交过该任务。请先刷新打卡记录，勿重复提交。"
    private static let oversizedFile = "凭证文件超过服务器限制，请删除过大文件后重新选择。"

    private static func containsAny(_ message: String, values: [String]) -> Bool {
        values.contains { message.contains($0) }
    }
}
