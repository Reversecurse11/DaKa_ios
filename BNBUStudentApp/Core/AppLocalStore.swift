import CryptoKit
import Foundation

enum LocalStoreReadStatus: String, Hashable {
    case missing = "未保存"
    case loaded = "已读取"
    case decodeFailed = "解码失败"
    case discarded = "已丢弃"
}

enum LocalStoreWriteStatus: String, Hashable {
    case idle = "未写入"
    case saved = "写入成功"
    case failed = "写入失败"
    case cleared = "已清理"
}

struct LocalStoreReadResult<Value> {
    let value: Value?
    let status: LocalStoreReadStatus
}

struct LocalStoreHealth: Hashable {
    var workspaceReadStatus: LocalStoreReadStatus
    var draftReadStatus: LocalStoreReadStatus
    var lastWriteStatus: LocalStoreWriteStatus
    var lastEvent: String

    static let fresh = LocalStoreHealth(
        workspaceReadStatus: .missing,
        draftReadStatus: .missing,
        lastWriteStatus: .idle,
        lastEvent: "尚未读取本地数据"
    )
}

/// Persists student caches as protected, non-backed-up files.
///
/// Tests can opt into an isolated `UserDefaults` suite. Production uses a
/// dedicated Application Support directory with complete file protection so
/// workspaces, drafts, thumbnails and original proof bytes are unavailable
/// while the device is locked and never mix with another app preference.
struct AppLocalStore {
    static let workspaceStorageKey = "bnbu.student.workspace.v1"
    static let draftStorageKey = "bnbu.student.checkin.draft.v1"
    static let pendingMutationStorageKey = "bnbu.student.remote.mutations.v1"
    static let remoteWorkspaceStorageKeyPrefix = "bnbu.student.remote.workspace.v1"

    private let workspaceKey = Self.workspaceStorageKey
    private let draftKey = Self.draftStorageKey
    private let pendingMutationKey = Self.pendingMutationStorageKey
    private let defaults: UserDefaults?
    private let legacyDefaults: UserDefaults
    private let fileManager: FileManager
    private let protectedDirectoryURL: URL?
    private let shouldFailWrite: ((String) -> Bool)?
    private let shouldFailRemoval: ((String) -> Bool)?

    init(
        defaults: UserDefaults? = nil,
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        legacyDefaults: UserDefaults = .standard,
        shouldFailWrite: ((String) -> Bool)? = nil,
        shouldFailRemoval: ((String) -> Bool)? = nil
    ) {
        self.defaults = defaults
        self.legacyDefaults = legacyDefaults
        self.fileManager = fileManager
        self.shouldFailWrite = shouldFailWrite
        self.shouldFailRemoval = shouldFailRemoval

        if defaults != nil {
            protectedDirectoryURL = nil
        } else if let directoryURL {
            protectedDirectoryURL = directoryURL
        } else {
            let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            protectedDirectoryURL = applicationSupport?
                .appendingPathComponent("BNBUStudent", isDirectory: true)
                .appendingPathComponent("ProtectedState", isDirectory: true)
        }

        if defaults == nil {
            prepareProtectedDirectory()
            migrateLegacyDefaultsIfNeeded()
        }
    }

    var usesProtectedFileStorage: Bool {
        protectedDirectoryURL != nil
    }

    func loadWorkspace() -> StudentWorkspace? {
        readWorkspace().value
    }

    func readWorkspace() -> LocalStoreReadResult<StudentWorkspace> {
        read(StudentWorkspace.self, forKey: workspaceKey)
    }

    @discardableResult
    func saveWorkspace(_ workspace: StudentWorkspace) -> Bool {
        save(workspace, forKey: workspaceKey)
    }

    func loadDraft() -> CheckInDraft? {
        readDraft().value
    }

    func readDraft() -> LocalStoreReadResult<CheckInDraft> {
        read(CheckInDraft.self, forKey: draftKey)
    }

    @discardableResult
    func saveDraft(_ draft: CheckInDraft) -> Bool {
        save(draft, forKey: draftKey)
    }

    func clearDraft() {
        _ = removeValue(forKey: draftKey)
    }

    func readPendingRemoteMutations() -> LocalStoreReadResult<[String: PendingRemoteMutationAttempt]> {
        read([String: PendingRemoteMutationAttempt].self, forKey: pendingMutationKey)
    }

    @discardableResult
    func savePendingRemoteMutations(_ attempts: [String: PendingRemoteMutationAttempt]) -> Bool {
        guard !attempts.isEmpty else {
            return clearPendingRemoteMutations()
        }
        return save(attempts, forKey: pendingMutationKey)
    }

    func clearPendingRemoteMutations() -> Bool {
        removeValue(forKey: pendingMutationKey)
    }

    func readRemoteWorkspace(baseURL: URL, studentID: String) -> LocalStoreReadResult<StudentWorkspace> {
        read(StudentWorkspace.self, forKey: remoteWorkspaceKey(baseURL: baseURL, studentID: studentID))
    }

    @discardableResult
    func saveRemoteWorkspace(_ workspace: StudentWorkspace, baseURL: URL, studentID: String) -> Bool {
        save(workspace, forKey: remoteWorkspaceKey(baseURL: baseURL, studentID: studentID))
    }

    func clearRemoteWorkspace(baseURL: URL, studentID: String) {
        _ = removeValue(forKey: remoteWorkspaceKey(baseURL: baseURL, studentID: studentID))
    }

