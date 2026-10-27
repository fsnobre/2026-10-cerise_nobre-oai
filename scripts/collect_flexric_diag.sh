#!/usr/bin/env bash
set -u
set -o pipefail

# collect_flexric_diag.sh
#
# Read-only diagnostic collector for a FlexRIC nearRT-RIC host.
# Collects RIC process state, E2 agent connections, xApp status,
# service model availability, and recent log output.
#
# Usage examples:
#   ./collect_flexric_diag.sh
#   ./collect_flexric_diag.sh --compose docker-compose-ric.yaml
#   ./collect_flexric_diag.sh --flexric-bin /usr/local/bin/nearRT-RIC --pcap 15
#   ./collect_flexric_diag.sh --since 60m --full-logs
#
# Notes:
# - Does not change FlexRIC or gNB configuration.
# - Optional tcpdump capture requires sudo.
# - If FlexRIC runs as a bare process (not container), pass --bare-process.

COMPOSE_FILE="docker-compose-ric.yaml"
FLEXRIC_BIN=""
FLEXRIC_CONF="/usr/local/etc/flexric/flexric.conf"
XAPP_PATTERN="xapp"
RIC_PORT=36421
E2_PORT=36422
SINCE="30m"
PCAP_SECONDS=0
OUT_PARENT="."
INCLUDE_FULL_LOGS=0
BARE_PROCESS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose)         COMPOSE_FILE="$2";  shift 2 ;;
    --flexric-bin)     FLEXRIC_BIN="$2";   shift 2 ;;
    --flexric-conf)    FLEXRIC_CONF="$2";  shift 2 ;;
    --xapp-pattern)    XAPP_PATTERN="$2";  shift 2 ;;
    --ric-port)        RIC_PORT="$2";      shift 2 ;;
    --e2-port)         E2_PORT="$2";       shift 2 ;;
    --since)           SINCE="$2";         shift 2 ;;
    --pcap)            PCAP_SECONDS="$2";  shift 2 ;;
    --out-parent)      OUT_PARENT="$2";    shift 2 ;;
    --full-logs)       INCLUDE_FULL_LOGS=1; shift ;;
    --bare-process)    BARE_PROCESS=1;     shift ;;
    -h|--help) sed -n '1,30p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

TS="$(date +%Y%m%d_%H%M%S)"
OUT="${OUT_PARENT%/}/flexric_diag_${TS}"
mkdir -p "$OUT"

log()      { echo "[$(date '+%F %T')] $*" | tee -a "$OUT/00_run.log"; }
have_cmd() { command -v "$1" >/dev/null 2>&1; }

run_shell() {
  local name="$1"; shift
  local cmd="$*"
  log "Running: $name"
  {
    echo "===== $name ====="
    echo "Command: $cmd"
    echo "Date: $(date -Is)"
    echo
    bash -lc "$cmd"
  } > "$OUT/${name}.txt" 2>&1 || {
    echo "Command failed (non-zero exit): $cmd" >> "$OUT/${name}.txt"
    return 0
  }
}

docker_compose_cmd() {
  if docker compose version >/dev/null 2>&1; then echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then echo "docker-compose"
  else echo ""
  fi
}

DC="$(docker_compose_cmd)"

# ---------------------------------------------------------------------------
# Detect FlexRIC components
# ---------------------------------------------------------------------------

# Containers whose names suggest RIC / E2 / xApp involvement
detect_ric_containers() {
  docker ps -a --format '{{.Names}}' 2>/dev/null \
    | grep -Ei '(^|[-_])(ric|flexric|nearrt|e2|xapp|kpm|rc|slice|oai-ric)' \
    | sort -u || true
}

RIC_CONTAINERS="$(detect_ric_containers | tr '\n' ' ')"

# Bare process detection
detect_ric_processes() {
  ps aux 2>/dev/null | grep -Ei 'nearRT-RIC|flexric|nr-softmodem.*e2|xapp_kpm|xapp_rc|xapp_slice' \
    | grep -v grep || true
}

{
  echo "Timestamp=$TS"
  echo "Output directory=$OUT"
  echo "Compose file=$COMPOSE_FILE"
  echo "FlexRIC config=$FLEXRIC_CONF"
  echo "Detected RIC containers=${RIC_CONTAINERS:-none}"
  echo "SINCE=$SINCE"
  echo "PCAP_SECONDS=$PCAP_SECONDS"
  echo "RIC_PORT=$RIC_PORT"
  echo "E2_PORT=$E2_PORT"
} > "$OUT/00_detected.txt"

