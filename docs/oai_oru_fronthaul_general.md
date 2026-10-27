# OAI O-RAN 7.2x Fronthaul Configuration Reference

> **Scope:** OAI acting as O-DU over eCPRI/7.2x fronthaul toward an O-RU (Benetel RAN650/RAN550 or oairu emulator). Monolithic O-DU (full stack: RRC through Upper PHY on one host).  
> **Stack:** OAI `develop` branch, YAML config format, SA 5G NR.  
> **Not covered:** F1 split with O-DU as DU (see Batch 1 + future extension), O-RU internal configuration (vendor-specific).  
> **Timing:** IEEE 1588v2 PTP G.8275.1 telecom profile with external grandmaster required for real O-RU. Free-running mode available for oairu emulator.

---

## 1. Architecture Overview

```
                    ┌─────────────────────────────┐
                    │         Core Network         │
                    │   AMF (N2/NGAP)  UPF (N3)   │
                    └────────┬─────────────┬───────┘
                             │ N2           │ N3
                    ┌────────┴─────────────┴───────┐
                    │      O-DU (monolithic)        │
                    │  RRC / PDCP / RLC / MAC       │
                    │  Upper PHY (OAI nr-softmodem) │
                    │  local_rf: no                 │
                    │  RU type: oai_oran             │
                    └────────────┬─────────────────┘
                                 │ eCPRI over Ethernet
                                 │ Fronthaul NIC (dedicated)
                                 │ Plane C: 7.2x control
                                 │ Plane U: 7.2x user (IQ samples)
                                 │ Plane S: synchronization (PTP/SyncE)
                    ┌────────────┴─────────────────┐
                    │           O-RU                │
                    │  Lower PHY + RF               │
                    │  (Benetel RAN650 / RAN550      │
                    │   or oairu emulator)          │
                    └──────────────────────────────┘
                                 ↑
                    ┌────────────┴─────────────────┐
                    │    PTP Grandmaster            │
                    │  (Falcon RX/812/G or similar) │
                    │  IEEE 1588v2 G.8275.1         │
                    └──────────────────────────────┘
```

**Key difference from USRP (local RF) config:**

| Aspect | USRP (local RF) | O-RAN 7.2x fronthaul |
|---|---|---|
| `local_rf` | `yes` | **`no`** |
| `sdr_addrs` | USRP IP | **absent** |
| RU type | `None` (implicit local) | **`oai_oran`** |
| RF transport | UHD over 10GbE | **eCPRI over dedicated Ethernet** |
| Timing | USRP internal/external | **PTP G.8275.1 required for real O-RU** |
| `fh_conf` block | absent | **required** |
| Compression | N/A | **BFP (real O-RU) or none (emulator)** |
| Lower PHY | runs on O-DU host | **runs on O-RU** |
| Thread model | `PARALLEL_RU_L1_SPLIT` | **`PARALLEL_RU_L1_TRX_SPLIT`** recommended |

---

## 2. Tier Definitions

| Tier | Meaning |
|---|---|
| **Required** | OAI crashes or refuses to start without it. No safe default. |
| **Recommended** | OAI starts without it but behaviour may be wrong or silently broken. |
| **Optional** | Safe default exists. Only set to override. |

---

## 3. O-DU Configuration Reference

### 3.1 RUs Block — O-RAN Fronthaul

This is the most significant structural change from the USRP config. The `RUs` block gains a `ru_config` sub-block and a `fh_conf` sub-block.

#### Top-level RU fields

| Parameter | Tier | Notes |
|---|---|---|
| `local_rf` | Required | **`no`** — RF is on the O-RU, not the O-DU host. If `yes`, OAI tries to open a local radio device and ignores the fronthaul. |
| `nb_tx` | Required | Number of TX antennas. Must match O-RU capability (4 for Benetel RAN650/RAN550). |
| `nb_rx` | Required | Number of RX antennas. Must match O-RU capability. |
| `bands` | Required | NR band. Must match O-RU RF configuration. |
| `max_rxgain` | Required | Used for automatic gain control reference even in fronthaul mode. |
| `att_tx` | Optional | Default 0. Software TX attenuation — 0 for normal operation. |
| `att_rx` | Optional | Default 0. Software RX attenuation — 0 for normal operation. |
| `eNB_instances` | Required | `[0]` for single gNB. |

