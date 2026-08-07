#!/bin/sh
set -eu

expected_sha256="914084874afda2481813a041da4cc01249aa9ea557d9a8bf29baeed4f10e0dc9"
snapshot="${SRCROOT:-$(pwd)}/Contracts/openapi.snapshot.yaml"

if [ ! -f "$snapshot" ]; then
  echo "error: Required OpenAPI snapshot is missing: $snapshot" >&2
  exit 1
fi
actual_sha256="$(shasum -a 256 "$snapshot" | awk '{print $1}')"
if [ "$actual_sha256" != "$expected_sha256" ]; then
  echo "error: OpenAPI SHA-256 mismatch. Expected $expected_sha256, got $actual_sha256" >&2
  exit 1
fi

ruby "${SRCROOT:-$(pwd)}/scripts/generate-openapi-models.rb" \
  --input "$snapshot" \
  --check

generated="${SRCROOT:-$(pwd)}/BNBUStudentApp/Backend/Generated/APIV1Models.generated.swift"
if grep -qi "storageKey" "$generated"; then
  echo "error: Public generated DTOs must not expose storageKey." >&2
  exit 1
fi
