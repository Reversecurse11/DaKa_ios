import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const iosRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = join(iosRoot, "..");
const normalizeLF = (value) => value.replace(/\r\n?/gu, "\n");
const read = (path) => normalizeLF(readFileSync(path, "utf8"));
const remote = read(join(iosRoot, "BNBUStudentApp", "Core", "RemoteStudentRepository.swift"));
const appState = read(join(iosRoot, "BNBUStudentApp", "Core", "AppState.swift"));
const models = read(join(iosRoot, "BNBUStudentApp", "Core", "Models.swift"));
const checkIn = read(join(iosRoot, "BNBUStudentApp", "Features", "CheckInView.swift"));
const captureComponents = read(join(iosRoot, "BNBUStudentApp", "Features", "ExerciseCaptureComponents.swift"));
const sharedComponents = read(join(iosRoot, "BNBUStudentApp", "Features", "Components.swift"));
const dashboard = read(join(iosRoot, "BNBUStudentApp", "Features", "DashboardView.swift"));
const grades = read(join(iosRoot, "BNBUStudentApp", "Features", "GradesView.swift"));
const appEntry = read(join(iosRoot, "BNBUStudentApp", "BNBUStudentApp.swift"));
const openapi = read(join(repoRoot, "docs", "backend-contracts", "openapi.yaml"));
const openapiSnapshot = read(join(iosRoot, "openapi", "openapi.snapshot.yaml"));
const contractMetadata = JSON.parse(read(join(iosRoot, "openapi", "contract.json")));
const project = read(join(iosRoot, "BNBUStudent.xcodeproj", "project.pbxproj"));
const login = read(join(iosRoot, "BNBUStudentApp", "Features", "LoginView.swift"));
const courseJoin = read(join(iosRoot, "BNBUStudentApp", "Features", "CourseJoinViews.swift"));
const profile = read(join(iosRoot, "BNBUStudentApp", "Features", "ProfileView.swift"));
const profileDetails = read(join(iosRoot, "BNBUStudentApp", "Features", "ProfileDetailViews.swift"));
const courses = read(join(iosRoot, "BNBUStudentApp", "Features", "CoursesView.swift"));
const appShell = read(join(iosRoot, "BNBUStudentApp", "Features", "AppShellViews.swift"));
const releaseInfo = read(join(iosRoot, "BNBUStudentApp", "Resources", "Info.plist"));
const debugInfo = read(join(iosRoot, "BNBUStudentApp", "Resources", "Info-Debug.plist"));
const modelTests = read(join(iosRoot, "BNBUStudentTests", "BNBUStudentModelTests.swift"));
const uiTests = read(join(iosRoot, "BNBUStudentUITests", "BNBUStudentSmokeUITests.swift"));

function filesRecursively(directory, extension) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = join(directory, entry.name);
    if (entry.isDirectory()) return filesRecursively(fullPath, extension);
    return entry.isFile() && entry.name.endsWith(extension) ? [fullPath] : [];
  });
}

function stripDisabledSwiftBlocks(source) {
  const lines = source.split(/\r?\n/);
  let disabledDepth = 0;
  return lines.filter((line) => {
    if (/^\s*#if\s+false\b/.test(line)) {
      disabledDepth += 1;
      return false;
    }
    if (disabledDepth > 0 && /^\s*#if\b/.test(line)) {
      disabledDepth += 1;
      return false;
    }
    if (disabledDepth > 0 && /^\s*#endif\b/.test(line)) {
      disabledDepth -= 1;
      return false;
    }
    return disabledDepth === 0;
  }).join("\n");
}

function releaseSwiftProjection(source) {
  const lines = source.split(/\r?\n/);
  const stack = [];
  let included = true;
  const output = [];
  for (const line of lines) {
    if (/^\s*#if\s+DEBUG\b/.test(line)) {
      stack.push({ kind: "debug", parentIncluded: included });
      included = false;
      continue;
    }
    if (/^\s*#if\b/.test(line)) {
      stack.push({ kind: "other", parentIncluded: included });
      continue;
    }
    if (/^\s*#else\b/.test(line) && stack.length > 0) {
      const frame = stack.at(-1);
      if (frame.kind === "debug") included = frame.parentIncluded;
      continue;
    }
    if (/^\s*#endif\b/.test(line) && stack.length > 0) {
      const frame = stack.pop();
      included = frame.parentIncluded;
      continue;
    }
    if (included) output.push(line);
  }
  assert.equal(stack.length, 0, "unbalanced Swift conditional compilation block");
  return output.join("\n");
}

function section(source, start, end) {
  const from = source.indexOf(start);
  assert.notEqual(from, -1, `missing section start: ${start}`);
  const to = source.indexOf(end, from + start.length);
  assert.notEqual(to, -1, `missing section end: ${end}`);
  return source.slice(from, to);
}

function ordered(source, labels) {
  let cursor = -1;
  for (const label of labels) {
    const next = source.indexOf(label, cursor + 1);
    assert.notEqual(next, -1, `missing ordered token: ${label}`);
    assert.ok(next > cursor, `out-of-order token: ${label}`);
    cursor = next;
  }
}

