# OAI O-RAN 7.2x Fronthaul — Testbed Reference

> **Testbed:** Band 78 · 40 MHz · 30 kHz SCS · 106 PRB · 4T4R  
> **O-DU host:** WS-gnb2  
> **O-RU:** Benetel RAN650 (primary) or RAN550 (variant)  
> **Emulator:** oairu on WS-gnb1 or loopback on WS-gnb2  
> **Timing:** Falcon RX/812/G PTP grandmaster · IEEE 1588v2 G.8275.1  
> **Stack:** OAI `develop` (monolithic O-DU)

---

## 1. Testbed Topology

```
WS-CN (192.168.70.x)
  └── AMF (192.168.70.132) / SMF / UPF

WS-gnb2 (O-DU host)
  ├── demo-oai NIC:     192.168.70.129   ← N2 toward AMF, N3 toward UPF
  ├── fronthaul NIC:    192.168.50.1     ← eCPRI toward Benetel O-RU
  │     MAC: <WS-gnb2 FH NIC MAC>       ← used in fh_conf.du_addr
  └── USRP NIC:         192.168.40.2    ← NOT used in O-RAN mode
                                           (X310 disconnected or powered off)

Benetel RAN650/RAN550
  ├── fronthaul port:   192.168.50.2    ← eCPRI toward WS-gnb2
  │     MAC: <Benetel FH MAC>           ← used in fh_conf.ru_addr
  └── management port:  192.168.50.x   ← vendor web UI / SSH

Falcon RX/812/G PTP Grandmaster
  └── connected to fronthaul switch
      G.8275.1 profile, domain 24

[Emulator variant]
WS-gnb1 (oairu host) or WS-gnb2 loopback
  └── oairu NIC / veth MAC: <oairu MAC> ← used in fh_conf.ru_addr
```

---

## 2. What Changes vs. Monolithic USRP Config

| Config area | USRP monolithic | O-RAN O-DU |
|---|---|---|
| `local_rf` | `yes` | **`no`** |
| `sdr_addrs` | USRP IP | **absent** |
| `ru_type` | absent | **`oai_oran`** |
| `nb_tx` / `nb_rx` | `1` | **`4`** (Benetel 4T4R) |
| `pdsch_AntennaPorts` | `1` | **`4`** |
| `pusch_AntennaPorts_XP` | `1` | **`4`** |
| `ru_config` block | absent | **required** |
| `fh_conf` block | absent | **required** |
| `THREAD_STRUCT` | `PARALLEL_RU_L1_SPLIT` | **`PARALLEL_RU_L1_TRX_SPLIT`** |
| Launch flag | `--usrp-tx-thread-config 1` | **absent** (not for fronthaul) |
| Host PTP | not needed | **required before start** |

---

## 3. How to Find Your MAC Addresses

Before filling in the YAML, get both MAC addresses:

```bash
# O-DU fronthaul NIC MAC (on WS-gnb2)
ip link show <fh_iface>
# Look for: link/ether xx:xx:xx:xx:xx:xx

# Benetel O-RU MAC
# Option 1: label on the Benetel unit
# Option 2: arping from O-DU host after connecting the cable
sudo arping -I <fh_iface> -c 3 192.168.50.2
# The reply shows the Benetel MAC

# Verify eCPRI frames are flowing after startup
sudo tcpdump -ni <fh_iface> ether proto 0xAEFE -c 20
```

---

## 4. PTP Setup on WS-gnb2

Run these **before** starting nr-softmodem. OAI does not wait for PTP lock at startup.

```bash
# /etc/linuxptp/g8275.1.conf — create this file
[global]
network_transport      L2
dataset_comparison     G.8275.x
G.8275.defaultDS.localPriority 128
domainNumber           24
slaveOnly              1
tx_timestamp_timeout   20
logging_level          6

[<fh_iface>]
# interface-specific settings if needed
```

```bash
# Start PTP (run as systemd service or in a separate terminal)
sudo ptp4l -i <fh_iface> -f /etc/linuxptp/g8275.1.conf -m 2>&1 | tee /tmp/ptp4l.log &

# Sync system clock to PTP hardware clock
sudo phc2sys -s <fh_iface> -c CLOCK_REALTIME -n 24 -O 0 -m 2>&1 | tee /tmp/phc2sys.log &

# Wait for lock — this typically takes 10-30 seconds with Falcon RX/812/G
watch -n1 "pmc -u -b 0 'GET CURRENT_DATA_SET' | grep -E 'offsetFromMaster|meanPathDelay'"
# Good lock: offsetFromMaster < 500 ns
# Required for Benetel: offsetFromMaster < 1000 ns
```

