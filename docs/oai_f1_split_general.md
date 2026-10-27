# OAI gNB F1 Split Configuration Reference

> **Scope:** CU (combined CU-CP+CU-UP) + DU split over F1 interface.  
> **Stack:** OAI `develop` branch, YAML config format, SA 5G NR.  
> **Not covered:** E1 interface (CU-CP/CU-UP separation), O-RU fronthaul (see Batch 2), handover (see Batch 3).  
> **E1 note:** As of OAI `develop` mid-2025, E1 is partially implemented. Bearer setup works; some handover and PDU session modification procedures have known gaps. Combined CU-CP+CU-UP avoids these gaps entirely.

---

## 1. Architecture Overview

```
                    ┌─────────────────────────────┐
                    │           Core Network       │
                    │   AMF (N2/NGAP)   UPF (N3)  │
                    └────────┬──────────────┬──────┘
                             │ N2 (SCTP)    │ N3 (GTP-U)
                    ┌────────┴──────────────┴──────┐
                    │       CU (combined)           │
                    │   CU-CP + CU-UP on one host   │
                    │   Runs: nr-softmodem --gNB    │
                    └────────────┬─────────────────┘
                                 │ F1 (SCTP)
                                 │ F1-C: port 38472 (F1AP)
                                 │ F1-U: port 2152  (GTP-U)
                    ┌────────────┴─────────────────┐
                    │              DU               │
                    │   Runs: nr-softmodem --DU     │
                    │   Local RF: USRP X310         │
                    └──────────────────────────────┘
```

**Key difference from monolithic gNB:**

| Aspect | Monolithic | CU+DU split |
|---|---|---|
| Process | One `nr-softmodem` | Two `nr-softmodem` instances |
| RRC/PDCP | Same host as RF | CU host (separate from RF) |
| F1AP | Not used | SCTP on port 38472 |
| F1-U | Not used | GTP-U on port 2152 (separate tunnel from N3) |
| Config files | One YAML | One CU YAML + one DU YAML |
| AMF connection | gNB connects | CU connects (DU has no N2) |
| UPF connection | gNB connects | CU connects (DU has no N3) |

---

## 2. Tier Definitions

| Tier | Meaning |
|---|---|
| **Required** | OAI crashes or refuses to start without it. No safe default. |
| **Recommended** | OAI starts without it but behaviour may be wrong or silently broken. |
| **Optional** | Safe default exists. Only set to override. |

---

## 3. CU Configuration Reference

The CU YAML is structurally similar to the monolithic gNB YAML with three key differences:
- `tr_s_preference: f1` in MACRLCs (tells RRC/PDCP to use F1 toward DU)
- `local_rf: no` in RUs (CU has no RF)
- F1AP bind address and DU connection parameters in a new `F1AP` or `GNBCUUPFunction` block

### 3.1 Identity and Core Connectivity

Same as monolithic. See base reference. Key fields:

| Parameter | Tier | Notes |
|---|---|---|
| `gNB_ID` | Required | Must be identical in CU and DU configs. |
| `tracking_area_code` | Required | CU owns N2; must match AMF. DU does not connect to AMF. |
| `plmn_list` | Required | Defined in CU. DU inherits via F1AP `gNB-DU-System-Information`. |
| `nr_cellid` | Required | Defined in CU. Must match DU cell config. |
| `amf_ip_address` | Required | CU only. DU has no AMF connection. |
| `NETWORK_INTERFACES` for N2/N3 | Recommended | CU only. Set explicitly — multi-homed host risk. |

### 3.2 F1 Interface (CU side)

New block not present in monolithic config.

