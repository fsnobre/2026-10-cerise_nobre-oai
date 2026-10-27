# OAI gNB F1 Split — Testbed Reference

> **Testbed:** Band 78 · 40 MHz · 30 kHz SCS · 106 PRB · USRP X310 on DU  
> **Hosts:** WS-gnb1 (CU) · WS-gnb2 (DU) · WS-CN (Core Network)  
> **Stack:** OAI `develop` + FlexRIC nearRT-RIC  
> **Relation to monolithic config:** This document assumes you have a working monolithic gNB YAML (see testbed reference). It focuses on what changes in the split.

---

## 1. Testbed Topology

```
WS-CN (192.168.70.x)
  ├── oai-amf  (192.168.70.132)
  ├── oai-smf
  ├── oai-upf
  └── demo-oai bridge

WS-gnb1 (CU host)
  ├── demo-oai NIC: 192.168.70.129   ← N2 toward AMF, N3 toward UPF
  └── data NIC:     192.168.80.1     ← F1 toward DU (WS-gnb2)

WS-gnb2 (DU host)
  ├── data NIC:     192.168.80.2     ← F1 toward CU (WS-gnb1)
  └── USRP 10GbE:   192.168.40.2    ← X310 radio
```

> Adjust these IPs to match your actual interface addresses. The key constraint is that the F1 link (192.168.80.x) must be a direct or routed path between WS-gnb1 and WS-gnb2 with SCTP allowed.

---

## 2. What Changes vs. Monolithic

| Config area | Monolithic (WS-gnb1) | Split CU (WS-gnb1) | Split DU (WS-gnb2) |
|---|---|---|---|
| AMF address | present | present | **absent** |
| N2/N3 interfaces | present | present | **absent** |
| `tr_s_preference` | `local_L1` | **`f1`** | `local_L1` |
| `tr_n_preference` | `local_RRC` | `local_RRC` | **`f1`** |
| `local_rf` | `yes` | **`no`** | `yes` |
| `sdr_addrs` | present | **absent** | present |
| `THREAD_STRUCT` | `PARALLEL_RU_L1_SPLIT` | not needed | `PARALLEL_RU_L1_SPLIT` |
| `gNB_DU_ID` | absent | absent | **required** |
| F1 address params | absent | **required** | **required** |
| `servingCellConfigCommon` | present | present (RRC) | present (PHY) |

---

## 3. Fixed Values (same as monolithic, both CU and DU)

These do not change from your monolithic config:

| Parameter | Value |
|---|---|
| `gNB_ID` | `0xe00` |
| `nr_cellid` | `12345678` |
| `tracking_area_code` | `1` |
| `mcc` / `mnc` | `001` / `01` |
| `dl_carrierBandwidth` / `ul_carrierBandwidth` | `106` |
| `initialDL/ULBWPlocationAndBandwidth` | `28875` |
| `absoluteFrequencySSB` | `640704` |
| `dl_absoluteFrequencyPointA` | `639996` |
| `dl/ul_subcarrierSpacing` | `1` (30 kHz) |
| `ssb_PositionsInBurst_PR` | `2` |
| `ra_ResponseWindow` | `10` |
| `prach_ConfigurationIndex` | `98` |

---

## 4. CU-Specific Configuration

### 4.1 F1 Parameters (WS-gnb1)

```yaml
# In MACRLCs block:
tr_s_preference: f1                    # was local_L1 in monolithic
local_s_address: 192.168.80.1          # CU-side F1-U GTP-U IP (data NIC)
remote_s_address: 192.168.80.2         # DU-side F1-U GTP-U IP
local_s_portc: 500                     # F1-C CU port
local_s_portd: 2152                    # F1-U CU port
remote_s_portc: 500                    # F1-C DU port
remote_s_portd: 2152                   # F1-U DU port

# F1AP block (top-level or under gNBs):
F1AP:
  CU_F1AP_IP_ADDRESS: 192.168.80.1     # CU listens here for DU F1AP connection
  CU_PORT: 38472                       # F1AP SCTP port (3GPP standard)
```

### 4.2 RU on CU

