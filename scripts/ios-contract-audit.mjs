import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// The P0 flow audit owns the detailed session, record, media, exemption,
// authentication and atomic-join assertions. Importing it makes this wider iOS
// gate fail whenever that contract-critical audit fails.
await import("./p0-contract-flow-audit.mjs");
await import("./r02-source-audit.mjs");

const iosRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
const repoRoot = join(iosRoot, "..");
const normalizeLF = (value) => value.replace(/\r\n?/gu, "\n");
const read = (path) => normalizeLF(readFileSync(path, "utf8"));
const authoritativePath = join(repoRoot, "docs", "backend-contracts", "openapi.yaml");
const snapshotPath = join(iosRoot, "openapi", "openapi.snapshot.yaml");
const metadataPath = join(iosRoot, "openapi", "contract.json");
const expectedVersion = "3.0.0-contract";
const expectedHash = "020594cb6c0dc220bf96f30326a04144cb8081ec44f56bc8b3746ea4001ace4f";

function filesRecursively(directory, extension) {
  return readdirSync(directory, { withFileTypes: true }).flatMap((entry) => {
    const fullPath = join(directory, entry.name);
    if (entry.isDirectory()) return filesRecursively(fullPath, extension);
    return entry.isFile() && entry.name.endsWith(extension) ? [fullPath] : [];
  });
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
  assert.equal(blockDepth, 0, `${label} has an unterminated block comment`);
  assert.equal(stack.length, 0, `${label} has an unterminated delimiter`);
  assert.ok(!source.includes("<<<<<<<"), `${label} contains a merge-conflict marker`);
}

const authoritative = read(authoritativePath);
const snapshot = read(snapshotPath);
const metadata = JSON.parse(read(metadataPath));
const actualHash = createHash("sha256").update(snapshot).digest("hex");
assert.equal(snapshot, authoritative, "iOS OpenAPI snapshot LF-canonical content differs from monorepo authority");
assert.equal(metadata.contractVersion, expectedVersion);
assert.equal(metadata.sha256, expectedHash);
assert.equal(metadata.byteLength, 348350);
assert.equal(Buffer.byteLength(snapshot, "utf8"), metadata.byteLength);
assert.equal(actualHash, expectedHash);
assert.match(authoritative, /version:\s*3\.0\.0-contract\b/);

const appRoot = join(iosRoot, "BNBUStudentApp");
const testRoot = join(iosRoot, "BNBUStudentTests");
const uiTestRoot = join(iosRoot, "BNBUStudentUITests");
const appSwiftFiles = filesRecursively(appRoot, ".swift");
const testSwiftFiles = filesRecursively(testRoot, ".swift");
const uiTestSwiftFiles = filesRecursively(uiTestRoot, ".swift");
for (const file of [...appSwiftFiles, ...testSwiftFiles, ...uiTestSwiftFiles]) {
  assertBalancedSwift(read(file), file);
}

const appSources = appSwiftFiles.map(read).join("\n");
assert.doesNotMatch(
  appSources,
  /["'](?:auth\/login|sport\/|student\/(?:profile|courses|workspace|grades|physical-test-exemptions|checkin-exemptions)|upload\/proof|common\/notifications)/,
  "retired route literal remains in app source"
);
assert.doesNotMatch(appSources, /import\s+CoreLocation/);
assert.doesNotMatch(appSources, /ExerciseLocationProvider/);

const remote = read(join(appRoot, "Core", "RemoteStudentRepository.swift"));
for (const route of [
  "auth/student-sign-in-codes",
  "auth/student-sign-in-codes/verify",
  "course-invites/\\(tokenPath)/preview",
  "course-invites/\\(tokenPath)/join-capabilities",
  "course-invites/\\(tokenPath)/join",
  "me/email-verification-challenges",
  "auth/logout",
  "exercise-sessions",
  "exercise-records",
  "media-uploads",
  "exemption-applications",
  "system-mode",
  "app-release-policy",
  "help-articles",
  "feedback",
]) {
  assert.ok(remote.includes(route), `missing current-contract route ${route}`);
}
for (const retiredRoute of [
  'get("health")',
  'get("config/minimum-app-version")',
  'get("common/help-articles")',
  'post(\n            "scoring/convert-endurance"',
]) {
  assert.ok(!remote.includes(retiredRoute), `retired runtime route remains: ${retiredRoute}`);
}

// Every literal request made through the repository HTTP helpers must resolve
// to an operation in the authoritative OpenAPI. The signed object-storage
// upload intentionally bypasses these helpers and is the sole external-URL
// exception. Dynamic session actions are constrained to the three explicit
// contract operations below rather than treated as an arbitrary wildcard.
const openapiOperations = [];
let activePath = null;
for (const line of authoritative.split(/\r?\n/u)) {
  const pathMatch = line.match(/^  (\/[^:]+):\s*$/u);
  if (pathMatch) {
    activePath = pathMatch[1];
    continue;
  }
  const methodMatch = line.match(/^    (get|post|put|patch|delete):\s*$/u);
  if (activePath && methodMatch) {
    openapiOperations.push({ method: methodMatch[1].toUpperCase(), path: activePath });
  }
}

const literalRuntimeCalls = [...remote.matchAll(/\b(get|post|patch|put)\s*\(\s*"((?:\\.|[^"\\])*)"/gsu)]
  .map((match) => ({ method: match[1].toUpperCase(), path: match[2] }));
const paginatedRuntimeCalls = [...remote.matchAll(
  /\bgetAllContractPages\s*\(\s*[A-Za-z][A-Za-z0-9.]*,\s*path:\s*"((?:\\.|[^"\\])*)"/gsu,
)].map((match) => ({ method: "GET", path: match[1] }));
const runtimeCalls = [...literalRuntimeCalls, ...paginatedRuntimeCalls];
const uniqueRuntimeCalls = new Set(runtimeCalls.map(({ method, path }) => `${method} ${path}`));
assert.equal(runtimeCalls.length, 52, "unexpected number of iOS literal HTTP call sites");
assert.equal(uniqueRuntimeCalls.size, 44, "unexpected number of unique iOS literal HTTP operations");

