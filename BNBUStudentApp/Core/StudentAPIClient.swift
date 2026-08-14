import Foundation

enum HTTPMethod: String, Codable {
    case get = "GET"
    case head = "HEAD"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"

    var isSafeToRetry: Bool { self == .get || self == .head }
}

enum APIAuthorization: Equatable {
    case none
    case bearer(String)
    case joinCapability(String)
}

struct APIRequest: Equatable {
    let operationID: String
    let method: HTTPMethod
    let path: String
    var queryItems: [URLQueryItem] = []
    var body: Data?
    var authorization: APIAuthorization = .none
    var idempotencyKey: String?
    var additionalHeaders: [String: String] = [:]

    static func jsonBody<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}

struct APIResponseMeta: Decodable, Equatable {
    let requestId: String
    let pagination: APIV1PaginationMeta?
}

struct APISuccessEnvelope<Value: Decodable & Equatable>: Decodable, Equatable {
    let data: Value
    let meta: APIResponseMeta
}

struct APIErrorEnvelope: Decodable, Equatable {
    let code: String
    let message: String
    let details: APIV1JSONValue
    let requestId: String
    let timestamp: String

    var knownCode: APIV1ErrorCode? { APIV1ErrorCode(rawValue: code) }
}

struct APIResponse<Value: Equatable>: Equatable {
    let value: Value
    let requestId: String
    let pagination: APIV1PaginationMeta?
    let statusCode: Int
}

struct APIRawResponse {
    let data: Data
    let response: HTTPURLResponse
    let requestId: String?
}

/// Actual bytes written by an OpenAPI V1 private signed upload. Ordinary
/// multipart uploads use the same URLSession delegate signal, so neither path
/// needs timer-based or estimated progress.
struct APIUploadProgress: Equatable, Sendable {
    let bytesSent: Int64
    let totalBytes: Int64

    var fraction: Double {
        guard totalBytes > 0 else { return 0 }
        return min(max(Double(bytesSent) / Double(totalBytes), 0), 1)
    }

    var percentage: Int {
        min(max(Int(fraction * 100), 0), 100)
    }
}

private final class APIUploadProgressDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let progressHandler: @Sendable (APIUploadProgress) -> Void

    init(progressHandler: @escaping @Sendable (APIUploadProgress) -> Void) {
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
        progressHandler(APIUploadProgress(
            bytesSent: min(max(totalBytesSent, 0), totalBytesExpectedToSend),
            totalBytes: totalBytesExpectedToSend
        ))
    }
}

enum APITransportError: Error, LocalizedError, Equatable {
    case invalidRequest
    case invalidResponse
    case malformedSuccessEnvelope(statusCode: Int, requestId: String?)
    case requestIdMismatch(header: String, body: String)
    case failure(statusCode: Int, envelope: APIErrorEnvelope)
    case undecodableFailure(statusCode: Int, requestId: String?)
    case network(URLError.Code)

    var requestId: String? {
        switch self {
        case .malformedSuccessEnvelope(_, let requestId), .undecodableFailure(_, let requestId):
            return requestId
        case .requestIdMismatch(let header, _):
            return header
        case .failure(_, let envelope):
            return envelope.requestId
        case .invalidRequest, .invalidResponse, .network:
            return nil
        }
    }

    var statusCode: Int? {
        switch self {
        case .malformedSuccessEnvelope(let statusCode, _),
             .failure(let statusCode, _),
             .undecodableFailure(let statusCode, _):
            return statusCode
        case .invalidRequest, .invalidResponse, .requestIdMismatch, .network:
            return nil
        }
    }

    var errorDescription: String? {
        let suffix = requestId.map { " (requestId: \($0))" } ?? ""
        switch self {
        case .failure(_, let envelope):
            return (MediaValidationErrorPolicy.message(for: self) ?? envelope.message) + suffix
        case .network:
            return "Network request failed." + suffix
        case .invalidRequest:
            return "The API request is invalid."
        case .invalidResponse, .malformedSuccessEnvelope, .requestIdMismatch, .undecodableFailure:
            return "The server returned an invalid response." + suffix
        }
    }
}