#### `ru_config` sub-block

Defines the fronthaul transport type and compression.

| Parameter | Tier | Default | Notes |
|---|---|---|---|
| `ru_type` | Required | — | **`oai_oran`** for 7.2x fronthaul. `oai_usrp` for USRP. `oai_rfsim` for simulation. |
| `if_freq` | Recommended | 0 | Center frequency offset (Hz). Usually 0 for direct conversion. |
| `dl_compr_meth` | Required | — | DL IQ compression method. `0`=none, `1`=BFP (Block Floating Point). Use `1` for Benetel. |
| `dl_compr_iq_bitwidth` | Required | — | DL compressed IQ sample bit width. `9` for Benetel BFP. |
| `ul_compr_meth` | Required | — | UL IQ compression method. Same values as DL. |
| `ul_compr_iq_bitwidth` | Required | — | UL compressed IQ sample bit width. `9` for Benetel BFP. |
| `prach_compr_meth` | Recommended | same as UL | PRACH IQ compression. Some O-RUs handle PRACH differently. |
| `prach_compr_iq_bitwidth` | Recommended | same as UL | PRACH compressed bit width. |
| `dl_compr_bias_compensation` | Optional | 0 | BFP bias compensation for DL. |
| `ul_compr_bias_compensation` | Optional | 0 | BFP bias compensation for UL. |

**Compression values for common scenarios:**

| Scenario | `dl/ul_compr_meth` | `dl/ul_compr_iq_bitwidth` |
|---|---|---|
| Benetel RAN650 | `1` (BFP) | `9` |
| Benetel RAN550 | `1` (BFP) | `9` |
| oairu emulator | `0` (none) | `16` |

#### `fh_conf` sub-block

Defines fronthaul network topology and timing window parameters per 3GPP TS 38.174 and O-RAN WG4 CUS-Plane spec.

| Parameter | Tier | Notes |
|---|---|---|
| `du_addr` | Required | O-DU MAC address of the fronthaul NIC. Use `ip link show <iface>` to find it. Format: `xx:xx:xx:xx:xx:xx`. |
| `ru_addr` | Required | O-RU MAC address. For Benetel: found on the unit label or via `arping` on the fronthaul network. |
| `mtu_size` | Recommended | Ethernet MTU for eCPRI frames. Default 9000 (jumbo frames). Must match switch/NIC MTU. |
| `vlan_tag_strip` | Optional | `0` or `1`. Strip VLAN tag on ingress. Required if O-RU sends tagged frames. |
| `io_core` | Recommended | CPU core pinned to fronthaul I/O thread. Pin to an isolated core away from OS tasks. |
| `io_sleep` | Optional | I/O thread sleep between polls (µs). 0 = busy-poll. Recommended: 0 for lowest latency. |
| `io_worker` | Optional | Number of I/O worker threads. Default 1. |

**Timing window parameters** (O-RAN WG4 Section 4.3):

These define the timing advance windows between O-DU and O-RU. They depend on your fronthaul latency and must be measured/tuned for your specific cable/switch setup.

| Parameter | Tier | Typical value | Notes |
|---|---|---|---|
| `T1a_max_up` | Required | 500 | Max time (µs) O-DU sends DL U-Plane before symbol start. Increase for higher latency fronthaul. |
| `T1a_min_up` | Required | 258 | Min time (µs). Must be > fronthaul one-way latency. |
| `T1a_max_cp_dl` | Required | 500 | Max time (µs) O-DU sends DL C-Plane before symbol. |
| `T1a_min_cp_dl` | Required | 285 | Min time (µs) for DL C-Plane. |
| `T2a_max_up` | Required | 500 | Max time (µs) O-RU receives U-Plane before processing. |
| `T2a_min_up` | Required | 25 | Min time (µs). |
| `T2a_max_cp_dl` | Required | 500 | Max time (µs) O-RU receives DL C-Plane. |
| `T2a_min_cp_dl` | Required | 25 | Min time (µs). |
| `Ta3_max` | Required | 500 | Max time (µs) O-RU sends UL U-Plane after symbol end. |
| `Ta3_min` | Required | 25 | Min time (µs). |
| `T4a_max` | Required | 500 | Max time (µs) O-DU receives UL U-Plane. |
| `T4a_min` | Required | 25 | Min time (µs). |

