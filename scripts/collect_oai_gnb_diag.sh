#!/usr/bin/env bash
set -u
set -o pipefail

# collect_oai_gnb_diag.sh
#
# Read-only diagnostic collector for an OAI gNB host/container.
#
# Usage examples:
#   ./collect_oai_gnb_diag.sh
#   ./collect_oai_gnb_diag.sh --compose docker-compose-gnb.yaml --container oai-gnb
#   ./collect_oai_gnb_diag.sh --usrp-iface enp1s0f0 --pcap 20
#   ./collect_oai_gnb_diag.sh --amf-ip 192.168.70.132 --gnb-ip 172.16.2.56
#
# Notes:
# - Does not change gNB/Core/USRP/network configuration.
# - Optional tcpdump capture requires sudo.

COMPOSE_FILE="docker-compose-gnb.yaml"
CONTAINER_HINT="oai-gnb"
GNB_CONF=""
USRP_IFACES=()
PCAP_SECONDS=0
AMF_IP=""
GNB_IP=""
SINCE="30m"
OUT_PARENT="."
INCLUDE_FULL_LOGS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose)        COMPOSE_FILE="$2";       shift 2 ;;
    --container)      CONTAINER_HINT="$2";     shift 2 ;;
    --gnb-conf)       GNB_CONF="$2";           shift 2 ;;
    --usrp-iface|--iface) USRP_IFACES+=("$2"); shift 2 ;;
    --pcap)           PCAP_SECONDS="$2";       shift 2 ;;
    --amf-ip)         AMF_IP="$2";             shift 2 ;;
    --gnb-ip)         GNB_IP="$2";             shift 2 ;;
    --since)          SINCE="$2";              shift 2 ;;
    --out-parent)     OUT_PARENT="$2";         shift 2 ;;
    --full-logs)      INCLUDE_FULL_LOGS=1;     shift ;;
    -h|--help) sed -n '1,25p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

TS="$(date +%Y%m%d_%H%M%S)"
OUT="${OUT_PARENT%/}/oai_gnb_diag_${TS}"
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

# FIX: stricter container detection — prefer exact match first
detect_container() {
  local hint="$1"
  local found=""
  # 1. exact match
  found="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "^${hint}$" | head -1 || true)"
  # 2. prefix match
  [[ -z "$found" ]] && found="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E "^${hint}" | head -1 || true)"
  # 3. broad fallback (only well-known OAI names)
  [[ -z "$found" ]] && found="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -E '^oai-gnb$|^oai-gnb-' | head -1 || true)"
  [[ -z "$found" ]] && found="$(docker ps --format '{{.Names}}' 2>/dev/null | grep -Ei 'nr-softmodem' | head -1 || true)"
  echo "$found"
}

# FIX: detect both .conf and .yaml config paths from compose file
detect_gnb_conf_from_compose() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  awk '
    /\/opt\/oai-gnb\/etc\/(gnb\.conf|gnb\.yaml)/ {
      line=$0
      gsub(/^[[:space:]]*-[[:space:]]*/, "", line)
      split(line, a, ":")
      print a[1]
      exit
    }
  ' "$f" | sed 's#^\./##'
}

GNB_CONTAINER="$(detect_container "$CONTAINER_HINT")"
if [[ -z "$GNB_CONF" ]]; then
  GNB_CONF="$(detect_gnb_conf_from_compose "$COMPOSE_FILE" || true)"
fi

{
  echo "Timestamp=$TS"
  echo "Output directory=$OUT"
  echo "Compose file=$COMPOSE_FILE"
  echo "Docker compose command=${DC:-none}"
  echo "Container hint=$CONTAINER_HINT"
  echo "Detected gNB container=${GNB_CONTAINER:-none}"
  echo "Detected config=${GNB_CONF:-none}"
  echo "USRP interfaces=${USRP_IFACES[*]:-none}"
  echo "PCAP_SECONDS=$PCAP_SECONDS"
  echo "AMF_IP=${AMF_IP:-auto}"
  echo "GNB_IP=${GNB_IP:-auto}"
  echo "SINCE=$SINCE"
} > "$OUT/00_detected.txt"

