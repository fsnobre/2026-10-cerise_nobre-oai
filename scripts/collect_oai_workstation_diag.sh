#!/usr/bin/env bash
set -u
set -o pipefail

# collect_oai_workstation_diag.sh
#
# Aggregates gNB + CN + (optionally) FlexRIC diagnostics when running
# on the same workstation or when scripts are co-located.
#
# Usage examples:
#   ./collect_oai_workstation_diag.sh
#   ./collect_oai_workstation_diag.sh --gnb-compose docker-compose-gnb.yaml --cn-compose docker-compose.yaml
#   ./collect_oai_workstation_diag.sh --usrp-iface enp1s0f0 --imsi 001010000000002 --pcap 20
#   ./collect_oai_workstation_diag.sh --with-flexric --flexric-compose docker-compose-ric.yaml
#
# Subscripts called:
#   collect_oai_gnb_diag.sh
#   collect_oai_cn_diag.sh
#   collect_flexric_diag.sh  (only if --with-flexric is passed AND script is found)
#
# No configuration changes are made.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GNB_SCRIPT="${SCRIPT_DIR}/collect_oai_gnb_diag.sh"
CN_SCRIPT="${SCRIPT_DIR}/collect_oai_cn_diag.sh"
FLEXRIC_SCRIPT="${SCRIPT_DIR}/collect_flexric_diag.sh"

GNB_COMPOSE="docker-compose-gnb.yaml"
CN_COMPOSE="docker-compose.yaml"
FLEXRIC_COMPOSE="docker-compose-ric.yaml"
GNB_CONTAINER="oai-gnb"
IMSI=""
SINCE="30m"
PCAP_SECONDS=0
USRP_IFACES=()
OUT_PARENT="."
FULL_LOGS=0
AMF_IP=""
GNB_IP=""
WITH_FLEXRIC=0
WORKDIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gnb-script)      GNB_SCRIPT="$2";       shift 2 ;;
    --cn-script)       CN_SCRIPT="$2";        shift 2 ;;
    --flexric-script)  FLEXRIC_SCRIPT="$2";   shift 2 ;;
    --gnb-compose)     GNB_COMPOSE="$2";      shift 2 ;;
    --cn-compose)      CN_COMPOSE="$2";       shift 2 ;;
    --flexric-compose) FLEXRIC_COMPOSE="$2";  shift 2 ;;
    --gnb-container)   GNB_CONTAINER="$2";    shift 2 ;;
    --imsi|--supi)     IMSI="$2";             shift 2 ;;
    --since)           SINCE="$2";            shift 2 ;;
    --pcap)            PCAP_SECONDS="$2";     shift 2 ;;
    --usrp-iface|--iface) USRP_IFACES+=("$2"); shift 2 ;;
    --amf-ip)          AMF_IP="$2";           shift 2 ;;
    --gnb-ip)          GNB_IP="$2";           shift 2 ;;
    --workdir)         WORKDIR="$2";          shift 2 ;;
    --out-parent)      OUT_PARENT="$2";       shift 2 ;;
    --full-logs)       FULL_LOGS=1;           shift ;;
    --with-flexric)    WITH_FLEXRIC=1;        shift ;;
    -h|--help) sed -n '1,35p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

TS="$(date +%Y%m%d_%H%M%S)"
OUT="${OUT_PARENT%/}/oai_workstation_diag_${TS}"
mkdir -p "$OUT"

log() { echo "[$(date '+%F %T')] $*" | tee -a "$OUT/00_run.log"; }

# FIX: check -f and -x separately for clear error messages
check_script() {
  local label="$1" path="$2" required="$3"
  if [[ ! -f "$path" ]]; then
    if [[ "$required" == "required" ]]; then
      echo "ERROR: $label script not found: $path" >&2
      echo "Place it next to this script or pass --${label,,}-script /path/to/script" >&2
      return 1
    else
      return 2   # not found, but optional
    fi
  fi
  if [[ ! -x "$path" ]]; then
    echo "ERROR: $label script exists but is not executable: $path" >&2
    echo "Run: chmod +x '$path'" >&2
    return 1
  fi
  return 0
}

check_script "GNB"    "$GNB_SCRIPT"     "required" || exit 1
check_script "CN"     "$CN_SCRIPT"      "required" || exit 1

