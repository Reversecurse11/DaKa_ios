import Foundation

struct StudentAPIClient {
    let baseURL: URL
    var token: String?

    init(baseURL: URL = StudentServerConfig.resolvedBaseURL(), token: String? = nil) {
        self.baseURL = baseURL
        self.token = token
    }

    func request(for endpoint: StudentEndpoint) -> URLRequest {
        var request = URLRequest(
            url: baseURL.appending(path: endpoint.path),
            timeoutInterval: StudentServerConfig.requestTimeout
        )
        request.httpMethod = endpoint.method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }
}

enum HTTPMethod: String {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
}

enum StudentEndpoint {
    case login
    case sportSummary
    case sportRecords
    case sportRecordDetail(id: String)
    case sportIdentity
    case notifications
    case markNotificationRead(id: String)

    var method: HTTPMethod {
        switch self {
        case .login, .sportRecords:
            return .post
        case .markNotificationRead:
            return .put
        case .sportSummary, .sportRecordDetail, .sportIdentity, .notifications:
            return .get
        }
    }

    var path: String {
        switch self {
        case .login:
            return "/auth/login"
        case .sportSummary:
            return "/sport/summary"
        case .sportRecords:
            return "/sport/records"
        case .sportRecordDetail(let id):
            return "/sport/records/\(id)"
        case .sportIdentity:
            return "/sport/identity"
        case .notifications:
            return "/common/notifications"
        case .markNotificationRead(let id):
            return "/common/notifications/\(id)/read"
        }
    }
}

struct SubmitSportRecordRequest: Encodable {
    let creditType: String
    let courseId: String?
    let hours: Double
    let description: String
    let proofFiles: [ProofFileReference]
}

struct ProofFileReference: Encodable {
    let cosKey: String
    let mediaType: String
    let mimeType: String
    let size: Int
}
