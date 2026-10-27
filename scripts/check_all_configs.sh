#!/usr/bin/env bash
#
# check_all_configs.sh
#
# Repository validation suite: runs validate_gnb_yaml.py over every YAML file
# in configs/ and exits non-zero if any of them reports an error.
#
# This is the check to run before committing a config change. It is read-only:
# it never edits a config.
#
# Usage:
#   ./scripts/check_all_configs.sh                 # validate configs/*.yaml
#   ./scripts/check_all_configs.sh --verbose       # also print each validator report
#   ./scripts/check_all_configs.sh --dir path/     # validate a different directory
#   ./scripts/check_all_configs.sh -- --strict     # pass flags to the validator
#
# Exit codes:
#   0 = every config validated without errors
#   1 = at least one config reported errors or failed to parse
#   2 = harness problem (validator or config directory missing, no python3)
#
# Note: configs/*.conf are OAI libconfig files, not YAML. The validator only
# understands YAML, so .conf files are listed as skipped rather than failed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
VALIDATOR="${SCRIPT_DIR}/validate_gnb_yaml.py"
CONFIG_DIR="${REPO_ROOT}/configs"
VERBOSE=0
VALIDATOR_ARGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --verbose|-v) VERBOSE=1; shift ;;
    --dir)        CONFIG_DIR="$2"; shift 2 ;;
    --)           shift; while [ $# -gt 0 ]; do VALIDATOR_ARGS+=("$1"); shift; done ;;
    -h|--help)    sed -n '3,25p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 2 ;;
  esac
done

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 not found." >&2; exit 2; }
[ -f "$VALIDATOR" ] || { echo "ERROR: validator not found: $VALIDATOR" >&2; exit 2; }
[ -d "$CONFIG_DIR" ] || { echo "ERROR: config directory not found: $CONFIG_DIR" >&2; exit 2; }

passed=0
failed=0
skipped=0
failed_names=""

echo "=== Validating configs in ${CONFIG_DIR} ==="
echo

for cfg in "$CONFIG_DIR"/*.yaml; do
  [ -e "$cfg" ] || continue
  name="$(basename "$cfg")"

  rc=0
  output="$(python3 "$VALIDATOR" "$cfg" ${VALIDATOR_ARGS[@]+"${VALIDATOR_ARGS[@]}"} 2>&1)" || rc=$?

  case "$rc" in
    0)
      # Surface the warning count so a "pass" is not mistaken for "clean".
      summary="$(printf '%s\n' "$output" | grep -o 'Summary: .*' | head -1 || true)"
      printf '  PASS   %-36s %s\n' "$name" "${summary:-}"
      passed=$((passed + 1))
      ;;
    1)
      summary="$(printf '%s\n' "$output" | grep -o 'Summary: .*' | head -1 || true)"
      if [ -z "$summary" ]; then
        # No summary means the validator aborted rather than completing a report.
        if printf '%s\n' "$output" | grep -q 'Traceback (most recent call last)'; then
          summary="validator CRASHED: $(printf '%s\n' "$output" | tail -1)"
        else
          summary="validator produced no summary"
        fi
      fi
      printf '  FAIL   %-36s %s\n' "$name" "$summary"
      failed=$((failed + 1))
      failed_names="${failed_names}${name} "
      ;;
    2)
      printf '  FAIL   %-36s %s\n' "$name" "validator could not parse the file (exit 2)"
      failed=$((failed + 1))
      failed_names="${failed_names}${name} "
      ;;
    *)
      printf '  FAIL   %-36s %s\n' "$name" "validator exited unexpectedly (exit ${rc})"
      failed=$((failed + 1))
      failed_names="${failed_names}${name} "
      ;;
  esac

  if [ "$VERBOSE" -eq 1 ]; then
    printf '%s\n' "$output" | sed 's/^/         | /'
    echo
  fi
done

for cfg in "$CONFIG_DIR"/*.conf; do
  [ -e "$cfg" ] || continue
  printf '  SKIP   %-36s %s\n' "$(basename "$cfg")" "libconfig format, not YAML"
  skipped=$((skipped + 1))
done

echo
echo "=== ${passed} passed, ${failed} failed, ${skipped} skipped ==="

if [ "$failed" -gt 0 ]; then
  echo "Failing configs: ${failed_names}" >&2
  echo "Re-run with --verbose to see why. Do not edit a config just to satisfy the" >&2
  echo "validator: a _testbed config may be recording reality, and a _general config" >&2
  echo "may be an annotated template rather than a deployable file." >&2
  exit 1
fi

exit 0