log "Output directory: $OUT"

run_shell "01_system" '
date; uname -a
lsb_release -a 2>/dev/null || cat /etc/os-release
whoami; id; uptime
'

run_shell "02_realtime_cpu_status" '
echo "cmdline:"
cat /proc/cmdline
echo
echo "realtime kernel:"
cat /sys/kernel/realtime 2>/dev/null || echo "not set"
echo
echo "SMT:"
cat /sys/devices/system/cpu/smt/active 2>/dev/null || echo "unknown"
echo
echo "Governors:"
for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
  [ -e "$f" ] || continue
  echo "$(basename $(dirname $(dirname $f))): $(cat "$f")"
done
echo
lscpu
echo
cpupower frequency-info 2>/dev/null || true
cpupower idle-info 2>/dev/null || true
'

run_shell "03_kernel_network_tuning" '
sysctl net.core.wmem_max net.core.rmem_max net.core.wmem_default net.core.rmem_default 2>/dev/null || true
sysctl net.ipv4.ip_forward net.ipv4.conf.all.forwarding 2>/dev/null || true
ulimit -a
echo
echo "rtprio/memlock limits:"
grep -R "rtprio\|memlock\|usrp" /etc/security/limits.conf /etc/security/limits.d 2>/dev/null || true
'

if [[ -n "$DC" && -f "$COMPOSE_FILE" ]]; then
  run_shell "04_compose_ps"     "$DC -f '$COMPOSE_FILE' ps"
  run_shell "05_compose_config" "$DC -f '$COMPOSE_FILE' config"
else
  echo "Compose file not found: $COMPOSE_FILE" > "$OUT/04_compose_ps.txt"
fi

run_shell "06_docker_ps_gnb" "docker ps -a --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}' | grep -Ei 'name|gnb|ran|softmodem|flexric|e2|ric' || true"

if [[ -n "$GNB_CONTAINER" ]]; then
  run_shell "07_docker_inspect_gnb"      "docker inspect '$GNB_CONTAINER'"
  run_shell "08_docker_top_gnb"          "docker top '$GNB_CONTAINER' aux || true"
  run_shell "09_docker_stats_gnb"        "docker stats '$GNB_CONTAINER' --no-stream || true"
  run_shell "10_docker_logs_gnb_recent"  "docker logs '$GNB_CONTAINER' --since '$SINCE'"
  if [[ "$INCLUDE_FULL_LOGS" -eq 1 ]]; then
    run_shell "11_docker_logs_gnb_full"  "docker logs '$GNB_CONTAINER'"
  else
    echo "Full logs skipped. Re-run with --full-logs." > "$OUT/11_docker_logs_gnb_full.txt"
  fi

  # FIX: try both .conf and .yaml inside container
  run_shell "12_docker_exec_gnb_runtime" "
    docker exec '$GNB_CONTAINER' bash -lc '
      date; ps aux
      echo
      ip -br addr
      echo
      ip route
      echo
      ss -tunap 2>/dev/null || netstat -tunap 2>/dev/null || true
      echo
      ls -l /opt/oai-gnb/etc/ 2>/dev/null || true
      echo \"=== gnb.conf ===\"
      sed -n \"1,300p\" /opt/oai-gnb/etc/gnb.conf 2>/dev/null || echo \"not found\"
      echo \"=== gnb.yaml ===\"
      sed -n \"1,300p\" /opt/oai-gnb/etc/gnb.yaml 2>/dev/null || echo \"not found\"
    '"
else
  echo "No running gNB container detected." > "$OUT/07_docker_inspect_gnb.txt"
fi

