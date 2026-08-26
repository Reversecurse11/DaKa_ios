import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const iosRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = join(iosRoot, "..");
const normalizeLF = (value) => value.replace(/\r\n?/gu, "\n");
const read = (...parts) => normalizeLF(readFileSync(join(...parts), "utf8"));

const remote = read(iosRoot, "BNBUStudentApp", "Core", "RemoteStudentRepository.swift");
const models = read(iosRoot, "BNBUStudentApp", "Core", "Models.swift");
const appState = read(iosRoot, "BNBUStudentApp", "Core", "AppState.swift");
const checkIn = read(iosRoot, "BNBUStudentApp", "Features", "CheckInView.swift");
const components = read(iosRoot, "BNBUStudentApp", "Features", "Components.swift");
const courseJoin = read(iosRoot, "BNBUStudentApp", "Features", "CourseJoinViews.swift");
const details = read(iosRoot, "BNBUStudentApp", "Features", "DetailViews.swift");
const feedback = read(iosRoot, "BNBUStudentApp", "Features", "FeedbackViews.swift");
const grades = read(iosRoot, "BNBUStudentApp", "Features", "GradesView.swift");
const login = read(iosRoot, "BNBUStudentApp", "Features", "LoginView.swift");
const profile = read(iosRoot, "BNBUStudentApp", "Features", "ProfileDetailViews.swift");
const profileView = read(iosRoot, "BNBUStudentApp", "Features", "ProfileView.swift");
const studentExperience = read(iosRoot, "BNBUStudentApp", "Features", "StudentExperienceViews.swift");
const mockRepository = read(iosRoot, "BNBUStudentApp", "Core", "MockStudentRepository.swift");
const tests = read(iosRoot, "BNBUStudentTests", "BNBUStudentModelTests.swift");
const debugInfo = read(iosRoot, "BNBUStudentApp", "Resources", "Info-Debug.plist");
const releaseInfo = read(iosRoot, "BNBUStudentApp", "Resources", "Info.plist");
const privacy = read(iosRoot, "BNBUStudentApp", "Resources", "PrivacyInfo.xcprivacy");
const openapi = read(repoRoot, "docs", "backend-contracts", "openapi.yaml");

function containsAll(source, tokens, label) {
  for (const token of tokens) {
    assert.ok(source.includes(token), `${label} missing: ${token}`);
  }
}

function ordered(source, tokens, label) {
  let cursor = -1;
  for (const token of tokens) {
    const next = source.indexOf(token, cursor + 1);
    assert.notEqual(next, -1, `${label} missing: ${token}`);
    assert.ok(next > cursor, `${label} out of order: ${token}`);
    cursor = next;
  }
}

// The public contract owns the formal +60-minute product operation. The old
// internal duration-advance helper remains isolated for automation only.
containsAll(openapi, [
  "/exercise-records/{recordId}/resubmissions:",
  "/exercise-records/{recordId}/attempt-context:",
  "/exemption-applications/{applicationId}/media-uploads:",
  "/me/account-deletion-challenges:",
  "/me/account-deletion-challenges/{challengeId}/confirm:",
  "CreateExerciseRecordResubmissionRequest:",
  "InitiateExemptionApplicationMediaUploadRequest:",
  "AccountDeletionStudentChallengeRequest:",
  "ConfirmStudentAccountDeletionRequest:",
  "/feedback:",
  "CreateFeedbackRequest:",
  "FeedbackListEnvelope:",
  "/exercise-sessions/{sessionId}/add-sixty-minutes:",
], "OpenAPI R02 contract");
assert.ok(!openapi.includes("internal/test-tools"));