FLEXRIC_AVAILABLE=0
if [[ "$WITH_FLEXRIC" -eq 1 ]]; then
  check_script "FlexRIC" "$FLEXRIC_SCRIPT" "optional"
  rc=$?
  if [[ "$rc" -eq 0 ]]; then
    FLEXRIC_AVAILABLE=1
    log "FlexRIC collector found: $FLEXRIC_SCRIPT"
  elif [[ "$rc" -eq 2 ]]; then
    log "INFO: --with-flexric requested but $FLEXRIC_SCRIPT not found. Skipping FlexRIC collection gracefully."
    echo "FlexRIC collection skipped: script not found at $FLEXRIC_SCRIPT" >> "$OUT/00_run.log"
  else
    log "WARN: FlexRIC script found but not executable. Skipping."
  fi
else
  log "INFO: FlexRIC collection not requested. Pass --with-flexric to include it."
fi

{
  echo "Timestamp=$TS"
  echo "Output directory=$OUT"
  echo "GNB_SCRIPT=$GNB_SCRIPT"
  echo "CN_SCRIPT=$CN_SCRIPT"
  echo "FLEXRIC_SCRIPT=$FLEXRIC_SCRIPT"
  echo "WITH_FLEXRIC=$WITH_FLEXRIC"
  echo "FLEXRIC_AVAILABLE=$FLEXRIC_AVAILABLE"
  echo "GNB_COMPOSE=$GNB_COMPOSE"
  echo "CN_COMPOSE=$CN_COMPOSE"
  echo "GNB_CONTAINER=$GNB_CONTAINER"
  echo "IMSI=${IMSI:-none}"
  echo "SINCE=$SINCE"
  echo "PCAP_SECONDS=$PCAP_SECONDS"
  echo "USRP_IFACES=${USRP_IFACES[*]:-none}"
  echo "AMF_IP=${AMF_IP:-auto}"
  echo "GNB_IP=${GNB_IP:-auto}"
  echo "WORKDIR=${WORKDIR:-(not set)}"
} > "$OUT/00_detected.txt"

log "Output directory: $OUT"

# FIX: track success/failure of each subscript explicitly
GNB_FAILED=0
CN_FAILED=0
FLEXRIC_FAILED=0

# --- Build arg arrays ---
GNB_ARGS=(
  --compose "$GNB_COMPOSE"
  --container "$GNB_CONTAINER"
  --since "$SINCE"
  --out-parent "$OUT"
)
CN_ARGS=(
  --compose "$CN_COMPOSE"
  --since "$SINCE"
  --out-parent "$OUT"
)

[[ "$PCAP_SECONDS" =~ ^[0-9]+$ && "$PCAP_SECONDS" -gt 0 ]] && {
  GNB_ARGS+=(--pcap "$PCAP_SECONDS")
  CN_ARGS+=(--pcap "$PCAP_SECONDS")
}
[[ -n "$IMSI"   ]] && CN_ARGS+=(--imsi "$IMSI")
[[ -n "$AMF_IP" ]] && GNB_ARGS+=(--amf-ip "$AMF_IP")
[[ -n "$GNB_IP" ]] && GNB_ARGS+=(--gnb-ip "$GNB_IP")
[[ -n "$WORKDIR" ]] && CN_ARGS+=(--workdir "$WORKDIR")
[[ "$FULL_LOGS" -eq 1 ]] && { GNB_ARGS+=(--full-logs); CN_ARGS+=(--full-logs); }

for iface in "${USRP_IFACES[@]}"; do
  GNB_ARGS+=(--usrp-iface "$iface")
done

# --- Run subscripts ---
log "Running gNB collector"
"$GNB_SCRIPT" "${GNB_ARGS[@]}" > "$OUT/01_gnb_collector_stdout.txt" 2>&1 || {
  log "WARN: gNB collector exited non-zero. See 01_gnb_collector_stdout.txt."
  GNB_FAILED=1
}

log "Running CN collector"
"$CN_SCRIPT" "${CN_ARGS[@]}" > "$OUT/02_cn_collector_stdout.txt" 2>&1 || {
  log "WARN: CN collector exited non-zero. See 02_cn_collector_stdout.txt."
  CN_FAILED=1
}

