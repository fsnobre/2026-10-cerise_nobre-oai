#!/usr/bin/env bash
# oai_usrp_perf_tune.sh
#
# Conservative OAI/USRP host-performance checker/tuner for Linux hosts.
#
# Default mode is CHECK ONLY. Use --apply to perform runtime-safe changes.
# Some changes can be persisted with explicit flags. Risky BIOS/GRUB/security
# changes are reported but are NOT automatically applied.
#
# Typical usage for an OAI gNB host with a USRP X310/N300/N310 on a 10GbE NIC:
#   sudo ./oai_usrp_perf_tune.sh --iface enp1s0f0 --apply --persist-sysctl --rtprio
#
# Check only:
#   ./oai_usrp_perf_tune.sh --iface enp1s0f0 --check
#
# Multiple NICs:
#   sudo ./oai_usrp_perf_tune.sh --iface enp1s0f0 --iface enp1s0f1 --apply
#
# Print OAI runtime option hints:
#   ./oai_usrp_perf_tune.sh --print-oai-hints
#
# Notes:
# - This script is idempotent and avoids destructive changes.
# - It does not edit GRUB, disable SMT, or disable kernel mitigations.
# - It does not install packages automatically.
# - MTU/ring/sysctl/governor/idle changes may be reset after reboot unless
#   you use persistence flags or configure your OS/network manager accordingly.
# - --idle-disable must be passed explicitly; it is NOT applied by default.

set -Eeuo pipefail

MODE="check"
IFACES=()
MTU="9000"
RING="4096"
BUFFER_BYTES="62500000"
SET_GOVERNOR="performance"
PERSIST_SYSCTL=0
APPLY_RTPRIO=0
APPLY_NM_UNMANAGED=0
PERSIST_NM_UNMANAGED=0
DISABLE_IDLE_STATES=0       # FIX: was 1 (applied silently). Now requires --idle-disable.
PRINT_OAI_HINTS=0
ENABLE_CORE_FORWARDING=0
QUIET=0
ASSUME_YES=0
TARGET_USER="${SUDO_USER:-$USER}"

green()  { printf '\033[0;32m%s\033[0m\n' "$*"; }
yellow() { printf '\033[0;33m%s\033[0m\n' "$*"; }
red()    { printf '\033[0;31m%s\033[0m\n' "$*" >&2; }
blue()   { printf '\033[0;34m%s\033[0m\n' "$*"; }
say()    { [[ "$QUIET" -eq 1 ]] || printf '%s\n' "$*"; }

need_root_for_apply() {
  if [[ "$MODE" == "apply" && "${EUID}" -ne 0 ]]; then
    red "ERROR: --apply requires root. Re-run with sudo."
    exit 1
  fi
}

usage() {
  cat <<'EOF'
Usage:
  oai_usrp_perf_tune.sh [--check|--apply] [options]

Core options:
  --check                  Check only (default).
  --apply                  Apply runtime-safe tuning (requires root).
  --iface IFACE            USRP Ethernet interface. Repeat for multiple NICs.
  --mtu N                  Desired MTU. Default: 9000.
  --ring N                 Desired RX/TX ring size. Default: 4096.
  --buffers BYTES          Socket buffer value. Default: 62500000.
  --governor GOV           CPU governor. Default: performance.
  --idle-disable           Apply cpupower idle-set -D 0 (NOT the default; opt-in only).
  --persist-sysctl         Write /etc/sysctl.d/99-oai-usrp-perf.conf.
  --rtprio                 Create usrp group, add user, write rtprio limits.
  --nm-unmanaged           Ask NetworkManager to stop managing --iface devices at runtime.
  --persist-nm-unmanaged   Persist NetworkManager unmanaged-devices for --iface MACs.
  --core-forwarding        Enable IPv4 forwarding for OAI core host.
  --irq-affinity CPU_LIST  Pin NIC IRQs to CPU list (e.g. 8,9,10,11). Requires --iface.
  --print-oai-hints        Print OAI command-line/config hints.
  --yes                    Skip apply confirmation prompt.
  --quiet                  Less output.
  -h, --help               Show this help.

Examples:
  ./oai_usrp_perf_tune.sh --iface enp1s0f0 --check
  sudo ./oai_usrp_perf_tune.sh --iface enp1s0f0 --apply --persist-sysctl --rtprio
  sudo ./oai_usrp_perf_tune.sh --iface enp1s0f0 --apply --idle-disable --irq-affinity 8,9,10,11
EOF
}