log "Output directory: $OUT"

# ---------------------------------------------------------------------------
# System baseline
# ---------------------------------------------------------------------------
run_shell "01_system" '
date; uname -a
lsb_release -a 2>/dev/null || cat /etc/os-release
uptime
'

# ---------------------------------------------------------------------------
# Process detection (bare and containerised)
# ---------------------------------------------------------------------------
run_shell "02_ric_processes" "
echo '=== Bare processes ==='
$(declare -f detect_ric_processes)
detect_ric_processes

echo
echo '=== Docker containers ==='
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null \
  | grep -Ei 'name|ric|flexric|e2|xapp|kpm|rc|slice|nearrt' || true
"

# ---------------------------------------------------------------------------
# FlexRIC config file
# ---------------------------------------------------------------------------
run_shell "03_flexric_config" "
if [ -f '$FLEXRIC_CONF' ]; then
  echo 'Config: $FLEXRIC_CONF'
  cat '$FLEXRIC_CONF'
else
  echo 'FlexRIC config not found at $FLEXRIC_CONF'
  echo 'Searching common locations...'
  find /usr/local/etc /etc /opt -maxdepth 4 -name 'flexric.conf' 2>/dev/null | head -10 || true
fi
"

# ---------------------------------------------------------------------------
# Docker compose
# ---------------------------------------------------------------------------
if [[ -n "$DC" && -f "$COMPOSE_FILE" ]]; then
  run_shell "04_compose_ps"     "$DC -f '$COMPOSE_FILE' ps"
  run_shell "05_compose_config" "$DC -f '$COMPOSE_FILE' config"
else
  echo "No compose file found at $COMPOSE_FILE" > "$OUT/04_compose_ps.txt"
fi

# ---------------------------------------------------------------------------
# Per-container: inspect, logs, exec
# ---------------------------------------------------------------------------
mkdir -p "$OUT/container_inspect" "$OUT/container_logs_recent" "$OUT/container_logs_full" "$OUT/container_exec"

for c in $RIC_CONTAINERS; do
  safe="${c//[^A-Za-z0-9_.-]/_}"
  log "Collecting container: $c"

  docker inspect "$c" > "$OUT/container_inspect/${safe}.json" 2>&1 || true
  docker logs "$c" --since "$SINCE" > "$OUT/container_logs_recent/${safe}.log" 2>&1 || true

  if [[ "$INCLUDE_FULL_LOGS" -eq 1 ]]; then
    docker logs "$c" > "$OUT/container_logs_full/${safe}.log" 2>&1 || true
  else
    echo "Full logs skipped. Re-run with --full-logs." > "$OUT/container_logs_full/${safe}.log"
  fi

  docker exec "$c" sh -lc '
    echo "=== date ===" && date
    echo "=== ps ===" && ps aux 2>/dev/null || ps
    echo "=== ip addr ===" && ip -br addr 2>/dev/null || true
    echo "=== listening sockets ===" && ss -tunap 2>/dev/null | grep -Ei "36421|36422|e2|ric|xapp" || true
    echo "=== flexric conf ===" && find /usr/local/etc /etc /opt -maxdepth 4 -name flexric.conf 2>/dev/null | xargs cat 2>/dev/null || true
    echo "=== service model shared libs ===" && find /usr/local/lib /usr/lib /opt -maxdepth 6 -name "*.so" 2>/dev/null | grep -i "sm\|kpm\|rc\|slice\|e2ap\|flexric" | sort || true
  ' > "$OUT/container_exec/${safe}_runtime.txt" 2>&1 || true
done

# ---------------------------------------------------------------------------
# E2 / RIC network sockets
# ---------------------------------------------------------------------------
run_shell "06_e2_ric_sockets" "
echo '=== Active E2/RIC sockets (ports $RIC_PORT and $E2_PORT) ==='
ss -tunap 2>/dev/null | grep -E '$RIC_PORT|$E2_PORT' || true
echo
echo '=== SCTP associations ==='
ss -nap --sctp 2>/dev/null || netstat -nap --sctp 2>/dev/null || true
echo
echo '=== All SCTP sockets ==='
cat /proc/net/sctp/assocs 2>/dev/null || true
echo
echo '=== Connections on E2 port from gNB ==='
ss -tnap 2>/dev/null | grep '$E2_PORT' || true
"

