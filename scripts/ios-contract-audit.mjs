import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const scriptDirectory = path.dirname(fileURLToPath(import.meta.url));
const iosRoot = path.resolve(scriptDirectory, "..");
const workspaceRoot = path.resolve(iosRoot, "..", "..");
const backendRoot = process.env.BNBU_BACKEND_ROOT
  ? path.resolve(process.env.BNBU_BACKEND_ROOT)
  : path.join(workspaceRoot, "BNBU-Sports-Android", "backend");

function read(relativePath) {
  return fs.readFileSync(path.join(iosRoot, relativePath), "utf8");
}

function requireText(source, expected, label) {
  if (!source.includes(expected)) {
    throw new Error(`${label}: missing ${JSON.stringify(expected)}`);
  }
  console.log(`PASS ${label}`);
}

function requireAnyText(source, candidates, label) {
  if (!candidates.some((candidate) => source.includes(candidate))) {
    throw new Error(`${label}: missing any of ${JSON.stringify(candidates)}`);
  }
  console.log(`PASS ${label}`);
}

function requireCount(source, expected, minimum, label) {
  const count = source.split(expected).length - 1;
  if (count < minimum) {
    throw new Error(`${label}: expected at least ${minimum} occurrences of ${JSON.stringify(expected)}, found ${count}`);
  }
  console.log(`PASS ${label}`);
}

function rejectText(source, forbidden, label) {
  if (source.includes(forbidden)) {
    throw new Error(`${label}: found forbidden ${JSON.stringify(forbidden)}`);
  }
  console.log(`PASS ${label}`);
}

function rejectPattern(source, forbidden, label) {
  if (forbidden.test(source)) {
    throw new Error(`${label}: matched forbidden ${forbidden}`);
  }
  console.log(`PASS ${label}`);
}

function swiftFiles(directory) {
  return fs.readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = path.join(directory, entry.name);
    if (entry.isDirectory()) return swiftFiles(fullPath);
    return entry.isFile() && entry.name.endsWith(".swift") ? [fullPath] : [];
  });
}

function assertBalancedSwiftDelimiters(filePath) {
  const source = fs.readFileSync(filePath, "utf8");
  const expectedCloser = { "(": ")", "[": "]", "{": "}" };
  const opening = new Set(Object.keys(expectedCloser));
  const closing = new Set(Object.values(expectedCloser));
  const stack = [];
  let state = "code";
  let blockDepth = 0;

  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    const next = source[index + 1];
    const nextTwo = source.slice(index, index + 3);

    if (state === "line-comment") {
      if (character === "\n") state = "code";
      continue;
    }
    if (state === "block-comment") {
      if (character === "/" && next === "*") {
        blockDepth += 1;
        index += 1;
      } else if (character === "*" && next === "/") {
        blockDepth -= 1;
        index += 1;
        if (blockDepth === 0) state = "code";
      }
      continue;
    }
    if (state === "string") {
      if (character === "\\") index += 1;
      else if (character === '"') state = "code";
      continue;
    }
    if (state === "multiline-string") {
      if (nextTwo === '\"\"\"') {
        state = "code";
        index += 2;
      }
      continue;
    }
    if (character === "/" && next === "/") {
      state = "line-comment";
      index += 1;
      continue;
    }
    if (character === "/" && next === "*") {
      state = "block-comment";
      blockDepth = 1;
      index += 1;
      continue;
    }
    if (nextTwo === '\"\"\"') {
      state = "multiline-string";
      index += 2;
      continue;
    }
    if (character === '"') {
      state = "string";
      continue;
    }
    if (opening.has(character)) stack.push(character);
    if (closing.has(character)) {
      const opener = stack.pop();
      if (!opener || expectedCloser[opener] !== character) {
        throw new Error(`Unbalanced delimiter in ${filePath} near character ${index}`);
      }
    }
  }

  if (state === "block-comment" || state === "string" || state === "multiline-string" || stack.length > 0) {
    throw new Error(`Unterminated Swift token in ${filePath}: state=${state}, stack=${stack.join("")}`);
  }
  rejectText(source, "<<<<<<<", `No merge-conflict marker in ${path.basename(filePath)}`);
}

const remote = read("BNBUStudentApp/Core/RemoteStudentRepository.swift");
const models = read("BNBUStudentApp/Core/Models.swift");
const appState = read("BNBUStudentApp/Core/AppState.swift");
const localStore = read("BNBUStudentApp/Core/AppLocalStore.swift");
const credentialStore = read("BNBUStudentApp/Core/SecureCredentialStore.swift");
const components = read("BNBUStudentApp/Features/Components.swift");
const loginView = read("BNBUStudentApp/Features/LoginView.swift");
const profileView = read("BNBUStudentApp/Features/ProfileView.swift");
const coursesView = read("BNBUStudentApp/Features/CoursesView.swift");
const checkinView = read("BNBUStudentApp/Features/CheckInView.swift");
const gradesView = read("BNBUStudentApp/Features/GradesView.swift");
const releaseInfoPlist = read("BNBUStudentApp/Resources/Info.plist");
const debugInfoPlist = read("BNBUStudentApp/Resources/Info-Debug.plist");
const privacyManifest = read("BNBUStudentApp/Resources/PrivacyInfo.xcprivacy");
const releaseValidator = read("scripts/validate-release-config.sh");
const macReleaseGate = read("scripts/run-macos-release-gate.sh");
const modelTests = read("BNBUStudentTests/BNBUStudentModelTests.swift");
const project = read("BNBUStudent.xcodeproj/project.pbxproj");
const appSources = swiftFiles(path.join(iosRoot, "BNBUStudentApp"))
  .map((file) => fs.readFileSync(file, "utf8"))
  .join("\n");