IRQ_CPU_LIST=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)               MODE="check"; shift ;;
    --apply)               MODE="apply"; shift ;;
    --iface)               IFACES+=("${2:?Missing IFACE}"); shift 2 ;;
    --mtu)                 MTU="${2:?}"; shift 2 ;;
    --ring)                RING="${2:?}"; shift 2 ;;
    --buffers)             BUFFER_BYTES="${2:?}"; shift 2 ;;
    --governor)            SET_GOVERNOR="${2:?}"; shift 2 ;;
    --idle-disable)        DISABLE_IDLE_STATES=1; shift ;;   # FIX: explicit opt-in
    --persist-sysctl)      PERSIST_SYSCTL=1; shift ;;
    --rtprio)              APPLY_RTPRIO=1; shift ;;
    --nm-unmanaged)        APPLY_NM_UNMANAGED=1; shift ;;
    --persist-nm-unmanaged) PERSIST_NM_UNMANAGED=1; shift ;;
    --core-forwarding)     ENABLE_CORE_FORWARDING=1; shift ;;
    --irq-affinity)        IRQ_CPU_LIST="${2:?}"; shift 2 ;;
    --print-oai-hints)     PRINT_OAI_HINTS=1; shift ;;
    --yes|-y)              ASSUME_YES=1; shift ;;
    --quiet)               QUIET=1; shift ;;
    -h|--help)             usage; exit 0 ;;
    *)                     red "Unknown argument: $1"; usage; exit 2 ;;
  esac
done

need_root_for_apply

confirm_apply() {
  [[ "$MODE" != "apply" ]] && return 0
  [[ "$ASSUME_YES" -eq 1 ]] && return 0
  # FIX: check for interactive terminal before using read
  if [[ ! -t 0 ]]; then
    yellow "Non-interactive mode detected. Use --yes to confirm apply non-interactively."
    exit 1
  fi
  cat <<EOF

About to apply runtime tuning:
  interfaces:       ${IFACES[*]:-(none)}
  MTU:              $MTU
  ring RX/TX:       $RING
  socket buffers:   $BUFFER_BYTES
  CPU governor:     $SET_GOVERNOR
  disable c-states: $DISABLE_IDLE_STATES
  persist sysctl:   $PERSIST_SYSCTL
  rtprio group:     $APPLY_RTPRIO for user $TARGET_USER
  NM unmanaged:     runtime=$APPLY_NM_UNMANAGED persistent=$PERSIST_NM_UNMANAGED
  core forwarding:  $ENABLE_CORE_FORWARDING
  IRQ affinity:     ${IRQ_CPU_LIST:-(not set)}

Continue? [y/N]
EOF
  read -r -t 30 ans || { yellow "Timed out. Aborted."; exit 0; }
  [[ "$ans" =~ ^[Yy]$ ]] || { yellow "Aborted."; exit 0; }
}

has_cmd() { command -v "$1" >/dev/null 2>&1; }

check_kernel() {
  blue "== Kernel / real-time status =="
  say "Kernel: $(uname -r)"

  # FIX: use /sys/kernel/realtime instead of broad uname grep
  if [[ -r /sys/kernel/realtime ]] && [[ "$(cat /sys/kernel/realtime)" == "1" ]]; then
    green "OK: kernel reports PREEMPT_RT (realtime) via /sys/kernel/realtime."
  elif uname -r | grep -Eqi 'lowlatency|preempt'; then
    green "OK: kernel string suggests lowlatency/preempt support."
  else
    yellow "WARN: kernel does not appear to be lowlatency or PREEMPT_RT. OAI radio stability benefits from lowlatency kernel on Ubuntu 24.04."
  fi

  if [[ -r /sys/devices/system/cpu/smt/active ]]; then
    local smt
    smt="$(cat /sys/devices/system/cpu/smt/active)"
    if [[ "$smt" == "1" ]]; then
      yellow "WARN: SMT/Hyper-Threading enabled. Disabling in BIOS can improve worst-case latency (last resort only)."
    else
      green "OK: SMT/Hyper-Threading disabled."
    fi
  else
    say "INFO: cannot read SMT status."
  fi

  if grep -qw "mitigations=off" /proc/cmdline 2>/dev/null; then
    yellow "INFO: kernel mitigations=off. Improves performance but reduces security. Only on isolated lab hosts."
  else
    say "INFO: kernel mitigations not globally disabled (safer)."
  fi
}