# ---------------------------------------------------------------------------
# Service model detection
# ---------------------------------------------------------------------------
run_shell "07_service_models" "
echo '=== FlexRIC service model shared libraries on host ==='
find /usr/local/lib /usr/lib /opt /home -maxdepth 8 \
  -name '*.so' 2>/dev/null \
  | grep -iE 'sm_|kpm|_rc|slice|e2ap|flexric|ccc' \
  | sort || true

echo
echo '=== Build artifacts (nearRT-RIC, xApp binaries) ==='
find /usr/local/bin /usr/bin /opt /home -maxdepth 8 \
  -name 'nearRT-RIC' -o -name 'xapp_kpm*' -o -name 'xapp_rc*' -o -name 'xapp_slice*' \
  -o -name 'xapp_ccc*' 2>/dev/null | sort || true

echo
echo '=== FlexRIC build dir (if present) ==='
find /home /opt /root -maxdepth 6 -name 'CMakeCache.txt' 2>/dev/null \
  | xargs grep -l 'flexric\|FlexRIC' 2>/dev/null | head -5 || true
"

# ---------------------------------------------------------------------------
# xApp process/container inspection
# ---------------------------------------------------------------------------
run_shell "08_xapp_status" "
echo '=== xApp processes ==='
ps aux 2>/dev/null | grep -Ei '$XAPP_PATTERN|xapp_kpm|xapp_rc|xapp_slice|xapp_ccc' | grep -v grep || true

echo
echo '=== xApp docker containers ==='
docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>/dev/null \
  | grep -Ei 'name|xapp|kpm|rc_app|slice|ccc' || true

echo
echo '=== Recent xApp logs (last 200 lines each container) ==='
for c in \$(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'xapp|kpm|rc_app|slice'); do
  echo '--- Container:' \$c '---'
  docker logs '\$c' --since '$SINCE' 2>&1 | tail -200 || true
done
"