struct APILogEvent: Equatable {
    enum Outcome: String { case succeeded, failed }

    let operationID: String
    let environment: BackendEnvironmentName
    let outcome: Outcome
    let statusCode: Int?
    let errorCode: String?
    let requestId: String?
}

protocol APIEventLogging: Sendable {
    func record(_ event: APILogEvent)
}

struct NoopAPIEventLogger: APIEventLogging {
    func record(_ event: APILogEvent) {}
}

struct StudentAPIClient: @unchecked Sendable {
    let baseURL: URL
    let environmentName: BackendEnvironmentName

    private let urlSession: URLSession
    private let logger: any APIEventLogging
    private let maximumSafeRetries: Int
    private let requestTimeout: TimeInterval

    init(
        environment: BackendEnvironment = .runtime,
        urlSession: URLSession = .shared,
        logger: any APIEventLogging = NoopAPIEventLogger(),
        maximumSafeRetries: Int = 1,
        requestTimeout: TimeInterval = StudentServerConfig.requestTimeout
    ) {
        self.baseURL = environment.baseURL
        self.environmentName = environment.name
        self.urlSession = urlSession
        self.logger = logger
        self.maximumSafeRetries = max(0, maximumSafeRetries)
        self.requestTimeout = requestTimeout
    }

    init(
        baseURL: URL,
        urlSession: URLSession = .shared,
        logger: any APIEventLogging = NoopAPIEventLogger(),
        maximumSafeRetries: Int = 1
    ) {
        self.init(
            environment: BackendEnvironment(name: .local, baseURL: baseURL),
            urlSession: urlSession,
            logger: logger,
            maximumSafeRetries: maximumSafeRetries
        )
    }

    func send<Value: Decodable & Equatable>(
        _ apiRequest: APIRequest,
        as type: Value.Type = Value.self
    ) async throws -> APIResponse<Value> {
        let request = try makeURLRequest(from: apiRequest)
        let raw = try await perform(request, safeToRetry: apiRequest.method.isSafeToRetry)
        let statusCode = raw.response.statusCode

        guard (200...299).contains(statusCode) else {
            let error = decodeFailure(from: raw)
            logger.record(APILogEvent(
                operationID: apiRequest.operationID,
                environment: environmentName,
                outcome: .failed,
                statusCode: statusCode,
                errorCode: errorCode(from: error),
                requestId: error.requestId
            ))
            throw error
        }

        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(APISuccessEnvelope<Value>.self, from: raw.data) else {
            let error = APITransportError.malformedSuccessEnvelope(
                statusCode: statusCode,
                requestId: raw.requestId
            )
            logger.record(APILogEvent(
                operationID: apiRequest.operationID,
                environment: environmentName,
                outcome: .failed,
                statusCode: statusCode,
                errorCode: nil,
                requestId: raw.requestId
            ))
            throw error
        }

        if let headerRequestId = raw.requestId, headerRequestId != envelope.meta.requestId {
            let error = APITransportError.requestIdMismatch(
                header: headerRequestId,
                body: envelope.meta.requestId
            )
            logger.record(APILogEvent(
                operationID: apiRequest.operationID,
                environment: environmentName,
                outcome: .failed,
                statusCode: statusCode,
                errorCode: nil,
                requestId: headerRequestId
            ))
            throw error
        }
        logger.record(APILogEvent(
            operationID: apiRequest.operationID,
            environment: environmentName,
            outcome: .succeeded,
            statusCode: statusCode,
            errorCode: nil,
            requestId: envelope.meta.requestId
        ))
        return APIResponse(
            value: envelope.data,
            requestId: envelope.meta.requestId,
            pagination: envelope.meta.pagination,
            statusCode: statusCode
        )
    }

    func raw(_ apiRequest: APIRequest) async throws -> APIRawResponse {
        let request = try makeURLRequest(from: apiRequest)
        return try await perform(request, safeToRetry: apiRequest.method.isSafeToRetry)
    }