check_governor() {
  blue "== CPU governor =="
  local found=0 nonmatching=0
  shopt -s nullglob
  for f in /sys/devices/system/cpu/cpu[0-9]*/cpufreq/scaling_governor; do
    found=1
    local cpu gov
    cpu="$(basename "$(dirname "$(dirname "$f")")")"
    gov="$(cat "$f" 2>/dev/null || echo unknown)"
    if [[ "$gov" != "$SET_GOVERNOR" ]]; then
      nonmatching=1
      yellow "WARN: $cpu governor=$gov, wanted $SET_GOVERNOR."
      if [[ "$MODE" == "apply" ]]; then
        # FIX: prefer cpupower, fall back to direct sysfs write
        if has_cmd cpupower; then
          cpupower frequency-set -c "${cpu#cpu}" -g "$SET_GOVERNOR" 2>/dev/null \
            || echo "$SET_GOVERNOR" > "$f" \
            || yellow "Could not set governor for $cpu."
        elif [[ -w "$f" ]]; then
          echo "$SET_GOVERNOR" > "$f" || yellow "Could not write to $f."
        else
          yellow "Neither cpupower nor writable sysfs path available for $cpu."
        fi
      fi
    fi
  done
  shopt -u nullglob
  [[ "$found" -eq 0 ]] && yellow "INFO: no cpufreq scaling_governor files found."
  [[ "$found" -eq 1 && "$nonmatching" -eq 0 ]] && green "OK: all CPU governors = $SET_GOVERNOR."
}

apply_idle_disable() {
  blue "== CPU idle states =="
  if [[ "$DISABLE_IDLE_STATES" -eq 0 ]]; then
    say "INFO: idle-state disabling not requested. Pass --idle-disable to apply cpupower idle-set -D 0."
    return
  fi
  if has_cmd cpupower; then
    if [[ "$MODE" == "apply" ]]; then
      cpupower idle-set -D 0 || yellow "cpupower idle-set -D 0 failed."
      green "Applied: cpupower idle-set -D 0"
    else
      say "CHECK: would run: cpupower idle-set -D 0"
    fi
  else
    yellow "WARN: cpupower not installed. Install linux-tools-$(uname -r) or cpupower."
  fi
}

check_sysctl_buffers() {
  blue "== Socket buffers =="
  local ok=1
  for key in net.core.wmem_max net.core.rmem_max net.core.wmem_default net.core.rmem_default; do
    local val
    val="$(sysctl -n "$key" 2>/dev/null || echo 0)"
    if [[ "$val" -lt "$BUFFER_BYTES" ]]; then
      yellow "WARN: $key=$val < $BUFFER_BYTES."
      ok=0
      if [[ "$MODE" == "apply" ]]; then
        sysctl -w "${key}=${BUFFER_BYTES}" >/dev/null || yellow "Could not set $key."
        green "Applied: $key=$BUFFER_BYTES"
      fi
    else
      say "OK: $key=$val"
    fi
  done
  [[ "$ok" -eq 1 ]] && green "OK: all socket buffers >= $BUFFER_BYTES."

  if [[ "$PERSIST_SYSCTL" -eq 1 && "$MODE" == "apply" ]]; then
    cat > /etc/sysctl.d/99-oai-usrp-perf.conf <<EOF
# OAI/USRP host tuning — written by oai_usrp_perf_tune.sh
net.core.wmem_max=$BUFFER_BYTES
net.core.rmem_max=$BUFFER_BYTES
net.core.wmem_default=$BUFFER_BYTES
net.core.rmem_default=$BUFFER_BYTES
EOF
    sysctl --system >/dev/null || yellow "sysctl --system reported an issue."
    green "Persisted: /etc/sysctl.d/99-oai-usrp-perf.conf"
  fi
}

iface_exists() { [[ -d "/sys/class/net/$1" ]]; }

get_iface_speed() {
  local iface="$1"
  [[ -r "/sys/class/net/$iface/speed" ]] && cat "/sys/class/net/$iface/speed" 2>/dev/null || echo "unknown"
}