// Client test tools require an explicit non-production build/runtime flag and
// the authenticated Backend capability. Release remains compile-time false.
containsAll(remote, [
  "enum StudentTestToolsConfig",
  'durationAdvanceCapability = "TEST_DURATION_ADVANCE"',
  "guard isDebugBuild else { return false }",
  'environment == "local" || environment == "test" || environment == "staging"',
  "enabled == \"true\" || enabled == \"1\"",
  "#if DEBUG",
  "#else\n        return false",
  "exerciseTestToolsEnabled: Bool = StudentTestToolsConfig.isEnabled",
  "func exerciseTestToolCapabilities() async throws -> Set<String>",
  'get("internal/test-tools/capabilities")',
  "func advanceExerciseSessionTestDuration(",
  "guard exerciseTestToolsEnabled else",
  "internal/test-tools/exercise-sessions/\\(sessionId)/advance-duration",
  "[\"expectedVersion\": expectedVersion]",
  "return try await getExerciseSession(sessionId: sessionId)",
], "iOS +60 transport");
const advanceTransport = remote.slice(
  remote.indexOf("func advanceExerciseSessionTestDuration("),
  remote.indexOf("func uploadExerciseEvidence(", remote.indexOf("func advanceExerciseSessionTestDuration(")),
);
assert.ok(!advanceTransport.includes("let current = try await getExerciseSession"));
ordered(advanceTransport, [
  "_ = try await post(",
  "return try await getExerciseSession(sessionId: sessionId)",
], "iOS +60 POST then authoritative GET");
containsAll(appState, [
  "func addSixtyMinutesToExerciseSession() async -> Bool",
  "remoteRepo.addSixtyMinutesToExerciseSession(",
  "applyingAuthoritativeDuration(",
], "iOS formal +60 state");
containsAll(checkIn, [
  "增加 60 分钟",
  "每次增加 60 分钟，由服务器记录并返回当前权威运动时长。",
  "checkin.add60Minutes",
], "iOS formal +60 UI");
assert.ok(!checkIn.includes("测试工具 · +60 分钟"));
assert.ok(!checkIn.includes("仅用于 Staging 测试，不代表真实运动时间"));
containsAll(debugInfo, [
  "<key>BNBUAppEnvironment</key>",
  "<string>local</string>",
  "<key>BNBUTestToolsEnabled</key>",
  "<false/>",
], "Debug test-tool defaults");
containsAll(releaseInfo, [
  "<key>BNBUAppEnvironment</key>",
  "<string>production</string>",
  "<key>BNBUTestToolsEnabled</key>",
  "<false/>",
], "Release test-tool defaults");
containsAll(models, [
  "authoritativeDurationSeconds",
  "authoritativeDurationObservedAt",
  "func applyingAuthoritativeDuration(",
  "ADR-103: GENERAL exercise requires a description",
  "static func isDescriptionRequired(for category: ExerciseCategory)",
  "category == .general",
  "static func validationMessage(note: String, for category: ExerciseCategory)",
], "authoritative duration model");
containsAll(checkIn, [
  "required: CheckInInputRule.isDescriptionRequired(for: session.category)",
  "课程相关运动可选",
  "for: session.category",
], "ADR-103 conditional exercise description UI");
containsAll(appState, [
  "CheckInInputRule.validationMessage(note: note, for: creditType)",
], "ADR-103 submission validation");

