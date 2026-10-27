#!/usr/bin/env bash
set -u
set -o pipefail

# collect_oai_cn_diag.sh
#
# Read-only diagnostic collector for an OAI 5G Core docker-compose host.
#
# Usage examples:
#   ./collect_oai_cn_diag.sh
#   ./collect_oai_cn_diag.sh --compose docker-compose.yaml --imsi 001010000000002
#   ./collect_oai_cn_diag.sh --pcap 20 --full-logs --workdir /opt/oai-cn5g
#
# Notes:
# - Does not change Core Network configuration.
# - Optional tcpdump capture requires sudo.

COMPOSE_FILE="docker-compose.yaml"
IMSI=""
SINCE="30m"
PCAP_SECONDS=0
OUT_PARENT="."
INCLUDE_FULL_LOGS=0
WORKDIR=""
MYSQL_CONTAINER_HINT="mysql"
MYSQL_DB="oai_db"
MYSQL_USER_CANDIDATES=("root" "test")
MYSQL_PASS_CANDIDATES=("linux" "test" "root" "")

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose)    COMPOSE_FILE="$2"; shift 2 ;;
    --imsi|--supi) IMSI="$2";        shift 2 ;;
    --since)      SINCE="$2";        shift 2 ;;
    --pcap)       PCAP_SECONDS="$2"; shift 2 ;;
    --out-parent) OUT_PARENT="$2";   shift 2 ;;
    --workdir)    WORKDIR="$2";      shift 2 ;;
    --full-logs)  INCLUDE_FULL_LOGS=1; shift ;;
    --mysql-db)   MYSQL_DB="$2";     shift 2 ;;
    -h|--help) sed -n '1,25p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

TS="$(date +%Y%m%d_%H%M%S)"
OUT="${OUT_PARENT%/}/oai_cn_diag_${TS}"
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
  if docker compose version >/dev/null 2>&1;   then echo "docker compose"
  elif command -v docker-compose >/dev/null 2>&1; then echo "docker-compose"
  else echo ""
  fi
}

DC="$(docker_compose_cmd)"

detect_core_containers() {
  docker ps -a --format '{{.Names}}' 2>/dev/null \
    | grep -Ei '(^|-)oai-|mysql|upf|nrf|amf|smf|nssf|udr|udm|ausf|ext-dn' \
    | sort -u || true
}

# Build IMSI pattern for SQL — use IMSI arg if given, else broad wildcard
imsi_sql_pattern() {
  if [[ -n "$IMSI" ]]; then
    echo "${IMSI}%"
  else
    echo "0010100000000%"   # FIX: still broad for test PLMN 001/01, but documents intent
  fi
}

mapfile -t CONTAINER_LIST < <(detect_core_containers)
CONTAINERS="${CONTAINER_LIST[*]:-}"

{
  echo "Timestamp=$TS"
  echo "Output directory=$OUT"
  echo "Compose file=$COMPOSE_FILE"
  echo "Workdir=${WORKDIR:-(not set, relative paths use CWD)}"
  echo "Docker compose command=${DC:-none}"
  echo "IMSI/SUPI=${IMSI:-none}"
  echo "SINCE=$SINCE"
  echo "Detected containers=${CONTAINERS:-none}"
} > "$OUT/00_detected.txt"

log "Output directory: $OUT"

run_shell "01_system" '
date; uname -a
lsb_release -a 2>/dev/null || cat /etc/os-release
whoami; id; uptime
'

run_shell "02_host_network_forwarding" '
ip -br addr; echo
ip route; echo
ip rule show; echo
sysctl net.ipv4.ip_forward net.ipv4.conf.all.forwarding 2>/dev/null || true
echo
iptables -S 2>/dev/null || true
echo
iptables -t nat -S 2>/dev/null || true
echo
nft list ruleset 2>/dev/null | sed -n "1,300p" || true
echo
ss -tunap 2>/dev/null || netstat -tunap 2>/dev/null || true
'

if [[ -n "$DC" && -f "$COMPOSE_FILE" ]]; then
  run_shell "03_compose_ps"     "$DC -f '$COMPOSE_FILE' ps"
  run_shell "04_compose_config" "$DC -f '$COMPOSE_FILE' config"