**Falcon RX/812/G settings to verify:**
- Profile: G.8275.1 (not G.8275.2 — that uses UDP, not L2)
- Domain: 24
- VLAN: check your switch config — if PTP uses a VLAN, add `vlan_tag` to ptp4l config
- The Falcon should report as `GRAND_MASTER` or `MASTER` in PTP state

---

## 5. Fronthaul NIC Preparation on WS-gnb2

```bash
# Get the fronthaul interface name
ip link show | grep -A1 "192.168.50"
# Or: check which NIC has the eCPRI cable connected

FH_IFACE=<your_fronthaul_iface>   # e.g. enp4s0f0

# Jumbo frames (must match Benetel and switch)
sudo ip link set $FH_IFACE mtu 9000

# Disable offloading (critical for eCPRI latency)
sudo ethtool -K $FH_IFACE gro off lro off tso off gso off

# Bring interface up (no IP needed — eCPRI is Layer 2)
sudo ip link set $FH_IFACE up

# Verify
ip link show $FH_IFACE | grep -E "mtu|state|ether"
```

---

## 6. Benetel-Specific Notes

### RAN650 vs RAN550 Key Differences

| Parameter | RAN650 | RAN550 |
|---|---|---|
| Form factor | Indoor small cell | Outdoor macro |
| Typical deployment | Lab / indoor | Outdoor |
| Band | n78 (3.3–3.8 GHz) | n77/n78 |
| Max TX power | 100 mW (20 dBm) | Higher |
| Boot time | ~2 minutes | ~3 minutes |
| `T1a_max_up` | 430 µs | 500 µs |
| `T1a_min_up` | 258 µs | 285 µs |
| `T1a_max_cp_dl` | 430 µs | 500 µs |
| `T1a_min_cp_dl` | 285 µs | 285 µs |
| `Ta3_max` | 300 µs | 350 µs |
| PTP requirement | G.8275.1 | G.8275.1 |
| Management interface | Web UI + SSH | Web UI + SSH |

### Benetel Initial Configuration

Before running OAI, verify on the Benetel web UI or SSH:
- **Frequency:** ARFCN matches `absoluteFrequencySSB` in O-DU config
- **Bandwidth:** 40 MHz (106 PRB at 30 kHz SCS)
- **PTP domain:** 24 (must match ptp4l config)
- **Compression:** BFP, 9-bit IQ
- **Cell ID:** matches `physCellId` in O-DU config

---

## 7. oairu Emulator Setup

### Option A: oairu on WS-gnb1 (separate host)

```
WS-gnb2 (O-DU)  ←— Ethernet cable —→  WS-gnb1 (oairu)
192.168.50.1 (FH NIC)              192.168.50.3 (FH NIC)
```

On WS-gnb1:
```bash
# Build oairu (part of OAI build)
cd ~/ORANSlice/oai_ran/cmake_targets/ran_build/build
# oairu binary should be present after building with --build-oairu flag

# Get WS-gnb1 fronthaul NIC MAC
ip link show <fh_iface_wsgn1>

# Start oairu
sudo ./oairu -O /path/to/oairu.yaml
```

### Option B: oairu on WS-gnb2 (loopback via veth)

```bash
# Create veth pair on WS-gnb2
sudo ip link add veth-odu type veth peer name veth-ru
sudo ip link set veth-odu up
sudo ip link set veth-ru up

# O-DU uses veth-odu MAC in fh_conf.du_addr
# oairu uses veth-ru MAC in its config
ip link show veth-odu | grep ether   # → du_addr
ip link show veth-ru  | grep ether   # → ru_addr in oairu config
```

---

## 8. Parameter Consistency Checklist (Groups M–Q)

Use this before every run:

| Check | O-DU value | O-RU / oairu value | Must match? |
|---|---|---|---|
| `fh_conf.du_addr` | WS-gnb2 FH NIC MAC | (source address on O-DU frames) | **Yes — exact** |
| `fh_conf.ru_addr` | Benetel/oairu MAC | (source address on O-RU frames) | **Yes — exact** |
| `dl_compr_meth` | `1` (BFP) | Benetel: BFP | **Yes** |
| `dl_compr_iq_bitwidth` | `9` | Benetel: 9-bit | **Yes** |
| `ul_compr_meth` | `1` (BFP) | Benetel: BFP | **Yes** |
| `ul_compr_iq_bitwidth` | `9` | Benetel: 9-bit | **Yes** |
| `mtu_size` | `9000` | Switch port MTU: 9000 | **Yes** |
| `absoluteFrequencySSB` | `640704` | Benetel ARFCN config | **Yes** |
| `physCellId` | `0` | Benetel cell ID config | **Yes** |
| PTP domain | `24` (ptp4l) | Falcon: `24` | **Yes** |
| PTP profile | G.8275.1 L2 | Falcon: G.8275.1 | **Yes** |