if [[ "$FLEXRIC_AVAILABLE" -eq 1 ]]; then
  FLEXRIC_ARGS=(--since "$SINCE" --out-parent "$OUT")
  [[ -f "$FLEXRIC_COMPOSE" ]] && FLEXRIC_ARGS+=(--compose "$FLEXRIC_COMPOSE")
  [[ "$PCAP_SECONDS" =~ ^[0-9]+$ && "$PCAP_SECONDS" -gt 0 ]] && FLEXRIC_ARGS+=(--pcap "$PCAP_SECONDS")
  [[ "$FULL_LOGS" -eq 1 ]] && FLEXRIC_ARGS+=(--full-logs)

  log "Running FlexRIC collector"
  "$FLEXRIC_SCRIPT" "${FLEXRIC_ARGS[@]}" > "$OUT/03_flexric_collector_stdout.txt" 2>&1 || {
    log "WARN: FlexRIC collector exited non-zero. See 03_flexric_collector_stdout.txt."
    FLEXRIC_FAILED=1
  }
else
  echo "FlexRIC collection was not requested or script was not available." \
    > "$OUT/03_flexric_collector_stdout.txt"
fi

# --- Workstation-level snapshot ---
log "Collecting workstation-level snapshot"
{
  echo "===== date ====="
  date -Is
  echo
  echo "===== docker ps ====="
  docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' 2>&1 || true
  echo
  echo "===== docker networks ====="
  docker network ls 2>&1 || true
  echo
  echo "===== ip addr ====="
  ip -br addr
  echo
  echo "===== ip route ====="
  ip route
  echo
  echo "===== listening sockets (OAI/5G ports) ====="
  ss -tunap 2>/dev/null \
    | grep -Ei '38412|2152|8805|8080|9090|36421|36422|sctp|gtp|oai|docker|gnb|amf|smf|upf|nrf|nssf' \
    || true
  echo
  echo "===== recent kernel messages (OAI/radio/network) ====="
  dmesg -T 2>/dev/null \
    | grep -Ei 'oai|gnb|nr-softmodem|sctp|gtp|usrp|uhd|x310|n300|n310|ethernet|docker|veth|bridge|telit|fn990|wwan|mbim|qmi' \
    | tail -500 || true
} > "$OUT/04_workstation_snapshot.txt" 2>&1

# --- Final summary ---
{
  echo "=== Collection summary ==="
  echo "gNB collector:     $( [[ "$GNB_FAILED"     -eq 0 ]] && echo OK || echo FAILED )"
  echo "CN collector:      $( [[ "$CN_FAILED"      -eq 0 ]] && echo OK || echo FAILED )"
  if [[ "$WITH_FLEXRIC" -eq 1 ]]; then
    if [[ "$FLEXRIC_AVAILABLE" -eq 1 ]]; then
      echo "FlexRIC collector: $( [[ "$FLEXRIC_FAILED" -eq 0 ]] && echo OK || echo FAILED )"
    else
      echo "FlexRIC collector: SKIPPED (script not found)"
    fi
  else
    echo "FlexRIC collector: NOT REQUESTED (pass --with-flexric to include)"
  fi
} | tee -a "$OUT/00_run.log"

cat > "$OUT/README_NEXT_STEPS.txt" <<EOF
Aggregated OAI workstation diagnostic bundle — $TS

This bundle contains:
- 01_gnb_collector_stdout.txt  + nested oai_gnb_diag_<ts>/
- 02_cn_collector_stdout.txt   + nested oai_cn_diag_<ts>/
- 03_flexric_collector_stdout.txt + nested flexric_diag_<ts>/ (if collected)
- 04_workstation_snapshot.txt

Suggested analysis order:
1) Check 04_workstation_snapshot.txt for global Docker/network state.
2) Open nested gNB bundle: 00_detected.txt, 10_docker_logs_gnb_recent.txt,
   13_gnb_config_extract.txt, 20_gnb_log_keyword_summary.txt.
3) Open nested CN bundle: 11b_nrf_registration_check.txt, 12_upf_pfcp_sessions.txt,
   10_log_keyword_summary.txt, 14_mysql_queries.txt.
4) If FlexRIC was collected: flexric_diag/06_e2_ric_sockets.txt,
   07_service_models.txt, 09_log_keyword_summary.txt.
5) Correlate timestamps: gNB NG setup → AMF logs → SMF PDU session → UPF PFCP.

No configuration changes were made.
EOF

tar czf "${OUT}.tar.gz" -C "$(dirname "$OUT")" "$(basename "$OUT")"
log "Done: ${OUT}.tar.gz"
echo
echo "Created: ${OUT}.tar.gz"