const openapiPath = path.join(backendRoot, "openapi", "openapi.yaml");

if (!fs.existsSync(openapiPath)) {
  throw new Error(`Backend OpenAPI not found: ${openapiPath}`);
}
const openapi = fs.readFileSync(openapiPath, "utf8");

for (const swiftFile of swiftFiles(path.join(iosRoot, "BNBUStudentApp")).concat(swiftFiles(path.join(iosRoot, "BNBUStudentTests")))) {
  assertBalancedSwiftDelimiters(swiftFile);
}
console.log("PASS Swift source delimiters are structurally balanced");

requireText(remote, 'http://123.207.5.70:82/api/v1', "Debug targets the current IP:82 /api/v1 server");
rejectText(remote, "123.207.5.70:3333", "Obsolete iOS API port is absent from runtime source");
requireText(remote, '"role": "student"', "Student login explicitly requests the student role");
requireText(remote, '"clientType": "mobile"', "Student login identifies the mobile client");

const workspaceEndpoints = [
  "sport/summary",
  "student/profile",
  "student/courses",
  "student/grades",
  "sport/records",
  "sport/identity",
  "common/notifications",
  "student/physical-test-exemptions"
];
for (const endpoint of workspaceEndpoints) {
  // getIfBusinessReady wraps get() for endpoints that may return
  // configuration-pending business errors (r19: CHECKIN_SETTING_REQUIRED etc).
  requireAnyText(
    remote,
    [`get("${endpoint}")`, `getIfBusinessReady("${endpoint}")`],
    `Workspace requests ${endpoint}`
  );
  requireText(openapi, `/${endpoint}:`, `OpenAPI publishes ${endpoint}`);
}

for (const endpoint of ["/auth/login:", "/scoring/convert-endurance:", "/upload/proof:"]) {
  requireText(openapi, endpoint, `OpenAPI publishes ${endpoint.slice(1, -1)}`);
}

requireText(remote, "StudentCoursesPayload", "Course-list response has a dedicated decoder");
requireText(remote, "StudentGradesPayload", "Grades response has a dedicated decoder");

// New business model: no task publishing, no review states. The legacy
// CourseTask/ReviewStatus chain and the check-in supplement flow are removed.
rejectText(appSources, "struct CourseTask", "Legacy CourseTask model is removed");
rejectText(appSources, "enum TaskStatus", "Legacy TaskStatus model is removed");
rejectText(appSources, "enum ReviewStatus", "Legacy ReviewStatus model is removed");
rejectText(appSources, "submissionTask(for", "Legacy submissionTask API is removed");
rejectText(appSources, 'get("student/tasks")', "iOS no longer requests the removed task list");
rejectText(appSources, 'getIfBusinessReady("student/tasks")', "iOS no longer requests the removed task list defensively");
rejectText(remote, '"taskId"', "Check-in submission no longer sends a task reference");
rejectText(remote, "supplementCheckIn", "The check-in supplement route is removed");
requireText(models, "enum RecordValidity", "Records use the valid/invalid model");
requireText(models, "case \"invalid\", \"INVALID\", \"无效\", \"rejected\", \"REJECTED\", \"被驳回\", \"已驳回\":", "Legacy review states map deterministically onto validity");
requireText(models, "var invalidReason: String?", "Invalid records surface the teacher-provided reason");
requireText(models, "struct CheckInSubmission", "Check-in submissions have a validated value type");
requireText(appState, "func validatedSubmission(creditType: CreditType, courseId: String?, hours: Double)", "Submission validation is centralized and fail-closed");
requireText(appState, "guard creditType != .organizationOffset else { return nil }", "Organization offsets can never be student-submitted");
requireText(appState, "func submissionContext(for session: ExerciseSession)", "Submission context derives from the completed exercise session");
requireText(remote, "record.representsCompleteServerRecord", "MutationResult cannot masquerade as a complete record");
requireText(remote, "application.representsCompleteServerApplication", "MutationResult cannot masquerade as a complete exemption");
requireText(coursesView, ".filter(\\.isCurrent)", "Current courses use the backend scope flag");
rejectText(coursesView, "currentSemesterKey", "Course scope no longer depends on an English semester label");