// Major iOS forms use the same native field semantics while preserving
// SwiftUI keyboard, Dynamic Type and VoiceOver behavior. This is source-only
// evidence; native accessibility interaction remains deferred to Xcode/device.
containsAll(components, [
  "struct BNBUFormField: View",
  "struct BNBUTextArea: View",
  "var required = false",
  "var helperText: String?",
  "var errorText: String?",
  "var successText: String?",
  "var characterLimit: Int?",
  "var textContentType: UITextContentType?",
  "var isSecure = false",
  "var loading = false",
  "var submitLabel: SubmitLabel = .done",
  "var focusBinding: FocusState<Bool>.Binding?",
  "Label(errorText, systemImage: \"exclamationmark.circle.fill\")",
  ".frame(minHeight: 112)",
], "shared iOS input semantics");
containsAll(login, [
  "BNBUFormField(",
  "textContentType: .emailAddress",
  "textContentType: .oneTimeCode",
  "onFocusChanged:",
  "accessibilityIdentifier: \"verification.contact\"",
  "accessibilityIdentifier: \"verification.code\"",
  "onSubmit: { if canSubmit { signIn() } }",
], "login and OTP inputs");
containsAll(courseJoin, [
  "accessibilityIdentifier: \"course.join.code.field\"",
  "accessibilityIdentifier: \"courseJoinConfirm.gradeYear\"",
  "accessibilityIdentifier: \"courseJoin.emailBinding.email\"",
  "accessibilityIdentifier: \"courseJoin.emailBinding.code\"",
], "course join inputs");
containsAll(feedback, [
  "BNBUTextArea(",
  "accessibilityIdentifier: \"feedback.description\"",
  "focusBinding: $descriptionFocused",
  "accessibilityIdentifier(\"feedback.privacyBoundary\")",
  "不会收集或发送邮箱、电话、截图、日志、Token 或设备标识",
], "feedback inputs");
assert.ok(!feedback.includes("accessibilityIdentifier: \"feedback.email\""));
assert.ok(!feedback.includes("accessibilityIdentifier: \"feedback.phone\""));
assert.ok(!feedback.includes("FeedbackScreenshotPanel(screenshots:"));
containsAll(grades, [
  "accessibilityIdentifier: \"exemption.organization.field\"",
  "accessibilityIdentifier: \"exemption.reason.field\"",
  "accessibilityIdentifier: \"exemption.detail.editor\"",
  "submittedForm = true",
], "exemption inputs");
containsAll(profileView, [
  "identifier: \"endurance.minutes\"",
  "identifier: \"endurance.seconds\"",
  "focusBinding: $minutesFocused",
  "focusBinding: $secondsFocused",
], "endurance inputs");
containsAll(checkIn, [
  "accessibilityIdentifier: \"checkin.sport.otherName\"",
  "accessibilityIdentifier(\"checkin.sport.error\")",
  "accessibilityIdentifier: \"checkin.note\"",
  "showValidationErrors: startAttempted",
  "customFocusBinding: $customSportFocused",
], "check-in inputs");
assert.ok(!profileView.includes("TextField(placeholder, text: text)"));
assert.ok(!checkIn.includes("TextField(\"具体运动名称\""));
containsAll(studentExperience, [
  "学生端使用学校邮箱验证码登录，不使用账号密码",
  "全部已确认保留素材会自动作为本次凭证提交",
  "确认保留后不能在最终提交时排除",
  "处理中或处理失败都会阻止提交",
], "student help business rules");
containsAll(mockRepository, [
  "全部已确认素材会自动进入本次凭证",
  "确认保留后不能在最终提交时排除",
], "mock help business rules");

// An INVALID historical attempt is read-only. A new completed Session creates
// a new DRAFT through the dedicated resubmission operation, then uses the
// ordinary submit operation with all retained evidence.
containsAll(remote, [
  "func getExerciseRecordAttemptContext(",
  "exercise-records/\\(recordId)/attempt-context",
  "previous.status == \"REVIEWED\"",
  "previous.currentReview?.result == \"INVALID\"",
  "exercise-records/\\(previousRecordId)/resubmissions",
  "resubmissionBody[\"expectedVersion\"] = previous.version",
  "resubmission.attemptContext.previousAttemptId == previousRecordId",
], "resubmission transport");
containsAll(appState, [
  "ExerciseRecordResubmissionSelection",
  "previousRecordId",
  "prepareExerciseRecordResubmission",
  "requestFields[\"previousRecordId\"]",
], "resubmission persistence");
containsAll(details, [
  "上一次提交已被拒绝",
  "原记录和审核结果会永久保留",
  "重新补交 · 第",
], "resubmission UI");

// Exemption uploads are scoped to the current application. A server-created
// DRAFT identifier is journalled before upload, so a restart cannot create a
// second draft or count immutable historical evidence against the new quota.
containsAll(remote, [
  "func createExemptionDraft(",
  "exemptionApplicationId: applicationId",
  "exemption-applications/\\(try Self.pathComponent(exemptionApplicationId))/media-uploads",
  "func updateAndSubmitCreatedExemption(",
], "scoped exemption transport");
containsAll(models, [
  "var targetResourceID: String?",
  "mutating func bindTargetResource(id: String, expectedVersion: Int)",
  "case targetResourceID",
], "scoped exemption journal");
containsAll(appState, [
  "attempt.bindTargetResource(",
  "id: draft.applicationId",
  "expectedVersion: draft.expectedVersion",
  "applicationId: applicationId",
  "targetResourceID",
], "scoped exemption state");