> **Tuning note:** Starting values above are conservative (500 µs windows) suitable for direct-cable or single-switch setups. If you see `[FH] Timing violation` in logs, increase `T1a_max_up` and `T2a_max_up` in 50 µs steps. The Benetel RAN650 datasheet quotes a fronthaul one-way latency of ~100–150 µs for a single cable hop.

**Benetel-specific timing (measured, direct cable):**

| Parameter | RAN650 | RAN550 |
|---|---|---|
| `T1a_max_up` | 430 | 500 |
| `T1a_min_up` | 258 | 285 |
| `T1a_max_cp_dl` | 430 | 500 |
| `T1a_min_cp_dl` | 285 | 285 |
| `Ta3_max` | 300 | 350 |
| `Ta3_min` | 25 | 25 |

---

### 3.2 PTP / Synchronization Configuration

PTP is configured at the **host OS level**, not in the OAI YAML. The YAML only references timing parameters derived from PTP lock quality.

**Required host-side PTP setup:**

```bash
# Install linuxptp
sudo apt install linuxptp

# Configure ptp4l for G.8275.1 telecom profile on fronthaul NIC
# /etc/linuxptp/ptp4l.conf — key settings:
#   network_transport     L2        (eCPRI uses raw Ethernet, not UDP)
#   dataset_comparison    G.8275.x
#   G.8275.defaultDS.localPriority  128
#   domainNumber          24        (G.8275.1 default domain)
#   slaveOnly             1         (O-DU is always a slave, never master)

sudo ptp4l -i <fronthaul_NIC> -f /etc/linuxptp/ptp4l.conf -m

# Verify lock
sudo pmc -u -b 0 'GET CURRENT_DATA_SET'
# Look for: offsetFromMaster < 100ns for good lock
```

**Falcon RX/812/G specific settings:**
- Profile: ITU-T G.8275.1
- `domainNumber`: 24 (G.8275.1 default — verify it matches your Falcon config)
- `priority1`: 128, `priority2`: 128 (Falcon defaults)
- Transport: L2 (Layer 2 multicast, not UDP)
- VLAN: depends on your switch config — check if the Falcon uses a dedicated VLAN for PTP

**In OAI YAML:** No explicit PTP block exists. OAI reads the system clock which must be disciplined by ptp4l + phc2sys before starting nr-softmodem:

```bash
# Sync system clock to PTP hardware clock on fronthaul NIC
sudo phc2sys -s <fronthaul_NIC> -c CLOCK_REALTIME -n 24 -O 0 -m
```

---

### 3.3 Threading for Fronthaul

The fronthaul I/O thread is timing-critical. OAI requires `PARALLEL_RU_L1_TRX_SPLIT` for O-RAN deployments to separate the fronthaul TX/RX threads from L1 processing.

| Config | Suitability |
|---|---|
| `PARALLEL_SINGLE_THREAD` | Not suitable — fronthaul deadlines will be missed |
| `PARALLEL_RU_L1_SPLIT` | Marginal — may work for low-load testing |
| `PARALLEL_RU_L1_TRX_SPLIT` | **Required** for production O-RAN deployment |

---

### 3.4 Cell Configuration for O-RAN

Most `servingCellConfigCommon` parameters are identical to the USRP monolithic config. Key differences:

| Parameter | USRP | O-RAN (Benetel) | Notes |
|---|---|---|---|
| `nb_tx` / `nb_rx` | 1 (SISO) | **4** (4T4R) | Benetel RAN650/RAN550 are 4T4R. |
| `pdsch_AntennaPorts` | 1 | **4** | Must match `nb_tx`. |
| `pusch_AntennaPorts_XP` | 1 | **4** | Must match `nb_rx`. |

> **Note on 4T4R:** Running 4T4R increases PUSCH/PDSCH processing load significantly. Ensure `pusch_proc_threads` is set to at least 8 on the O-DU host.

---

## 4. oairu Emulator Reference

The `oairu` binary ships with OAI and emulates an O-RU. It connects to the O-DU over a real Ethernet interface (or loopback) and processes IQ samples in software.

### 4.1 When to use oairu

