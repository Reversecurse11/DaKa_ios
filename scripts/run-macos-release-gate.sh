#!/usr/bin/env bash

set -Eeuo pipefail
IFS=$'\n\t'

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
IOS_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd -P)"
PROJECT_PATH="${IOS_ROOT}/BNBUStudent.xcodeproj"
SCHEME="BNBUStudent"

RELEASE_API_BASE_URL="${BNBU_RELEASE_API_BASE_URL:-}"
SIMULATOR_DESTINATION="${IOS_SIMULATOR_DESTINATION:-}"
BACKEND_ROOT="${BNBU_BACKEND_ROOT:-}"
REQUESTED_OUTPUT_DIR="${BNBU_IOS_GATE_OUTPUT_DIR:-}"
SIMULATOR_SELECTION="explicit"
SIMULATOR_UDID=""

usage() {
  cat <<'USAGE'
Usage:
  ./scripts/run-macos-release-gate.sh \
    --release-api-base-url 'https://<official-school-domain>/api/v1' \
    [--destination 'platform=iOS Simulator,name=iPhone 16 Pro,OS=latest'] \
    [--backend-root /path/to/BNBU-Sports-Android/backend] \
    [--output-dir /path/to/gate-output]

Environment equivalents:
  BNBU_RELEASE_API_BASE_URL
  IOS_SIMULATOR_DESTINATION
  BNBU_BACKEND_ROOT
  BNBU_IOS_GATE_OUTPUT_DIR

When --destination is omitted, the gate selects an available iOS Simulator,
preferring a booted iPhone and then the newest available iPhone runtime.

The Release API URL is build configuration, not a credential. Do not pass
student accounts, passwords, access tokens, COS keys, or signing credentials.
USAGE
}