| Parameter | Tier | Default | Notes |
|---|---|---|---|
| `F1AP.CU_F1AP_IP_ADDRESS` | Required | — | IP on which CU listens for F1AP (SCTP). DU will connect to this. |
| `F1AP.CU_PORT` | Optional | 38472 | F1AP SCTP port. 38472 per 3GPP TS 38.472. Change only if port conflicts. |
| `MACRLCs.[0].tr_s_preference` | Required | — | Must be `f1` (not `local_L1`). Tells MAC to use F1 transport to DU. |
| `MACRLCs.[0].local_s_address` | Required | — | CU-side IP for F1-U GTP-U tunnel (user plane toward DU). |
| `MACRLCs.[0].remote_s_address` | Recommended | — | DU-side IP for F1-U. Can be left blank if DU advertises it in F1AP Setup. |
| `MACRLCs.[0].local_s_portc` | Optional | 500 | F1-C control port on CU side. |
| `MACRLCs.[0].local_s_portd` | Optional | 2152 | F1-U data port on CU side. |
| `MACRLCs.[0].remote_s_portc` | Optional | 500 | F1-C control port on DU side. |
| `MACRLCs.[0].remote_s_portd` | Optional | 2152 | F1-U data port on DU side. |

### 3.3 RUs on CU

| Parameter | Tier | Value | Notes |
|---|---|---|---|
| `local_rf` | Required | `no` | CU has no RF. RF lives on the DU. Without this, OAI tries to open a radio device on the CU host and crashes. |

### 3.4 L1s on CU

| Parameter | Tier | Notes |
|---|---|---|
| `tr_n_preference` | Required | Must be `local_mac`. L1 on CU side is a stub — actual L1 runs on DU. |

### 3.5 Threading on CU

`THREAD_STRUCT` is **Optional** on the CU — the CU does not run real-time PHY processing. `PARALLEL_SINGLE_THREAD` is acceptable here.

---

## 4. DU Configuration Reference

The DU YAML contains the RF and cell-physical configuration. It does NOT contain AMF address, N2/N3 interfaces, or RRC parameters (those are owned by the CU).

### 4.1 F1 Interface (DU side)

| Parameter | Tier | Default | Notes |
|---|---|---|---|
| `MACRLCs.[0].tr_n_preference` | Required | — | Must be `f1`. |
| `MACRLCs.[0].local_n_address` | Required | — | DU-side IP for F1-C SCTP and F1-U GTP-U. |
| `MACRLCs.[0].remote_n_address` | Required | — | CU-side IP (must match `F1AP.CU_F1AP_IP_ADDRESS`). |
| `MACRLCs.[0].local_n_portc` | Optional | 500 | DU-side F1-C port. |
| `MACRLCs.[0].local_n_portd` | Optional | 2152 | DU-side F1-U port. |
| `MACRLCs.[0].remote_n_portc` | Optional | 500 | CU-side F1-C port. |
| `MACRLCs.[0].remote_n_portd` | Optional | 2152 | CU-side F1-U port. Must match CU `local_s_portd`. |

### 4.2 Cell Physical Configuration (DU side)

All `servingCellConfigCommon` parameters live in the DU config. Same rules as monolithic apply — Groups A–I from the base reference all apply here. The DU broadcasts SIB1 and handles RACH, so all RACH and SSB parameters must be present and consistent.

| Parameter | Tier | Notes |
|---|---|---|
| `physCellId` | Required | Physical cell identity. Must be unique per cell. |
| `absoluteFrequencySSB` | Required | DU broadcasts SSB. |
| `dl_carrierBandwidth` | Required | Group A: must match locationAndBandwidth. |
| `ra_ResponseWindow` | Recommended | Default 4 too tight for USRP OTA — use 10. |
| All other `servingCellConfigCommon` fields | Same tiers as monolithic | — |

### 4.3 gNB Identity in DU

| Parameter | Tier | Notes |
|---|---|---|
| `gNB_ID` | Required | Must be identical to CU config. |
| `gNB_DU_ID` | Required | **New in split mode.** Unique identifier for this DU within the gNB. Range: 0–2^36-1. If you have one DU, use 1. |
| `gNB_DU_name` | Optional | Human-readable DU name. |
| `nr_cellid` | Required | Must match CU config. |
| `plmn_list` | Required | Must match CU config exactly. |

> **Note:** `tracking_area_code` and `amf_ip_address` are **absent** from the DU config. The DU does not connect to the AMF. All core network connectivity is on the CU.

### 4.4 RUs on DU

Same as monolithic. The USRP X310 is attached to the DU host.