- Validating O-DU fronthaul configuration before Benetel hardware arrives
- Testing without PTP synchronization (free-running mode)
- CI/CD pipelines

### 4.2 oairu Configuration

The oairu has its own YAML or command-line configuration. Key parameters:

| Parameter | Notes |
|---|---|
| `oran_cfg.du_addr` | O-DU MAC address (same as `fh_conf.du_addr` in O-DU config) |
| `oran_cfg.ru_addr` | oairu MAC address (source MAC on oairu host NIC) |
| `oran_cfg.mtu_size` | Must match O-DU `fh_conf.mtu_size` |
| Compression | Must match O-DU `ru_config`: both `0` (none) for emulation |
| Interface | Physical NIC or veth pair for loopback testing |

### 4.3 oairu Timing

Without PTP, oairu runs in free-running mode. The O-DU must be configured with relaxed timing windows:

```yaml
# In O-DU fh_conf — relaxed for emulator (no PTP, higher jitter)
T1a_max_up: 1000
T1a_min_up: 50
Ta3_max: 1000
Ta3_min: 25
```

---

## 5. Parameter Dependencies and Compliance

All Groups A–I from the base reference apply. Additional fronthaul-specific groups:

### Group M — Compression Consistency (HARD: IQ samples corrupted)

```
O-DU ru_config.dl_compr_meth        ←→  O-RU DL compression config
O-DU ru_config.dl_compr_iq_bitwidth ←→  O-RU DL IQ bitwidth
O-DU ru_config.ul_compr_meth        ←→  O-RU UL compression config
O-DU ru_config.ul_compr_iq_bitwidth ←→  O-RU UL IQ bitwidth
```

A mismatch causes the O-RU to transmit compressed samples that the O-DU interprets as uncompressed (or vice versa), producing completely wrong IQ data. The radio appears to work (eCPRI frames flow) but no UE can decode the signal. This is the hardest fronthaul bug to diagnose.

### Group N — MAC Address Consistency (HARD: eCPRI frames dropped)

```
O-DU fh_conf.du_addr  =  actual MAC of O-DU fronthaul NIC
O-DU fh_conf.ru_addr  =  actual MAC of O-RU fronthaul port
```

eCPRI uses raw Layer 2 Ethernet — there is no IP routing. If either MAC is wrong, frames are silently dropped at the switch or NIC. Verify with `tcpdump -ni <fh_iface> ether proto 0xAEFE` (eCPRI EtherType).

### Group O — Antenna Count Consistency (HARD: PHY dimension mismatch)

```
nb_tx             =  pdsch_AntennaPorts
nb_rx             =  pusch_AntennaPorts_XP
Both              =  O-RU antenna count (4 for Benetel RAN650/RAN550)
```

### Group P — PTP Lock Before Start (SOFT: timing violations, failed RACH)

```
ptp4l must be locked (offsetFromMaster < 500ns) before nr-softmodem starts
phc2sys must be syncing system clock to PTP hardware clock
```

OAI does not check PTP lock at startup — it will start regardless and produce `[FH] Timing violation` warnings until lock is achieved. Best practice: wait for `ptp4l` to report `LOCKED` before launching nr-softmodem.

### Group Q — MTU Consistency (SOFT: eCPRI fragmentation, performance loss)

```
O-DU fh_conf.mtu_size  =  fronthaul NIC MTU  =  switch port MTU
```

If the NIC MTU is smaller than `mtu_size`, eCPRI frames are fragmented or silently dropped. Set:
```bash
sudo ip link set <fh_iface> mtu 9000
```

---

## 6. Common Errors

### 6.1 `[FH] Timing violation`

**Symptom:**
```
[FH] Timing violation: T1a window exceeded for symbol X
[FH] slot_offset=Y exceeds T1a_max_up=Z
```

| Cause | Fix |
|---|---|
| Fronthaul latency higher than `T1a_min_up` | Increase `T1a_max_up` and `T1a_min_up` in 50 µs steps |
| PTP not locked or drifting | Check `ptp4l` output for `LOCKED` state; check `offsetFromMaster` |
| `PARALLEL_RU_L1_SPLIT` instead of `TRX_SPLIT` | Switch to `PARALLEL_RU_L1_TRX_SPLIT` |
| Fronthaul NIC IRQs not isolated | Pin NIC IRQs to dedicated cores away from L1 thread pool |
| MTU mismatch causing fragmentation | Set NIC and switch MTU to 9000 |