---

## 9. Errors Specific to This Testbed

### 9.1 Benetel Not Sending UL Data After PTP Lock

Sometimes the Benetel requires a power-cycle after PTP first locks to correctly initialize its timing. If you see PTP locked but no UL U-Plane frames from the Benetel:
```bash
# Check eCPRI traffic
sudo tcpdump -ni <fh_iface> ether proto 0xAEFE -c 50
# You should see both DL (from O-DU) and UL (from Benetel) frames
# If only DL frames: Benetel is receiving but not responding
# → power-cycle the Benetel and wait for full boot + PTP relock
```

### 9.2 PTP Lock Lost After nr-softmodem Start

OAI's fronthaul I/O thread generates burst traffic that can interfere with PTP timestamping on a shared NIC. Fix: use the dedicated fronthaul NIC exclusively for eCPRI (no management traffic), and pin NIC IRQs to cores not used by `--thread-pool`.

### 9.3 `fh_conf.du_addr` Wrong After NIC Replacement

If WS-gnb2's fronthaul NIC is replaced (e.g. after hardware failure), the MAC changes. The YAML must be updated with the new MAC. Keep the `ip link show` command in your startup checklist.

### 9.4 oairu Compression Mismatch with Real O-DU Config

If you switch between oairu testing and Benetel without changing the YAML, the compression settings will be wrong for one of them. Always verify `dl/ul_compr_meth` and `dl/ul_compr_iq_bitwidth` match the target O-RU before launching.

---

## 10. Launch Sequence

```bash
# ─── WS-CN: verify CN is up ───────────────────────────────────────
docker ps | grep -E "oai-amf|oai-smf|oai-upf"

# ─── WS-gnb2: prepare host ────────────────────────────────────────
FH_IFACE=<fronthaul_iface>

# 1. Fronthaul NIC
sudo ip link set $FH_IFACE mtu 9000
sudo ethtool -K $FH_IFACE gro off lro off tso off gso off
sudo ip link set $FH_IFACE up

# 2. CPU tuning
sudo cpupower frequency-set -g performance
sudo cpupower idle-set -D 0

# 3. Start PTP (wait for LOCKED before continuing)
sudo ptp4l -i $FH_IFACE -f /etc/linuxptp/g8275.1.conf -m &
sudo phc2sys -s $FH_IFACE -c CLOCK_REALTIME -n 24 -O 0 -m &
sleep 15
pmc -u -b 0 'GET CURRENT_DATA_SET' | grep offsetFromMaster
# Must show < 1000 ns before proceeding

# 4. Verify Benetel is up and PTP-locked (check vendor UI/SSH)
arping -I $FH_IFACE -c 3 192.168.50.2   # Benetel responds?

# 5. Start O-DU
cd ~/ORANSlice/oai_ran/cmake_targets/ran_build/build
sudo ./nr-softmodem \
  -O /path/to/odu_ran650.yaml \   # or odu_ran550.yaml / odu_emulated.yaml
  --sa \
  --thread-pool 0,2,4,6 \
  --reorder-thread-disable 1

# [For oairu emulator only — start BEFORE nr-softmodem]
# sudo ./oairu -O /path/to/oairu.yaml
```

---

## 11. Pre-flight Checklist

```bash
# On WS-gnb2:
ip link show $FH_IFACE | grep -E "mtu 9000|UP"       # NIC up + jumbo frames
pmc -u -b 0 'GET CURRENT_DATA_SET' | grep offsetFromMaster  # PTP locked
sudo tcpdump -ni $FH_IFACE ether proto 0x8100 -c 5 2>/dev/null \
  || echo "No VLAN tags (expected for untagged setup)"  # VLAN check
ping -c 3 192.168.70.132                              # AMF reachable
sudo cpupower frequency-info | grep "current CPU frequency"  # governor=performance

# For Benetel:
arping -I $FH_IFACE -c 3 192.168.50.2               # O-RU responding
# (check Benetel web UI: PTP status = LOCKED, cell = active)
```
