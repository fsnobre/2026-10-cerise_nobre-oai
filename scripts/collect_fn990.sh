#!/usr/bin/env bash
set -u
set -o pipefail

# collect_fn990.sh
#
# Unified diagnostic collector for the Telit FN990 M.2 modem.
# Output: a single Markdown file with a quick-summary section followed
# by verbatim diagnostic sections.
#
# AT command collection — auto-detects best available method:
#   1. mmcli  (preferred — no serial port needed, MM handles locking)
#   2. expect + picocom on detected /dev/ttyUSBx  (fallback)
#   3. Neither available — all other sections still run, AT skipped
#
# Modes:
#   --mode full         (default) Everything: AT, interface, counters, connectivity
#   --mode at-only      Fast path: USB + AT commands only (~30s)
#   --mode connectivity Skip AT; run interface counters and connectivity tests
#
# Usage:
#   ./collect_fn990.sh
#   ./collect_fn990.sh --mode at-only
#   ./collect_fn990.sh --mode full --pcap 15
#   ./collect_fn990.sh --iface wwp0s21f0u2i12 --at /dev/ttyUSB2
#   ./collect_fn990.sh --mode full --no-ping   # skip long ping tests

MODE="full"
IFACE=""
ATPORT=""
PCAP_SECONDS=0
PING_COUNT=10
DNS1="1.1.1.1"
DNS2="8.8.8.8"
TEST_HOST="www.google.com"
AT_DELAY="0.5"
NO_PING=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)        MODE="$2";         shift 2 ;;
    --iface)       IFACE="$2";        shift 2 ;;
    --at)          ATPORT="$2";       shift 2 ;;
    --pcap)        PCAP_SECONDS="$2"; shift 2 ;;
    --ping-count)  PING_COUNT="$2";   shift 2 ;;
    --dns1)        DNS1="$2";         shift 2 ;;
    --dns2)        DNS2="$2";         shift 2 ;;
    --host)        TEST_HOST="$2";    shift 2 ;;
    --at-delay)    AT_DELAY="$2";     shift 2 ;;
    --no-ping)     NO_PING=1;         shift ;;
    -h|--help)     sed -n '1,40p' "$0"; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done

case "$MODE" in
  full|at-only|connectivity) ;;
  *) echo "ERROR: unknown --mode '$MODE'. Valid: full, at-only, connectivity" >&2; exit 1 ;;
esac

# ---------------------------------------------------------------------------
# Output: single Markdown file
# ---------------------------------------------------------------------------
TS="$(date +%Y%m%d_%H%M%S)"
OUTDIR="fn990_diag_${TS}"
OUTMD="${OUTDIR}/fn990_report_${TS}.md"
mkdir -p "$OUTDIR"

# Temp dir for raw captured output
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

have_cmd() { command -v "$1" >/dev/null 2>&1; }
log()      { echo "[$(date '+%F %T')] $*" | tee -a "$OUTDIR/run.log"; }

# ---------------------------------------------------------------------------
# Auto-detect FN990 interface
# ---------------------------------------------------------------------------
detect_fn990_iface() {
  local iface
  for iface in $(ip -o -4 addr show 2>/dev/null | awk '{print $2}' | sort -u); do
    [[ "$iface" == wwan* || "$iface" == wwp* ]] && { echo "$iface"; return; }
  done
  for iface in $(ip link show 2>/dev/null | awk -F': ' '/^[0-9]/{print $2}'); do
    [[ "$iface" == wwan* || "$iface" == wwp* ]] && { echo "$iface"; return; }
  done
  echo ""
}

if [[ -z "$IFACE" ]]; then
  IFACE="$(detect_fn990_iface)"
  [[ -z "$IFACE" ]] && { log "WARN: no wwan/wwp interface found. Pass --iface <name>."; IFACE="wwan0"; }
fi

# ---------------------------------------------------------------------------
# Auto-detect modem and AT method
# ---------------------------------------------------------------------------
MODEM=""
AT_METHOD="none"
AT_DETECTED_PORT=""

