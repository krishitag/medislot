#!/usr/bin/env bash
# MediSlot database helper (runs sqlplus inside the Oracle XE container)
#   tools/db.sh reset   ->  01_schema -> 02_plsql -> 03_seed  (fresh load)
#   tools/db.sh tests   ->  reset, then 04_tests; raw output saved to screenshots/tests_output.txt
set -euo pipefail
cd "$(dirname "$0")/.."

CONTAINER="${CONTAINER:-oracle-xe}"
CONN="medislot/medislot123@//localhost:1521/XEPDB1"

run_sql() {   # $1 = file, $2 = optional SQL*Plus settings to put first
  { printf '%s\n' "${2:-}"; cat "$1"; printf '\nexit\n'; } |
    docker exec -i "$CONTAINER" sqlplus -S -L "$CONN"
}

reset() {
  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "Container '$CONTAINER' is not running. Start it with:  docker start $CONTAINER" >&2
    exit 1
  fi
  for f in 01_schema 02_plsql 03_seed; do
    out=$(run_sql "database/$f.sql")
    if grep -qE 'ORA-|PLS-|SP2-' <<<"$out"; then
      echo "$out"; echo "!! $f.sql reported an error (see above)" >&2; exit 1
    fi
    echo "ok  $f.sql"
  done
  # every PL/SQL object must have compiled cleanly
  errs=$(printf 'SELECT COUNT(*) FROM user_errors;\n' | docker exec -i "$CONTAINER" sqlplus -S -L "$CONN" | tr -dc '0-9')
  echo "user_errors rows: $errs"
  [ "$errs" = "0" ] || { echo "!! compile errors present" >&2; exit 1; }
  echo "Database reset to fresh seed data."
}

tests() {
  reset
  mkdir -p screenshots
  # LINESIZE 200 only stops SQL*Plus from wrapping long lines at 80 columns
  run_sql database/04_tests.sql "SET LINESIZE 200" | tee screenshots/tests_output.txt
  echo
  echo "PASS lines: $(grep -c '^PASS' screenshots/tests_output.txt || true)   FAIL lines: $(grep -c '^FAIL' screenshots/tests_output.txt || true)"
  echo "Saved: screenshots/tests_output.txt"
}

case "${1:-}" in
  reset) reset ;;
  tests) tests ;;
  *) echo "usage: tools/db.sh reset|tests" >&2; exit 1 ;;
esac