```yaml
RUs:
  - local_rf: no        # CU has no RF — RF is on DU
    nb_tx: 1
    nb_rx: 1
    att_tx: 0
    att_rx: 0
    bands: [78]
    max_pdschReferenceSignalPower: -27
    max_rxgain: 75
    eNB_instances: [0]
    # No sdr_addrs — no USRP on CU host
```

### 4.3 Threading on CU

```yaml
# THREAD_STRUCT is not needed on CU — no real-time PHY here.
# If present, PARALLEL_SINGLE_THREAD is fine.
THREAD_STRUCT:
  - parallel_config: PARALLEL_SINGLE_THREAD
    worker_config: WORKER_ENABLE
```

### 4.4 ORANSlice on CU

```yaml
# SliceConf stays on the CU — the NVS scheduler runs in the MAC,
# which in split mode runs on the CU side.
MACRLCs:
  - tr_s_preference: f1
    tr_n_preference: local_RRC
    pusch_TargetSNRx10: 200
    pucch_TargetSNRx10: 200
    ul_prbblack_SNR_threshold: 10
    ulsch_max_frame_inactivity: 5
    SliceConf: "/home/nobre/oranslice2/ORANSlice/rrmPolicy.json"
```

---

## 5. DU-Specific Configuration

### 5.1 F1 Parameters (WS-gnb2)

```yaml
# In MACRLCs block:
tr_n_preference: f1                    # was local_RRC in monolithic
local_n_address: 192.168.80.2          # DU-side F1 IP
remote_n_address: 192.168.80.1         # CU-side F1 IP (must match CU F1AP address)
local_n_portc: 500
local_n_portd: 2152
remote_n_portc: 500
remote_n_portd: 2152
```

### 5.2 DU Identity Fields

```yaml
gNBs:
  - gNB_ID: 0xe00            # must match CU
    gNB_DU_ID: 1             # unique DU identifier — required, absent in monolithic
    gNB_DU_name: du-ws-gnb2  # optional but useful for multi-DU scenarios
    nr_cellid: 12345678       # must match CU
    # tracking_area_code: ABSENT — DU does not connect to AMF
    plmn_list:                # must match CU exactly
      - mcc: 001
        mnc: 01
        mnc_length: 2
        snssaiList:
          - sst: 1
            sd: 0x00001
          - sst: 1
            sd: 0x000002
```

### 5.3 RF / USRP on DU

Identical to monolithic. X310 is on WS-gnb2:

```yaml
RUs:
  - local_rf: yes
    nb_tx: 1
    nb_rx: 1
    att_tx: 0
    att_rx: 0
    bands: [78]
    max_pdschReferenceSignalPower: -27
    max_rxgain: 75
    eNB_instances: [0]
    sdr_addrs: "addr=192.168.40.2,clock_source=internal,time_source=internal,send_frame_size=8000,recv_frame_size=8000"
```

### 5.4 Threading on DU

```yaml
# Required for OTA — same as monolithic
THREAD_STRUCT:
  - parallel_config: PARALLEL_RU_L1_SPLIT
    worker_config: WORKER_ENABLE
```

---

## 6. F1 Address Dependency Table (Group J)

Every address pair must be consistent. Use this as a checklist:

| CU parameter | Value | DU parameter | Value | Must match? |
|---|---|---|---|---|
| `F1AP.CU_F1AP_IP_ADDRESS` | `192.168.80.1` | `MACRLCs.remote_n_address` | `192.168.80.1` | **Yes — exact** |
| `MACRLCs.local_s_address` | `192.168.80.1` | `MACRLCs.remote_n_address` | `192.168.80.1` | **Yes — exact** |
| `MACRLCs.remote_s_address` | `192.168.80.2` | `MACRLCs.local_n_address` | `192.168.80.2` | **Yes — exact** |
| `MACRLCs.local_s_portd` | `2152` | `MACRLCs.remote_n_portd` | `2152` | **Yes** |
| `MACRLCs.remote_s_portd` | `2152` | `MACRLCs.local_n_portd` | `2152` | **Yes** |
| `F1AP.CU_PORT` | `38472` | (DU connects to this port) | `38472` | **Yes** |