# ---------------------------------------------------------------------------
# Log keyword summary across all collected RIC logs
# ---------------------------------------------------------------------------
run_shell "09_log_keyword_summary" "
for f in '$OUT/container_logs_recent/'*.log; do
  [ -f \"\$f\" ] || continue
  echo '===== '\$(basename \"\$f\")' ====='
  grep -Ein \
    'error|warn|fail|fatal|assert|segfault|sctp|e2ap|e2sm|kpm|rc|slice|ccc|subscribe|indicate|control|reset|disconnect|connect|xapp|ricind|ricreq|ricctrl|timeout|abort|refused|rejected|unexpected|itti|teardown|setup|ack|nack|cause|ran_function|service model|sm_id|e2_node|gnb|plmn|mcc|mnc|001|rnti' \
    \"\$f\" || true
  echo
done
"

# ---------------------------------------------------------------------------
# E2 version and build info
# ---------------------------------------------------------------------------
run_shell "10_e2_version_info" "
echo '=== E2AP / KPM version from binary strings ==='
for b in \$(find /usr/local/bin /usr/bin /opt /home -maxdepth 8 \
            -name 'nearRT-RIC' -o -name 'nr-softmodem' 2>/dev/null); do
  echo '--- Binary: '\$b' ---'
  strings \"\$b\" 2>/dev/null | grep -Ei 'e2ap_v|kpm_v|E2AP|KPM|E2SM|flexric|version|build' | head -20 || true
  echo
done

echo '=== CMake build options (if build dir found) ==='
for cmake in \$(find /home /opt /root -maxdepth 8 -name 'CMakeCache.txt' 2>/dev/null \
               | xargs grep -l 'flexric\|FlexRIC' 2>/dev/null | head -3); do
  echo '--- '\$cmake' ---'
  grep -iE 'E2AP_VERSION|KPM_VERSION|RC_VERSION|E2SM|BUILD_TYPE|CMAKE_BUILD' \"\$cmake\" || true
  echo
done
"

# ---------------------------------------------------------------------------
# gNB ↔ RIC E2 connection check (from gNB side if available)
# ---------------------------------------------------------------------------
run_shell "11_gnb_e2_agent_status" "
echo '=== gNB container E2 agent socket ==='
for gnb in \$(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei '^oai-gnb|gnb|nr-softmodem'); do
  echo '--- Container: '\$gnb' ---'
  docker exec \"\$gnb\" ss -tnap 2>/dev/null | grep -E '$RIC_PORT|$E2_PORT|36421|36422' || true
  echo
done

echo '=== gNB E2 logs (recent keyword filter) ==='
for gnb in \$(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei '^oai-gnb|gnb|nr-softmodem'); do
  echo '--- Container: '\$gnb' ---'
  docker logs \"\$gnb\" --since '$SINCE' 2>&1 \
    | grep -Ei 'e2ap|e2sm|flexric|ric|xapp|subscribe|kpm|rc|slice|sctp.*36|36.*sctp' \
    | tail -100 || true
  echo
done
"

# ---------------------------------------------------------------------------
# Optional pcap: E2 interface (SCTP on RIC/E2 ports)
# ---------------------------------------------------------------------------
if [[ "$PCAP_SECONDS" =~ ^[0-9]+$ ]] && [[ "$PCAP_SECONDS" -gt 0 ]]; then
  if have_cmd tcpdump; then
    log "Running E2 interface tcpdump for $PCAP_SECONDS seconds"
    sudo timeout "$PCAP_SECONDS" tcpdump -ni any \
      "sctp or port $RIC_PORT or port $E2_PORT" \
      -w "$OUT/e2_sctp_${PCAP_SECONDS}s.pcap" > "$OUT/12_tcpdump_e2_pcap.txt" 2>&1 || true
    run_shell "12_tcpdump_e2_text" \
      "sudo timeout '$PCAP_SECONDS' tcpdump -ni any 'sctp or port $RIC_PORT or port $E2_PORT' -vv"
  else
    echo "tcpdump not installed." > "$OUT/12_tcpdump_e2_text.txt"
  fi
fi

# ---------------------------------------------------------------------------
# Host networking summary
# ---------------------------------------------------------------------------
run_shell "13_host_network" "
ip -br addr
echo
ip route
echo
ss -tunap 2>/dev/null | grep -Ei '36421|36422|e2|ric' || true
echo
docker network ls 2>/dev/null || true
"

# ---------------------------------------------------------------------------
# README
# ---------------------------------------------------------------------------
cat > "$OUT/README_NEXT_STEPS.txt" <<EOF
FlexRIC nearRT-RIC diagnostic bundle generated at: $TS

High-value files:
- 00_detected.txt
- 02_ric_processes.txt
- 03_flexric_config.txt
- 04_compose_ps.txt / 05_compose_config.txt
- 06_e2_ric_sockets.txt   — is SCTP on port $E2_PORT active? how many E2 nodes connected?
- 07_service_models.txt   — are KPM/RC/CCC .so files present?
- 08_xapp_status.txt      — which xApps are running?
- 09_log_keyword_summary.txt
- 10_e2_version_info.txt  — E2AP/KPM version consistency check
- 11_gnb_e2_agent_status.txt — gNB E2 agent socket and E2-related log lines

Analysis checklist:
1) Check 06 for SCTP association on port $E2_PORT. No association = gNB E2 agent not connecting.
2) Check 03 for flexric.conf — E2AP_VERSION and KPM_VERSION must match gNB build.
3) Check 07 for service model .so files — if missing, RIC cannot decode KPM/RC messages.
4) Check 09 for 'reject', 'cause', 'nack' — E2 setup cause codes are the first diagnostic.
5) Check 10 for E2AP/KPM version strings — version mismatch between gNB and RIC is
   the most common reason xApps subscribe successfully but receive no indications.
6) Check 11 for gNB-side E2 agent log lines — confirm subscribe/indicate/control cycle.

Common failure patterns:
- SCTP ABORT immediately after RIC start = normal FlexRIC teardown after xApp exit.
  This is NOT a failure if the xApp reported 'Test xApp run SUCCESSFULLY'.
- E2AP version mismatch = subscriptions succeed but no RIC Indication messages arrive.
  Fix: rebuild gNB and FlexRIC with matching E2AP_VERSION and KPM_VERSION in CMakeLists.
- 'RAN function not found' in xApp log = the gNB E2 agent does not expose the requested SM.
  Fix: rebuild gNB with --build-e2 and the correct SM enabled.

No configuration changes were made by this script.
EOF

tar czf "${OUT}.tar.gz" -C "$(dirname "$OUT")" "$(basename "$OUT")"
log "Done: ${OUT}.tar.gz"
echo
echo "Created: ${OUT}.tar.gz"
