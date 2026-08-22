import Foundation

enum BackendEnvironmentName: String, Codable, CaseIterable {
    case local
    case staging
    case production
}

enum BackendEnvironmentError: Error, LocalizedError, Equatable {
    case invalidEnvironment(String)
    case missingBaseURL(BackendEnvironmentName)
    case invalidBaseURL(BackendEnvironmentName)
    case invalidOrganizationCode(String?)
    case contractVersionMismatch(String?)
    case contractSHA256Mismatch(String?)

    var errorDescription: String? {
        switch self {
        case .invalidEnvironment(let value):
            return "Invalid backend environment: \(value)."
        case .missingBaseURL(let environment):
            return "Missing approved API base URL for \(environment.rawValue)."
        case .invalidBaseURL(let environment):
            return "Invalid API base URL for \(environment.rawValue)."
        case .invalidOrganizationCode:
            return "The organization code does not match the approved BNBU environment."
        case .contractVersionMismatch:
            return "The runtime Contract version does not match the generated API models."
        case .contractSHA256Mismatch:
            return "The runtime Contract SHA-256 does not match the generated API models."
        }
    }
}

struct BackendEnvironment: Equatable {
    static let approvedOrganizationCode = "BNBU"
    static let approvedStagingHost = "api.verityai.cn"

    let name: BackendEnvironmentName
    let baseURL: URL

    static let local = BackendEnvironment(
        name: .local,
        baseURL: URL(string: "http://127.0.0.1:3000/api/v1")!
    )

    /// Network clients use a non-routable endpoint if runtime configuration is
    /// corrupt. They never fall back from a formal environment to Local.
    static var runtime: BackendEnvironment {
        (try? resolve()) ?? BackendEnvironment(
            name: .production,
            baseURL: URL(string: "https://configuration-required.invalid/api/v1")!
        )
    }

    static func resolve(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main
    ) throws -> BackendEnvironment {
        let configuredName = processEnvironment["BNBU_ENVIRONMENT"]
            ?? bundle.object(forInfoDictionaryKey: "BNBUEnvironment") as? String
            ?? "local"
        guard let name = BackendEnvironmentName(rawValue: configuredName.lowercased()) else {
            throw BackendEnvironmentError.invalidEnvironment(configuredName)
        }

        if name != .local {
            let organizationCode = processEnvironment["BNBU_ORGANIZATION_CODE"]
                ?? bundle.object(forInfoDictionaryKey: "BNBUOrganizationCode") as? String
            guard organizationCode == Self.approvedOrganizationCode else {
                throw BackendEnvironmentError.invalidOrganizationCode(organizationCode)
            }
            let contractVersion = processEnvironment["BNBU_CONTRACT_VERSION"]
                ?? bundle.object(forInfoDictionaryKey: "BNBUContractVersion") as? String
            guard contractVersion == APIV1ContractMetadata.contractVersion else {
                throw BackendEnvironmentError.contractVersionMismatch(contractVersion)
            }
            let contractSHA256 = processEnvironment["BNBU_CONTRACT_SHA256"]
                ?? bundle.object(forInfoDictionaryKey: "BNBUContractSHA256") as? String
            guard contractSHA256 == APIV1ContractMetadata.sourceSHA256 else {
                throw BackendEnvironmentError.contractSHA256Mismatch(contractSHA256)
            }
        }

        let argumentURL = argumentValue(named: "-server-base-url", in: arguments)
        let configuredURL = argumentURL
            ?? processEnvironment["BNBU_API_BASE_URL"]
            ?? bundle.object(forInfoDictionaryKey: "BNBUAPIBaseURL") as? String

        if name == .local, configuredURL?.isEmpty != false {
            return .local
        }
        guard let configuredURL, !configuredURL.isEmpty else {
            throw BackendEnvironmentError.missingBaseURL(name)
        }
        guard let url = URL(string: configuredURL), isAllowed(url, for: name) else {
            throw BackendEnvironmentError.invalidBaseURL(name)
        }
        return BackendEnvironment(name: name, baseURL: url)
    }

    static func isAllowed(_ url: URL, for environment: BackendEnvironmentName) -> Bool {
        guard url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              url.path.replacingOccurrences(of: "/+$", with: "", options: .regularExpression) == APIV1ContractMetadata.apiPrefix,
              let scheme = url.scheme?.lowercased(),
              let host = url.host?.lowercased(),
              !host.isEmpty,
              !host.hasSuffix(".invalid"),
              host != "123.207.5.70" else {
            return false
        }

        switch environment {
        case .local:
            guard scheme == "http" || scheme == "https" else { return false }
            return host == "localhost" || host == "127.0.0.1" || isPrivateIPv4(host)
        case .staging:
            return scheme == "https" && host == Self.approvedStagingHost
        case .production:
            return scheme == "https" && host != "localhost" && host != "127.0.0.1" && !isPrivateIPv4(host)
        }
    }

    private static func isPrivateIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4, parts.allSatisfy({ (0...255).contains($0) }) else { return false }
        return parts[0] == 10 ||
            (parts[0] == 172 && (16...31).contains(parts[1])) ||
            (parts[0] == 192 && parts[1] == 168)
    }

    private static func argumentValue(named name: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }
}

/// Compatibility seam for the existing UI repository. New backend code uses
/// `BackendEnvironment` directly; legacy endpoints are not a fallback source.
enum StudentServerConfig {
    static let testBaseURL = BackendEnvironment.local.baseURL
    static let productionBaseURL = URL(string: "https://configuration-required.invalid/api/v1")!
    static let localDevelopmentBaseURL = BackendEnvironment.local.baseURL
    static let requestTimeout: TimeInterval = 30

    static func resolvedBaseURL(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundleValue: String? = Bundle.main.object(forInfoDictionaryKey: "BNBUAPIBaseURL") as? String
    ) -> URL {
        var values = environment
        values["BNBU_ENVIRONMENT"] = values["BNBU_ENVIRONMENT"] ?? "local"
        if let bundleValue, values["BNBU_API_BASE_URL"] == nil {
            values["BNBU_API_BASE_URL"] = bundleValue
        }
        return (try? BackendEnvironment.resolve(
            arguments: arguments,
            processEnvironment: values,
            bundle: .main
        ).baseURL) ?? BackendEnvironment.local.baseURL
    }

    static func validatedProductionBaseURL(_ rawValue: String?) -> URL? {
        guard let rawValue, let url = URL(string: rawValue),
              BackendEnvironment.isAllowed(url, for: .production) else {
            return nil
        }
        return url
    }
}