if [[ -n "$GNB_CONF" && -f "$GNB_CONF" ]]; then
  mkdir -p "$OUT/config"
  cp -a "$GNB_CONF" "$OUT/config/" 2>/dev/null || true

  # FIX: grep patterns work for both .conf (param = value) and .yaml (param: value)
  run_shell "13_gnb_config_extract" "
    echo 'Config file: $GNB_CONF'
    echo
    grep -nE \
      'gNB_ID|gNB_name|tracking_area_code|plmn_list|mcc|mnc|sst|sd|snssai|\
amf_ip_address|GNB_IPV4_ADDRESS|GNB_INTERFACE_NAME|NETWORK_INTERFACES|\
absoluteFrequencySSB|dl_absoluteFrequencyPointA|dl_carrierBandwidth|ul_carrierBandwidth|\
locationAndBandwidth|ra_ResponseWindow|ssb_PositionsInBurst|\
physCellId|ciphering|integrity|sdr_addrs|local_rf|nb_tx|nb_rx|\
min_rxtxtime|parallel_config|pusch_proc_threads|ulsch_max_frame_inactivity|\
att_tx|att_rx|max_rxgain|clock_source|time_source|SliceConf' \
      '$GNB_CONF' || true
  "

  # Extract AMF/GNB IPs from config if not passed as args
  if [[ -z "$AMF_IP" ]]; then
    AMF_IP="$(grep -E 'ipv4|amf_ip_address' "$GNB_CONF" -A3 2>/dev/null \
              | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)"
  fi
  if [[ -z "$GNB_IP" ]]; then
    GNB_IP="$(grep -E 'GNB_IPV4_ADDRESS_FOR_NG_AMF|GNB_IPV4_ADDRESS_FOR_NGU' "$GNB_CONF" 2>/dev/null \
              | grep -Eo '([0-9]{1,3}\.){3}[0-9]{1,3}' | head -1 || true)"
  fi
else
  echo "gNB config not detected: ${GNB_CONF:-none}" > "$OUT/13_gnb_config_extract.txt"
fi

{
  echo "AMF_IP=${AMF_IP:-none}"
  echo "GNB_IP=${GNB_IP:-none}"
} >> "$OUT/00_detected.txt"

run_shell "14_host_network" "
ip -br addr; echo
ip route; echo
ip rule show; echo
ss -tunap 2>/dev/null || netstat -tunap 2>/dev/null || true
echo
ip route get ${AMF_IP:-8.8.8.8} 2>/dev/null || true
echo
ip route get ${GNB_IP:-8.8.8.8} 2>/dev/null || true
"

run_shell "15_sctp_gtp_status" "
lsmod | grep -E '^sctp|^udp_tunnel|^gtp' || true
echo
ss -nape | grep -Ei 'sctp|38412|2152|36421|36422' || true
echo
dmesg -T | grep -Ei 'sctp|ngap|gtp|oai|gnb|nr-softmodem' | tail -300 || true
"

run_shell "16_docker_networks" "
docker network ls
echo
for n in \$(docker network ls --format '{{.Name}}' | grep -Ei 'oai|demo|ran|gnb|public|access|core|bridge'); do
  echo '===== network:' \$n '====='
  docker network inspect \"\$n\" || true
done
"

run_shell "17_usrp_uhd_detection" "
uhd_find_devices 2>&1 || true
echo
timeout 15 uhd_usrp_probe 2>&1 | head -80 || true
"

run_shell "18_usb_pci_radio_devices" "
lsusb
echo
lspci -nn 2>/dev/null | grep -Ei 'ethernet|network|xilinx|ettus|ni|fpga|intel|mellanox|broadcom|realtek' || true
echo
dmesg -T | grep -Ei 'uhd|usrp|x3|x300|x310|n3|n300|n310|b210|ettus|ni|fpga|10g|sfp|ethernet|ixgbe|i40e|ice|mlx|overrun|underrun|late' | tail -500 || true
"