const normalizeRuntimePath = (path) => `/${path}`
  .replace(/\\\((?:[^()]|\([^()]*\))*\)/gu, "{runtimeValue}")
  .replace(/\/{2,}/gu, "/");
const matchesContractPath = (runtimePath, contractPath) => {
  const runtimeSegments = runtimePath.split("/");
  const contractSegments = contractPath.split("/");
  return runtimeSegments.length === contractSegments.length && runtimeSegments.every((segment, index) => {
    const contractSegment = contractSegments[index];
    if (segment === "{runtimeValue}") return /^\{[^}]+\}$/u.test(contractSegment);
    return segment === contractSegment;
  });
};
const hasOperation = (method, path) => openapiOperations.some((operation) =>
  operation.method === method && matchesContractPath(path, operation.path)
);
const internalTestToolOperations = new Set([
  "GET /internal/test-tools/capabilities",
  "POST /internal/test-tools/exercise-sessions/{runtimeValue}/advance-duration",
]);
const observedInternalTestToolOperations = new Set();

for (const call of runtimeCalls) {
  if (call.path.includes("\\(action)")) {
    for (const action of ["pause", "resume", "finish"]) {
      const expanded = normalizeRuntimePath(call.path.replace("\\(action)", action));
      assert.ok(hasOperation(call.method, expanded), `iOS runtime call missing from OpenAPI: ${call.method} ${expanded}`);
    }
    continue;
  }
  const normalizedPath = normalizeRuntimePath(call.path);
  const normalizedOperation = `${call.method} ${normalizedPath}`;
  if (internalTestToolOperations.has(normalizedOperation)) {
    observedInternalTestToolOperations.add(normalizedOperation);
    assert.ok(
      !hasOperation(call.method, normalizedPath),
      `internal test-tool route must not enter the public OpenAPI: ${normalizedOperation}`
    );
    continue;
  }
  assert.ok(
    hasOperation(call.method, normalizedPath),
    `iOS runtime call missing from OpenAPI: ${call.method} ${normalizedPath}`
  );
}
assert.deepEqual(
  observedInternalTestToolOperations,
  internalTestToolOperations,
  "the exact iOS internal test-tool route inventory changed"
);
for (const scopedMediaInitiationPath of [
  "/media-uploads",
  "/exemption-applications/{runtimeValue}/media-uploads",
]) {
  assert.ok(
    hasOperation("POST", scopedMediaInitiationPath),
    `iOS scoped media initiation route missing from OpenAPI: POST ${scopedMediaInitiationPath}`
  );
}
assert.ok(remote.includes('initiatePath = "media-uploads"'));
assert.ok(
  remote.includes(
    'initiatePath = "exemption-applications/\\(try Self.pathComponent(exemptionApplicationId))/media-uploads"'
  )
);