    func clearAll() {
        if let defaults {
            defaults.removeObject(forKey: workspaceKey)
            defaults.removeObject(forKey: draftKey)
            defaults.removeObject(forKey: pendingMutationKey)
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(Self.remoteWorkspaceStorageKeyPrefix) {
                defaults.removeObject(forKey: key)
            }
            return
        }

        guard let protectedDirectoryURL else { return }
        if let children = try? fileManager.contentsOfDirectory(
            at: protectedDirectoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) {
            for child in children {
                try? fileManager.removeItem(at: child)
            }
        }
        removeLegacyDefaults()
    }

    func storageURL(forKey key: String) -> URL? {
        protectedDirectoryURL?.appendingPathComponent(hashedFileName(forKey: key), isDirectory: false)
    }

    private func remoteWorkspaceKey(baseURL: URL, studentID: String) -> String {
        let serverSuffix = baseURL.absoluteString
            .replacingOccurrences(of: "://", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        let studentSuffix = studentID
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "@", with: "-")
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        return "\(Self.remoteWorkspaceStorageKeyPrefix).\(serverSuffix).\(studentSuffix)"
    }

    private func read<T: Decodable>(_ type: T.Type, forKey key: String) -> LocalStoreReadResult<T> {
        let data: Data
        if let defaults {
            guard let storedData = defaults.data(forKey: key) else {
                return LocalStoreReadResult(value: nil, status: .missing)
            }
            data = storedData
        } else {
            guard let url = storageURL(forKey: key), fileManager.fileExists(atPath: url.path) else {
                return LocalStoreReadResult(value: nil, status: .missing)
            }
            guard let storedData = try? Data(contentsOf: url, options: [.mappedIfSafe]) else {
                return LocalStoreReadResult(value: nil, status: .decodeFailed)
            }
            data = storedData
        }

        do {
            return LocalStoreReadResult(
                value: try JSONDecoder().decode(type, from: data),
                status: .loaded
            )
        } catch {
            return LocalStoreReadResult(value: nil, status: .decodeFailed)
        }
    }

    private func save<T: Encodable>(_ value: T, forKey key: String) -> Bool {
        guard shouldFailWrite?(key) != true else { return false }
        guard let data = try? JSONEncoder().encode(value) else { return false }
        if let defaults {
            defaults.set(data, forKey: key)
            // `UserDefaults.set` does not report failures. Reading the exact
            // encoded value back gives callers a strict success signal and
            // keeps tests able to exercise the same fail-closed boundary used
            // by protected-file storage in production.
            return defaults.data(forKey: key) == data
        }

        guard let url = storageURL(forKey: key) else { return false }
        prepareProtectedDirectory()
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableURL = url
            try mutableURL.setResourceValues(values)
            return true
        } catch {
            return false
        }
    }

    private func removeValue(forKey key: String) -> Bool {
        guard shouldFailRemoval?(key) != true else { return false }
        if let defaults {
            defaults.removeObject(forKey: key)
            return defaults.object(forKey: key) == nil
        } else if let url = storageURL(forKey: key) {
            guard fileManager.fileExists(atPath: url.path) else { return true }
            do {
                try fileManager.removeItem(at: url)
                return !fileManager.fileExists(atPath: url.path)
            } catch {
                return false
            }
        }
        return false
    }

    private func hashedFileName(forKey key: String) -> String {
        let digest = SHA256.hash(data: Data(key.utf8))
        return digest.map { String(format: "%02x", $0) }.joined() + ".json"
    }

    private func prepareProtectedDirectory() {
        guard let protectedDirectoryURL else { return }
        do {
            try fileManager.createDirectory(
                at: protectedDirectoryURL,
                withIntermediateDirectories: true,
                attributes: [.protectionKey: FileProtectionType.complete]
            )
            try fileManager.setAttributes(
                [.protectionKey: FileProtectionType.complete],
                ofItemAtPath: protectedDirectoryURL.path
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            var mutableDirectoryURL = protectedDirectoryURL
            try mutableDirectoryURL.setResourceValues(values)
        } catch {
            // Save calls report the failure through their Bool return value.
        }
    }

    private func migrateLegacyDefaultsIfNeeded() {
        let fixedKeys = [workspaceKey, draftKey, pendingMutationKey]
        let remoteKeys = legacyDefaults.dictionaryRepresentation().keys.filter {
            $0.hasPrefix(Self.remoteWorkspaceStorageKeyPrefix)
        }
        for key in fixedKeys + remoteKeys {
            guard let data = legacyDefaults.data(forKey: key), writeRawData(data, forKey: key) else { continue }
            legacyDefaults.removeObject(forKey: key)
        }
    }

    private func writeRawData(_ data: Data, forKey key: String) -> Bool {
        guard let url = storageURL(forKey: key) else { return false }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
            try fileManager.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: url.path)
            return true
        } catch {
            return false
        }
    }

    private func removeLegacyDefaults() {
        legacyDefaults.removeObject(forKey: workspaceKey)
        legacyDefaults.removeObject(forKey: draftKey)
        legacyDefaults.removeObject(forKey: pendingMutationKey)
        for key in legacyDefaults.dictionaryRepresentation().keys where key.hasPrefix(Self.remoteWorkspaceStorageKeyPrefix) {
            legacyDefaults.removeObject(forKey: key)
        }
    }
}