    func upload(
        to signedURL: URL,
        data: Data,
        method: HTTPMethod,
        requiredHeaders: [String: String],
        progressHandler: @escaping @Sendable (APIUploadProgress) -> Void = { _ in }
    ) async throws -> HTTPURLResponse {
        guard method == .put || method == .post,
              isAllowedSignedUploadURL(signedURL),
              signedURL.user == nil,
              signedURL.password == nil,
              !data.isEmpty else {
            throw APITransportError.invalidRequest
        }
        var request = URLRequest(url: signedURL, timeoutInterval: requestTimeout)
        request.httpMethod = method.rawValue
        requiredHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let totalBytes = Int64(data.count)
        progressHandler(APIUploadProgress(bytesSent: 0, totalBytes: totalBytes))
        let delegate = APIUploadProgressDelegate(progressHandler: progressHandler)
        do {
            let (_, response) = try await urlSession.upload(for: request, from: data, delegate: delegate)
            guard let response = response as? HTTPURLResponse else {
                throw APITransportError.invalidResponse
            }
            guard (200...299).contains(response.statusCode) else {
                throw APITransportError.undecodableFailure(statusCode: response.statusCode, requestId: nil)
            }
            progressHandler(APIUploadProgress(bytesSent: totalBytes, totalBytes: totalBytes))
            return response
        } catch let error as URLError {
            throw APITransportError.network(error.code)
        }
    }

    /// File-backed signed upload used by short videos. Keeping the body on
    /// disk avoids materialising a potentially large MOV as one Data value.
    func upload(
        to signedURL: URL,
        fileURL: URL,
        method: HTTPMethod,
        requiredHeaders: [String: String],
        progressHandler: @escaping @Sendable (APIUploadProgress) -> Void = { _ in }
    ) async throws -> HTTPURLResponse {
        guard method == .put || method == .post,
              isAllowedSignedUploadURL(signedURL),
              signedURL.user == nil,
              signedURL.password == nil,
              fileURL.isFileURL,
              let values = try? fileURL.resourceValues(forKeys: [
                .isRegularFileKey,
                .fileSizeKey
              ]),
              values.isRegularFile == true,
              let fileSize = values.fileSize,
              fileSize > 0 else {
            throw APITransportError.invalidRequest
        }
        var request = URLRequest(url: signedURL, timeoutInterval: requestTimeout)
        request.httpMethod = method.rawValue
        requiredHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let totalBytes = Int64(fileSize)
        progressHandler(APIUploadProgress(bytesSent: 0, totalBytes: totalBytes))
        let delegate = APIUploadProgressDelegate(progressHandler: progressHandler)
        do {
            let (_, response) = try await urlSession.upload(
                for: request,
                fromFile: fileURL,
                delegate: delegate
            )
            guard let response = response as? HTTPURLResponse else {
                throw APITransportError.invalidResponse
            }
            guard (200...299).contains(response.statusCode) else {
                throw APITransportError.undecodableFailure(
                    statusCode: response.statusCode,
                    requestId: nil
                )
            }
            progressHandler(APIUploadProgress(bytesSent: totalBytes, totalBytes: totalBytes))
            return response
        } catch let error as URLError {
            throw APITransportError.network(error.code)
        }
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let method = HTTPMethod(rawValue: request.httpMethod ?? "GET") ?? .get
        let response = try await perform(request, safeToRetry: method.isSafeToRetry)
        return (response.data, response.response)
    }

