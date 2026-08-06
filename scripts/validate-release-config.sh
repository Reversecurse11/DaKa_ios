#!/bin/sh
set -eu

if [ "${BNBU_REQUIRE_APPROVED_API_URL:-NO}" != "YES" ]; then
  exit 0
fi

api_base_url="${BNBU_API_BASE_URL:-}"
environment_name="${BNBU_ENVIRONMENT:-}"

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