else
  echo "Compose file not found: $COMPOSE_FILE" > "$OUT/03_compose_ps.txt"
fi

run_shell "05_docker_ps_core" "docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' \
  | grep -Ei 'name|oai|mysql|upf|nrf|amf|smf|nssf|udr|udm|ausf|ext-dn' || true"

run_shell "06_docker_stats_snapshot" "docker stats --no-stream ${CONTAINERS:-} 2>/dev/null || docker stats --no-stream 2>/dev/null | head -30 || true"

mkdir -p "$OUT/container_inspect" "$OUT/container_logs_recent" "$OUT/container_logs_full" "$OUT/container_exec"

for c in "${CONTAINER_LIST[@]}"; do
  safe="${c//[^A-Za-z0-9_.-]/_}"
  log "Collecting container: $c"

  docker inspect "$c" > "$OUT/container_inspect/${safe}.json" 2>&1 || true
  docker logs "$c" --since "$SINCE" > "$OUT/container_logs_recent/${safe}.log" 2>&1 || true

  if [[ "$INCLUDE_FULL_LOGS" -eq 1 ]]; then
    docker logs "$c" > "$OUT/container_logs_full/${safe}.log" 2>&1 || true
  else
    # FIX: create per-container placeholder so ls of dir is not misleading
    echo "Full logs skipped for $c. Re-run with --full-logs." \
      > "$OUT/container_logs_full/${safe}_skipped.txt"
  fi

  docker exec "$c" sh -lc '
    date; ps aux 2>/dev/null || ps
    echo
    ip -br addr 2>/dev/null || true
    echo
    ip route 2>/dev/null || true
    echo
    ss -tunap 2>/dev/null || netstat -tunap 2>/dev/null || true
    echo
    find /openair-* -maxdepth 3 \( -name "*.yaml" -o -name "*.conf" \) -print 2>/dev/null | sort | head -80
  ' > "$OUT/container_exec/${safe}_runtime.txt" 2>&1 || true
done

run_shell "07_docker_networks" "
docker network ls
echo
for n in \$(docker network ls --format '{{.Name}}' | grep -Ei 'oai|demo|public|access|core|bridge|cn5g'); do
  echo '===== docker network:' \$n '====='
  docker network inspect \"\$n\" || true
done
"