rejectText(appState, "max(hours, 0.5)", "Submission hours cannot produce backend-invalid 0.5h values");
requireText(appState, "hours == 1 || hours == 2", "Submission hours are restricted to the 1h/2h API enum");
requireText(appState, 'TimeZone(identifier: "Asia/Shanghai")', "Daily submission guard uses the backend business timezone");
requireText(appState, ".withFractionalSeconds", "Daily submission guard parses backend fractional ISO timestamps");
requireText(models, "static let maxRequestBytes = 120_000_000", "Check-in proof batch enforces the 120MB request limit");
requireText(models, "enum ExemptionProofRule", "Physical exemptions have a dedicated proof rule");
requireText(models, "static let maxAttachmentCount = 5", "Physical exemptions enforce the five-proof API limit");
requireText(models, "static let maximumCombinedReasonLength = 2_000", "Physical exemption reason enforces the 2000-character API limit");
requireText(models, "static let maximumDescriptionLength = 200", "Check-in note enforces the 200-character business rule (stricter than the 2000-character API limit)");
requireText(models, "struct ExercisePause", "Exercise sessions record every pause/resume instant");
requireText(models, "static let maximumPauseBeforeAutoEnd: TimeInterval = 6 * oneHour", "A pause over six hours auto-ends the session");
requireText(models, "wallClock - paused", "Paused time never counts toward exercise duration");
requireText(models, "static let maximumPhotoDrafts = 6", "In-session photo drafts cap at six");
requireText(checkinView, "ExerciseCameraCaptureButton", "Check-in proofs are captured through the camera-only flow");
rejectText(checkinView, "PhotosPicker", "Check-in proofs cannot be picked from the photo library");
rejectText(checkinView, "ProofAttachmentPanel", "Check-in no longer uses the album-capable proof panel");
requireText(checkinView, "你确定要结束本次运动吗？", "Ending exercise passes the 5.6 anti-mistap confirmation");
requireText(checkinView, "运动时长未满 1 小时", "Under-one-hour ends surface the 5.6 notice after confirmation");
requireText(models, "enum CheckInTimeWindowRule", "The daily open window rule (3.3) exists client-side");
requireText(appState, "CheckInTimeWindowRule.canStartExercise", "Starting a session is gated by the daily open window");
requireText(appState, "session.locationStatus == .unavailable", "A location fix never overwrites an earlier one");
rejectText(appSources, "startUpdatingLocation", "Location is a one-shot fix, never continuous tracking");
requireText(debugInfoPlist, "NSLocationWhenInUseUsageDescription", "Debug build declares the when-in-use location purpose");
requireText(releaseInfoPlist, "NSLocationWhenInUseUsageDescription", "Release build declares the when-in-use location purpose");
rejectText(debugInfoPlist + releaseInfoPlist, "NSLocationAlwaysAndWhenInUseUsageDescription", "Background location is never requested");
requireText(gradesView, "maxAttachmentCount: ExemptionProofRule.maxAttachmentCount", "Exemption picker stops at five proofs");
requireText(appState, "guard ExemptionProofRule.accepts(proofAttachments)", "Exemption submission revalidates its proof contract");
requireText(remote, "guard attachment.uploadData != nil || attachment.sourceFileURL != nil", "Uploads require original bounded Data or the selected local file rather than a thumbnail");
rejectText(remote, "attachment.uploadData ?? attachment.thumbnailData", "Thumbnail data cannot be uploaded as original evidence");
rejectText(remote, 'path: "checkins/', "Frozen v1 upload never falls back to a legacy checkins path");
rejectText(remote, "尚未部署凭证上传接口", "404 errors do not expose a stale deployment diagnosis");

requireText(credentialStore, "import Security", "Credentials use Keychain Services");
requireText(credentialStore, "kSecAttrAccessibleWhenUnlockedThisDeviceOnly", "Keychain credentials are device-only and require unlock");
requireText(credentialStore, "kSecAttrSynchronizable", "Keychain explicitly controls synchronization");
requireText(credentialStore, "kCFBooleanFalse", "Credential synchronization is disabled");
rejectText(remote, "UserDefaults.standard.set(accessToken", "Access tokens are not written to UserDefaults");
requireText(remote, "credentialStore.set(Data(accessToken.utf8)", "Access tokens are persisted through secure storage");
requireText(remote, "legacyAccessTokenDefaultsKey", "Legacy plaintext token storage is migrated");

rejectText(remote, 'url(for: "auth/logout")', "Frozen v1 logout performs no unsupported network call");
rejectText(remote, 'url(for: "auth/refresh")', "Frozen v1 performs no unsupported token refresh");
rejectText(openapi, "/auth/logout:", "OpenAPI confirms there is no server logout endpoint");
rejectText(openapi, "/auth/refresh:", "OpenAPI confirms there is no refresh endpoint");
requireText(remote, "func logout() -> Bool", "Repository logout is deterministic local cleanup");
requireText(remote, "authenticationEpoch &+= 1", "Authentication responses are generation-guarded");
requireText(remote, "guard loginEpoch == authenticationEpoch", "A late login response cannot restore a logged-out session");
requireText(appState, "func logout() async", "App logout waits for local secure-store cleanup");
requireText(appState, "localStore.clearRemoteWorkspace", "Logout and expiry clear the active account cache");
requireText(appState, "localStore.clearDraft()", "Logout and expiry clear unsubmitted drafts");