---

## 7. FlexRIC in Split Mode

FlexRIC connects to the CU via E2, not the DU. The E2 agent runs in the CU process.

```yaml
# In CU config — same as monolithic gNB
# The E2 agent configuration (if present in your ORANSlice build) stays on the CU.
# WS-FlexRIC connects to WS-gnb1 (CU), not WS-gnb2 (DU).
```

The xApp's slice commands affect the NVS scheduler on the CU. Since F1 carries MAC PDUs between CU and DU, the scheduling decisions made by the NVS scheduler on the CU are enforced transparently — the DU sees the resulting grant allocations without needing to know about slicing.

---

## 8. Errors Specific to This Testbed

### 8.1 F1 SCTP Not Loading on Ubuntu 24.04

**Symptom:**
```
[F1AP] sctp_bindx failed: Protocol not available
```

Ubuntu 24.04 ships with SCTP as a loadable module that is not loaded by default.

```bash
# Load now
sudo modprobe sctp

# Persist across reboots
echo sctp | sudo tee /etc/modules-load.d/sctp.conf
```

### 8.2 F1-U GTP-U Port Conflict with N3

Both F1-U and N3 use GTP-U on port 2152. On a workstation where both CU and core network containers run (or where gNB and CN share a host), there can be a port conflict.

**Fix:** Use different interfaces for F1-U and N3, or use the `GNB_PORT_FOR_S1U` to offset N3. In your testbed this is not an issue since CU (WS-gnb1) and CN (WS-CN) are on separate hosts.

### 8.3 `gNB_DU_ID` Not Set

**Symptom:**
```
[F1AP] F1SetupRequest missing mandatory IE: gNB-DU-ID
```

OAI crashes or sends a malformed F1SetupRequest if `gNB_DU_ID` is absent from the DU config. This field has no default and is easy to miss when migrating from monolithic.

### 8.4 SliceConf on Wrong Host

If `SliceConf` is set in the DU config instead of the CU config, the NVS scheduler is not activated (scheduler runs on CU). The xApp will connect to FlexRIC, complete the E2 cycle, but PRB allocation will not change.

---

## 9. Launch Sequence for This Testbed

```bash
# Step 1: WS-CN — verify CN is up
docker ps | grep -E "oai-amf|oai-smf|oai-upf"

# Step 2: WS-gnb1 — load SCTP, start CU
sudo modprobe sctp
cd ~/ORANSlice/oai_ran/cmake_targets/ran_build/build
sudo ./nr-softmodem -O /path/to/cu.yaml --sa

# Wait for: "[F1AP] F1AP: Waiting for DU connection on 192.168.80.1:38472"

# Step 3: WS-gnb2 — start DU
sudo modprobe sctp
cd ~/ORANSlice/oai_ran/cmake_targets/ran_build/build
sudo ./nr-softmodem -O /path/to/du.yaml --sa \
  --usrp-tx-thread-config 1 \
  --thread-pool 0,2,4,6

# Wait for: "[F1AP] F1 Setup Response received" on DU
#           "[F1AP] DU connected: gNB-DU-ID=1" on CU

# Step 4: WS-FlexRIC — start RIC and xApps (same as monolithic)
```

---

## 10. Pre-flight Checklist

```bash
# On WS-gnb1 (CU host):
lsmod | grep sctp                          # SCTP loaded
ping -c 3 192.168.70.132                   # AMF reachable
ping -c 3 192.168.80.2                     # DU host reachable
ip addr show | grep 192.168.80.1           # F1 interface has correct IP

# On WS-gnb2 (DU host):
lsmod | grep sctp                          # SCTP loaded
uhd_find_devices --args "addr=192.168.40.2"  # USRP reachable
ping -c 3 192.168.80.1                     # CU host reachable
nc -zv 192.168.80.1 38472                  # F1AP port open on CU (run after CU starts)
benchmark_rate --args "addr=192.168.40.2" \
  --rx_rate 46.08e6 --tx_rate 46.08e6 --duration 10  # USRP sustained throughput
sudo cpupower frequency-set -g performance  # CPU governor
```