| Parameter | Tier | Notes |
|---|---|---|
| `local_rf` | Required | `yes` — RF is local to DU. |
| `nb_tx` / `nb_rx` | Required | — |
| `max_rxgain` | Required | Same tuning as monolithic — 70–80 dB for X310 SBX Band 78. |
| `att_tx` / `att_rx` | Optional | 0 for OTA. |
| `sdr_addrs` | Required | Include `clock_source` and `time_source` explicitly. |

### 4.5 Threading on DU

`THREAD_STRUCT` is **Required (Recommended tier)** on the DU — the DU runs the real-time PHY. Same rules as monolithic:

| Config | Use when |
|---|---|
| `PARALLEL_SINGLE_THREAD` | RFsim only |
| `PARALLEL_RU_L1_SPLIT` | OTA with X310 — minimum viable |
| `PARALLEL_RU_L1_TRX_SPLIT` | OTA under heavy load |

### 4.6 L1s on DU

Same as monolithic. `pusch_proc_threads` matters here — the DU runs LDPC decoding.

---

## 5. Launch Order

**Critical:** CU must be running and listening on F1AP before DU starts. DU initiates the F1 Setup procedure.

```bash
# Terminal 1 — start CU first
sudo ./nr-softmodem -O cu.yaml --sa

# Terminal 2 — start DU after CU is up and listening
sudo ./nr-softmodem -O du.yaml --sa \
  --usrp-tx-thread-config 1 \
  --thread-pool 0,2,4,6
```

Verify CU is ready before starting DU:
```bash
# CU should be listening on F1AP port
ss -tnlp | grep 38472
```

---

## 6. F1 Setup Procedure

When the DU starts, it initiates F1AP Setup:

```
DU                          CU
 |                           |
 |--- F1SetupRequest ------->|   DU sends: gNB-DU-ID, cell list, SIBs
 |                           |   CU validates: gNB_ID, PLMN, nr_cellid
 |<-- F1SetupResponse -------|   CU sends: RRC version, cell activation
 |                           |
 |  [Cell is now active]     |
```

If F1 Setup fails, check:
- `gNB_ID` matches between CU and DU configs
- `nr_cellid` matches
- `plmn_list` matches exactly (mcc, mnc, sst, sd)
- CU F1AP port is reachable from DU host (`nc -zv <CU_IP> 38472`)
- SCTP is loaded: `lsmod | grep sctp`

---

## 7. Parameter Dependencies and Compliance

All Groups A–I from the base reference apply to the DU config (where the cell parameters live). Additional F1-specific dependencies:

### Group J — F1 Address Consistency (HARD: F1 Setup fails or GTP-U misrouted)

```
CU F1AP.CU_F1AP_IP_ADDRESS      ←→  DU MACRLCs.remote_n_address
CU MACRLCs.local_s_portd         ←→  DU MACRLCs.remote_n_portd
CU MACRLCs.remote_s_portd        ←→  DU MACRLCs.local_n_portd
CU MACRLCs.local_s_address       ←→  DU MACRLCs.remote_n_address (for F1-U GTP-U)
```

A mismatch here means the F1AP SCTP connects (since SCTP is connection-oriented) but F1-U GTP-U packets are sent to the wrong address, causing silent DRB data loss while the control plane appears healthy.

### Group K — gNB_ID Consistency (HARD: F1 Setup rejected by CU)

```
CU gNB_ID  =  DU gNB_ID
CU nr_cellid  =  DU nr_cellid
CU plmn_list  =  DU plmn_list (exact match: mcc, mnc, mnc_length, sst, sd)
```

The CU will reject F1SetupRequest if gNB_ID or nr_cellid does not match what the CU expects.

### Group L — Transport Preference Chain in Split Mode (HARD: crash)

```
CU:
  MACRLCs.tr_s_preference = "f1"          ← not "local_L1"
  MACRLCs.tr_n_preference = "local_RRC"
  L1s.tr_n_preference     = "local_mac"   ← stub L1 on CU

DU:
  MACRLCs.tr_s_preference = "local_L1"    ← DU has local RF
  MACRLCs.tr_n_preference = "f1"          ← not "local_RRC"
  L1s.tr_n_preference     = "local_mac"
```

