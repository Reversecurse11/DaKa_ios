import Foundation

struct StudentAPIClient {
    let baseURL: URL

    init(baseURL: URL = StudentServerConfig.resolvedBaseURL()) {
        self.baseURL = baseURL
    }
}