# FIX: use --workdir if provided so relative paths resolve correctly
CONF_SEARCH_DIR="${WORKDIR:-.}"
run_shell "08_core_config_files" "
echo 'Compose file: $COMPOSE_FILE'
[ -f '$COMPOSE_FILE' ] && sed -n '1,300p' '$COMPOSE_FILE' || echo 'Compose file not found at $COMPOSE_FILE'
echo
echo '=== conf files in $CONF_SEARCH_DIR ==='
find '$CONF_SEARCH_DIR/conf' -maxdepth 2 -type f 2>/dev/null | sort || true
echo
for f in '$CONF_SEARCH_DIR'/conf/*.yaml '$CONF_SEARCH_DIR'/conf/*.yml '$CONF_SEARCH_DIR'/conf/*.conf; do
  [ -f \"\$f\" ] || continue
  echo '===== ' \$f ' ====='
  sed -n '1,300p' \"\$f\"
done
echo
echo '=== database SQL references ==='
find '$CONF_SEARCH_DIR/database' -type f 2>/dev/null | xargs grep -niE \
  'AuthenticationSubscription|SessionManagementSubscription|sst|sd|dnn|internet|oai\\.ipv4|IPV4' \
  2>/dev/null | head -80 || true
"

run_shell "09_slice_dnn_summary_grep" "
grep -RniE \
  'plmn|mcc|mnc|tac|nssai|snssai|sst|sd|dnn|internet|oai\\.ipv4|\
upf|smf|nrf|nssf|use_local_subscription_info|pdu_session_type|\
ipv4_subnet|staticIpAddress|001010000000' \
  '$CONF_SEARCH_DIR/conf' '$CONF_SEARCH_DIR/database' \
  '$COMPOSE_FILE' 2>/dev/null || true
"

run_shell "10_log_keyword_summary" "
for f in '$OUT'/container_logs_recent/*.log; do
  [ -f \"\$f\" ] || continue
  echo '===== ' \$(basename \"\$f\") ' ====='
  grep -Ein \
    'error|warn|fail|fatal|reject|exception|assert|segmentation|timeout|\
registration|deregister|authentication|security|nas|5gmm|5gsm|ngap|sctp|\
pdu|session|smf|upf|pfcp|n4|n3|gtp|gtpu|nrf|nssf|slice|snssai|s-nssai|\
dnn|001010000000${IMSI:+|$IMSI}' \
    \"\$f\" || true
  echo
done
"

# FIX: NRF query — use mapfile/while read instead of for-in subshell
run_shell "11_nrf_queries" "
while IFS= read -r nrf; do
  [ -z \"\$nrf\" ] && continue
  ip=\$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}} {{end}}' \"\$nrf\" 2>/dev/null | awk '{print \$1}')
  echo '===== NRF: '\"\$nrf\"' ip='\"\$ip\"' ====='
  [ -z \"\$ip\" ] && continue
  for nf in AMF SMF UPF AUSF UDM UDR NSSF NRF; do
    echo '--- nf-type='\"\$nf\"' ---'
    curl -sS --max-time 3 \"http://\$ip/nnrf-nfm/v1/nf-instances?nf-type=\$nf\" 2>&1 | head -c 8000
    echo
  done
done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'nrf')
"

# FIX: validate that expected NFs are registered
run_shell "11b_nrf_registration_check" "
while IFS= read -r nrf; do
  [ -z \"\$nrf\" ] && continue
  ip=\$(docker inspect -f '{{range.NetworkSettings.Networks}}{{.IPAddress}} {{end}}' \"\$nrf\" 2>/dev/null | awk '{print \$1}')
  [ -z \"\$ip\" ] && continue
  echo '=== NRF '\$nrf' registration summary ==='
  for nf in AMF SMF UPF AUSF UDM UDR; do
    count=\$(curl -sS --max-time 3 \"http://\$ip/nnrf-nfm/v1/nf-instances?nf-type=\$nf\" 2>/dev/null \
             | grep -o '\"nfInstanceId\"' | wc -l || echo 0)
    if [ \"\$count\" -gt 0 ]; then
      echo \"  OK: \$nf registered (\$count instance(s))\"
    else
      echo \"  WARN: \$nf NOT registered with NRF\"
    fi
  done
done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'nrf')
"

# FIX: PFCP session check on UPF
run_shell "12_upf_pfcp_sessions" "
while IFS= read -r upf; do
  [ -z \"\$upf\" ] && continue
  echo '=== UPF container: '\$upf' ==='
  docker exec \"\$upf\" sh -lc '
    echo \"--- Active PFCP sessions ---\"
    # OAI UPF-VPP: check via vppctl if available
    vppctl show upf session 2>/dev/null || true
    # Generic: check listening sockets
    ss -unap 2>/dev/null | grep -E \"8805|pfcp\" || true
    # GTP tunnel state
    ip xfrm state 2>/dev/null | head -30 || true
    # GTP-U tunnel interfaces
    ip link show type gtp 2>/dev/null || true
    # Recent log lines with TEID/PFCP
    dmesg -T 2>/dev/null | grep -Ei \"gtp|teid|pfcp\" | tail -50 || true
  ' 2>&1 || echo \"Could not exec into \$upf\"
  echo
done < <(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'upf')
"

# MySQL queries
MYSQL_CONTAINER="$(docker ps --format '{{.Names}}' 2>/dev/null \
  | grep -E "^${MYSQL_CONTAINER_HINT}$|mysql" | head -1 || true)"
{
  echo "MYSQL_CONTAINER=${MYSQL_CONTAINER:-none}"
} > "$OUT/13_mysql_detected.txt"

SQL_PATTERN="$(imsi_sql_pattern)"

if [[ -n "$MYSQL_CONTAINER" ]]; then
  {
    echo "MySQL container: $MYSQL_CONTAINER"
    echo "IMSI/SUPI pattern: $SQL_PATTERN"
    echo
  } > "$OUT/14_mysql_queries.txt"

  success=0
  for u in "${MYSQL_USER_CANDIDATES[@]}"; do
    for p in "${MYSQL_PASS_CANDIDATES[@]}"; do
      echo "===== Trying user=$u pass=${p:-<empty>} =====" >> "$OUT/14_mysql_queries.txt"
      if [[ -n "$p" ]]; then
        MYSQL_CMD="mysql -u'$u' -p'$p' -D '$MYSQL_DB' -e"
      else
        MYSQL_CMD="mysql -u'$u' -D '$MYSQL_DB' -e"
      fi
      # FIX: use parameterised pattern instead of hardcoded PLMN prefix
      docker exec "$MYSQL_CONTAINER" sh -lc "$MYSQL_CMD \"
        SELECT 'AuthenticationSubscription' AS tbl, ueid, authenticationMethod
          FROM AuthenticationSubscription WHERE ueid LIKE '$SQL_PATTERN' LIMIT 20;
        SELECT 'AccessAndMobilitySubscriptionData' AS tbl, ueid, servingPlmnid, nssai
          FROM AccessAndMobilitySubscriptionData WHERE ueid LIKE '$SQL_PATTERN' LIMIT 20;
        SELECT 'SessionManagementSubscriptionData' AS tbl, ueid, servingPlmnid, singleNssai, dnnConfigurations
          FROM SessionManagementSubscriptionData WHERE ueid LIKE '$SQL_PATTERN' LIMIT 20;
      \"" >> "$OUT/14_mysql_queries.txt" 2>&1 && success=1 && break 2
    done
  done
  [[ "$success" -eq 1 ]] || echo "No MySQL credential candidate succeeded." >> "$OUT/14_mysql_queries.txt"
else
  echo "No MySQL container detected." > "$OUT/14_mysql_queries.txt"
fi

if [[ "$PCAP_SECONDS" =~ ^[0-9]+$ ]] && [[ "$PCAP_SECONDS" -gt 0 ]]; then
  if have_cmd tcpdump; then
    log "Running CN tcpdump for $PCAP_SECONDS seconds"
    run_shell "15_tcpdump_control_plane_text" \
      "sudo timeout '$PCAP_SECONDS' tcpdump -ni any 'sctp or port 38412 or port 80 or port 8080 or port 8805' -vv"
    sudo timeout "$PCAP_SECONDS" tcpdump -ni any \
      "sctp or port 38412 or port 80 or port 8080 or port 8805" \
      -w "$OUT/cn_control_plane_${PCAP_SECONDS}s.pcap" > "$OUT/15_tcpdump_cp_pcap.txt" 2>&1 || true

    run_shell "16_tcpdump_gtpu_text" \
      "sudo timeout '$PCAP_SECONDS' tcpdump -ni any 'udp port 2152' -vv"
    sudo timeout "$PCAP_SECONDS" tcpdump -ni any "udp port 2152" \
      -w "$OUT/cn_gtpu_${PCAP_SECONDS}s.pcap" > "$OUT/16_tcpdump_gtpu_pcap.txt" 2>&1 || true
  else
    echo "tcpdump not installed." > "$OUT/15_tcpdump_control_plane_text.txt"
  fi
fi

cat > "$OUT/README_NEXT_STEPS.txt" <<EOF
OAI CN diagnostic bundle — $TS

Key files:
- 00_detected.txt
- 03_compose_ps.txt / 04_compose_config.txt
- container_logs_recent/
- 10_log_keyword_summary.txt
- 11_nrf_queries.txt / 11b_nrf_registration_check.txt
- 12_upf_pfcp_sessions.txt
- 14_mysql_queries.txt
- 02_host_network_forwarding.txt

Analysis order:
1) NRF registration: 11b — all expected NFs must show OK.
2) AMF/gNB NG setup and UE registration: oai-amf logs.
3) SMF PDU session and DNN/S-NSSAI: oai-smf-* logs.
4) UPF PFCP sessions: 12_upf_pfcp_sessions.txt and oai-upf-* logs.
5) Subscriber DB: 14_mysql_queries.txt.
6) Host forwarding/NAT: 02_host_network_forwarding.txt.

No configuration changes were made.
EOF

tar czf "${OUT}.tar.gz" -C "$(dirname "$OUT")" "$(basename "$OUT")"
log "Done: ${OUT}.tar.gz"
echo
echo "Created: ${OUT}.tar.gz"