detect_at_method() {
  # Method 1: mmcli
  if have_cmd mmcli; then
    local m
    m="$(mmcli -L 2>/dev/null | awk -F/ '/Modem/ {print $6}' | awk '{print $1}' | tail -1 || true)"
    if [[ -n "$m" ]]; then
      MODEM="$m"; AT_METHOD="mmcli"
      log "AT method: mmcli (modem $MODEM)"; return
    fi
    log "mmcli present but no modem detected."
  else
    log "mmcli not installed."
  fi

  # Method 2: expect + picocom
  if have_cmd expect && have_cmd picocom; then
    local port
    for port in /dev/ttyUSB*; do
      [[ -e "$port" ]] || continue
      # Quick probe: send AT, expect OK within 2s
      local resp
      resp="$(expect -c "
        log_user 0
        spawn picocom -b 115200 --imap lfcrnl \"$port\"
        after 500
        send \"AT\r\"
        expect {
          \"OK\" { puts \"OK\"; exit 0 }
          timeout { exit 1 }
        }
      " 2>/dev/null || true)"
      if [[ "$resp" == "OK" ]]; then
        AT_METHOD="picocom"; AT_DETECTED_PORT="$port"
        log "AT method: picocom on $port"; return
      fi
    done
    log "expect+picocom present but no responsive ttyUSB port found."
  else
    have_cmd expect  || log "expect not installed."
    have_cmd picocom || log "picocom not installed."
  fi

  log "No AT method available. AT section will be skipped."
  AT_METHOD="none"
}

detect_at_method

# Override with explicit --at flag
if [[ -n "$ATPORT" ]]; then
  if have_cmd expect && have_cmd picocom; then
    AT_METHOD="picocom"; AT_DETECTED_PORT="$ATPORT"
    log "Using explicit AT port: $ATPORT"
  else
    log "WARN: --at provided but expect/picocom not available."
  fi
fi

EFFECTIVE_ATPORT="${ATPORT:-$AT_DETECTED_PORT}"

# ---------------------------------------------------------------------------
# Network state
# ---------------------------------------------------------------------------
UE_IP="$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1 || true)"
UE_CIDR="$(ip -4 -o addr show dev "$IFACE" 2>/dev/null | awk '{print $4}' | head -1 || true)"
GATEWAY=""
if [[ -n "$UE_IP" ]]; then
  GATEWAY="$(ip route show dev "$IFACE" 2>/dev/null | awk '$1=="default"{print $3;exit}')"
  [[ -z "$GATEWAY" ]] && GATEWAY="$(ip route show dev "$IFACE" 2>/dev/null | awk '/via/{print $3;exit}')"
fi

log "Mode=$MODE | Iface=$IFACE | IP=${UE_IP:-none} | AT=$AT_METHOD | Modem=${MODEM:-none}"

# ===========================================================================
# DATA COLLECTION FUNCTIONS
# Each writes raw output to $TMP/<name>.txt
# ===========================================================================