**Log levels:**
```yaml
hw_log_level: debug    # Shows FH timing events
```

### 6.2 No eCPRI Traffic (Radio Silent)

**Symptom:** O-DU starts, no `[FH]` errors, but UEs cannot find the cell.

| Cause | Fix |
|---|---|
| Wrong `du_addr` or `ru_addr` MAC | Verify both MACs with `ip link show` and O-RU label |
| Fronthaul NIC not up | `ip link set <fh_iface> up` |
| Switch blocking Layer 2 multicast | Enable L2 multicast forwarding on switch |
| VLAN mismatch | Check if O-RU expects tagged frames; set `vlan_tag_strip` |
| eCPRI EtherType filtered | `tcpdump -ni <fh_iface> ether proto 0xAEFE` — if no frames, check switch ACLs |

### 6.3 IQ Corruption / UE Sees Cell But Cannot Decode

**Symptom:** UE detects SSB but RACH fails; MCS is stuck at low values; BLER is very high.

| Cause | Fix |
|---|---|
| Compression mismatch (Group M) | Verify `dl/ul_compr_meth` and `dl/ul_compr_iq_bitwidth` match O-RU config |
| BFP bias compensation needed | Try `dl_compr_bias_compensation: 1` |
| O-RU not applying beamforming weights | Check O-RU vendor config for beam management |
| PTP phase error too large | `pmc -u -b 0 'GET CURRENT_DATA_SET'` — `offsetFromMaster` must be < 1 µs |

### 6.4 `local_rf: yes` Crash on O-DU Host

**Symptom:**
```
[HW] ERROR: cannot open device: addr=...
[OAI] Exiting due to RF failure
```

**Cause:** `local_rf: yes` in the RU config when no USRP is attached to the O-DU host.

**Fix:** Set `local_rf: no` in the O-DU `RUs` block.

### 6.5 Benetel O-RU Not Responding

**Symptom:** O-DU starts, sends eCPRI C-Plane, but receives no U-Plane responses from the O-RU.

| Cause | Fix |
|---|---|
| O-RU not powered/booted | Wait for Benetel boot LED sequence to complete (~2 min) |
| O-RU PTP not locked | Check Benetel status page; PTP must lock before O-RU transmits |
| Wrong O-RU MAC in `ru_addr` | Verify MAC on Benetel label or `arping -I <fh_iface> <benetel_mgmt_ip>` |
| O-RU band/frequency mismatch | Benetel must be configured for same ARFCN as O-DU |
| Compression negotiation failed | Check O-RU vendor logs for capability mismatch |

---

## 7. Host Preparation Checklist

```bash
# 1. Fronthaul NIC: jumbo frames, no offloading
sudo ip link set <fh_iface> mtu 9000
sudo ethtool -K <fh_iface> gro off lro off

# 2. PTP: lock before starting OAI
sudo ptp4l -i <fh_iface> -f /etc/linuxptp/ptp4l.conf -m &
sudo phc2sys -s <fh_iface> -c CLOCK_REALTIME -n 24 -O 0 -m &
# Wait for: "ptp4l[...]: LOCKED to remote master"
# Check:    pmc -u -b 0 'GET CURRENT_DATA_SET' | grep offsetFromMaster

# 3. CPU governor
sudo cpupower frequency-set -g performance

# 4. Disable C-states
sudo cpupower idle-set -D 0

# 5. IRQ affinity for fronthaul NIC
# Pin NIC IRQs to isolated cores (NOT the same cores as --thread-pool)
# Example: NIC IRQs on cores 8-11, OAI thread-pool on cores 0-7

# 6. Verify eCPRI EtherType forwarding on switch
# (vendor-specific — ensure 0xAEFE is not filtered)
```

---

## 8. Launch Command

```bash
sudo ./nr-softmodem \
  -O odu.yaml \
  --sa \
  --thread-pool 0,2,4,6 \
  --reorder-thread-disable 1
  # Note: no --usrp-tx-thread-config (that flag is USRP-specific)
  # Note: no --usrp-tx-thread-config 1 — fronthaul I/O is managed by fh_conf.io_core
```