requireText(appState, "@MainActor\nfinal class AppState", "Observable UI state is MainActor isolated");
requireText(remote, "actor RemoteStudentRepository", "Network session mutation is actor isolated");
requireText(appState, "isRefreshingWorkspace", "Workspace refreshes are single-flight guarded");
requireText(appState, "InFlightMutationGate", "Mutation requests have a reusable duplicate-submission gate");
requireText(appState, 'let mutationKey = "submit-exemption"', "Exemption submissions have a single-flight guard");
requireText(appState, 'let mutationKey = "supplement-exemption:', "Exemption supplements have an identity-scoped guard");
requireText(models, "enum IdempotencyKeyPolicy", "iOS defines the backend idempotency-key policy");
requireText(models, '"ios-\\(UUID().uuidString.lowercased())"', "iOS mutation attempts receive a valid unique key");
requireText(models, "struct PendingRemoteMutationAttempt", "Pending mutations retain their logical-attempt identity");
requireText(models, "let serverIdentity: String", "Pending mutations are server scoped");
requireText(models, "let studentID: String", "Pending mutations are account scoped");
requireText(models, "let requestFields: [String: String]", "Pending mutations persist their canonical request fields");
requireText(models, "let sourceProofs: [ProofAttachment]", "Pending mutations persist stable source-proof identity");
requireText(models, "private struct PersistedSourceProof", "Source-proof recovery uses a restricted persisted representation");
requireText(models, "private struct PersistedUploadedProof", "Uploaded-proof recovery uses canonical COS references");
requireText(models, '!trimmed.contains("://")', "Pending source-proof persistence strips signed and local URLs");
requireText(models, "thumbnailData: nil", "Pending mutation references omit thumbnails");
requireText(models, "uploadData: nil", "Pending mutation references omit original bytes");
requireText(models, "let contentDigest: String?", "Local proof identity survives protected draft persistence");
requireText(models, "try container.encodeIfPresent(contentDigest", "Proof content identity is persisted without original bytes");
requireText(models, "for (position, attachment) in attachments.enumerated()", "Mutation fingerprints preserve attachment order");
requireText(models, "append(String(position), to: &input)", "Mutation fingerprints encode only the stable attachment position");
requireText(models, "append(attachment.contentDigest ??", "Mutation fingerprints use the persisted proof content identity");
for (const metadataAppend of [
  "append(attachment.id",
  "append(attachment.type",
  "append(attachment.fileName",
  "append(attachment.byteCount",
  "append(attachment.durationSeconds",
  "append(attachment.source",
  "append(attachment.cosKey",
  "append(attachment.mimeType",
]) {
  rejectText(models, metadataAppend, `Mutation fingerprint excludes attachment metadata ${metadataAppend}`);
}
requireText(models, "enum ProofContentDigest", "Proof content hashing has a single auditable implementation");
requireText(models, "static let streamingChunkBytes = 1_048_576", "File proof hashing has a bounded one-megabyte buffer");
requireText(models, "let handle = try FileHandle(forReadingFrom: fileURL)", "File proof hashing reads from the original local URL");
requireText(models, "handle.read(upToCount: chunkSize)", "File proof hashing is chunked instead of whole-file Data");
requireText(models, "hasher.update(data: chunk)", "Every streamed proof chunk feeds incremental SHA-256");
requireText(models, "return hasher.finalize().hexString", "Streamed proof hashing returns canonical SHA-256");
requireText(models, "var sourceFileURL: URL? = nil", "Large proof uploads keep a transient local file URL");
rejectText(models, "case sourceFileURL", "Transient proof file URLs are never Codable persistence fields");
requireText(models, "var pendingRemoteMutation: PendingRemoteMutationAttempt?", "Check-in drafts persist ambiguous mutation attempts");
requireText(appState, 'let scope = "sport-record:create"', "Check-in creation resolves a stable logical attempt");
requireText(appState, 'let scope = "exemption:create:physical-test"', "Exemption creation resolves a stable logical attempt");
requireText(appState, 'let scope = "exemption:supplement:', "Exemption supplements resolve a stable logical attempt");
requireText(appState, "for index in attempt.uploadedProofs.count..<sourceProofs.count", "Check-in retry skips proofs already uploaded to COS");
requireCount(appState, "idempotencyKey: attempt.idempotencyKey", 3, "AppState passes its stable key to all three remote mutations");
requireText(localStore, 'pendingMutationStorageKey = "bnbu.student.remote.mutations.v1"', "Pending attempts have a dedicated protected journal");
requireText(localStore, "readPendingRemoteMutations", "Pending attempt journal is restored on launch");
requireText(localStore, "savePendingRemoteMutations", "Pending attempt journal is durably updated");
requireText(localStore, "clearPendingRemoteMutations", "Pending attempt journal has explicit cleanup");
requireText(localStore, "return defaults.data(forKey: key) == data", "Defaults-backed journal writes are verified by exact read-back");
requireText(localStore, "shouldFailRemoval", "Pending-journal removal failures are injectable for behavior tests");
requireText(localStore, "guard shouldFailRemoval?(key) != true else { return false }", "Injected removal failures return a strict failure signal");
requireText(appState, "localStore.readPendingRemoteMutations()", "AppState restores all pending mutation scopes at startup");
requireText(appState, "clearAllPendingRemoteMutations()", "Session boundaries discard durable mutation attempts");
requireText(appState, "sanitizePersistedRemoteMutations", "Persisted mutation attempts are validated after login");
requireText(appState, "attempt.serverIdentity == remoteMutationServerIdentity", "Restored attempts reject another server");
requireText(appState, "attempt.studentID == studentID", "Restored attempts reject another account");
requireText(appState, "RemoteMutationJournalPolicy.shouldRetain(after: error)", "All three flows use one phase-independent journal error policy");
requireText(appState, "try storePendingRemoteMutation(attempt)", "Remote writes require a confirmed durable attempt");
requireText(appState, "throw RemoteMutationJournalError.writeFailed", "Journal persistence fails closed before further network writes");
requireText(appState, "if attempt.isServerConfirmed", "Server-confirmed entries dispatch to cleanup-only recovery");
requireCount(appState, "guard !attempt.isServerConfirmed else {", 3, "All three original forms block a server-confirmed mutation before network work");
requireText(appState, "retainServerConfirmedAttemptInMemory(attempt)", "Failed success-marker cleanup remains visibly server-confirmed");
requireText(appState, "pendingRemoteMutations[attempt.scope] = previous", "Failed journal writes roll back the published in-memory attempt");
requireText(models, "case finalMutationPrepared", "The journal records preparation immediately before a final mutation");
requireText(models, "case serverConfirmed", "The journal distinguishes server success from ambiguous completion");
requireText(models, "mutating func markServerConfirmed", "All successful flows can enter the cleanup-only state");
requireText(appState, "try removePendingRemoteMutationStrict(scope: scope)", "Deterministic failures clear only their affected scope");
requireText(appState, "canResumePendingCheckIn", "A fully uploaded persisted attempt can resume without original bytes");
requireText(appState, "pendingExemptionFormRecovery", "Exemption forms can recover their persisted payload and proof identity");
requireText(appState, "canResumePendingExemption", "Exemption retries can continue without original bytes after all uploads completed");
requireText(appState, "func discardPendingRemoteMutation(scope: String)", "Every pending scope exposes a safe explicit discard API");
requireText(appState, "func canRetryPendingRemoteMutation(scope: String)", "Every pending scope exposes readiness for a user-triggered retry");
requireText(appState, "func retryPendingRemoteMutation(scope: String) async", "Every pending scope has a journal-backed retry dispatcher");
requireText(profileView, 'SectionTitle(eyebrow: "RECOVERY", title: "本地恢复操作")', "Profile enumerates mutation recovery and cleanup state");
requireText(profileView, "appState.pendingRemoteMutationSummaries", "Profile lists all pending scopes");
requireText(profileView, "appState.retryPendingRemoteMutation(scope:", "Profile exposes user-triggered retry for every ready scope");
requireText(profileView, 'summary.isServerConfirmed ? "仅清理本地标记" : "继续安全重试"', "Profile labels server-confirmed recovery as local cleanup only");
requireText(profileView, "appState.discardPendingRemoteMutation(scope:", "Profile exposes per-scope discard");
requireText(profileView, '"放弃这次待重试操作？"', "Per-scope discard requires destructive confirmation");
requireText(remote, "case serverError(statusCode: Int, code: String?, message: String)", "Server mutation errors preserve HTTP status and API code");
requireCount(remote, ".serverError(statusCode: statusCode, code: error.code, message: error.message)", 2, "Both backend error envelopes preserve API codes");
requireText(remote, 'statusCode == 409 && normalizedCode.hasPrefix("IDEMPOTENCY_")', "Every backend IDEMPOTENCY_* conflict retains the logical attempt");
requireText(remote, "[408, 425, 429].contains(statusCode)", "Timeout, Too Early and rate-limit responses retain the logical attempt");
requireText(remote, 'request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")', "Repository sends the stable Idempotency-Key header");
requireText(remote, '"student/physical-test-exemptions"', "Exemptions use the canonical physical-test route");
requireText(remote, '"student/physical-test-exemptions/\\(application.id)/supplements"', "Exemption supplements use the canonical route");
requireText(openapi, "/student/physical-test-exemptions/{id}/supplements:", "OpenAPI publishes canonical exemption supplements");
rejectText(remote, 'post("student/exemptions"', "iOS no longer writes through the deprecated exemption route");
rejectText(remote, 'get("student/exemptions")', "iOS no longer lists through the deprecated exemption route");
requireText(models, "case supplementRequired", "Supplement-required exemption state remains distinct");
requireText(models, "case expired", "Expired exemption state remains distinct");
requireText(models, "var canSupplement: Bool", "Exemption supplement eligibility is explicit");
requireText(gradesView, "if application.status.canSupplement", "Only actionable exemptions expose the supplement button");
requireText(gradesView, 'Label("补充材料"', "iOS exposes the exemption supplement action");
requireText(profileView, ".sheet(item: $supplementApplication)", "The exemption center presents the supplement form");
rejectText(gradesView, "免测接口暂不支持补材料", "Stale unsupported-supplement copy is removed");
requireText(components, "@MainActor\n    final class Coordinator", "UIKit camera callbacks are MainActor isolated");