check_iface() {
  local iface="$1"
  blue "== Interface $iface =="
  if ! iface_exists "$iface"; then
    red "ERROR: interface $iface does not exist."
    return 1
  fi

  local state speed mac
  local mtu_cur   # FIX: was missing 'local'
  state="$(cat "/sys/class/net/$iface/operstate" 2>/dev/null || echo unknown)"
  mtu_cur="$(cat "/sys/class/net/$iface/mtu" 2>/dev/null || echo unknown)"
  speed="$(get_iface_speed "$iface")"
  mac="$(cat "/sys/class/net/$iface/address" 2>/dev/null || echo unknown)"
  say "state=$state mtu=$mtu_cur speed=${speed}Mb/s mac=$mac"

  if [[ "$speed" != "unknown" && "$speed" -lt 10000 && "$MTU" -gt 1500 ]]; then
    yellow "WARN: $iface speed=${speed}Mb/s. MTU 9000 is for 10GbE; on 1GbE use MTU 1500."
  fi

  if [[ "$mtu_cur" != "$MTU" ]]; then
    yellow "WARN: $iface MTU=$mtu_cur, wanted $MTU."
    if [[ "$MODE" == "apply" ]]; then
      ip link set dev "$iface" mtu "$MTU" || yellow "Could not set MTU on $iface."
      green "Applied: ip link set dev $iface mtu $MTU"
    fi
  else
    green "OK: $iface MTU=$MTU"
  fi

  if has_cmd ethtool; then
    say "ethtool driver:"
    ethtool -i "$iface" 2>/dev/null | sed 's/^/  /' || true

    say "ring parameters:"
    ethtool -g "$iface" 2>/dev/null | sed 's/^/  /' || yellow "Could not read ring parameters for $iface."

    if [[ "$MODE" == "apply" ]]; then
      # FIX: use range pattern to isolate Pre-set maximums section
      local max_rx max_tx
      max_rx="$(ethtool -g "$iface" 2>/dev/null | awk '
        /Pre-set maximums:/ { in_section=1; next }
        in_section && /Current hardware settings:/ { exit }
        in_section && /^[[:space:]]*RX:/ { print $2; exit }
      ')"
      max_tx="$(ethtool -g "$iface" 2>/dev/null | awk '
        /Pre-set maximums:/ { in_section=1; next }
        in_section && /Current hardware settings:/ { exit }
        in_section && /^[[:space:]]*TX:/ { print $2; exit }
      ')"

      local desired_rx="$RING" desired_tx="$RING"
      [[ "$max_rx" =~ ^[0-9]+$ && "$desired_rx" -gt "$max_rx" ]] && desired_rx="$max_rx"
      [[ "$max_tx" =~ ^[0-9]+$ && "$desired_tx" -gt "$max_tx" ]] && desired_tx="$max_tx"

      if [[ "$desired_rx" =~ ^[0-9]+$ && "$desired_tx" =~ ^[0-9]+$ ]]; then
        ethtool -G "$iface" rx "$desired_rx" tx "$desired_tx" \
          || yellow "Could not set ring buffers on $iface."
        green "Applied: ethtool -G $iface rx $desired_rx tx $desired_tx"
      else
        yellow "Could not parse max ring size; trying $RING directly."
        ethtool -G "$iface" rx "$RING" tx "$RING" || yellow "Could not set ring buffers on $iface."
      fi
    fi
  else
    yellow "WARN: ethtool not installed. Cannot check/apply ring buffers."
  fi

  if has_cmd nmcli; then
    local nm_state
    nm_state="$(nmcli -t -f DEVICE,STATE device status 2>/dev/null | awk -F: -v dev="$iface" '$1==dev{print $2}')"
    if [[ -n "$nm_state" ]]; then
      say "NetworkManager state for $iface: $nm_state"
      if [[ "$APPLY_NM_UNMANAGED" -eq 1 && "$MODE" == "apply" ]]; then
        nmcli device set "$iface" managed no || yellow "Could not mark $iface unmanaged."
        green "Applied runtime NM unmanaged: $iface"
      fi
      if [[ "$PERSIST_NM_UNMANAGED" -eq 1 && "$MODE" == "apply" ]]; then
        local mac_addr
        mac_addr="$(cat "/sys/class/net/$iface/address")"
        mkdir -p /etc/NetworkManager/conf.d
        cat > "/etc/NetworkManager/conf.d/99-oai-usrp-unmanaged-${iface}.conf" <<EOF
[keyfile]
unmanaged-devices=mac:$mac_addr
EOF
        green "Persisted NM unmanaged for $iface."
        yellow "Restart NetworkManager for persistent setting to take effect."
      fi
    else
      say "NetworkManager does not manage $iface."
    fi
  fi
}