const nonLiteralHelperCalls = [...remote.matchAll(/\b(get|post|patch|put)\s*\(\s*([A-Za-z][A-Za-z0-9_]*)/gu)]
  .map((match) => `${match[1].toUpperCase()} ${match[2]}`);
assert.deepEqual(
  nonLiteralHelperCalls,
  ["GET path", "POST initiatePath", "GET path"],
  "an unaudited variable HTTP route was introduced",
);
assert.equal(
  [...remote.matchAll(/getIfBusinessReady\s*\(/gu)].length,
  1,
  "the legacy guarded variable route must remain uncalled"
);
assert.ok(remote.includes('headers: ["X-Join-Capability": capability.joinCapability]'));
assert.ok(remote.includes("for (name, value) in headers"));
assert.ok(remote.includes("private var refreshTask: Task<Void, Error>?"));
assert.ok(remote.includes("private func getAllContractPages<Value: Decodable & Sendable>"));
assert.ok(remote.includes('URLQueryItem(name: "cursor", value: cursor)'));
assert.ok(remote.includes("seenCursors.insert(nextCursor).inserted"));

const models = read(join(appRoot, "Core", "Models.swift"));
assert.ok(models.includes("static let minimumLength = 16"));
assert.ok(models.includes("static let maximumLength = 512"));
assert.ok(models.includes('environment["BNBU_INVITE_URL_HOSTS"]'));
assert.ok(models.includes("allowedURLHosts.contains(host)"));
assert.ok(models.includes("static let maximumVideoDurationSeconds: TimeInterval = 15"));

const captureComponents = read(join(appRoot, "Features", "ExerciseCaptureComponents.swift"));
const sharedComponents = read(join(appRoot, "Features", "Components.swift"));
assert.ok(captureComponents.includes("ExerciseMediaDraftRule.maximumVideoDurationSeconds"));
assert.ok(captureComponents.includes("authorizationStatus(for: .audio)"));
assert.ok(captureComponents.includes("requestAccess(for: .audio)"));
assert.ok(sharedComponents.includes("picker.videoMaximumDuration = videoMaximumDuration"));
assert.ok(!sharedComponents.includes("picker.videoMaximumDuration = 30"));

const project = read(join(iosRoot, "BNBUStudent.xcodeproj", "project.pbxproj"));
assert.ok(project.includes("StudentAPIClient.swift in Sources"));
assert.ok(!project.includes("ExerciseLocationProvider.swift"));
assert.ok(!project.includes("JoinRequestStatusView.swift"));

const releaseInfo = read(join(appRoot, "Resources", "Info.plist"));
const debugInfo = read(join(appRoot, "Resources", "Info-Debug.plist"));
const privacyManifest = read(join(appRoot, "Resources", "PrivacyInfo.xcprivacy"));
const privacyPolicyEnglish = read(join(appRoot, "Resources", "privacy_policy_en.md"));
const privacyPolicyChinese = read(join(appRoot, "Resources", "privacy_policy_zh_cn.md"));
for (const plist of [releaseInfo, debugInfo]) {
  assert.ok(plist.includes("BNBUOrganizationCode"));
  assert.ok(plist.includes("BNBUInviteURLHosts"));
  assert.doesNotMatch(plist, /NSLocation(?:WhenInUse|Always)/);
}
assert.doesNotMatch(
  privacyManifest,
  /NSPrivacyCollectedDataType(?:Precise|Coarse)Location/,
  "privacy manifest must not declare location while the app does not collect it"
);
assert.ok(privacyPolicyEnglish.includes("does not request location permission, collect coordinates"));
assert.ok(privacyPolicyChinese.includes("不调用 Core Location，不读取、保存或上传经纬度"));
JSON.parse(read(join(appRoot, "Resources", "InfoPlist.xcstrings")));
JSON.parse(read(join(appRoot, "Resources", "Localizable.xcstrings")));

const modelTests = read(join(testRoot, "BNBUStudentModelTests.swift"));
assert.ok(modelTests.includes("testLegacyPhoneCodeSignInFailsClosed"));
assert.ok(modelTests.includes("testLegacyCourseJoinRequestNeverCreatesTeacherApprovalState"));
assert.ok(modelTests.includes("testLegacyPendingCourseJoinCacheIsIgnoredOnRelaunch"));
assert.ok(modelTests.includes("testExerciseSessionNeverCollectsLocation"));
assert.ok(modelTests.includes("testExerciseVideoCaptureUsesAcceptedFifteenSecondLimit"));
assert.ok(modelTests.includes("testCursorListsDrainEveryPageWithoutRepeatingTheFirstCursor"));
assert.doesNotMatch(modelTests, /XCTAssertTrue\([^\n]*(?:submitCourseJoinRequest|sendLoginCode|signInWithCode|sendContactVerificationCode|verifyContactCode|submitRecoveryRequest)/);
assert.doesNotMatch(modelTests, /attachExerciseSessionLocation/);

const uiTests = read(join(uiTestRoot, "BNBUStudentSmokeUITests.swift"));
assert.doesNotMatch(uiTests, /BNBU_TEST_PASSWORD|ui-testing-login-password/);
assert.ok(uiTests.includes("testLocalRealLoginFlow"));
assert.ok(uiTests.includes("testLocalRealCheckInSubmitAndReadBackFlow"));
assert.ok(uiTests.includes("testLocalRecordsShowExpectedNote"));
assert.ok(uiTests.includes("waitForLocalMailpitCode"));
assert.ok(uiTests.includes('"http://127.0.0.1:13000/api/v1"'));
assert.ok(uiTests.includes('"http://127.0.0.1:18025"'));

console.log(`PASS iOS contract audit (${expectedVersion}, ${expectedHash})`);