// Student account deletion uses two destructive confirmations around email
// OTP reauthentication and clears all local state only after Backend success.
containsAll(remote, [
  "func requestAccountDeletionChallenge(",
  "me/account-deletion-challenges",
  "\"expectedVersion\": current.user.version",
  "\"locale\": locale",
  "func confirmAccountDeletion(",
  "me/account-deletion-challenges/\\(challengeId)/confirm",
  "\"verificationCode\": verificationCode",
  "result.allSessionsRevoked",
  "result.newRegistrationRequired",
  "invalidateInMemorySession()",
  "clearPersistedAccessToken()",
  "ACCOUNT_DELETION_ACTIVE_SESSION",
  "ACCOUNT_DELETION_PENDING_REVIEW",
  "ACCOUNT_DELETION_REAUTH_REQUIRED",
], "account deletion transport and errors");
containsAll(profile, [
  "struct AccountDeletionView: View",
  "if let challenge",
  "explanationPanel",
  "verificationPanel(challenge)",
  "showInitialConfirmation",
  "showFinalConfirmation",
  "注销账户",
  "邮箱验证码",
  "继续注销账户",
  "已填写验证码，继续最终确认",
  "永久注销账户",
  "textContentType: .oneTimeCode",
  "focusBinding: $verificationCodeFocused",
  "if isValidCode && !appState.isProcessingAccountDeletion",
], "account deletion UI");
containsAll(appState, [
  "func requestAccountDeletionChallenge(",
  "func confirmAccountDeletion(",
  "await logout()",
  "context: .accountDeletion",
], "account deletion state cleanup");

// Feedback is a real authenticated R02 capability. It follows the canonical
// cursor/idempotency/error pipeline and serializes only the OpenAPI allowlist.
containsAll(models, [
  "case bug = \"功能异常\"",
  "case suggestion = \"改进建议\"",
  "case accessibility = \"无障碍使用\"",
  "case privacy = \"隐私问题\"",
  "var apiValue: String",
], "feedback contract categories");
containsAll(remote, [
  "private struct ContractFeedbackPayload",
  "func listFeedback() async throws -> [FeedbackTicket]",
  "path: \"feedback\"",
  "func createFeedback(",
  "\"category\": category.apiValue",
  "\"content\": normalizedContent",
  "\"clientContext\": [",
  "\"platform\": \"IOS\"",
  "idempotencyKey: IdempotencyKeyPolicy.make()",
], "feedback transport");
containsAll(appState, [
  "func refreshFeedbackTickets() async",
  "try await remoteRepo.listFeedback()",
  "func submitFeedback(",
  "try await remoteRepo.createFeedback(",
  "context: .feedback",
  "feedbackTickets = []",
  "feedbackNotice = nil",
], "feedback state and errors");

// Source-only evidence is intentionally present on Windows. These assertions
// do not claim XCTest execution.
containsAll(tests, [
  "testStudentTestToolsRequireDebugAllowedEnvironmentAndExplicitFlag",
  "testExerciseTestToolCapabilityUsesAuthenticatedInternalRead",
  "testExerciseTestToolPostsExpectedVersionThenRefreshesAuthoritativeState",
  "testExerciseDurationUsesAuthoritativeServerSnapshotWithoutChangingStartTime",
  "testRejectedAttemptContextRoundTripsWithoutMutatingHistory",
  "testPendingMutationPersistsScopedExemptionTarget",
  "testExemptionMutationsRecoverSamePayloadKeyAndUploadedReferencesAfterRestart",
  "/api/v1/exemption-applications/ex-new/media-uploads",
  "testAccountDeletionErrorsUseSafeSpecificActions",
  "testStudentAccountDeletionUsesFrozenTwoStepContractAndClearsCredentials",
  "testFeedbackUsesPrivacyBoundedListAndCreateContract",
  "testFeedbackErrorMappingKeepsRequestIdAndHidesInternalCause",
  "XCTAssertNil(body[\"email\"])",
  "XCTAssertNil(body[\"phone\"])",
  "XCTAssertNil(clientContext[\"deviceId\"])",
  "testRejectedRecordResubmissionCreatesNewAttemptAndNeverMutatesOldRecord",
  "CheckInInputRule.validationMessage(note: \"\", for: ExerciseCategory.courseRelated)",
], "R02 Swift source tests");
containsAll(privacy, [
  "NSPrivacyTracking",
  "NSPrivacyCollectedDataTypes",
  "NSPrivacyAccessedAPITypes",
], "privacy manifest");

console.log("iOS R02 source audit passed");
