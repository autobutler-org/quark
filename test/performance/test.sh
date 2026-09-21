#!/usr/bin/env bash
set -euo pipefail

BASE_URL="${QUARK_BASE_URL:-http://127.0.0.1:8080}"
AUTH_USER="${QUARK_USERNAME:-perf}"
AUTH_PASS="${QUARK_PASSWORD:-perf-password}"
ACCESS_TOKEN="${QUARK_ACCESS_TOKEN:-}"
READER_USER="${QUARK_READER_USERNAME:-perf-reader}"
READER_PASS="${QUARK_READER_PASSWORD:-perf-reader-password}"
READER_TOKEN=""
THREADS="${TEST_THREADS:-4}"
CONCURRENCY="${TEST_CONCURRENCY:-20}"
DURATION="${TEST_DURATION:-20s}"
UPLOAD_CONCURRENCY="${TEST_UPLOAD_CONCURRENCY:-10}"
UPLOAD_COUNT="${TEST_UPLOAD_COUNT:-20}"

WORK_DIR="${WORK_DIR:-$PWD/test-results/performance}"
PERF_FIXTURE_TARGET_DIR="${PERF_FIXTURE_TARGET_DIR:-$HOME/quark/data/files}"
SCENARIO_DIR="$PWD/test/performance/wrk"

mkdir -p "$WORK_DIR" "$WORK_DIR/upload-fixtures"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "missing required command: $1" >&2
    exit 1
  fi
}

require_cmd curl
require_cmd wrk

wait_for_server() {
  local retries=60
  local status_url="$BASE_URL/api/v0/auth/status"
  for _ in $(seq 1 "$retries"); do
    if curl -sS -f "$status_url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  echo "server did not become ready: $status_url" >&2
  return 1
}

extract_session_token() {
  local cookie_file="$1"
  # curl cookie-jar stores HttpOnly cookies with a "#HttpOnly_" prefix in
  # column 1. Those are real cookie rows, not comments, so include them.
  awk '((($0 !~ /^#/) || ($1 ~ /^#HttpOnly_/)) && $6 == "session") { print $7 }' "$cookie_file" | tail -n 1
}

auth_setup_if_needed() {
  local setup_resp
  local setup_status
  local cookie_file="$WORK_DIR/auth_cookie_setup.txt"
  setup_resp="$(curl -sS "$BASE_URL/api/v0/auth/status")"

  if echo "$setup_resp" | grep -q '"setup":true'; then
    return 0
  fi

  setup_status="$(curl -sS -o /dev/null -w "%{http_code}" \
    -c "$cookie_file" \
    -X POST "$BASE_URL/api/v0/auth/setup" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$AUTH_USER\",\"password\":\"$AUTH_PASS\"}")"

  if [[ "$setup_status" != "200" ]]; then
    echo "failed to initialize auth via /api/v0/auth/setup (status=$setup_status)." >&2
    return 1
  fi

  if [[ -z "$ACCESS_TOKEN" ]]; then
    ACCESS_TOKEN="$(extract_session_token "$cookie_file")"
    if [[ -z "$ACCESS_TOKEN" ]]; then
      echo "setup succeeded but no session token cookie was returned." >&2
      return 1
    fi
  fi
}

auth_login_and_get_token() {
  # Respect explicit token override from env for CI or local debugging.
  if [[ -n "$ACCESS_TOKEN" ]]; then
    return 0
  fi

  local login_status
  local cookie_file="$WORK_DIR/auth_cookie_login.txt"
  login_status="$(curl -sS -o /dev/null -w "%{http_code}" \
    -c "$cookie_file" \
    -X POST "$BASE_URL/api/v0/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$AUTH_USER\",\"password\":\"$AUTH_PASS\"}")"

  if [[ "$login_status" != "200" ]]; then
    echo "quark auth mismatch: login failed for configured credentials (status=$login_status)." >&2
    echo "set QUARK_ACCESS_TOKEN or QUARK_USERNAME/QUARK_PASSWORD correctly for this instance." >&2
    return 1
  fi

  ACCESS_TOKEN="$(extract_session_token "$cookie_file")"
  if [[ -z "$ACCESS_TOKEN" ]]; then
    echo "login succeeded but no session token cookie was returned." >&2
    return 1
  fi
}

