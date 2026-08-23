#!/bin/sh
set -eu

if [ "${BNBU_REQUIRE_APPROVED_API_URL:-NO}" != "YES" ]; then
  exit 0
fi

api_base_url="${BNBU_API_BASE_URL:-}"
environment_name="${BNBU_ENVIRONMENT:-}"
organization_code="${BNBU_ORGANIZATION_CODE:-}"
contract_version="${BNBU_CONTRACT_VERSION:-}"
contract_sha256="${BNBU_CONTRACT_SHA256:-}"

case "$environment_name" in
  staging|production) ;;
  *)
    echo "error: Approved remote builds require BNBU_ENVIRONMENT=staging or production." >&2
    exit 1
    ;;
esac

case "$api_base_url" in
  https://*) ;;
  *)
    echo "error: Approved remote BNBU_API_BASE_URL must use HTTPS." >&2
    exit 1
    ;;
esac

case "$api_base_url" in
  *configuration-required.invalid*|*.invalid/*|*localhost*|*127.0.0.1*)
    echo "error: Replace the placeholder BNBU_API_BASE_URL before building Staging or Release." >&2
    exit 1
    ;;
esac

case "$api_base_url" in
  */api/v1) ;;
  *)
    echo "error: Approved remote BNBU_API_BASE_URL must end with /api/v1." >&2
    exit 1
    ;;
esac

if [ "$organization_code" != "BNBU" ]; then
  echo "error: Approved remote builds require BNBU_ORGANIZATION_CODE=BNBU." >&2
  exit 1
fi

if [ "$contract_version" != "2.0.10-contract" ]; then
  echo "error: Approved remote builds require BNBU_CONTRACT_VERSION=2.0.10-contract." >&2
  exit 1
fi

if [ "$contract_sha256" != "56f7f13cdd8122dae630fec93bf198f7ed6d92a5fc4f67ae4f866a3b41c38ad7" ]; then
  echo "error: Approved remote builds require the published Contract 2.0.10 SHA-256." >&2
  exit 1
fi

if [ "$environment_name" = "staging" ] && [ "$api_base_url" != "https://api.verityai.cn/api/v1" ]; then
  echo "error: Staging builds must use the frozen R01 HTTPS API URL." >&2
  exit 1
fi
