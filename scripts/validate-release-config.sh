#!/bin/sh
set -eu

if [ "${CONFIGURATION:-}" != "Release" ]; then
  exit 0
fi

api_base_url="${BNBU_API_BASE_URL:-}"

case "$api_base_url" in
  https://*) ;;
  *)
    echo "error: Release BNBU_API_BASE_URL must use HTTPS." >&2
    exit 1
    ;;
esac

case "$api_base_url" in
  *configuration-required.invalid*|*.invalid/*|*localhost*|*127.0.0.1*)
    echo "error: Replace the placeholder BNBU_API_BASE_URL before archiving Release." >&2
    exit 1
    ;;
esac

case "$api_base_url" in
  */api/v1) ;;
  *)
    echo "error: Release BNBU_API_BASE_URL must end with /api/v1." >&2
    exit 1
    ;;
esac