function assertBalancedSwift(source, label) {
  const expectedCloser = { "(": ")", "[": "]", "{": "}" };
  const opening = new Set(Object.keys(expectedCloser));
  const closing = new Set(Object.values(expectedCloser));
  const stack = [];
  let state = "code";
  let blockDepth = 0;
  for (let index = 0; index < source.length; index += 1) {
    const character = source[index];
    const next = source[index + 1];
    const nextThree = source.slice(index, index + 3);
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
      if (nextThree === '\"\"\"') {
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
    if (nextThree === '\"\"\"') {
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
      assert.equal(expectedCloser[opener], character, `${label} has an unbalanced delimiter`);
    }
  }
  assert.ok(
    state !== "block-comment" && state !== "string" && state !== "multiline-string" && stack.length === 0,
    `${label} has an unterminated Swift token`
  );
  assert.ok(!source.includes("<<<<<<<"), `${label} contains a merge-conflict marker`);
}

for (const [label, source] of [
  ["RemoteStudentRepository.swift", remote],
  ["AppState.swift", appState],
  ["Models.swift", models],
  ["CheckInView.swift", checkIn],
  ["ExerciseCaptureComponents.swift", captureComponents],
  ["Components.swift", sharedComponents],
  ["DashboardView.swift", dashboard],
  ["GradesView.swift", grades],
  ["BNBUStudentApp.swift", appEntry],
  ["LoginView.swift", login],
  ["CourseJoinViews.swift", courseJoin],
  ["ProfileView.swift", profile],
  ["ProfileDetailViews.swift", profileDetails],
  ["BNBUStudentModelTests.swift", modelTests],
  ["BNBUStudentSmokeUITests.swift", uiTests],
]) {
  assertBalancedSwift(source, label);
}

assert.match(openapi, /version:\s*3\.0\.0-contract\b/);
assert.equal(openapiSnapshot, openapi, "iOS snapshot must LF-canonical-match the authoritative OpenAPI");
const contractHash = createHash("sha256").update(openapiSnapshot).digest("hex");
assert.equal(contractMetadata.contractVersion, "3.0.0-contract");
assert.equal(contractMetadata.sha256, "020594cb6c0dc220bf96f30326a04144cb8081ec44f56bc8b3746ea4001ace4f");
assert.equal(contractMetadata.byteLength, 348350);
assert.equal(Buffer.byteLength(openapiSnapshot, "utf8"), contractMetadata.byteLength);
assert.equal(contractHash, contractMetadata.sha256, "iOS snapshot hash must match contract.json");
for (const path of [
  "/exercise-sessions",
  "/exercise-sessions/{sessionId}/cancel",
  "/exercise-records",
  "/media-uploads",
  "/exemption-applications",
]) {
  assert.ok(openapi.includes(`  ${path}:`) || openapi.includes(`  ${path}/{`), `missing ${path}`);
}
const studentScoreContract = section(openapi, "  /student-scores:\n", "  /student-scores/{studentScoreId}:");
assert.ok(studentScoreContract.includes("allowedRoles: [STUDENT, TEACHER, ADMIN]"));
const studentScoreSchema = section(openapi, "    StudentScore:\n", "    ScoreContribution:\n");
for (const field of [
  "validCourseDurationSeconds",
  "validGeneralDurationSeconds",
  "totalValidDurationSeconds",
  "qualificationStatus",
]) assert.ok(studentScoreSchema.includes(field), `authoritative StudentScore schema missing ${field}`);
const scoreRuleContract = section(
  openapi,
  "  /class-sections/{classSectionId}/score-rules:\n",
  "  /score-rules/{scoreRuleId}:"
);
assert.ok(scoreRuleContract.includes("allowedRoles: [TEACHER, ADMIN]"));

assert.ok(remote.includes("let enrollmentId: String?"), "AuthSession.enrollmentId must stay optional");
assert.ok(
  remote.includes('path: "enrollments"') && remote.includes("getAllContractPages("),
  "nil enrollment must resolve through every ACTIVE enrollment page",
);
assert.ok(remote.includes('URLQueryItem(name: "status", value: "ACTIVE")'));
assert.ok(!remote.includes('post("auth/password-login"'), "student login must not use the staff password route");
assert.ok(remote.includes("installContractSession(rotated)"), "refresh must persist the rotated AuthSession");
assert.ok(remote.includes('url(for: "auth/refresh")'), "401 retry must use the refresh token route");
assert.ok(remote.includes("requestId: error.requestId"), "contract error requestId must be retained");
assert.ok(remote.includes('request.setValue(Self.makeRequestId(), forHTTPHeaderField: "X-Request-ID")'));

const authenticatedTransport = section(remote, "private func perform(_ request:", "private func refreshContractSession()");
ordered(authenticatedTransport, [
  "let failure = try apiError",
  "failure.isAccessTokenExpired",
  "refreshContractSession()",
  "mayRefresh: false",
  "failure.isTerminalAuthenticationFailure",
]);
assert.doesNotMatch(authenticatedTransport, /statusCode\s*==\s*401/);

const cancelRepositoryFlow = section(
  remote,
  "func cancelExerciseSession(",
  "func getExerciseSession(sessionId:"
);
ordered(cancelRepositoryFlow, [
  "getExerciseSession(sessionId: sessionId)",
  'if current.status == "CANCELLED"',
  '"exercise-sessions/\\(try Self.pathComponent(sessionId))/cancel"',
  '"expectedVersion": current.version',
]);
assert.ok(cancelRepositoryFlow.includes('current.status == "IN_PROGRESS" || current.status == "PAUSED"'));

const cancelAppFlow = section(
  appState,
  "func discardExerciseSessionAuthoritatively()",
  "/// The credit bucket a completed session's record belongs to."
);
assert.ok(cancelAppFlow.includes("guard isRemoteMode else"), "local abandon behavior must remain separate");
ordered(cancelAppFlow, [
  "remoteRepo.cancelExerciseSession(",
  'remote.status == "CANCELLED"',
  "localStore.clearExerciseSession()",
  "clearExerciseMediaDrafts(sessionID: session.id)",
  "exerciseSession = nil",
]);
assert.ok(checkIn.includes("await appState.discardExerciseSessionAuthoritatively()"));

const mutationJournal = section(
  models,
  "struct PendingRemoteMutationAttempt:",
  "struct PendingRemoteMutationSummary:"
);
for (const field of [
  "authoritativeSessionID",
  "authoritativeEnrollmentID",
  "preparedExpectedVersion",
  "preparedMediaIDs",
]) {
  assert.ok(mutationJournal.includes(`case ${field}`), `${field} must be Codable`);
  assert.ok(mutationJournal.includes(`forKey: .${field}`), `${field} must be decoded/encoded`);
}

const startFlow = section(
  appState,
  "func startExerciseSessionAuthoritatively(",
  "func reconcileExerciseSession("
);
assert.ok(startFlow.includes("remoteRepo.startOrRecoverExerciseSession"));
assert.ok(startFlow.includes("id: remote.id"));
assert.ok(!startFlow.includes("id: UUID().uuidString"), "remote start must not invent a sessionId");
assert.ok(!startFlow.includes("hasSubmittedCheckInToday"), "remote start must defer businessDate to Backend");
for (const token of [
  "recoverableLocalSessionId: recoverableLocalSession?.id",
  "localSession.id == session.id",
  "case .alreadyActive(let session, let requestId)",
  "existingRemoteExerciseSession = ExistingRemoteExerciseSession(",
  "exerciseSession = nil",
]) assert.ok(startFlow.includes(token), `cross-device Session boundary missing ${token}`);
assert.ok(startFlow.includes("courseContextMatches"), "same-device recovery must retain the protected local context");
assert.ok(appState.includes("func refreshExistingRemoteExerciseSession() async"));
assert.ok(checkIn.includes("ExistingRemoteExerciseSessionPanel("));
assert.ok(checkIn.includes("checkin.existingSession.refresh"));
assert.ok(checkIn.includes("checkin.existingSession.home"));

const captureEntry = section(
  captureComponents,
  "struct ExerciseCameraCaptureButton:",
  "private enum ExerciseCameraAlert:"
);
for (const token of [
  "pendingAttachment = attachment",
  "ExerciseCaptureConfirmationSheet(",
  'title: "确认保留"',
  'title: "重拍"',
  'title: "放弃"',
  "onCapture(attachment)",
]) assert.ok(captureEntry.includes(token), `pre-retention capture action missing ${token}`);
const retainedPanel = section(
  captureComponents,
  "struct ExerciseProofSelectionPanel:",
  "struct ExerciseMediaDraftCard:"
);
assert.doesNotMatch(retainedPanel, /Toggle\s*\(|onDelete|removeExerciseMediaDraft|selectedDraftIDs/);
assert.ok(retainedPanel.includes("ForEach(drafts)"));
assert.ok(appState.includes("var currentExerciseMediaDrafts: [ExerciseMediaDraft]"));
assert.ok(!appState.includes("func removeExerciseMediaDraft(id:"));
assert.ok(checkIn.includes("appState.currentExerciseMediaDrafts.compactMap"));
assert.doesNotMatch(checkIn, /selectedDraftIDs|toggleDraft|excludeDraft/);

const uploadFlow = section(
  remote,
  "private func uploadContractEvidence(",
  "private func waitForAvailableMedia(ids:"
);
ordered(uploadFlow, [
  '"media-uploads/\\(uploadSessionId)/confirm"',
  "if bindToSession",
  '"media/\\(try Self.pathComponent(media.id))/bind"',
  "waitForAvailableMedia(id: media.id)",
]);
assert.ok(uploadFlow.includes('["UPLOADED", "BOUND", "PROCESSING", "AVAILABLE"]'));

const createExemption = section(
  remote,
  "func createExemptionDraft(",
  "func updateAndSubmitCreatedExemption("
);
ordered(createExemption, [
  '"mediaIds": []',
  '"exemption-applications"',
  "ContractExemptionDraftPlan(",
]);

const submitCreatedExemption = section(
  remote,
  "func updateAndSubmitCreatedExemption(",
  "func prepareExemptionSupplement("
);
ordered(submitCreatedExemption, [
  'get("exemption-applications/\\(applicationId)")',
  'patch(',
  "waitForAvailableMedia(ids: current.mediaIds)",
  "submitContractExemption(",
]);

const updateExemption = section(
  remote,
  "func updateAndSubmitExemption(",
  "func exemptionEnrollmentID("
);
ordered(updateExemption, [
  'get("exemption-applications/\\(applicationId)")',
  'if current.status == "SUBMITTED"',
  "current.reason == expectedReason",
  "current.mediaIds == preparedMediaIds",
  'patch(',
  "waitForAvailableMedia(ids: updated.mediaIds)",
  "submitContractExemption(",
]);
assert.ok(updateExemption.includes('"expectedVersion": preparedExpectedVersion'));
assert.ok(updateExemption.includes('"mediaIds": preparedMediaIds'));

const prepareSupplement = section(
  remote,
  "func prepareExemptionSupplement(",
  "func updateAndSubmitExemption("
);
assert.ok(prepareSupplement.includes("Array(Set(current.mediaIds + newMediaIds)).sorted()"));
assert.ok(prepareSupplement.includes("preparedExpectedVersion") === false);

const recordFlow = section(appState, "private func submitCheckInRemote(", "private func submitExemptionRemote(");
assert.ok(recordFlow.includes("recoverySessionID ?? exerciseSession?.id"));
assert.ok(!recordFlow.includes("hasSubmittedCheckInToday"), "remote submit must not use a device-local day gate");
ordered(recordFlow, [
  "remoteRepo.getExerciseSession(sessionId: authoritativeSessionID)",
  "authoritativeSession.id == authoritativeSessionID",
  'authoritativeSession.status == "COMPLETED"',
  "authoritativeSession.enrollmentId != recoveryEnrollmentID",
  "checkInFingerprint(",
  "uploadExerciseEvidence(",
  "submitExerciseRecord(",
]);
assert.ok(recordFlow.includes("authoritativeSessionID: authoritativeSession.id"));
assert.ok(recordFlow.includes("authoritativeEnrollmentID: authoritativeSession.enrollmentId"));
assert.ok(recordFlow.includes("uploadExerciseEvidence("));
assert.ok(recordFlow.includes("submitExerciseRecord("));
assert.ok(!recordFlow.includes("remoteRepo.uploadProof("));
assert.ok(!recordFlow.includes("remoteRepo.submitCheckIn("));
const submitBoundary = section(appState, "func submitCheckIn(", "func submitExemption(");
for (const token of [
  "retainedDrafts",
  "materializedRetainedProofs",
  "effectiveProofAttachments",
  "retainedDrafts.isEmpty || materializedRetainedProofs.count == retainedDrafts.count",
]) assert.ok(submitBoundary.includes(token), `retained evidence submit boundary missing ${token}`);
const postSubmitRefresh = section(
  recordFlow,
  "var refreshedSubmittedRecord = false",
  "workspace.notices.insert("
);
assert.ok(postSubmitRefresh.includes("upsertCheckInRecord(submittedRecord)"));
assert.ok(postSubmitRefresh.includes("status: .queued"));
assert.ok(!postSubmitRefresh.includes("creditSubmittedExercise("));

const exemptionFlow = section(appState, "private func submitExemptionRemote(", "private func supplementExemptionRemote(");
assert.ok(exemptionFlow.includes("resolveActiveEnrollmentID("));
assert.ok(exemptionFlow.includes("createExemptionDraft("));
assert.ok(exemptionFlow.includes("uploadExemptionEvidence("));
assert.ok(exemptionFlow.includes("updateAndSubmitCreatedExemption("));

const supplementFlow = section(appState, "private func supplementExemptionRemote(", "private func resolvePersistentAttempt(");
assert.ok(supplementFlow.includes("exemptionEnrollmentID("));
assert.ok(supplementFlow.includes("updateAndSubmitExemption("));
assert.ok(!supplementFlow.includes("supplemented.status = .pending"));
ordered(supplementFlow, [
  "prepareExemptionSupplement(",
  "attempt.markFinalMutationPrepared(",
  "try storePendingRemoteMutation(attempt)",
  "updateAndSubmitExemption(",
]);
assert.ok(supplementFlow.includes("attempt.preparedExpectedVersion"));
assert.ok(supplementFlow.includes("attempt.preparedMediaIDs"));

const retryFlow = section(
  appState,
  "func retryPendingRemoteMutation(scope:",
  "func pendingExemptionFormRecovery("
);
assert.ok(retryFlow.includes("let authoritativeSessionID = attempt.authoritativeSessionID"));
assert.ok(retryFlow.includes("let authoritativeEnrollmentID = attempt.authoritativeEnrollmentID"));
assert.ok(retryFlow.includes("recoverySessionID: authoritativeSessionID"));
assert.ok(retryFlow.includes("recoveryEnrollmentID: authoritativeEnrollmentID"));
assert.ok(retryFlow.includes("allowPreparedRecovery: true"));
const retryEligibility = section(
  appState,
  "func canRetryPendingRemoteMutation(scope:",
  "func retryPendingRemoteMutation(scope:"
);
assert.ok(!retryEligibility.includes("hasSubmittedCheckInToday"));
assert.ok(appState.includes("application.status.canSupplement || hasPreparedRecovery"));
assert.ok(appState.includes("workspaceApplication.status.canSupplement || allowPreparedRecovery"));

const proofKeyToken = 'idempotencyKey: "\\(attempt.idempotencyKey).proof-\\(index)"';
assert.equal(appState.split(proofKeyToken).length - 1, 3, "all P0 upload loops need stable per-proof keys");
const proofKey = (base, index) => `${base}.proof-${index}`;
assert.equal(proofKey("ios-attempt-123", 0), proofKey("ios-attempt-123", 0));
assert.notEqual(proofKey("ios-attempt-123", 0), proofKey("ios-attempt-123", 1));
const canonicalMediaUnion = (current, added) => [...new Set([...current, ...added])].sort();
assert.deepEqual(canonicalMediaUnion(["media-b", "media-a"], ["media-c", "media-a"]), [
  "media-a",
  "media-b",
  "media-c",
]);

const autoEnd = section(checkIn, ".task(id: displayedSession.status)", "/// Android titles the running session");
ordered(autoEnd, ["endExerciseSessionAuthoritatively(", "autoEndAlert = alert"]);
assert.ok(!autoEnd.includes("reconcileExerciseSession"));

const appSwiftFiles = filesRecursively(join(iosRoot, "BNBUStudentApp"), ".swift");
for (const file of appSwiftFiles) {
  assertBalancedSwift(read(file), file);
}
const allAppSwift = appSwiftFiles.map(read).join("\n");
const compiledAppSwift = appSwiftFiles.map((file) => stripDisabledSwiftBlocks(read(file))).join("\n");
assert.doesNotMatch(
  allAppSwift,
  /["'](?:auth\/login|sport\/|student\/(?:profile|courses|workspace|grades|physical-test-exemptions|checkin-exemptions)|upload\/proof|common\/notifications)/,
  "app sources must not retain retired network routes"
);

const clientErrors = section(remote, "enum ClientErrorContext:", "enum RepositoryError:");
for (const token of [
  "struct UserFacingError:",
  "enum ClientErrorMapper",
  "enum SafeClientLogger",
  '"^[A-Z][A-Z0-9_]{0,79}$"',
  '"^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$"',
  "SafeContractErrorDetails",
  "fieldErrors",
  "startedOnCurrentAuthSession",
]) assert.ok(clientErrors.includes(token), `safe client error system missing ${token}`);
assert.doesNotMatch(clientErrors, /message:\s*metadata\.|internalMessage|localizedDescription/);
assert.ok(sharedComponents.includes("struct BNBUErrorPanel: View"));
assert.ok(sharedComponents.includes("error: UserFacingError,"));
assert.ok(sharedComponents.includes("struct BNBUFormField: View"));
assert.ok(sharedComponents.includes("revealsSecureText.toggle()"));
assert.ok(sharedComponents.includes('accessibilityLabel(revealsSecureText ? "隐藏密码" : "显示密码")'));
assert.ok(checkIn.includes("BNBUTextArea("));
assert.ok(courseJoin.includes("BNBUFormField("));

const studentProfile = section(models, "struct StudentProfile:", "struct StudentAcademicProjection:");
const displayStudentNumber = section(studentProfile, "var displayStudentNumber:", "init(");
assert.ok(displayStudentNumber.includes('return BNBUL10n.text("待同步")'));
assert.doesNotMatch(displayStudentNumber, /return\s+id\b/);
assert.ok(profile.includes("ViewThatFits(in: .horizontal)"));
assert.ok(profileDetails.includes("ViewThatFits(in: .horizontal)"));
assert.ok(profileDetails.includes('BNBUGroupLabel("账户与安全")'));
assert.ok(profileDetails.includes('title: "绑定或更换登录邮箱"'));
assert.ok(profileDetails.includes('systemImage: "envelope.fill"'));
assert.ok(profileDetails.includes('title: "注销账户"'));
assert.ok(profileDetails.includes('systemImage: "trash.fill"'));
assert.ok(profileDetails.indexOf('title: "绑定或更换登录邮箱"') < profileDetails.indexOf('title: "注销账户"'));

const loginRequest = section(remote, "func requestStudentSignInCode(", "func verifyStudentSignInCode(");
for (const token of [
  '"auth/student-sign-in-codes"',
  '"organizationCode": organizationCode',
  '"account": normalizedAccount',
  '"channel": "EMAIL"',
  '"locale": locale',
]) assert.ok(loginRequest.includes(token), `student EMAIL OTP request missing ${token}`);
const loginVerify = section(remote, "func verifyStudentSignInCode(", "func previewCourseInvite(");
for (const token of [
  '"auth/student-sign-in-codes/verify"',
  '"challengeId": challengeId',
  '"code": code',
  '"deviceId": try persistentDeviceID()',
]) assert.ok(loginVerify.includes(token), `student EMAIL OTP verify missing ${token}`);
assert.ok(remote.includes('deviceIDStorageKey = "bnbu.auth.deviceId.v1"'));
assert.ok(remote.includes("credentialStore.set(Data(generated.utf8), forKey: deviceIDStorageKey)"));

const sessionRestore = section(remote, "func restoreStudentSession()", "func requestStudentSignInCode(");
ordered(sessionRestore, [
  "guard contractSession != nil",
  'get("me")',
  'current.user.status == "ACTIVE" || current.user.status == "PENDING_CONTACT_BINDING"',
  "let currentSession = contractSession",
  "installContractSession(refreshedSession)",
]);
const appSessionRestore = section(appState, "func restoreRemoteSessionIfAvailable()", "/// The academic year rolls over");
ordered(appSessionRestore, [
  "remoteRepo.restoreStudentSession()",
  "if outcome.requiresFirstEmailBinding",
  "firstEmailBindingExpectedVersion = outcome.userVersion",
  "return .requiresFirstEmailBinding",
  "activateRemoteStudent(outcome.student",
]);

const joinFlow = section(remote, "func previewCourseInvite(", "func requestFirstEmailBinding(");
ordered(joinFlow, [
  "let tokenPath = try Self.percentEncodedPathComponent(token)",
  '"course-invites/\\(tokenPath)/preview"',
  '"course-invites/\\(tokenPath)/join-capabilities"',
  '"course-invites/\\(tokenPath)/join"',
  'headers: ["X-Join-Capability": capability.joinCapability]',
  'result.enrollment.status == "ACTIVE"',
]);
assert.ok(joinFlow.includes('result.authSession.user.status == "PENDING_CONTACT_BINDING"'));
assert.ok(remote.includes('allowed.remove(charactersIn: "/?#%")'));
assert.ok(remote.includes("components.percentEncodedPath ="));
const postTransport = section(remote, "private func post(", "private func patch(");
ordered(postTransport, [
  "for (name, value) in headers",
  "request.setValue(value, forHTTPHeaderField: name)",
  "if authenticated",
]);

const firstEmailBinding = section(remote, "func requestFirstEmailBinding(", "@discardableResult\n    func logout()");
for (const token of [
  '"me/email-verification-challenges"',
  '"expectedVersion": expectedVersion',
  'challenge.mode == "FIRST_BIND"',
  '"me/email-verification-challenges/\\(challengeID)/verify"',
  '"newEmailCode": newEmailCode',
  'current.user.status == "ACTIVE"',
]) assert.ok(firstEmailBinding.includes(token), `first email binding missing ${token}`);

const logoutFlow = section(remote, "func logout() async", "func clearSession()");
assert.ok(logoutFlow.includes('"auth/logout"'));
assert.ok(logoutFlow.includes('["refreshToken": current.refreshToken]'));
assert.ok(remote.includes("private var refreshTask: Task<Void, Error>?"));
const refreshFlow = section(remote, "private func refreshContractSession()", "private func rotateContractSession(");
ordered(refreshFlow, [
  "if let refreshTask",
  "return try await refreshTask.value",
  "let intent = try refreshIntent(for: current)",
  "refreshTask = task",
]);
const rotateRefresh = section(remote, "private func rotateContractSession(", "private func refreshIntent(for current:");
assert.ok(rotateRefresh.includes('request.setValue(intent.idempotencyKey, forHTTPHeaderField: "Idempotency-Key")'));
assert.ok(rotateRefresh.includes("failure.isTerminalAuthenticationFailure"));
const refreshIntent = section(remote, "private func refreshIntent(for current:", "private func refreshSessionFingerprint(");
ordered(refreshIntent, [
  "credentialStore.data(forKey: refreshIntentStorageKey)",
  "existing.sessionFingerprint == fingerprint",
  "credentialStore.set(",
]);
assert.ok(refreshIntent.includes("IdempotencyKeyPolicy.make()"));
const refreshFingerprint = section(remote, "private func refreshSessionFingerprint(", "private func performUpload(");
for (const token of [
  'scope: "auth-refresh"',
  '"sessionId": session.sessionId ?? ""',
  '"userId": session.user.id',
  '"refreshTokenSha256": ProofContentDigest.sha256',
]) assert.ok(refreshFingerprint.includes(token), `refresh fingerprint missing ${token}`);
const authErrorClassification = section(remote, "var isAccessTokenExpired:", "var isAmbiguousMutationFailure:");
assert.ok(authErrorClassification.includes('code == "AUTH_TOKEN_EXPIRED"'));
for (const code of [
  "AUTH_CREDENTIAL_INVALID",
  "AUTH_TOKEN_INVALID",
  "AUTH_SESSION_REVOKED",
  "AUTH_ACCOUNT_DISABLED",
]) assert.ok(authErrorClassification.includes(code), `terminal auth classification missing ${code}`);
assert.doesNotMatch(authErrorClassification, /AUTH_REQUIRED.*return true/s);
const appAuthClassification = section(appState, "private func isUnauthorized(_ error:", "private static var localWorkspaceLoadedOperation:");
assert.ok(appAuthClassification.includes("repositoryError.isTerminalAuthenticationFailure"));
assert.doesNotMatch(appAuthClassification, /statusCode\s*==\s*401/);

const workspaceFlow = section(remote, "private func loadContractWorkspace()", "private func workspace(");
for (const token of [
  'get("me")',
  'get("semesters/current")',
]) assert.ok(workspaceFlow.includes(token), `current workspace missing ${token}`);
for (const path of [
  "enrollments",
  "courses",
  "class-sections",
  "exercise-records",
]) {
  assert.ok(workspaceFlow.includes(`path: "${path}"`), `current workspace missing paginated ${path}`);
}
assert.ok(workspaceFlow.includes("getAllContractPages("));
assert.ok(workspaceFlow.includes('URLQueryItem(name: "limit", value: "100")'));
assert.ok(workspaceFlow.includes('$0.currentReview?.result == "VALID"'));
assert.ok(workspaceFlow.includes("Double(courseSeconds + generalSeconds) / 3600"));
assert.ok(workspaceFlow.includes("source: \"OpenAPI /exercise-records:VALID_SUM\""));
assert.ok(workspaceFlow.includes("authoritativeQualificationStatus: nil"));
assert.ok(!workspaceFlow.includes('path: "student-scores"'));
assert.ok(workspaceFlow.includes("hourRule: .unavailable"));
assert.ok(!workspaceFlow.includes("hourRule: .standard"));
assert.ok(models.includes("static let unavailable = SportHourRule("));
assert.ok(models.includes("var authoritativeTotalHours: Double?"));
assert.ok(models.includes("var authoritativeQualificationStatus: String?"));
const appProgressProjection = section(appState, "var courseRemaining: Double", "var academicProjection:");
assert.ok(appProgressProjection.includes("workspace.progress.authoritativeTotalHours ?? 0"));
assert.ok(appProgressProjection.includes("guard !isRemoteMode"));
assert.ok(!appProgressProjection.includes("if isRemoteMode {\n            return min("));
const localCredit = section(appState, "private func creditSubmittedExercise(", "private func saveExerciseSubmissionDate(");
assert.ok(localCredit.includes("guard !isRemoteMode"));
assert.ok(dashboard.includes("Backend organization businessDate"));
assert.ok(dashboard.includes("提交资格由服务器判断"));
assert.ok(dashboard.includes("进度按当前课程中审核结果为有效的打卡记录实时累计。"));
assert.ok(grades.includes("progress.authoritativeTotalHours"));
assert.ok(grades.includes("已按有效打卡记录累计"));
assert.ok(!grades.includes("等待服务端生成 TOTAL_ONLY 进度投影"));
assert.ok(checkIn.includes("appState.isRemoteMode || !appState.hasSubmittedCheckInToday()"));
assert.equal(
  checkIn.split("if !appState.isRemoteMode, appState.hasSubmittedCheckInToday()").length - 1,
  2,
  "remote start/submit UI must not use the device-local day gate"
);

assert.ok(models.includes("static let minimumLength = 16"));
assert.ok(models.includes("static let maximumLength = 512"));
assert.ok(models.includes("raw.trimmingCharacters(in: .whitespacesAndNewlines)"));
assert.ok(!models.includes("func normalized(_ raw: String) -> String {\n        raw.uppercased"));
assert.ok(models.includes('environment["BNBU_INVITE_URL_HOSTS"]'));
assert.ok(models.includes("allowedURLHosts.contains(host)"));
assert.ok(courseJoin.includes("CONTRACT DECISION REQUIRED"));
assert.ok(releaseInfo.includes("BNBUInviteURLHosts") && debugInfo.includes("BNBUInviteURLHosts"));
assert.ok(remote.includes('localDevelopmentBaseURL = URL(string: "http://127.0.0.1:13000/api/v1")'));
assert.ok(project.includes('BNBU_API_BASE_URL = "http://127.0.0.1:13000/api/v1";'));
assert.ok(project.includes("BNBU_ORGANIZATION_CODE = BNBU;"));
assert.doesNotMatch(remote + project + debugInfo, /123\.207\.5\.70/);

assert.doesNotMatch(compiledAppSwift, /import\s+CoreLocation/);
assert.doesNotMatch(compiledAppSwift, /ExerciseLocationProvider/);
assert.doesNotMatch(releaseInfo + debugInfo, /NSLocation(?:WhenInUse|Always)/);
assert.ok(!project.includes("ExerciseLocationProvider.swift"));
assert.ok(!project.includes("JoinRequestStatusView.swift"));
assert.ok(appShell.includes("本 App 不申请定位权限，也不采集位置或坐标"));
assert.doesNotMatch(compiledAppSwift, /为什么获取不到定位|正在获取当前位置|正在定位/);

const compiledLogin = stripDisabledSwiftBlocks(login);
const compiledJoin = stripDisabledSwiftBlocks(courseJoin);
const compiledCourses = stripDisabledSwiftBlocks(courses);
assert.doesNotMatch(compiledLogin, /AccountPasswordLoginView|RecoveryRequestView|case recovery|新手机号/);
assert.doesNotMatch(compiledJoin, /ContactChannelPanel|等待任课老师审核|待教师审核/);
assert.doesNotMatch(compiledCourses, /PendingEnrollmentCard|等待任课老师审核|待审核课程/);
assert.ok(compiledJoin.includes("FirstEmailBindingView"));
assert.ok(compiledJoin.includes("interactiveDismissDisabled(requiresFirstEmailBinding)"));
assert.ok(appShell.includes("restoreRemoteSessionIfAvailable()"));
assert.ok(appShell.includes("CourseJoinSheet(startsWithFirstEmailBinding: true)"));

const releaseLogin = releaseSwiftProjection(login);
const releaseAppState = releaseSwiftProjection(appState);
const releaseAppEntry = releaseSwiftProjection(appEntry);
const releaseAppShell = releaseSwiftProjection(appShell);
assert.doesNotMatch(releaseLogin, /免登录测试入口|Password-free review access|login\.localReview/);
assert.doesNotMatch(releaseLogin, /appState\.demoLogin\(\)/);
assert.doesNotMatch(releaseAppState, /func\s+demoLogin\s*\(/);
assert.doesNotMatch(releaseAppEntry, /state\.demoLogin\(\)/);
assert.doesNotMatch(releaseAppShell, /免登录测试模式|Password-free review mode|banner\.localReview/);
assert.ok(appState.includes('static let launchArgument = "-bnbu-local-demo"'));
assert.ok(appState.includes("guard LocalDemoAccess.permitsMockWorkspace else"));
assert.ok(login.includes("guard LocalDemoAccess.showsLoginOption else"));
assert.ok(appEntry.includes("if LocalDemoAccess.permitsMockWorkspace,"));
assert.ok(uiTests.includes('XCTAssertTrue(app.buttons["login.localReview"].exists)'));
assert.ok(uiTests.includes('"-bnbu-local-demo"'));
assert.ok(login.includes('title: copy("以测试学生身份进入", "Enter as test student")'));
assert.ok(appShell.includes('appState.isLocalReviewMode'));
assert.ok(appShell.includes('banner.localReview'));
assert.doesNotMatch(
  uiTests,
  /-ui-testing-remote-completed-exercise/,
  "XCUITest must not claim a remote completed Session through an unhandled App argument"
);
const remoteCheckInGate = section(
  uiTests,
  "func testLocalRealCheckInSubmitAndReadBackFlow() async throws {",
  "// Read-only local check:"
);
assert.ok(remoteCheckInGate.includes("XCTFail("));
assert.ok(remoteCheckInGate.includes("real Backend-completed ExerciseSession"));

assert.doesNotMatch(
  modelTests,
  /repository\.(?:login|submitCheckIn|uploadProof|supplementExemption)\s*\(/,
  "XCTest must not call removed RemoteStudentRepository compatibility methods"
);
assert.doesNotMatch(
  modelTests,
  /["']\/api\/v1\/(?:auth\/login|sport\/|student\/|upload\/proof)/,
  "XCTest URLProtocol fixtures must use the current contract routes"
);
for (const token of [
  "repository.verifyStudentSignInCode(",
  "repository.submitExerciseRecord(",
  "repository.uploadExerciseEvidence(",
  "repository.createExemptionDraft(",
  "repository.updateAndSubmitCreatedExemption(",
  "repository.prepareExemptionSupplement(",
  "repository.updateAndSubmitExemption(",
  '"/api/v1/media-uploads"',
  '"/api/v1/exercise-records"',
  '"/api/v1/exemption-applications"',
]) assert.ok(modelTests.includes(token), `current-contract XCTest coverage missing ${token}`);
for (const testName of [
  "testRemoteProgressUsesOnlyAuthoritativeStudentScoreTotal",
  "device-local-today",
  "progressBeforeServerRefresh",
  "testProtected401OtherThanTokenExpiredDoesNotRefreshOrClearSession",
  "testRefreshAmbiguousFailuresRetainSessionAndPersistentIntent",
  "testRefreshIntentSurvivesRestartReusesKeyAndClearsAfterSuccess",
  "testRefreshTerminalCredentialFailuresClearSessionAndIntent",
  "testSuccessfulNewLoginClearsStaleRefreshIntent",
  "testCheckInCannotExcludeAnyConfirmedRetainedEvidence",
  "testMatchingProtectedSessionIsRecoveredButOtherDeviceSessionIsReadOnlyConflict",
  "testRepositoryErrorsUseSafeActionableStudentMessages",
  "testStudentNumberNeverFallsBackToOpaqueInternalID",
]) assert.ok(modelTests.includes(testName), `authority-boundary XCTest coverage missing ${testName}`);

JSON.parse(read(join(iosRoot, "BNBUStudentApp", "Resources", "InfoPlist.xcstrings")));
JSON.parse(read(join(iosRoot, "BNBUStudentApp", "Resources", "Localizable.xcstrings")));

console.log("P0_CONTRACT_FLOW_AUDIT_PASS");
