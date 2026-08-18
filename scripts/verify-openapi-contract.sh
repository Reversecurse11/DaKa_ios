#!/bin/sh
set -eu

expected_sha256="853e7f5efadb10dcbbe0f446c4c60962ce2fd864360a156343b5740d0c1761a4"
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
