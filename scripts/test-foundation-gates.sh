#!/bin/sh
set -eu

root="${SRCROOT:-$(pwd)}"
temporary_directory="$(mktemp -d)"
trap 'rm -rf "$temporary_directory"' EXIT HUP INT TERM

"$root/scripts/verify-openapi-contract.sh"

cp "$root/Contracts/openapi.snapshot.yaml" "$temporary_directory/openapi.snapshot.yaml"
printf '\n# hash-gate-negative-test\n' >> "$temporary_directory/openapi.snapshot.yaml"
if ruby "$root/scripts/generate-openapi-models.rb" \
  --input "$temporary_directory/openapi.snapshot.yaml" \
  --output "$temporary_directory/generated.swift" >/dev/null 2>&1; then
  echo "error: Modified OpenAPI snapshot unexpectedly passed the hash gate." >&2
  exit 1
fi

if grep -q "http://123\.207\.5\.70\|127\.0\.0\.1:8080" \
  "$root/BNBUStudentApp/Core/RemoteStudentRepository.swift" \
  "$root/BNBUStudentApp/Core/StudentAPIClient.swift" \
  "$root/BNBUStudentApp/Backend/BackendEnvironment.swift"; then
  echo "error: Legacy API endpoint remains reachable in backend foundation code." >&2
  exit 1
fi

if BNBU_REQUIRE_APPROVED_API_URL=YES \
   BNBU_ENVIRONMENT=production \
   BNBU_API_BASE_URL=https://configuration-required.invalid/api/v1 \
   CONFIGURATION=Release \
   "$root/scripts/validate-release-config.sh" >/dev/null 2>&1; then
  echo "error: Placeholder production URL unexpectedly passed release validation." >&2
  exit 1
fi

echo "Foundation static gates passed."