while (($# > 0)); do
  case "$1" in
    --release-api-base-url)
      (($# >= 2)) || { echo "error: --release-api-base-url requires a value" >&2; exit 64; }
      RELEASE_API_BASE_URL="$2"
      shift 2
      ;;
    --destination)
      (($# >= 2)) || { echo "error: --destination requires a value" >&2; exit 64; }
      SIMULATOR_DESTINATION="$2"
      shift 2
      ;;
    --backend-root)
      (($# >= 2)) || { echo "error: --backend-root requires a value" >&2; exit 64; }
      BACKEND_ROOT="$2"
      shift 2
      ;;
    --output-dir)
      (($# >= 2)) || { echo "error: --output-dir requires a value" >&2; exit 64; }
      REQUESTED_OUTPUT_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument: $1" >&2
      usage >&2
      exit 64
      ;;
  esac
done

RUN_ID="$(date -u '+%Y%m%dT%H%M%SZ')-$$"
STARTED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
RELEASE_API_CONFIGURED="false"
if [[ -n "${RELEASE_API_BASE_URL}" ]]; then
  RELEASE_API_CONFIGURED="true"
fi

if [[ -n "${REQUESTED_OUTPUT_DIR}" ]]; then
  OUTPUT_DIR="${REQUESTED_OUTPUT_DIR}"
else
  OUTPUT_DIR="${IOS_ROOT}/artifacts/ios-release-gate/${RUN_ID}"
fi

case "${OUTPUT_DIR}" in
  *$'\n'*|*$'\r'*|*$'\t'*)
    echo "error: output directory contains a forbidden control character" >&2
    exit 64
    ;;
esac

mkdir -p -- "${OUTPUT_DIR}"
OUTPUT_DIR="$(CDPATH= cd -- "${OUTPUT_DIR}" && pwd -P)"
if [[ -n "$(find "${OUTPUT_DIR}" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  echo "error: output directory must be empty: ${OUTPUT_DIR}" >&2
  exit 73
fi
mkdir -- "${OUTPUT_DIR}/logs" "${OUTPUT_DIR}/results"
LOG_DIR="${OUTPUT_DIR}/logs"
RESULT_DIR="${OUTPUT_DIR}/results"
DERIVED_DATA_DIR="${OUTPUT_DIR}/DerivedData"
STEPS_FILE="${OUTPUT_DIR}/steps.tsv"
SUMMARY_FILE="${OUTPUT_DIR}/summary.json"

: > "${STEPS_FILE}"

STEP_IDS=(
  "preflight"
  "static_audit"
  "debug_clean_build"
  "xctest"
  "xcuitest"
  "release_build_unsigned"
  "release_analyze_unsigned"
)
STEP_LABELS=(
  "Toolchain, project, API and Simulator preflight"
  "iOS static contract audit"
  "Debug clean Simulator build"
  "XCTest unit suite"
  "XCUITest smoke suite"
  "Unsigned Release generic iOS build"
  "Unsigned Release generic iOS analyze"
)
STEP_RESULT_BUNDLES=(
  ""
  ""
  "results/debug-clean-build.xcresult"
  "results/xctest.xcresult"
  "results/xcuitest.xcresult"
  "results/release-build.xcresult"
  "results/release-analyze.xcresult"
)

LAST_COMPLETED_INDEX=-1
OVERALL_STATUS="FAIL"

record_step() {
  local index="$1"
  local status="$2"
  local exit_code="$3"
  local log_path="logs/${STEP_IDS[$index]}.log"
  local result_bundle="${STEP_RESULT_BUNDLES[$index]}"

  printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${STEP_IDS[$index]}" \
    "${STEP_LABELS[$index]}" \
    "${status}" \
    "${exit_code}" \
    "${log_path}" \
    "${result_bundle}" >> "${STEPS_FILE}"
}

json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\b'/\\b}"
  value="${value//$'\f'/\\f}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

write_summary_with_bash() {
  local status="$1"
  local exit_code="$2"
  local finished_at="$3"
  local id label step_status raw_exit_code log_path result_bundle
  local first_step="true"
  local log_exists result_exists

  {
    printf '{\n'
    printf '  "schemaVersion": 1,\n'
    printf '  "gate": "bnbu-ios-macos-release",\n'
    printf '  "runId": "%s",\n' "$(json_escape "${RUN_ID}")"
    printf '  "status": "%s",\n' "$(json_escape "${status}")"
    printf '  "exitCode": %s,\n' "${exit_code}"
    printf '  "startedAt": "%s",\n' "$(json_escape "${STARTED_AT}")"
    printf '  "finishedAt": "%s",\n' "$(json_escape "${finished_at}")"
    printf '  "project": "BNBUStudent.xcodeproj",\n'
    printf '  "scheme": "BNBUStudent",\n'
    printf '  "simulator": {\n'
    if [[ -n "${SIMULATOR_DESTINATION}" ]]; then
      printf '    "destination": "%s",\n' "$(json_escape "${SIMULATOR_DESTINATION}")"
    else
      printf '    "destination": null,\n'
    fi
    printf '    "selection": "%s"\n' "$(json_escape "${SIMULATOR_SELECTION}")"
    printf '  },\n'
    printf '  "release": {\n'
    printf '    "destination": "generic/platform=iOS",\n'
    printf '    "configuration": "Release",\n'
    printf '    "apiBaseURLProvided": %s,\n' "${RELEASE_API_CONFIGURED}"
    printf '    "codeSigningAllowed": false\n'
    printf '  },\n'
    printf '  "outputDirectory": "%s",\n' "$(json_escape "${OUTPUT_DIR}")"
    printf '  "steps": [\n'

    while IFS=$'\t' read -r id label step_status raw_exit_code log_path result_bundle; do
      if [[ "${first_step}" == "true" ]]; then
        first_step="false"
      else
        printf ',\n'
      fi

      if [[ -f "${OUTPUT_DIR}/${log_path}" ]]; then log_exists="true"; else log_exists="false"; fi
      if [[ -n "${result_bundle}" && -d "${OUTPUT_DIR}/${result_bundle}" ]]; then
        result_exists="true"
      else
        result_exists="false"
      fi

      printf '    {\n'
      printf '      "id": "%s",\n' "$(json_escape "${id}")"
      printf '      "label": "%s",\n' "$(json_escape "${label}")"
      printf '      "status": "%s",\n' "$(json_escape "${step_status}")"
      if [[ "${raw_exit_code}" == "-" ]]; then
        printf '      "exitCode": null,\n'
      else
        printf '      "exitCode": %s,\n' "${raw_exit_code}"
      fi
      printf '      "log": "%s",\n' "$(json_escape "${log_path}")"
      printf '      "logExists": %s,\n' "${log_exists}"
      if [[ -n "${result_bundle}" ]]; then
        printf '      "resultBundle": "%s",\n' "$(json_escape "${result_bundle}")"
        printf '      "resultBundleExists": %s\n' "${result_exists}"
      else
        printf '      "resultBundle": null,\n'
        printf '      "resultBundleExists": null\n'
      fi
      printf '    }'
    done < "${STEPS_FILE}"

    printf '\n  ]\n'
    printf '}\n'
  } > "${SUMMARY_FILE}"
}

print_summary_as_single_line() {
  local line
  printf 'BNBU_IOS_RELEASE_GATE_RESULT='
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line%$'\r'}"
    printf '%s' "${line}"
  done < "${SUMMARY_FILE}"
  printf '\n'
}

finalize() {
  local shell_exit_code="$1"
  local final_exit_code
  local finished_at
  local index
  local node_summary_written="false"

  trap - EXIT
  set +e

  if ((shell_exit_code != 0)); then
    OVERALL_STATUS="FAIL"
  fi

  for ((index = LAST_COMPLETED_INDEX + 1; index < ${#STEP_IDS[@]}; index += 1)); do
    printf 'SKIPPED %s because an earlier preflight or process failure stopped the gate.\n' \
      "${STEP_IDS[$index]}" > "${LOG_DIR}/${STEP_IDS[$index]}.log"
    record_step "${index}" "SKIPPED" "-"
  done

  if [[ "${OVERALL_STATUS}" == "PASS" ]]; then
    final_exit_code=0
  elif ((shell_exit_code != 0)); then
    final_exit_code="${shell_exit_code}"
  else
    final_exit_code=1
  fi

  finished_at="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"

  if command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("node:fs");
      const path = require("node:path");
      const [stepsFile, summaryFile, status, exitCode, runId, startedAt, finishedAt,
        outputDirectory, simulatorDestination, simulatorSelection, releaseApiConfigured] = process.argv.slice(1);
      const rows = fs.readFileSync(stepsFile, "utf8").trim().split(/\r?\n/).filter(Boolean);
      const steps = rows.map((row) => {
        const [id, label, stepStatus, rawExitCode, log, resultBundle] = row.split("\t");
        const absoluteResult = resultBundle ? path.join(outputDirectory, resultBundle) : null;
        return {
          id,
          label,
          status: stepStatus,
          exitCode: rawExitCode === "-" ? null : Number(rawExitCode),
          log,
          logExists: fs.existsSync(path.join(outputDirectory, log)),
          resultBundle: resultBundle || null,
          resultBundleExists: absoluteResult === null ? null : fs.existsSync(absoluteResult)
        };
      });
      const summary = {
        schemaVersion: 1,
        gate: "bnbu-ios-macos-release",
        runId,
        status,
        exitCode: Number(exitCode),
        startedAt,
        finishedAt,
        project: "BNBUStudent.xcodeproj",
        scheme: "BNBUStudent",
        simulator: {
          destination: simulatorDestination || null,
          selection: simulatorSelection
        },
        release: {
          destination: "generic/platform=iOS",
          configuration: "Release",
          apiBaseURLProvided: releaseApiConfigured === "true",
          codeSigningAllowed: false
        },
        outputDirectory,
        steps
      };
      fs.writeFileSync(summaryFile, `${JSON.stringify(summary, null, 2)}\n`, "utf8");
    ' "${STEPS_FILE}" "${SUMMARY_FILE}" "${OVERALL_STATUS}" "${final_exit_code}" \
      "${RUN_ID}" "${STARTED_AT}" "${finished_at}" "${OUTPUT_DIR}" \
      "${SIMULATOR_DESTINATION}" "${SIMULATOR_SELECTION}" "${RELEASE_API_CONFIGURED}" &&
      node_summary_written="true"
  fi

  if [[ "${node_summary_written}" != "true" || ! -s "${SUMMARY_FILE}" ]]; then
    write_summary_with_bash "${OVERALL_STATUS}" "${final_exit_code}" "${finished_at}"
  fi

  if [[ -s "${SUMMARY_FILE}" ]]; then
    print_summary_as_single_line
    printf 'BNBU_IOS_RELEASE_GATE_SUMMARY=%s\n' "${SUMMARY_FILE}"
  else
    printf 'BNBU_IOS_RELEASE_GATE_RESULT={"schemaVersion":1,"gate":"bnbu-ios-macos-release","status":"FAIL","exitCode":%s,"summaryWriteFailed":true}\n' "${final_exit_code}"
  fi

  exit "${final_exit_code}"
}

trap 'finalize "$?"' EXIT

redact_release_url_from_log() {
  local log_path="$1"
  local log_contents

  [[ -n "${RELEASE_API_BASE_URL}" ]] || return 0

  if command -v node >/dev/null 2>&1; then
    if BNBU_REDACT_LOG_PATH="${log_path}" \
      BNBU_REDACT_VALUE="${RELEASE_API_BASE_URL}" \
        node -e '
          const fs = require("node:fs");
          const logPath = process.env.BNBU_REDACT_LOG_PATH;
          const value = process.env.BNBU_REDACT_VALUE;
          const source = fs.readFileSync(logPath, "utf8");
          fs.writeFileSync(logPath, source.split(value).join("[REDACTED_RELEASE_API_BASE_URL]"), "utf8");
        '; then
      return 0
    fi

    printf 'error: log was suppressed because the Release API URL could not be safely redacted.\n' > "${log_path}"
    return 1
  fi

  log_contents="$(< "${log_path}")"
  if [[ "${log_contents}" == *"${RELEASE_API_BASE_URL}"* ]]; then
    printf 'error: log was suppressed because the Release API URL could not be safely redacted without Node.\n' > "${log_path}"
    return 1
  fi
}

run_step() {
  local index="$1"
  shift
  local log_path="${LOG_DIR}/${STEP_IDS[$index]}.log"
  local exit_code

  printf '\n=== [%s] %s ===\n' "${STEP_IDS[$index]}" "${STEP_LABELS[$index]}"

  set +e
  "$@" > "${log_path}" 2>&1
  exit_code=$?

  if ! redact_release_url_from_log "${log_path}"; then
    exit_code=1
  fi
  set -e

  cat -- "${log_path}" || true

  if ((exit_code == 0)); then
    record_step "${index}" "PASS" "0"
    printf 'PASS %s\n' "${STEP_IDS[$index]}"
  else
    record_step "${index}" "FAIL" "${exit_code}"
    printf 'FAIL %s (exit %s)\n' "${STEP_IDS[$index]}" "${exit_code}" >&2
  fi

  LAST_COMPLETED_INDEX="${index}"
  return "${exit_code}"
}

require_command() {
  local command_name="$1"
  command -v "${command_name}" >/dev/null 2>&1 || {
    echo "error: required command is not available: ${command_name}" >&2
    return 1
  }
}

require_file() {
  local file_path="$1"
  [[ -f "${file_path}" ]] || {
    echo "error: required file is missing: ${file_path}" >&2
    return 1
  }
}

require_result_bundle() {
  local result_bundle="$1"
  [[ -d "${result_bundle}" ]] || {
    echo "error: xcodebuild exited successfully but did not create the expected result bundle: ${result_bundle}" >&2
    return 1
  }
}

validate_release_api_url() {
  node -e '
    const net = require("node:net");
    const raw = process.argv[1] || "";
    let url;
    try { url = new URL(raw); } catch { throw new Error("Release API URL is missing or malformed"); }
    const hostname = url.hostname.toLowerCase();
    const forbiddenHost =
      !hostname ||
      hostname === "localhost" ||
      hostname === "example.com" ||
      hostname === "example.org" ||
      hostname === "example.net" ||
      hostname.endsWith(".invalid") ||
      hostname.endsWith(".example") ||
      hostname.endsWith(".test") ||
      hostname.includes("configuration-required") ||
      hostname.includes("your-school") ||
      net.isIP(hostname) !== 0;
    if (url.protocol !== "https:") throw new Error("Release API URL must use HTTPS");
    if (forbiddenHost) throw new Error("Release API URL must use the confirmed official domain, not a placeholder, localhost, or IP address");
    if (url.username || url.password) throw new Error("Release API URL must not contain credentials");
    if (url.search || url.hash) throw new Error("Release API URL must not contain query parameters or a fragment");
    if (!url.pathname.endsWith("/api/v1")) throw new Error("Release API URL must end with /api/v1");
  ' "${RELEASE_API_BASE_URL}"
}

select_simulator_destination() {
  local simulator_json

  simulator_json="$(xcrun simctl list devices available --json)" || return 1
  SIMULATOR_UDID="$(printf '%s' "${simulator_json}" | node -e '
    let input = "";
    process.stdin.setEncoding("utf8");
    process.stdin.on("data", (chunk) => { input += chunk; });
    process.stdin.on("end", () => {
      const payload = JSON.parse(input);
      const candidates = [];
      for (const [runtime, devices] of Object.entries(payload.devices || {})) {
        if (!runtime.includes(".SimRuntime.iOS-")) continue;
        const match = runtime.match(/iOS-(\d+)(?:-(\d+))?(?:-(\d+))?$/);
        const version = match ? match.slice(1).map((part) => Number(part || 0)) : [0, 0, 0];
        for (const device of devices || []) {
          if (device.isAvailable === false || !device.udid) continue;
          candidates.push({
            ...device,
            version,
            isBooted: device.state === "Booted" ? 1 : 0,
            isIPhone: /iPhone/i.test(`${device.name || ""} ${device.deviceTypeIdentifier || ""}`) ? 1 : 0
          });
        }
      }
      const pool = candidates.some((candidate) => candidate.isIPhone === 1)
        ? candidates.filter((candidate) => candidate.isIPhone === 1)
        : candidates;
      pool.sort((left, right) =>
        right.isBooted - left.isBooted ||
        right.version[0] - left.version[0] ||
        right.version[1] - left.version[1] ||
        right.version[2] - left.version[2] ||
        String(left.name).localeCompare(String(right.name))
      );
      if (pool.length === 0) {
        console.error("No available iOS Simulator was found. Install an iOS Simulator runtime in Xcode Settings > Platforms.");
        process.exit(2);
      }
      process.stdout.write(pool[0].udid);
    });
  ')" || return 1
  SIMULATOR_DESTINATION="platform=iOS Simulator,id=${SIMULATOR_UDID}"
  SIMULATOR_SELECTION="automatic"
}

preflight() {
  local default_backend_root="${IOS_ROOT}/../../BNBU-Sports-Android/backend"

  [[ "$(uname -s)" == "Darwin" ]] || {
    echo "error: this gate must run on macOS with full Xcode installed" >&2
    return 1
  }

  require_command node || return 1
  require_command xcodebuild || return 1
  require_command xcrun || return 1

  require_file "${PROJECT_PATH}/project.pbxproj" || return 1
  require_file "${PROJECT_PATH}/xcshareddata/xcschemes/${SCHEME}.xcscheme" || return 1
  require_file "${SCRIPT_DIR}/ios-contract-audit.mjs" || return 1
  require_file "${SCRIPT_DIR}/validate-release-config.sh" || return 1
  require_file "${IOS_ROOT}/BNBUStudentTests/BNBUStudentModelTests.swift" || return 1
  require_file "${IOS_ROOT}/BNBUStudentUITests/BNBUStudentSmokeUITests.swift" || return 1

  if [[ -z "${BACKEND_ROOT}" ]]; then
    BACKEND_ROOT="${default_backend_root}"
  fi
  [[ -d "${BACKEND_ROOT}" ]] || {
    echo "error: backend root is missing; pass --backend-root" >&2
    return 1
  }
  BACKEND_ROOT="$(CDPATH= cd -- "${BACKEND_ROOT}" && pwd -P)"
  require_file "${BACKEND_ROOT}/openapi/openapi.yaml" || return 1

  validate_release_api_url || return 1

  if [[ -z "${SIMULATOR_DESTINATION}" ]]; then
    select_simulator_destination || return 1
  else
    case "${SIMULATOR_DESTINATION}" in
      "platform=iOS Simulator,"*) ;;
      *)
        echo "error: --destination must target platform=iOS Simulator" >&2
        return 1
        ;;
    esac
    case "${SIMULATOR_DESTINATION}" in
      *$'\n'*|*$'\r'*|*$'\t'*)
        echo "error: --destination contains a forbidden control character" >&2
        return 1
        ;;
    esac
    SIMULATOR_UDID="$(printf '%s' "${SIMULATOR_DESTINATION}" | sed -nE 's/.*[, ]id=([0-9A-Fa-f-]{36})(,.*)?$/\1/p')"
  fi

  xcodebuild -version || return 1
  xcode-select -p || return 1
  node --version || return 1
  xcodebuild -project "${PROJECT_PATH}" -scheme "${SCHEME}" -showdestinations || return 1

  if [[ -n "${SIMULATOR_UDID}" ]]; then
    xcrun simctl boot "${SIMULATOR_UDID}" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "${SIMULATOR_UDID}" -b || return 1
  fi

  printf 'Selected Simulator destination: %s (%s)\n' "${SIMULATOR_DESTINATION}" "${SIMULATOR_SELECTION}"
  echo "Release API: confirmed HTTPS domain supplied (value intentionally omitted)"
  echo "Credential input: none"
}

static_audit() {
  (
    cd -- "${IOS_ROOT}"
    node --check scripts/ios-contract-audit.mjs &&
    BNBU_BACKEND_ROOT="${BACKEND_ROOT}" node scripts/ios-contract-audit.mjs
  )
}

debug_clean_build() {
  xcodebuild \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -sdk iphonesimulator \
    -destination "${SIMULATOR_DESTINATION}" \
    -derivedDataPath "${DERIVED_DATA_DIR}" \
    -resultBundlePath "${RESULT_DIR}/debug-clean-build.xcresult" \
    clean build &&
    require_result_bundle "${RESULT_DIR}/debug-clean-build.xcresult"
}

run_xctest() {
  xcodebuild test \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination "${SIMULATOR_DESTINATION}" \
    -derivedDataPath "${DERIVED_DATA_DIR}" \
    -resultBundlePath "${RESULT_DIR}/xctest.xcresult" \
    -enableCodeCoverage YES \
    -only-testing:BNBUStudentTests &&
    require_result_bundle "${RESULT_DIR}/xctest.xcresult"
}

run_xcuitest() {
  xcodebuild test \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Debug \
    -destination "${SIMULATOR_DESTINATION}" \
    -derivedDataPath "${DERIVED_DATA_DIR}" \
    -resultBundlePath "${RESULT_DIR}/xcuitest.xcresult" \
    -only-testing:BNBUStudentUITests &&
    require_result_bundle "${RESULT_DIR}/xcuitest.xcresult"
}

release_build_unsigned() {
  xcodebuild build \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "${DERIVED_DATA_DIR}" \
    -resultBundlePath "${RESULT_DIR}/release-build.xcresult" \
    "BNBU_API_BASE_URL=${RELEASE_API_BASE_URL}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    "CODE_SIGN_IDENTITY=" \
    "PROVISIONING_PROFILE_SPECIFIER=" &&
    require_result_bundle "${RESULT_DIR}/release-build.xcresult"
}

release_analyze_unsigned() {
  xcodebuild analyze \
    -project "${PROJECT_PATH}" \
    -scheme "${SCHEME}" \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "${DERIVED_DATA_DIR}" \
    -resultBundlePath "${RESULT_DIR}/release-analyze.xcresult" \
    "BNBU_API_BASE_URL=${RELEASE_API_BASE_URL}" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    "CODE_SIGN_IDENTITY=" \
    "PROVISIONING_PROFILE_SPECIFIER=" &&
    require_result_bundle "${RESULT_DIR}/release-analyze.xcresult"
}

if run_step 0 preflight; then
  :
else
  exit 1
fi

ANY_FAILURE=0

if run_step 1 static_audit; then :; else ANY_FAILURE=1; fi
if run_step 2 debug_clean_build; then :; else ANY_FAILURE=1; fi
if run_step 3 run_xctest; then :; else ANY_FAILURE=1; fi
if run_step 4 run_xcuitest; then :; else ANY_FAILURE=1; fi
if run_step 5 release_build_unsigned; then :; else ANY_FAILURE=1; fi
if run_step 6 release_analyze_unsigned; then :; else ANY_FAILURE=1; fi

if ((ANY_FAILURE == 0)); then
  OVERALL_STATUS="PASS"
  exit 0
fi

exit 1