requireText(localStore, ".completeFileProtection", "Student caches use complete file protection");
requireText(localStore, "FileProtectionType.complete", "Protected storage applies NSFileProtectionComplete");
requireText(localStore, "isExcludedFromBackup = true", "Student caches are excluded from cloud backup");
requireText(localStore, "SHA256.hash", "Account/server cache filenames do not reveal identifiers");
requireText(localStore, "clearRemoteWorkspace", "A single account cache can be erased on logout");
requireText(remote, "makeProtectedMultipartBodyFile", "Multipart uploads use protected temporary files");
requireText(remote, "fromFile: bodyFileURL", "Large uploads stream from a file instead of duplicating request Data");
requireText(remote, "defer { try? FileManager.default.removeItem(at: bodyFileURL) }", "Multipart files are deleted after every upload result");
requireText(remote, "removeStaleUploadFiles", "Crash-leftover multipart files are cleaned on repository startup");
requireText(remote, "attachment.uploadData != nil || attachment.sourceFileURL != nil", "Proof upload accepts bounded Data or a file-backed source");
requireText(remote, "FileHandle(forReadingFrom: sourceFileURL)", "Large multipart bodies stream from the local proof file");
requireText(remote, "sourceHandle.read(upToCount: ProofContentDigest.streamingChunkBytes)", "Multipart file copying is also bounded");
requireText(remote, "ProofTransientFileStore.removeStaleCopies()", "Crash-leftover local proof copies are removed on startup");
requireText(components, "struct ImportedProofFile: Transferable", "PhotosPicker imports large proofs as file representations");
requireText(components, "FileRepresentation(importedContentType: .movie)", "Photo-library videos remain file-backed");
requireText(components, "let digest = try ProofContentDigest.sha256(fileURL: fileURL)", "Photo-library file identity uses streaming SHA-256");
requireText(components, "let digest = try ProofContentDigest.sha256(fileURL: protectedURL)", "Camera video identity uses streaming SHA-256");
requireText(models, "attributes: [.protectionKey: FileProtectionType.complete]", "Transient proof files use complete file protection");
requireText(models, "values.isExcludedFromBackup = true", "Transient proof files are excluded from backup");