This is the most common misconfiguration when migrating from monolithic to split. Mixing `local_*` and `f1` on the wrong side crashes OAI at startup.

---

## 8. Common Errors

### 8.1 F1 Setup Timeout

**Symptom:**
```
[F1AP] F1 Setup Request sent, waiting for response...
[F1AP] F1 Setup timeout — no response from CU
```

| Cause | Fix |
|---|---|
| CU not started yet | Start CU first, verify `ss -tnlp | grep 38472` |
| Wrong CU IP in DU config | Check `remote_n_address` matches CU host IP |
| SCTP not loaded | `sudo modprobe sctp` |
| Firewall blocking port 38472 | `sudo ufw allow 38472/sctp` or disable ufw |
| gNB_ID mismatch | Must be identical in both configs |

**Log levels:**
```yaml
# DU config
log_config:
  f1ap_log_level: debug
```

### 8.2 F1 Setup Rejected

**Symptom:**
```
[F1AP] F1SetupFailure received: cause = ...
```

| Cause | Fix |
|---|---|
| `nr_cellid` mismatch | Must match exactly in CU and DU |
| PLMN mismatch | `plmn_list` must be identical |
| CU already has a DU with same `gNB_DU_ID` | Use unique `gNB_DU_ID` per DU |

### 8.3 UE Attaches but No Data (Silent DRB failure)

**Symptom:** UE registers, PDU session established, but no user-plane traffic. No errors in logs.

**Root cause:** F1-U GTP-U misrouting — F1AP (control plane) uses one IP pair, F1-U (user plane) uses another. If `local_s_address` / `remote_s_address` are wrong, the tunnel is built toward the wrong endpoint.

| Fix |
|---|
| Verify `CU.MACRLCs.local_s_address` is reachable from DU host |
| Verify `DU.MACRLCs.local_n_address` is reachable from CU host |
| Run `tcpdump -ni any udp port 2152` on both hosts simultaneously |
| Check for TEID mismatch: `[GTPU] unknown teid` on either side |

**Log levels:**
```yaml
ngap_log_level: debug
f1ap_log_level: debug
```

### 8.4 `tr_s_preference`/`tr_n_preference` Crash

**Symptom:** OAI crashes at startup with transport mismatch assertion.

```
[MAC] ERROR: incompatible transport preferences
```

**Fix:** See Group L in Section 7. The most common mistake is copying the monolithic config and only changing `tr_s_preference` on one side.

### 8.5 DU Real-Time Failures (`L` flood)

Same causes and fixes as monolithic — see base reference Section 3.6. The DU is the only side that runs real-time PHY. The CU has no timing constraints.

---

## 9. Log Levels by Diagnostic Goal

| Goal | CU | DU |
|---|---|---|
| F1 Setup debugging | `f1ap_log_level: debug` | `f1ap_log_level: debug` |
| UE registration | `ngap_log_level: debug`, `rrc_log_level: debug` | `mac_log_level: debug` |
| User-plane data | `ngap_log_level: debug` | `pdcp_log_level: debug` |
| RACH/Msg3 failures | not applicable | `mac_log_level: debug`, `phy_log_level: debug` |
| UHD/timing | not applicable | `hw_log_level: debug` |

---

## 10. Launch Command Reference

**CU:**
```bash
sudo ./nr-softmodem \
  -O cu.yaml \
  --sa
# No --usrp-tx-thread-config or --thread-pool needed on CU
```

**DU:**
```bash
sudo ./nr-softmodem \
  -O du.yaml \
  --sa \
  --usrp-tx-thread-config 1 \
  --thread-pool 0,2,4,6
```

**Pre-flight:**
```bash
# 1. SCTP loaded
lsmod | grep sctp || sudo modprobe sctp

# 2. CU listening (run after CU starts, before DU starts)
ss -tnlp | grep 38472

# 3. DU can reach CU F1AP port
nc -zv <CU_F1AP_IP> 38472

# 4. USRP reachable from DU host
uhd_find_devices --args "addr=<USRP_IP>"

# 5. CN containers up and reachable from CU host
ping -c 3 <AMF_IP>
```