# FIX: new section — IRQ affinity
apply_irq_affinity() {
  [[ -z "$IRQ_CPU_LIST" ]] && return
  [[ "${#IFACES[@]}" -eq 0 ]] && { yellow "WARN: --irq-affinity requires --iface."; return; }

  blue "== IRQ affinity =="

  # Convert CPU list to hex bitmask
  local mask=0
  IFS=',' read -ra cpus <<< "$IRQ_CPU_LIST"
  for cpu in "${cpus[@]}"; do
    mask=$(( mask | (1 << cpu) ))
  done
  local hex_mask
  hex_mask="$(printf '%x' "$mask")"

  for iface in "${IFACES[@]}"; do
    iface_exists "$iface" || continue
    say "Setting IRQ affinity for $iface NIRQs to CPUs $IRQ_CPU_LIST (mask 0x$hex_mask)"

    local irq_dir="/sys/class/net/$iface/device/msi_irqs"
    if [[ ! -d "$irq_dir" ]]; then
      yellow "WARN: MSI IRQ directory not found for $iface at $irq_dir. Trying /proc/interrupts."
      local irqs
      irqs="$(grep "$iface" /proc/interrupts 2>/dev/null | awk -F: '{print $1}' | tr -d ' ')"
      if [[ -z "$irqs" ]]; then
        yellow "WARN: no IRQs found for $iface in /proc/interrupts."
        continue
      fi
      for irq in $irqs; do
        if [[ "$MODE" == "apply" ]]; then
          echo "$hex_mask" > "/proc/irq/$irq/smp_affinity" 2>/dev/null \
            || yellow "Could not set affinity for IRQ $irq."
        else
          say "CHECK: would set /proc/irq/$irq/smp_affinity = $hex_mask"
        fi
      done
    else
      for irq in "$irq_dir"/*; do
        local irq_num
        irq_num="$(basename "$irq")"
        if [[ "$MODE" == "apply" ]]; then
          echo "$hex_mask" > "/proc/irq/$irq_num/smp_affinity" 2>/dev/null \
            || yellow "Could not set affinity for IRQ $irq_num."
          green "Applied: /proc/irq/$irq_num/smp_affinity = $hex_mask"
        else
          say "CHECK: would set /proc/irq/$irq_num/smp_affinity = $hex_mask"
        fi
      done
    fi
  done
}

# FIX: new section — FPGA/UHD version cross-check
check_uhd_fpga_version() {
  blue "== UHD / FPGA version check =="
  if ! has_cmd uhd_find_devices; then
    yellow "WARN: uhd_find_devices not in PATH. Cannot check UHD/FPGA version."
    return
  fi

  local uhd_ver
  uhd_ver="$(uhd_find_devices 2>&1 | grep -i 'UHD' | head -1 || true)"
  say "UHD: ${uhd_ver:-(not detected)}"

  if has_cmd uhd_usrp_probe; then
    say "Probing USRP (may take a few seconds)..."
    local probe_out
    probe_out="$(timeout 15 uhd_usrp_probe 2>&1 || true)"

    local fpga_ver
    fpga_ver="$(echo "$probe_out" | grep -iE 'FPGA compat|fpga_version|compat number' | head -3)"
    if [[ -n "$fpga_ver" ]]; then
      say "FPGA compatibility info:"
      echo "$fpga_ver" | sed 's/^/  /'
      green "OK: FPGA detected. If you see 'FPGA image version mismatch' in OAI logs, run: uhd_images_downloader"
    else
      yellow "WARN: could not extract FPGA version from uhd_usrp_probe. Check that USRP is powered and connected."
    fi
  else
    yellow "WARN: uhd_usrp_probe not found."
  fi
}

list_candidate_ifaces() {
  blue "== Candidate high-speed interfaces =="
  for p in /sys/class/net/*; do
    local iface speed state
    iface="$(basename "$p")"
    [[ "$iface" == "lo" ]] && continue
    speed="$(get_iface_speed "$iface")"
    state="$(cat "$p/operstate" 2>/dev/null || echo unknown)"
    if [[ "$speed" != "unknown" && "$speed" -ge 10000 ]]; then
      say "candidate: $iface speed=${speed}Mb/s state=$state mtu=$(cat "$p/mtu" 2>/dev/null || echo unknown)"
    fi
  done
}

apply_rtprio() {
  blue "== UHD thread-priority permissions =="
  if [[ "$APPLY_RTPRIO" -eq 0 ]]; then
    if id -nG "$TARGET_USER" 2>/dev/null | tr ' ' '\n' | grep -qx usrp; then
      green "OK: user $TARGET_USER is already in group usrp."
    else
      yellow "INFO: user $TARGET_USER not in group usrp. Use --rtprio --apply to configure."
    fi
    return
  fi

  if [[ "$MODE" == "apply" ]]; then
    getent group usrp >/dev/null || groupadd usrp
    usermod -aG usrp "$TARGET_USER"
    cat > /etc/security/limits.d/99-usrp-rtprio.conf <<'EOF'
@usrp - rtprio 99
@usrp - memlock unlimited
EOF
    green "Applied: usrp group, user $TARGET_USER added, rtprio limits written."
    yellow "You must log out/in for group membership and PAM limits to take effect."
  else
    say "CHECK: would configure group usrp and rtprio limits for $TARGET_USER."
  fi
}

apply_core_forwarding() {
  [[ "$ENABLE_CORE_FORWARDING" -eq 0 ]] && return
  blue "== OAI Core forwarding helper =="
  if [[ "$MODE" == "apply" ]]; then
    sysctl -w net.ipv4.ip_forward=1 >/dev/null || true
    sysctl -w net.ipv4.conf.all.forwarding=1 >/dev/null || true
    if has_cmd iptables; then
      # FIX: use a targeted rule instead of system-wide policy change
      iptables -C FORWARD -j ACCEPT 2>/dev/null \
        || iptables -I FORWARD -j ACCEPT \
        || yellow "Could not insert iptables FORWARD ACCEPT rule."
      green "Applied: IPv4 forwarding enabled, iptables FORWARD ACCEPT rule inserted."
      yellow "Note: use iptables -D FORWARD -j ACCEPT to remove this rule if no longer needed."
    fi
  else
    say "CHECK: would enable net.ipv4.ip_forward=1 and insert iptables -I FORWARD -j ACCEPT."
  fi
}

print_oai_hints() {
  [[ "$PRINT_OAI_HINTS" -eq 0 ]] && return
  blue "== OAI runtime/config hints =="
  cat <<'EOF'
These are not applied by this script. They depend on your radio and failure mode.

Launch command (X310 OTA):
  sudo ./nr-softmodem -O gnb.yaml --sa \
    --usrp-tx-thread-config 1 \
    --thread-pool 0,2,4,6

For heavy UL real-time pressure (YAML — MACRLCs section):
  ul_max_mcs: 14

For lower user-plane latency (YAML — MACRLCs section):
  ulsch_max_frame_inactivity: 0

For N300/X300/X310 DC-carrier UL noise (launch flag):
  --tune-offset <Hz>
  Typical first try: half of occupied bandwidth, then reduce.

For repeated RA / Msg3 timing problems (YAML — servingCellConfigCommon):
  ra_ResponseWindow: 10       (was 4, too tight for USRP OTA)
  min_rxtxtime: 8             (increase from 6 if on 1 GbE)

For X310 clock drift / invalid timing advance:
  In sdr_addrs: clock_source=external,time_source=external
  (requires OctoClock-G or GPSDO connected to REF IN)

For soft-modem timing thread configuration (YAML — THREAD_STRUCT):
  parallel_config: PARALLEL_RU_L1_SPLIT    (minimum for OTA)
  parallel_config: PARALLEL_RU_L1_TRX_SPLIT (for heavy load)

BIOS-level (not applied by this script, do manually):
  Disable C-states (set C1E only or disable all)
  Disable P-states / SpeedStep
  Disable Hyper-Threading (last resort only)
EOF
}

main() {
  say "Mode: $MODE"
  confirm_apply
  check_kernel
  check_governor
  apply_idle_disable
  check_sysctl_buffers
  apply_rtprio
  if [[ "${#IFACES[@]}" -eq 0 ]]; then
    yellow "INFO: no --iface specified. NIC MTU/ring/NM tuning skipped."
    list_candidate_ifaces
  else
    for iface in "${IFACES[@]}"; do
      check_iface "$iface"
    done
    apply_irq_affinity
  fi
  check_uhd_fpga_version
  apply_core_forwarding
  print_oai_hints

  blue "== Summary =="
  if [[ "$MODE" == "check" ]]; then
    say "Check complete. Re-run with --apply to apply runtime-safe changes."
  else
    say "Apply complete. Some changes require logout/login or reboot."
  fi
  yellow "Reminder: this script does not edit GRUB, disable SMT, or disable kernel mitigations."
}

main "$@"