requireText(debugInfoPlist, "<key>NSAllowsArbitraryLoads</key>\n\t\t<false/>", "Debug ATS arbitrary network access is disabled");
requireText(debugInfoPlist, "<key>NSAllowsLocalNetworking</key>\n\t\t<true/>", "Debug keeps local simulator networking");
requireText(debugInfoPlist, "<key>123.207.5.70</key>", "Debug has a narrow temporary HTTP test-host exception");
requireText(releaseInfoPlist, "<key>NSAllowsArbitraryLoads</key>\n\t\t<false/>", "Release ATS arbitrary network access is disabled");
rejectText(releaseInfoPlist, "NSAllowsLocalNetworking", "Release does not allow local networking");
rejectText(releaseInfoPlist, "NSExceptionDomains", "Release contains no insecure HTTP exception");
rejectText(releaseInfoPlist, "123.207.5.70", "Release plist contains no staging host");
rejectText(debugInfoPlist + releaseInfoPlist, "NSTemporaryExceptionAllowsInsecureHTTPLoads", "Deprecated ATS exceptions are absent");
requireText(debugInfoPlist + releaseInfoPlist, "NSCameraUsageDescription", "Camera access has a purpose description");
requireText(debugInfoPlist + releaseInfoPlist, "NSMicrophoneUsageDescription", "Video audio access has a purpose description");
rejectText(debugInfoPlist + releaseInfoPlist, "NSPhotoLibraryUsageDescription", "System PhotosPicker avoids broad photo-library permission");
rejectText(components, "PHPhotoLibrary.requestAuthorization", "Photo selection does not request full library access");
requireText(components, ".photosPicker(", "Photo evidence uses the system privacy-preserving picker");

requireText(privacyManifest, "<key>NSPrivacyTracking</key>\n\t<false/>", "Privacy manifest declares no tracking");
requireText(privacyManifest, "NSPrivacyAccessedAPICategoryUserDefaults", "Privacy manifest declares UserDefaults required-reason API");
requireText(privacyManifest, "CA92.1", "UserDefaults access has the app-only required reason");
for (const dataType of ["UserID", "Fitness", "PhotosorVideos", "OtherUserContent", "SensitiveInfo", "PreciseLocation"]) {
  requireText(privacyManifest, `NSPrivacyCollectedDataType${dataType}`, `Privacy manifest declares ${dataType}`);
}

rejectText(debugInfoPlist + releaseInfoPlist, "CFBundleURLTypes", "No custom URL-scheme deep-link surface is registered");
rejectText(project, "com.apple.developer.associated-domains", "No unreviewed universal-link entitlement is enabled");
rejectText(appSources, ".onOpenURL", "App has no implicit deep-link handler");