collect_usb() {
  log "Collecting USB info"
  {
    echo "=== lsusb ==="
    lsusb 2>/dev/null || echo "lsusb not available"
    echo
    echo "=== lsusb -t ==="
    lsusb -t 2>/dev/null || true
    echo
    echo "=== Telit device sysfs ==="
    for d in /sys/bus/usb/devices/*; do
      grep -q '1bc7' "$d/idVendor" 2>/dev/null || continue
      echo "Device: $d"
      for f in product idProduct speed power/control power/autosuspend; do
        [[ -r "$d/$f" ]] && printf "  %-25s %s\n" "$f:" "$(cat "$d/$f")"
      done
    done
    echo
    echo "=== Interface type (sysfs) ==="
    for iface in $(ip link show 2>/dev/null | awk -F': ' '/^[0-9]/{print $2}' | grep -E '^wwan|^wwp'); do
      local type_val mtu state
      type_val=$(cat "/sys/class/net/$iface/type" 2>/dev/null || echo unknown)
      mtu=$(cat "/sys/class/net/$iface/mtu" 2>/dev/null || echo unknown)
      state=$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo unknown)
      echo "$iface: type=$type_val mtu=$mtu state=$state"
      case "$type_val" in
        530) echo "  → MBIM raw-IP mode (correct for FN990 MBIM)" ;;
        1)   echo "  → Ethernet/QMI mode" ;;
      esac
      echo -n "  qmi/raw_ip: "; cat "/sys/class/net/$iface/qmi/raw_ip" 2>/dev/null || echo "n/a"
    done
    echo
    echo "=== cdc-wdm devices ==="
    ls -l /dev/cdc-wdm* 2>/dev/null || echo "No /dev/cdc-wdm* devices"
    echo
    echo "=== ttyUSB devices ==="
    ls -l /dev/ttyUSB* 2>/dev/null || echo "No /dev/ttyUSB* devices"
    echo
    echo "=== serial/by-id ==="
    ls -l /dev/serial/by-id/ 2>/dev/null || echo "No serial/by-id entries"
  } > "$TMP/usb.txt" 2>&1
}

collect_kernel() {
  log "Collecting kernel messages"
  dmesg -T 2>/dev/null | grep -Ei \
    'telit|fn990|wwan|mbim|qmi|cdc|usb|qcserial|option|urb|disconnect|reset|1bc7' \
    | tail -300 > "$TMP/kernel.txt" 2>&1 || true
}

collect_mmcli() {
  [[ -z "$MODEM" ]] && { echo "No modem." > "$TMP/mmcli.txt"; return; }
  log "Collecting mmcli state"
  {
    echo "=== mmcli -L ==="
    mmcli -L 2>&1 || true
    echo
    echo "=== mmcli -m $MODEM ==="
    mmcli -m "$MODEM" 2>&1 || true
    echo
    echo "=== signal setup + get ==="
    if [[ "${EUID:-1000}" -eq 0 ]]; then
      mmcli -m "$MODEM" --signal-setup=5 2>&1 || true
    else
      sudo -n mmcli -m "$MODEM" --signal-setup=5 2>/dev/null || \
        echo "(signal-setup requires root — skipped)"
    fi
    mmcli -m "$MODEM" --signal-get 2>&1 || true
    echo
    echo "=== bearers ==="
    local bearers
    bearers="$(mmcli -m "$MODEM" 2>/dev/null \
      | awk -F/ '/Bearer/{print $NF}' | awk '{print $1}' | tr '\n' ' ' || true)"
    echo "Detected bearers: ${bearers:-none}"
    for b in $bearers; do
      echo "--- Bearer $b ---"
      mmcli -b "$b" 2>&1 || true
    done
  } > "$TMP/mmcli.txt" 2>&1
}

# ---------------------------------------------------------------------------
# AT command list — used by both mmcli and picocom methods
# ---------------------------------------------------------------------------
AT_CMDS=(
  'AT'
  'ATI'
  'AT+CGMI'
  'AT+CGMM'
  'AT+CGMR'
  'AT+CGSN'
  'AT+CPIN?'
  'AT+CIMI'
  'AT+COPS?'
  'AT+CEREG?'
  'AT+CEREG=3'
  'AT+CEREG?'
  'AT+C5GREG?'
  'AT+C5GREG=3'
  'AT+C5GREG?'
  'AT+CGATT?'
  'AT+CGACT?'
  'AT+CGDCONT?'
  'AT+CGPADDR'
  'AT+CGCONTRDP'
  'AT+CSQ'
  'AT+CESQ'
  'AT#SERVINFO'
  'AT#RFSTS'
  'AT#MONI'
  'AT#MONI=7'
  'AT#CAINFO'
  'AT#BND?'
  'AT#WS46?'
  'AT#USBCFG?'
)

collect_at_mmcli() {
  log "Collecting AT commands via mmcli"
  {
    echo "Method: mmcli"
    echo "Modem: $MODEM"
    echo "Date: $(date -Is)"
    echo "NOTE: AT+CEREG=3 and AT+C5GREG=3 set URC mode (side effect)."
    echo
    for cmd in "${AT_CMDS[@]}"; do
      echo "===== $cmd ====="
      mmcli -m "$MODEM" --command="$cmd" --timeout=10 2>&1 || true
      echo
      sleep "$AT_DELAY"
    done
  } > "$TMP/at.txt" 2>&1
}

collect_at_picocom() {
  local port="$1"
  log "Collecting AT commands via picocom on $port"

  # Release ModemManager's lock on the port before using it directly
  if have_cmd mmcli && [[ -n "$MODEM" ]]; then
    log "Suspending ModemManager for AT collection"
    sudo mmcli -G ERR 2>/dev/null || true   # silence MM logging
    sudo mmcli -m "$MODEM" --command='AT' --timeout=1 >/dev/null 2>&1 || true
  fi

  # Reset port state
  sudo stty -F "$port" 115200 cs8 -cstopb -parenb -echo raw 2>/dev/null || true

  {
    echo "Method: picocom"
    echo "Port: $port"
    echo "Date: $(date -Is)"
    echo "NOTE: AT+CEREG=3 and AT+C5GREG=3 set URC mode (side effect)."
    echo

    # Per-command timeouts — some Telit commands take longer
    declare -A CMD_TIMEOUT=(
      ['AT#MONI=7']="5"
      ['AT#RFSTS']="5"
      ['AT#SERVINFO']="5"
      ['AT#CAINFO']="5"
      ['AT+COPS?']="10"
    )

    for cmd in "${AT_CMDS[@]}"; do
      echo "===== $cmd ====="
      local timeout="${CMD_TIMEOUT[$cmd]:-3}"
      # Use expect to drive picocom: spawn, send command, wait for OK/ERROR/+CME
      expect -c "
        log_user 1
        set timeout $timeout
        spawn picocom -b 115200 --imap lfcrnl --omap delbs \"$port\"
        after 300
        send \"ATE0\r\"
        expect -re {OK|ERROR} {}
        after 200
        send \"${cmd}\r\"
        expect -re {OK|ERROR|\\+CME ERROR|\\+CMS ERROR|NO CARRIER} {
          after 100
        }
        close
        wait
      " 2>/dev/null | grep -v "^$\|picocom v\|Terminal ready\|Terminating\|Thanks\|port is\|Escape\|Type" || true
      echo
      sleep 0.3
    done
  } > "$TMP/at.txt" 2>&1

  # Restore ModemManager logging
  if have_cmd mmcli; then
    sudo mmcli -G INFO 2>/dev/null || true
  fi
}

collect_network() {
  log "Collecting network state"
  {
    echo "=== ip addr ==="
    ip -br addr 2>/dev/null || true
    echo
    echo "=== ip -d link show $IFACE ==="
    ip -d link show "$IFACE" 2>/dev/null || true
    echo
    echo "=== ip route ==="
    ip route 2>/dev/null || true
    echo
    echo "=== ip rule ==="
    ip rule show 2>/dev/null || true
    echo
    echo "=== resolv.conf ==="
    cat /etc/resolv.conf 2>/dev/null || true
    echo
    echo "=== resolvectl / systemd-resolve ==="
    resolvectl status 2>/dev/null || systemd-resolve --status 2>/dev/null || true
    echo
    echo "=== nmcli dev show $IFACE ==="
    nmcli dev show "$IFACE" 2>/dev/null || echo "(nmcli not available or iface not managed)"
    echo
    echo "=== nmcli con show --active ==="
    nmcli con show --active 2>/dev/null || true
    echo
    echo "=== ethtool -S $IFACE ==="
    ethtool -S "$IFACE" 2>/dev/null || true
    echo
    echo "=== sysfs qmi/mbim ==="
    for f in \
      /sys/class/net/"$IFACE"/qmi/raw_ip \
      /sys/class/net/"$IFACE"/type \
      /sys/class/net/"$IFACE"/mtu \
      /sys/class/net/"$IFACE"/operstate; do
      [[ -r "$f" ]] && echo "$f: $(cat "$f")"
    done
  } > "$TMP/network.txt" 2>&1
}

collect_counters() {
  local tag="$1"  # "before" or "after"
  ip -s link show "$IFACE" 2>/dev/null > "$TMP/counters_${tag}.txt" || true
}

collect_connectivity() {
  log "Running connectivity tests"
  PING_GW_RESULT="skipped"
  PING_8_RESULT="skipped"
  PING_1_RESULT="skipped"
  DNS1_RESULT="skipped"
  DNS2_RESULT="skipped"
  HTTP_RESULT="skipped"
  HTTPS_RESULT="skipped"
  MTU_1472="skipped"
  MTU_1400="skipped"
  MTU_1300="skipped"

  if [[ -z "$UE_IP" ]]; then
    log "No IP on $IFACE — skipping connectivity tests"
    return
  fi

  run_ping() {
    local target="$1" label="$2"
    local out
    out="$(ping -I "$IFACE" -c "$PING_COUNT" -W 3 "$target" 2>&1)" || true
    echo "$out" > "$TMP/ping_${label}.txt"
    # Extract: min/avg/max and packet loss
    local stats loss
    stats="$(echo "$out" | grep -E 'rtt|round-trip' | grep -Eo '[0-9]+\.[0-9]+/[0-9]+\.[0-9]+/[0-9]+\.[0-9]+' | head -1 || true)"
    loss="$(echo "$out" | grep -Eo '[0-9]+% packet loss' | head -1 || echo "100% packet loss")"
    if [[ -n "$stats" ]]; then
      echo "PASS | $loss | rtt min/avg/max=$stats ms"
    else
      echo "FAIL | $loss"
    fi
  }

  run_mtu_ping() {
    local size="$1"
    local out
    out="$(ping -I "$IFACE" -M do -s "$size" -c 3 -W 3 8.8.8.8 2>&1)" || true
    echo "$out" > "$TMP/ping_mtu${size}.txt"
    if echo "$out" | grep -q "bytes from"; then echo "PASS"; else echo "FAIL"; fi
  }

  [[ "$NO_PING" -eq 0 ]] && {
    [[ -n "$GATEWAY" ]] && PING_GW_RESULT="$(run_ping "$GATEWAY" gw)"
    PING_8_RESULT="$(run_ping 8.8.8.8 8888)"
    PING_1_RESULT="$(run_ping 1.1.1.1 1111)"
    MTU_1472="$(run_mtu_ping 1472)"
    MTU_1400="$(run_mtu_ping 1400)"
    MTU_1300="$(run_mtu_ping 1300)"
  }

  if have_cmd dig; then
    local dig_out
    dig_out="$(dig @"$DNS1" "$TEST_HOST" A -b "$UE_IP" +time=3 +tries=1 2>&1)" || true
    echo "$dig_out" > "$TMP/dns1.txt"
    DNS1_RESULT="$(echo "$dig_out" | grep -q 'ANSWER SECTION' && echo "PASS" || echo "FAIL")"

    dig_out="$(dig @"$DNS2" "$TEST_HOST" A -b "$UE_IP" +time=3 +tries=1 2>&1)" || true
    echo "$dig_out" > "$TMP/dns2.txt"
    DNS2_RESULT="$(echo "$dig_out" | grep -q 'ANSWER SECTION' && echo "PASS" || echo "FAIL")"
  fi

  local curl_out
  curl_out="$(curl -4 --interface "$IFACE" -s -o /dev/null -w '%{http_code} | time=%{time_total}s | size=%{size_download}B' \
    "https://$TEST_HOST" --max-time 15 2>&1)" || true
  echo "$curl_out" > "$TMP/https.txt"
  HTTPS_RESULT="$(echo "$curl_out" | grep -Eq '^2[0-9]{2}' && echo "PASS ($curl_out)" || echo "FAIL ($curl_out)")"

  curl_out="$(curl -4 --interface "$IFACE" -s -o /dev/null -w '%{http_code} | time=%{time_total}s' \
    "http://neverssl.com" --max-time 15 2>&1)" || true
  echo "$curl_out" > "$TMP/http.txt"
  HTTP_RESULT="$(echo "$curl_out" | grep -Eq '^2[0-9]{2}' && echo "PASS ($curl_out)" || echo "FAIL ($curl_out)")"

  if [[ "$PCAP_SECONDS" =~ ^[0-9]+$ && "$PCAP_SECONDS" -gt 0 ]]; then
    have_cmd tcpdump && \
      sudo timeout "$PCAP_SECONDS" tcpdump -ni "$IFACE" \
        -w "$OUTDIR/${IFACE}_${PCAP_SECONDS}s.pcap" > "$TMP/pcap.txt" 2>&1 || true
  fi
}

# ---------------------------------------------------------------------------
# EXTRACT QUICK-SUMMARY FIELDS
# ---------------------------------------------------------------------------
extract_summary_fields() {
  # USB PID
  USB_PID="$(lsusb 2>/dev/null | grep -i '1bc7' | grep -Eo '1bc7:[0-9a-f]{4}' | head -1 || echo "not found")"
  case "$USB_PID" in
    "1bc7:1071") USB_PID_STATUS="✓ CORRECT (MBIM composition)" ;;
    "1bc7:1070") USB_PID_STATUS="✗ WRONG (incorrect USB composition — run AT#USBCFG?)" ;;
    "not found") USB_PID_STATUS="⚠ No Telit device found" ;;
    *)           USB_PID_STATUS="? Unknown PID — check AT#USBCFG?" ;;
  esac

  # Interface mode
  IFACE_TYPE="$(cat "/sys/class/net/$IFACE/type" 2>/dev/null || echo unknown)"
  case "$IFACE_TYPE" in
    530) IFACE_MODE="MBIM raw-IP ✓" ;;
    1)   IFACE_MODE="Ethernet/QMI" ;;
    *)   IFACE_MODE="Unknown (type=$IFACE_TYPE)" ;;
  esac

  # Registration from AT output or mmcli
  REG_STATE="unknown"
  OPERATOR="unknown"
  RSRP="unknown"
  RSRQ="unknown"
  BAND="unknown"
  RAT="unknown"

  if [[ -f "$TMP/at.txt" ]]; then
    # AT+COPS? → operator and RAT
    local cops
    cops="$(grep -A2 'AT+COPS?' "$TMP/at.txt" | grep '+COPS:' | head -1 || true)"
    if [[ -n "$cops" ]]; then
      OPERATOR="$(echo "$cops" | grep -Eo '"[^"]+"' | head -1 | tr -d '"' || echo unknown)"
      # RAT: 7=LTE, 11=NR, 12=NR (SA)
      local rat_code
      rat_code="$(echo "$cops" | grep -Eo ',[0-9]+$' | tr -d ',' || true)"
      case "$rat_code" in
        7)  RAT="LTE" ;;
        11) RAT="NR (NSA)" ;;
        12) RAT="NR (SA)" ;;
        *)  RAT="code=$rat_code" ;;
      esac
    fi

    # AT+C5GREG? → 5G registration state
    local c5greg
    c5greg="$(grep -A2 'AT+C5GREG?' "$TMP/at.txt" | grep '+C5GREG:' | tail -1 || true)"
    if [[ -n "$c5greg" ]]; then
      local stat
      stat="$(echo "$c5greg" | grep -Eo ',[0-9]+' | head -1 | tr -d ',' || true)"
      case "$stat" in
        0) REG_STATE="Not registered" ;;
        1) REG_STATE="Registered (home)" ;;
        2) REG_STATE="Searching" ;;
        3) REG_STATE="Registration denied" ;;
        5) REG_STATE="Registered (roaming)" ;;
        *) REG_STATE="stat=$stat" ;;
      esac
    fi

    # AT#RFSTS → RSRP, RSRQ, band
    local rfsts
    rfsts="$(grep -A3 'AT#RFSTS' "$TMP/at.txt" | grep '#RFSTS:' | head -1 || true)"
    if [[ -n "$rfsts" ]]; then
      RSRP="$(echo "$rfsts" | grep -Eo ',-?[0-9]+\.[0-9]+' | head -1 | tr -d ',' || echo unknown) dBm"
      RSRQ="$(echo "$rfsts" | grep -Eo ',-?[0-9]+\.[0-9]+' | sed -n '2p' | tr -d ',' || echo unknown) dB"
    fi

    # AT#BND? → band
    local bnd
    bnd="$(grep -A2 'AT#BND?' "$TMP/at.txt" | grep '#BND:' | head -1 || true)"
    [[ -n "$bnd" ]] && BAND="$(echo "$bnd" | grep -Eo '[0-9]+' | head -1 || echo unknown)"
  fi

  # Fall back to mmcli for signal if AT didn't yield it
  if [[ "$RSRP" == "unknown" && -f "$TMP/mmcli.txt" ]]; then
    RSRP="$(grep -Ei 'rsrp|signal strength' "$TMP/mmcli.txt" | grep -Eo '[-0-9.]+\s*dBm' | head -1 || echo unknown)"
    RSRQ="$(grep -Ei 'rsrq' "$TMP/mmcli.txt" | grep -Eo '[-0-9.]+\s*dB' | head -1 || echo unknown)"
  fi

  [[ "$RSRP" == "unknown" ]] && RSRP="not available"
  [[ "$RSRQ" == "unknown" ]] && RSRQ="not available"
}

# ===========================================================================
# RUN COLLECTION
# ===========================================================================
collect_usb
collect_kernel
collect_mmcli

if [[ "$MODE" != "connectivity" ]]; then
  case "$AT_METHOD" in
    mmcli)   collect_at_mmcli ;;
    picocom) collect_at_picocom "$EFFECTIVE_ATPORT" ;;
    none)
      {
        echo "AT commands not collected."
        echo
        echo "No AT method available:"
        have_cmd mmcli   && echo "  mmcli: installed but no modem detected" \
                        || echo "  mmcli: not installed (apt install modemmanager)"
        have_cmd expect  || echo "  expect: not installed (apt install expect)"
        have_cmd picocom || echo "  picocom: not installed (apt install picocom)"
        [[ "$(have_cmd expect && have_cmd picocom && echo yes || echo no)" == "yes" ]] && \
          echo "  expect+picocom: installed but no responsive ttyUSB found"
        echo
        echo "To force a specific port: $0 --at /dev/ttyUSBx"
      } > "$TMP/at.txt"
      ;;
  esac
fi

collect_network
collect_counters before

[[ "$MODE" != "at-only" ]] && collect_connectivity

collect_counters after
extract_summary_fields

# ===========================================================================
# RENDER MARKDOWN REPORT
# ===========================================================================
log "Rendering Markdown report"

{
cat << MDHEAD
# FN990 Diagnostic Report

**Generated:** $(date -Is)
**Host:** $(hostname)
**Mode:** $MODE
**Interface:** $IFACE
**AT method:** $AT_METHOD${MODEM:+ (modem $MODEM)}

---

## Quick Summary

| Item | Value | Status |
|---|---|---|
| USB PID | \`$USB_PID\` | $USB_PID_STATUS |
| Interface mode | $IFACE | $IFACE_MODE |
| IP address | ${UE_CIDR:-not assigned} | $([ -n "$UE_IP" ] && echo "✓" || echo "✗ No IP") |
| Gateway | ${GATEWAY:-none} | $([ -n "$GATEWAY" ] && echo "✓" || echo "—") |
| Registration (5G) | $REG_STATE | — |
| Operator | $OPERATOR | — |
| RAT | $RAT | — |
| Band | $BAND | — |
| RSRP | $RSRP | — |
| RSRQ | $RSRQ | — |
MDHEAD

if [[ "$MODE" != "at-only" && -n "$UE_IP" ]]; then
cat << MDCONN
| Ping gateway | ${PING_GW_RESULT:-skipped} | — |
| Ping 8.8.8.8 | ${PING_8_RESULT:-skipped} | — |
| Ping 1.1.1.1 | ${PING_1_RESULT:-skipped} | — |
| DNS ($DNS1) | ${DNS1_RESULT:-skipped} | — |
| DNS ($DNS2) | ${DNS2_RESULT:-skipped} | — |
| HTTPS | ${HTTPS_RESULT:-skipped} | — |
| HTTP | ${HTTP_RESULT:-skipped} | — |
| MTU 1472 | ${MTU_1472:-skipped} | — |
| MTU 1400 | ${MTU_1400:-skipped} | — |
| MTU 1300 | ${MTU_1300:-skipped} | — |
MDCONN
fi

echo ""
echo "---"
echo ""

# Section: USB & Interface
echo "## USB & Interface"
echo ""
echo "\`\`\`"
cat "$TMP/usb.txt" 2>/dev/null || echo "(not collected)"
echo "\`\`\`"
echo ""
echo "---"
echo ""

# Section: ModemManager State
echo "## ModemManager State"
echo ""
echo "\`\`\`"
cat "$TMP/mmcli.txt" 2>/dev/null || echo "(not collected)"
echo "\`\`\`"
echo ""
echo "---"
echo ""

# Section: AT Commands
echo "## AT Commands"
echo ""
if [[ "$MODE" == "connectivity" ]]; then
  echo "_AT collection skipped in \`--mode connectivity\`._"
else
  echo "\`\`\`"
  cat "$TMP/at.txt" 2>/dev/null || echo "(not collected)"
  echo "\`\`\`"
fi
echo ""
echo "---"
echo ""

# Section: Network
echo "## Network"
echo ""
echo "\`\`\`"
cat "$TMP/network.txt" 2>/dev/null || echo "(not collected)"
echo "\`\`\`"
echo ""
echo "---"
echo ""

# Section: Connectivity
if [[ "$MODE" != "at-only" ]]; then
  echo "## Connectivity"
  echo ""
  if [[ -z "$UE_IP" ]]; then
    echo "_No IP address on $IFACE — connectivity tests skipped._"
  else
    # Summary already in Quick Summary table. Here: verbatim ping outputs.
    echo "### Ping to Gateway"
    echo "\`\`\`"
    cat "$TMP/ping_gw.txt" 2>/dev/null || echo "(skipped)"
    echo "\`\`\`"
    echo ""
    echo "### Ping 8.8.8.8"
    echo "\`\`\`"
    cat "$TMP/ping_8888.txt" 2>/dev/null || echo "(skipped)"
    echo "\`\`\`"
    echo ""
    echo "### Ping 1.1.1.1"
    echo "\`\`\`"
    cat "$TMP/ping_1111.txt" 2>/dev/null || echo "(skipped)"
    echo "\`\`\`"
    echo ""
    echo "### DNS Resolution"
    echo "\`\`\`"
    echo "=== dig @$DNS1 ==="
    cat "$TMP/dns1.txt" 2>/dev/null || echo "(skipped)"
    echo ""
    echo "=== dig @$DNS2 ==="
    cat "$TMP/dns2.txt" 2>/dev/null || echo "(skipped)"
    echo "\`\`\`"
  fi
  echo ""
  echo "---"
  echo ""
fi

# Section: Kernel Messages
echo "## USB & Kernel Messages"
echo ""
echo "\`\`\`"
cat "$TMP/kernel.txt" 2>/dev/null || echo "(not collected)"
echo "\`\`\`"
echo ""
echo "---"
echo ""

# Appendix
echo "## Appendix"
echo ""
echo "### Interface Counters (before)"
echo "\`\`\`"
cat "$TMP/counters_before.txt" 2>/dev/null || echo "(not collected)"
echo "\`\`\`"
echo ""
echo "### Interface Counters (after)"
echo "\`\`\`"
cat "$TMP/counters_after.txt" 2>/dev/null || echo "(not collected)"
echo "\`\`\`"
echo ""

if [[ "$MODE" != "at-only" && -n "$UE_IP" ]]; then
  echo "### MTU Ping Tests"
  echo "\`\`\`"
  echo "=== 1472 bytes ==="
  cat "$TMP/ping_mtu1472.txt" 2>/dev/null || echo "(skipped)"
  echo ""
  echo "=== 1400 bytes ==="
  cat "$TMP/ping_mtu1400.txt" 2>/dev/null || echo "(skipped)"
  echo ""
  echo "=== 1300 bytes ==="
  cat "$TMP/ping_mtu1300.txt" 2>/dev/null || echo "(skipped)"
  echo "\`\`\`"
  echo ""
  echo "### HTTP/HTTPS Full Output"
  echo "\`\`\`"
  echo "=== HTTPS ($TEST_HOST) ==="
  cat "$TMP/https.txt" 2>/dev/null || echo "(skipped)"
  echo ""
  echo "=== HTTP (neverssl.com) ==="
  cat "$TMP/http.txt" 2>/dev/null || echo "(skipped)"
  echo "\`\`\`"
  echo ""
fi

[[ -f "$OUTDIR/${IFACE}_${PCAP_SECONDS}s.pcap" ]] && \
  echo "_pcap saved: ${IFACE}_${PCAP_SECONDS}s.pcap_"

echo ""
echo "---"
echo ""
echo "_Report generated by collect\\_fn990.sh — $(date -Is)_"

} > "$OUTMD"

log "Done: $OUTMD"
echo
echo "Report: $OUTMD"