if [[ "${#USRP_IFACES[@]}" -eq 0 ]]; then
  run_shell "19_candidate_usrp_ifaces" "
    for p in /sys/class/net/*; do
      i=\$(basename \"\$p\")
      [ \"\$i\" = lo ] && continue
      speed=\$(cat \"\$p/speed\" 2>/dev/null || echo unknown)
      mtu=\$(cat \"\$p/mtu\" 2>/dev/null || echo unknown)
      state=\$(cat \"\$p/operstate\" 2>/dev/null || echo unknown)
      mac=\$(cat \"\$p/address\" 2>/dev/null || echo unknown)
      printf '%-20s speed=%-8s mtu=%-8s state=%-12s mac=%s\n' \"\$i\" \"\$speed\" \"\$mtu\" \"\$state\" \"\$mac\"
    done
  "
else
  for iface in "${USRP_IFACES[@]}"; do
    safe="${iface//[^A-Za-z0-9_.-]/_}"
    run_shell "19_iface_${safe}_details" "
      ip -d link show '$iface' 2>&1 || true; echo
      ip -s link show '$iface' 2>&1 || true; echo
      ethtool -i '$iface' 2>&1 || true; echo
      ethtool -g '$iface' 2>&1 || true; echo
      ethtool -k '$iface' 2>&1 || true; echo
      ethtool -S '$iface' 2>&1 || true; echo
      nmcli dev show '$iface' 2>/dev/null || true
    "
  done
fi

# FIX: grep from already-collected log file instead of re-running docker logs
run_shell "20_gnb_log_keyword_summary" "
  if [ -f '$OUT/10_docker_logs_gnb_recent.txt' ]; then
    grep -Ein \
      'error|warn|fail|fatal|assert|segmentation|sctp|ng setup|ngap|amf|\
registration|rrc|security|nas|pdu|gtp|gtpu|late|underflow|overflow|overrun|\
sync|random access|rach|msg3|rlf|reconfiguration|snssai|slice|dnn|\
x310|n300|n310|usrp|uhd|timeout|realtime|real-time' \
      '$OUT/10_docker_logs_gnb_recent.txt' || true
  else
    echo 'Recent log file not found — was gNB container detected?'
  fi
"

if [[ "$PCAP_SECONDS" =~ ^[0-9]+$ ]] && [[ "$PCAP_SECONDS" -gt 0 ]]; then
  if have_cmd tcpdump; then
    log "Running gNB-side tcpdump for $PCAP_SECONDS seconds"
    run_shell "21_tcpdump_n2_sctp_text" "sudo timeout '$PCAP_SECONDS' tcpdump -ni any 'sctp or port 38412' -vv"
    sudo timeout "$PCAP_SECONDS" tcpdump -ni any "sctp or port 38412" \
      -w "$OUT/n2_sctp_${PCAP_SECONDS}s.pcap" > "$OUT/21_tcpdump_n2_sctp_pcap.txt" 2>&1 || true

    # FIX: exclude loopback to avoid Docker bridge noise on N3 capture
    run_shell "22_tcpdump_n3_gtpu_text" "sudo timeout '$PCAP_SECONDS' tcpdump -ni any 'udp port 2152 and not host 127.0.0.1' -vv"
    sudo timeout "$PCAP_SECONDS" tcpdump -ni any "udp port 2152 and not host 127.0.0.1" \
      -w "$OUT/n3_gtpu_${PCAP_SECONDS}s.pcap" > "$OUT/22_tcpdump_n3_gtpu_pcap.txt" 2>&1 || true
  else
    echo "tcpdump not installed." > "$OUT/21_tcpdump_n2_sctp_text.txt"
  fi
fi

cat > "$OUT/README_NEXT_STEPS.txt" <<EOF
gNB diagnostic bundle — $TS

Key files:
- 00_detected.txt
- 10_docker_logs_gnb_recent.txt
- 13_gnb_config_extract.txt
- 14_host_network.txt
- 15_sctp_gtp_status.txt
- 17_usrp_uhd_detection.txt
- 20_gnb_log_keyword_summary.txt

Analysis order:
1) NG setup: grep 10/20 for NG SETUP, SCTP, AMF, NGAP.
2) RACH/Msg3: grep for random access, Msg3, RACH, RRCSetup.
3) USRP timing: grep for UHD, late, underflow, overflow.
4) Confirm gNB config and AMF IP in 13_gnb_config_extract.txt.
5) For FlexRIC/E2: run collect_flexric_diag.sh on WS-FlexRIC.

No configuration changes were made.
EOF

tar czf "${OUT}.tar.gz" -C "$(dirname "$OUT")" "$(basename "$OUT")"
log "Done: ${OUT}.tar.gz"
echo
echo "Created: ${OUT}.tar.gz"