rejectPattern(appSources, /(^|[^A-Za-z0-9_])print\s*\(/m, "Runtime source does not print sensitive values");
rejectText(appSources, "NSLog(", "Runtime source does not use unredacted NSLog");
requireText(remote, 'return "服务器未能处理该请求，请检查提交内容或稍后重试。"', "Unknown backend errors are sanitized before display");

requireText(project, 'INFOPLIST_FILE = "BNBUStudentApp/Resources/Info-Debug.plist";', "Debug uses the debug-only ATS plist");
requireText(project, "INFOPLIST_FILE = BNBUStudentApp/Resources/Info.plist;", "Release uses the hardened plist");
requireText(project, 'BNBU_API_BASE_URL = "https://configuration-required.invalid/api/v1";', "Release starts with an explicit non-shippable API placeholder");
requireText(project, "Validate Release Configuration", "Xcode runs the Release configuration gate");
requireText(releaseValidator, 'if [ "${CONFIGURATION:-}" != "Release" ]', "Release validator leaves Debug builds untouched");
requireText(releaseValidator, "configuration-required.invalid", "Release validator rejects the placeholder host");
requireText(releaseValidator, "*/api/v1", "Release validator enforces the frozen API prefix");
requireText(macReleaseGate, "set -Eeuo pipefail", "Mac Release gate fails closed on shell errors");
for (const step of [
  "preflight",
  "static_audit",
  "debug_clean_build",
  "xctest",
  "xcuitest",
  "release_build_unsigned",
  "release_analyze_unsigned"
]) {
  requireText(macReleaseGate, step, `Mac Release gate records ${step}`);
}
requireText(macReleaseGate, "write_summary_with_bash", "Mac Release gate can write its summary without Node");
requireText(macReleaseGate, "command -v node", "Mac Release gate selects the available JSON writer safely");
requireText(macReleaseGate, "BNBU_IOS_RELEASE_GATE_RESULT", "Mac Release gate emits a machine-readable final marker");
requireText(macReleaseGate, "summary.json", "Mac Release gate persists a machine-readable summary");
requireText(macReleaseGate, "validate_release_api_url", "Mac Release gate validates the formal API URL before building");
requireText(macReleaseGate, 'url.protocol !== "https:"', "Mac Release gate requires HTTPS for formal builds");
requireText(macReleaseGate, "CODE_SIGNING_ALLOWED=NO", "Mac Release gate supports unsigned CI build and analysis");
requireText(macReleaseGate, "only-testing:BNBUStudentTests", "Mac Release gate executes the XCTest target");
requireText(macReleaseGate, "only-testing:BNBUStudentUITests", "Mac Release gate executes the XCUITest target");
requireText(macReleaseGate, "redact_release_url_from_log", "Mac Release gate redacts the formal API URL from logs");
requireText(project, "COPY_PHASE_STRIP = YES;", "Release strips copied symbols");
requireText(project, "STRIP_INSTALLED_PRODUCT = YES;", "Release strips the installed product");
requireText(project, 'SWIFT_OPTIMIZATION_LEVEL = "-O";', "Release enables Swift optimization");

requireText(components, 'accessibilityLabel("删除凭证 \\(attachment.fileName)")', "Proof deletion has a descriptive VoiceOver label");
requireText(components, ".accessibilityElement(children: .combine)", "Status rows expose combined VoiceOver context");
requireText(loginView, '.accessibilityLabel("学号或邮箱")', "Login account field has an explicit accessibility label");
requireText(gradesView, '.accessibilityLabel("情况说明")', "Exemption detail editor has an explicit accessibility label");
requireText(profileView, '"退出登录？"', "Logout requires user confirmation");

for (const sourceName of [
  "RemoteStudentRepository.swift",
  "SecureCredentialStore.swift",
  "AppLocalStore.swift",
  "Models.swift",
  "AppState.swift",
  "CoursesView.swift",
  "GradesView.swift"
]) {
  requireText(project, sourceName, `Xcode project contains ${sourceName}`);
}
requireText(project, "PrivacyInfo.xcprivacy in Resources", "Xcode copies the privacy manifest into the app");

requireText(modelTests, "testCurrentBackendStudentWorkspacePayloadsDecode", "XCTest covers current workspace payload shapes");
requireText(modelTests, "testRecordValidityMapsLegacyReviewStatesOntoValidInvalid", "XCTest covers legacy review-state mapping onto validity");
requireText(modelTests, "testMutationResultsAreNotMistakenForCompleteDomainObjects", "XCTest covers mutation-result classification");
requireText(modelTests, "testStudentProgressWithoutIdentityFailsClosedToEmptyIdentifier", "XCTest covers missing progress identity without a hard-coded student fallback");
requireText(modelTests, "testSubmissionHoursAlwaysMatchBackendOneOrTwoHourContract", "XCTest covers the hours enum");
requireText(modelTests, "testDailySubmissionBoundaryUsesChinaTimeAndFractionalISODate", "XCTest covers the China-time daily boundary");
requireText(modelTests, "testExemptionProofRuleStopsAtFiveBackendReferences", "XCTest covers exemption proof count");
requireText(modelTests, "testExemptionReasonMatchesBackendLengthContract", "XCTest covers exemption reason length");
requireText(modelTests, "testCheckInDescriptionStopsAboveTwoHundredCharacters", "XCTest covers check-in description length");
requireText(modelTests, "testPersistedLocalProofRequiresOriginalFileReselection", "XCTest covers restored proof integrity");
requireText(modelTests, "testMembershipAndExemptionStatusDecodeCurrentNullableBackendShape", "XCTest covers nullable identity and exemption statuses");
requireText(modelTests, "testProductionURLValidationRejectsPlaceholderAndInsecureHosts", "XCTest covers Release API URL validation");
requireText(modelTests, "testMutationGateRejectsDuplicateInFlightOperationUntilCompletion", "XCTest covers duplicate in-flight mutation rejection");
requireText(modelTests, "testAccessTokenMigratesFromDefaultsToDeviceCredentialStore", "XCTest covers plaintext-token migration");
requireText(modelTests, "testLogoutIsLocalAndClearsSecureCredentialWithoutServerEndpoint", "XCTest covers local-only logout");
requireText(modelTests, "testLogoutInvalidatesLoginResponseThatFinishesLater", "XCTest covers logout-versus-login race handling");
requireText(modelTests, "testCourseRelatedSubmissionKeepsCourseReferenceWhileGeneralOmitsIt", "XCTest covers course references and taskId-free submission bodies");
requireText(modelTests, "testProofUploadUsesOnlyFrozenV1EndpointAndCleansTemporaryBody", "XCTest covers the sole v1 upload path and temporary-file cleanup");
requireText(modelTests, "testProtectedLocalStoreUsesFilesExcludedFromBackup", "XCTest covers protected file persistence");
requireText(modelTests, "testAppStateLogoutClearsDraftAndPersistedLocalState", "XCTest covers logout cleanup of drafts and caches");
requireText(modelTests, "testIdempotencyAttemptMatchesOnlySamePayloadAccountAndServer", "XCTest covers payload/account/server attempt isolation");
requireText(modelTests, "testCheckInAmbiguousRetryReusesUploadedProofBodyAndIdempotencyKey", "XCTest covers restart-safe same-key, same-body retry without re-upload");
requireText(modelTests, "testExemptionMutationsRecoverSamePayloadKeyAndUploadedReferencesAfterRestart", "XCTest covers restart-safe recovery for both exemption mutations");
requireText(modelTests, "testAllPendingMutationScopesRoundTripWithoutRawBytesThumbnailsOrSignedURLs", "XCTest covers the safe journal representation for every scope");
requireText(modelTests, "testPendingMutationSummariesAllowPerScopeDiscardAndLogoutCleanup", "XCTest covers per-scope discard and logout cleanup");
requireText(modelTests, "testDeterministicClientErrorDiscardsCheckInAttemptJournal", "XCTest covers deterministic 4xx journal cleanup");
requireText(modelTests, "testUploadStageDeterministicClientErrorClearsEachMutationScope", "XCTest covers upload-stage deterministic cleanup in all flows");
requireText(modelTests, "testUploadStageAmbiguousNetworkErrorRetainsEachMutationScope", "XCTest covers upload-stage ambiguous retention in all flows");
requireText(modelTests, "testInitialJournalWriteFailureBlocksUploadAndFinalMutationForAllFlows", "XCTest covers fail-closed initial journal persistence in all flows");
requireText(modelTests, "testUploadedProofReferenceWriteFailureBlocksFinalMutationForAllFlows", "XCTest covers fail-closed proof-reference persistence in all flows");
requireText(modelTests, "testServerConfirmedCleanupFailureNeverResubmitsAndClearsOnNextLoginForAllFlows", "XCTest covers cleanup failure, no-resubmit and later cleanup in all flows");
requireText(modelTests, 'XCTAssertTrue(authoritativeProof.source.hasPrefix("https://"))', "XCTest verifies the authoritative signed proof URL is reloaded after restart retry success");
requireText(modelTests, "testProofContentDigestSurvivesDraftRoundTripWithoutPersistingOriginalBytes", "XCTest covers proof fingerprint persistence and changed-byte detection");
requireText(modelTests, "testRemoteMutationFingerprintReusesIdentityWhenSameContentIsRenamed", "XCTest covers same-content rename and metadata-stable attempt identity");
requireText(modelTests, "testRemoteMutationFingerprintChangesWhenAttachmentBytesChange", "XCTest covers changed bytes rotating attempt identity");
requireText(modelTests, "testProofContentDigestStreamsFileInBoundedChunks", "XCTest audits bounded multi-chunk file hashing");
requireText(modelTests, "observedChunkSizes.allSatisfy", "XCTest asserts the streaming SHA-256 buffer ceiling");
requireText(modelTests, "XCTAssertFalse(journalText.contains(fileURL.path))", "XCTest proves the pending journal excludes transient local proof URLs");
requireText(modelTests, "testChangedCheckInPayloadStartsNewIdempotencyAttemptAndUploadSet", "XCTest covers changed payload receiving a new key and upload set");
requireText(modelTests, "testCanonicalMutationRoutesCarryExplicitIdempotencyKeys", "XCTest covers all four canonical idempotent mutation routes");
requireText(modelTests, "testIdempotencyConflictCodesRemainStructuredAndAmbiguous", "XCTest covers IDEMPOTENCY_CONFLICT and IDEMPOTENCY_KEY_REUSED retention");
requireText(modelTests, "testAppStateSupplementsOnlyActionableExemptionStatuses", "XCTest covers exemption supplement eligibility and state transition");

console.log(`PASS iOS contract audit (${openapiPath})`);