# A non-admin account with read access to the whole files root. Admins skip
# the access checks entirely, so without this the non-admin path never runs.
setup_reader() {
  local create_resp
  local create_status
  local reader_id
  local grant_status
  local cookie_file="$WORK_DIR/auth_cookie_reader.txt"

  create_resp="$WORK_DIR/reader_create.json"
  create_status="$(curl -sS -o "$create_resp" -w "%{http_code}" \
    -X POST "$BASE_URL/api/v0/admin/users" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$READER_USER\",\"password\":\"$READER_PASS\"}")"

  # 409 means an earlier run against this instance already made the account.
  if [[ "$create_status" == "201" ]]; then
    reader_id="$(sed -n 's/.*"id":\([0-9][0-9]*\).*/\1/p' "$create_resp")"
    grant_status="$(curl -sS -o /dev/null -w "%{http_code}" \
      -X PUT "$BASE_URL/api/v0/access" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"deviceSerial\":\"\",\"relPath\":\"\",\"userId\":$reader_id,\"level\":\"read\"}")"
    if [[ "$grant_status" != "200" ]]; then
      echo "failed to grant $READER_USER read access via /api/v0/access (status=$grant_status)." >&2
      return 1
    fi
  elif [[ "$create_status" != "409" ]]; then
    echo "failed to create $READER_USER via /api/v0/admin/users (status=$create_status)." >&2
    return 1
  fi

  local login_status
  login_status="$(curl -sS -o /dev/null -w "%{http_code}" \
    -c "$cookie_file" \
    -X POST "$BASE_URL/api/v0/auth/login" \
    -H "Content-Type: application/json" \
    -d "{\"username\":\"$READER_USER\",\"password\":\"$READER_PASS\"}")"
  if [[ "$login_status" != "200" ]]; then
    echo "login failed for $READER_USER (status=$login_status)." >&2
    return 1
  fi
  READER_TOKEN="$(extract_session_token "$cookie_file")"
  if [[ -z "$READER_TOKEN" ]]; then
    echo "login succeeded for $READER_USER but no session token cookie was returned." >&2
    return 1
  fi
}

prepare_fixtures() {
  bash "$PWD/test/performance/generate_files.sh" "$PERF_FIXTURE_TARGET_DIR"
  for i in $(seq 1 "$UPLOAD_COUNT"); do
    dd if=/dev/zero of="$WORK_DIR/upload-fixtures/upload-$i.bin" bs=1024 count=64 status=none
  done
}

seed_albums() {
  curl -sS -X POST "$BASE_URL/api/v0/albums" \
    -H "Authorization: Bearer $ACCESS_TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"name":"perf-root"}' >/dev/null || true

  for i in $(seq 1 25); do
    curl -sS -X POST "$BASE_URL/api/v0/albums" \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"name\":\"perf-album-$i\"}" >/dev/null || true
  done
}

run_wrk() {
  local name="$1"
  local script="$2"
  local token="${3:-$ACCESS_TOKEN}"

  echo "Running $name"
  wrk \
    -t"$THREADS" \
    -c"$CONCURRENCY" \
    -d"$DURATION" \
    --latency \
    -H "Authorization: Bearer $token" \
    -s "$script" \
    "$BASE_URL" | tee "$WORK_DIR/$name.txt"
}

run_upload_stress() {
  echo "Running upload stress"
  ls "$WORK_DIR/upload-fixtures"/*.bin | \
    xargs -I{} -P "$UPLOAD_CONCURRENCY" \
      curl -sS -o /dev/null -w "%{http_code}\n" \
        -X POST "$BASE_URL/api/v0/files/upload" \
        -H "Authorization: Bearer $ACCESS_TOKEN" \
        -F "file=@{}" > "$WORK_DIR/upload_status_codes.txt"

  local failures
  failures="$(grep -vc '^200$' "$WORK_DIR/upload_status_codes.txt" || true)"
  if [[ "$failures" != "0" ]]; then
    echo "upload stress had non-200 responses: $failures" >&2
    return 1
  fi
}

main() {
  wait_for_server
  auth_setup_if_needed
  auth_login_and_get_token
  prepare_fixtures
  setup_reader
  seed_albums

  run_wrk "files_list" "$SCENARIO_DIR/files_list.lua"
  run_wrk "files_list_nonadmin" "$SCENARIO_DIR/files_list.lua" "$READER_TOKEN"
  run_wrk "files_stat" "$SCENARIO_DIR/files_stat.lua"
  run_wrk "files_stat_nonadmin" "$SCENARIO_DIR/files_stat.lua" "$READER_TOKEN"
  run_wrk "photos_list" "$SCENARIO_DIR/photos_list.lua"
  run_wrk "thumbnails" "$SCENARIO_DIR/thumbnails.lua"
  run_wrk "albums_list" "$SCENARIO_DIR/albums_list.lua"
  run_wrk "photos_metadata" "$SCENARIO_DIR/photos_metadata.lua"
  run_upload_stress
}

main "$@"