    func upload(
        for request: URLRequest,
        fromFile bodyFileURL: URL,
        delegate: URLSessionTaskDelegate
    ) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.upload(for: request, fromFile: bodyFileURL, delegate: delegate)
        } catch let error as URLError {
            throw APITransportError.network(error.code)
        }
    }

    private func isAllowedSignedUploadURL(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "https" { return true }
        guard environmentName == .local,
              url.scheme?.lowercased() == "http",
              Self.isTrustedLocalUploadHost(url.host, relativeTo: baseURL.host) else {
            return false
        }
        return true
    }

    private static func isTrustedLocalUploadHost(_ uploadHost: String?, relativeTo apiHost: String?) -> Bool {
        guard let uploadHost = uploadHost?.lowercased(),
              let apiHost = apiHost?.lowercased() else { return false }
        return uploadHost == apiHost || (isLoopbackHost(uploadHost) && isLoopbackHost(apiHost))
    }

    private static func isLoopbackHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private func makeURLRequest(from apiRequest: APIRequest) throws -> URLRequest {
        guard !apiRequest.path.contains("://") else { throw APITransportError.invalidRequest }
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let basePath = components?.path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) ?? ""
        let endpointPath = apiRequest.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        components?.path = "/" + [basePath, endpointPath].filter { !$0.isEmpty }.joined(separator: "/")
        components?.queryItems = apiRequest.queryItems.isEmpty ? nil : apiRequest.queryItems
        guard let url = components?.url else { throw APITransportError.invalidRequest }

        var request = URLRequest(url: url, timeoutInterval: requestTimeout)
        request.httpMethod = apiRequest.method.rawValue
        request.httpBody = apiRequest.body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ios-\(UUID().uuidString.lowercased())", forHTTPHeaderField: "X-Request-ID")
        if apiRequest.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let idempotencyKey = apiRequest.idempotencyKey {
            guard Self.isValidIdempotencyKey(idempotencyKey) else {
                throw APITransportError.invalidRequest
            }
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        switch apiRequest.authorization {
        case .none:
            break
        case .bearer(let accessToken):
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        case .joinCapability(let capability):
            request.setValue(capability, forHTTPHeaderField: "X-Join-Capability")
        }
        apiRequest.additionalHeaders.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return request
    }

    private func perform(_ request: URLRequest, safeToRetry: Bool) async throws -> APIRawResponse {
        let maximumAttempts = safeToRetry ? maximumSafeRetries + 1 : 1
        var attempt = 0
        while attempt < maximumAttempts {
            attempt += 1
            do {
                let (data, response) = try await urlSession.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw APITransportError.invalidResponse
                }
                if safeToRetry,
                   attempt < maximumAttempts,
                   [502, 503, 504].contains(httpResponse.statusCode) {
                    continue
                }
                return APIRawResponse(
                    data: data,
                    response: httpResponse,
                    requestId: httpResponse.value(forHTTPHeaderField: "X-Request-ID")
                )
            } catch let error as URLError {
                if safeToRetry, attempt < maximumAttempts, Self.isRetryable(error.code) {
                    continue
                }
                throw APITransportError.network(error.code)
            }
        }
        throw APITransportError.invalidResponse
    }

    private func decodeFailure(from raw: APIRawResponse) -> APITransportError {
        guard let envelope = try? JSONDecoder().decode(APIErrorEnvelope.self, from: raw.data) else {
            return .undecodableFailure(statusCode: raw.response.statusCode, requestId: raw.requestId)
        }
        if let headerRequestId = raw.requestId, headerRequestId != envelope.requestId {
            return .requestIdMismatch(header: headerRequestId, body: envelope.requestId)
        }
        return .failure(statusCode: raw.response.statusCode, envelope: envelope)
    }

    private func errorCode(from error: APITransportError) -> String? {
        if case .failure(_, let envelope) = error { return envelope.code }
        return nil
    }

    private static func isRetryable(_ code: URLError.Code) -> Bool {
        [.timedOut, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed].contains(code)
    }

    static func isValidIdempotencyKey(_ value: String) -> Bool {
        let bytes = Array(value.utf8)
        return (1...128).contains(bytes.count) && bytes.allSatisfy { (0x21...0x7e).contains($0) }
    }
}

enum APIPath {
    static func component(_ value: String) throws -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        guard !value.isEmpty,
              let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed),
              !encoded.contains("/") else {
            throw APITransportError.invalidRequest
        }
        return encoded
    }
}
