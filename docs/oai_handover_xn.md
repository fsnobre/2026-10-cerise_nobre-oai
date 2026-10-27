# OAI Inter-gNB Xn Handover — Configuration and Signaling Reference

> **Scope:** Handover between two separate gNB processes over the Xn interface (direct gNB-to-gNB signaling, no AMF involvement in the handover decision). Monolithic gNB only (both WS-gnb1 and WS-gnb2).  
> **Trigger:** A3 event on source gNB → XnAP HandoverRequest to target gNB.  
> **Fallback:** If Xn fails mid-handover, AMF-mediated N2 fallback — documented in Section 7.

---

## 1. Architecture

```
WS-gnb1 (gNB-1, source)          WS-gnb2 (gNB-2, target)
  physCellId=0                      physCellId=1
  gNB_ID=0xe00                      gNB_ID=0xe01
        │                                 │
        │◄────── Xn-AP (SCTP) ───────────►│
        │        port 38422               │
        │                                 │
        │            AMF (WS-CN)          │
        └──── N2 ────────────────── N2 ──►│
                  (path switch only)
```

**Key difference from intra-gNB:** The source gNB sends a `HandoverRequest` to the target gNB over Xn **before** commanding the UE to handover. The target gNB prepares resources and responds with `HandoverRequestAck` containing a `RRCReconfiguration` container to forward to the UE.

---

## 2. New Configuration Block: `gNB_XnAPConfig`

This block is absent in the monolithic base config. It must be added to both gNBs.

| Parameter | Tier | Notes |
|---|---|---|
| `gNB_XnAPConfig` | Required | Top-level block. Without it, Xn is disabled and inter-gNB handover falls back to N2. |
| `gNB_XnAPConfig.gNB_IP_address` | Required | List of **peer** gNB IP addresses for Xn SCTP. Each gNB lists the other's IP here. |
| `gNB_XnAPConfig.gNB_ID` | Required | List of **peer** gNB IDs. Must match the other gNB's `gNB_ID`. |
| `gNB_XnAPConfig.SCTP_INSTREAMS` | Optional | Default 2. |
| `gNB_XnAPConfig.SCTP_OUTSTREAMS` | Optional | Default 2. |
| `gNB_XnAPConfig.sctp_port` | Optional | Default 38422. XnAP SCTP port per 3GPP TS 38.422. |

**Example — WS-gnb1 config:**
```yaml
gNB_XnAPConfig:
  gNB_IP_address:           # Peer gNB IPs (WS-gnb2 addresses)
    - ipv4: 192.168.70.130  # WS-gnb2 N2 interface IP (or dedicated Xn NIC if available)
  gNB_ID: [0xe01]           # Peer gNB ID (WS-gnb2 gNB_ID)
  SCTP_INSTREAMS: 2
  SCTP_OUTSTREAMS: 2
```

**Example — WS-gnb2 config:**
```yaml
gNB_XnAPConfig:
  gNB_IP_address:
    - ipv4: 192.168.70.129  # WS-gnb1 N2 interface IP
  gNB_ID: [0xe00]           # WS-gnb1 gNB_ID
  SCTP_INSTREAMS: 2
  SCTP_OUTSTREAMS: 2
```

---

## 3. Measurement Configuration (same as intra-gNB, applied per-gNB)

Each gNB configures measurements independently for its connected UEs. The neighbor cell list on gNB-1 must point to gNB-2's cell, and vice versa.

| Parameter | gNB-1 (WS-gnb1) | gNB-2 (WS-gnb2) |
|---|---|---|
| `do_MeasurementConfig` | `1` | `1` |
| `measurement_events` | `["A3"]` | `["A3"]` |
| `A3_event.a3Offset` | e.g. `4` | e.g. `4` |
| `A3_event.hysteresis` | e.g. `2` | e.g. `2` |
| `A3_event.timeToTrigger` | e.g. `160` | e.g. `160` |
| `neighbour_cell_configuration[0].physCellId` | `1` (gNB-2 cell) | `0` (gNB-1 cell) |
| `neighbour_cell_configuration[0].absoluteFrequencySSB` | gNB-2 SSB ARFCN | gNB-1 SSB ARFCN |

---

## 4. gNB Identity for Xn

For Xn, both gNBs must have **different** `gNB_ID` values. This is the most common first-run mistake when creating the second gNB config by copying the first.

| Parameter | WS-gnb1 | WS-gnb2 |
|---|---|---|
| `gNB_ID` | `0xe00` | **`0xe01`** (must differ) |
| `nr_cellid` | `12345678` | **`12345679`** (must differ) |
| `physCellId` | `0` | **`1`** (must differ) |
| `tracking_area_code` | `1` | `1` (can be same TAC or different) |
| `absoluteFrequencySSB` | gNB-1 frequency | gNB-2 frequency (same band, different or same ARFCN) |

---

## 5. Signaling Flow — Xn Handover (Parameter Level)

```
UE              gNB-1 (Source, WS-gnb1)           gNB-2 (Target, WS-gnb2)          AMF
 │                        │                                  │                        │
 │                        │◄────── XnSetup ────────────────►│                        │
 │                        │   (at startup, SCTP assoc)       │                        │
 │                        │   XnAP port 38422                │  ← gNB_XnAPConfig      │
 │                        │   gNB-1 ID=0xe00                 │  ← gNB_ID              │
 │                        │   gNB-2 ID=0xe01                 │                        │
 │                        │                                  │                        │
 │ ◄── RRCReconfiguration─┤                                  │                        │
 │     [MeasConfig A3]    │                                  │                        │
 │     a3Offset=4         │  ← A3_event.a3Offset             │                        │
 │     hysteresis=2       │  ← A3_event.hysteresis           │                        │
 │     timeToTrigger=160  │  ← A3_event.timeToTrigger        │                        │
 │     neighbor:          │                                  │                        │
 │       physCellId=1     │  ← neighbour_cell_config[0]      │                        │
 │       arfcn=640704     │  ← neighbour absoluteFreqSSB     │                        │
 │                        │                                  │                        │
 │  [UE measures gNB-2]   │                                  │                        │
 │  [A3 condition met     │                                  │                        │
 │   for timeToTrigger]   │                                  │                        │
 │                        │                                  │                        │
 │ ──MeasurementReport───►│                                  │                        │
 │   rsrp(cell0)=X        │                                  │                        │
 │   rsrp(cell1)=X+offset │                                  │                        │
 │                        │                                  │                        │
 │              [gNB-1 decides: HO to gNB-2]                │                        │
 │              [Selects target: gNB_ID=0xe01]               │                        │
 │              [from gNB_XnAPConfig peer list]              │                        │
 │                        │                                  │                        │
 │                        │──── XnAP HandoverRequest ───────►│                        │
 │                        │     sourceToTarget-Container:    │                        │
 │                        │       UE context                 │                        │
 │                        │       RRC handover preparation   │                        │
 │                        │       DRB list                   │                        │
 │                        │     targetCell-ID:               │                        │
 │                        │       physCellId=1               │  ← target physCellId   │
 │                        │     UE-X2AP-ID-Source            │                        │
 │                        │                                  │                        │
 │                        │             [gNB-2 prepares]     │                        │
 │                        │             [admits UE context]  │                        │
 │                        │             [allocates RACH]     │                        │
 │                        │             [prepares RRC cmd]   │                        │
 │                        │                                  │                        │
 │                        │◄─── XnAP HandoverRequestAck ─────│                        │
 │                        │     targetToSource-Container:    │                        │
 │                        │       RRCReconfiguration         │                        │
 │                        │       mobilityControlInfo:       │                        │
 │                        │         targetPhysCellId=1       │                        │
 │                        │         t304 = T304              │  ← T304 config          │
 │                        │         ra-PreambleIndex         │  ← dedicated preamble  │
 │                        │         carrierFreq (gNB-2)      │                        │
 │                        │     admittedBearers              │                        │
 │                        │                                  │                        │
 │ ◄── RRCReconfiguration─┤                                  │                        │
 │     [HandoverCommand]  │                                  │                        │
 │     (forwarded from    │                                  │                        │
 │      gNB-2's Ack)      │                                  │                        │
 │                        │                                  │                        │
 │  [T304 starts]         │                                  │                        │
 │  [Data forwarding:     │                                  │                        │
 │   gNB-1 forwards DL    │──── XnAP SNStatus Transfer ─────►│                        │
 │   PDCP PDUs to gNB-2]  │     PDCP SN / HFN status        │                        │
 │                        │──── DL data forwarding ─────────►│  (GTP-U direct tunnel) │
 │                        │                                  │                        │
 │ ────RACH Msg1 ─────────────────────────────────────────►  │                        │
 │     dedicated preamble │                                  │                        │
 │                        │                                  │                        │
 │ ◄───RACH Msg2 (RAR) ───────────────────────────────────   │                        │
 │                        │                                  │                        │
 │ ────RRCReconfigComplete────────────────────────────────►  │                        │
 │     [T304 stops]       │                                  │                        │
 │                        │                                  │                        │
 │                        │◄─── XnAP UEContextRelease ───────│                        │
 │                        │     (gNB-2 signals success)      │                        │
 │                        │                                  │                        │
 │                        │                                  │──PathSwitchRequest────►│
 │                        │                                  │  newAMF-UE-NGAP-ID     │
 │                        │                                  │  UE context            │
 │                        │                                  │  targetCellInfo        │
 │                        │                                  │                        │
 │                        │                                  │◄─PathSwitchRequestAck──│
 │                        │                                  │  [UPF tunnel updated]  │
 │                        │                                  │                        │
 │                        │◄─── XnAP UEContextRelease ───────│                        │
 │                        │     source UE context            │                        │
 │                        │     release                      │                        │
```

**Critical parameter dependencies in this flow:**

| XnAP Message | IE | Driven by YAML parameter |
|---|---|---|
| XnSetup | `GlobalgNB-ID` | `gNB_ID` (each gNB) |
| XnSetup | SCTP association | `gNB_XnAPConfig.gNB_IP_address` + port 38422 |
| HandoverRequest | `targetCell-ID.physCellId` | target gNB `physCellId` |
| HandoverRequestAck | `t304` in RRC container | target gNB `T304` |
| HandoverRequestAck | `ra-PreambleIndex` | target gNB RACH config |
| SNStatusTransfer | PDCP SN | OAI internal — no direct YAML parameter |
| PathSwitchRequest | `targetCellInfo` | target gNB `nr_cellid`, `plmn_list` |

---

## 6. Dependency Groups for Xn HO

### Group T — Xn Peer Consistency (HARD: XnSetup fails)

```
gNB-1 gNB_XnAPConfig.gNB_IP_address  =  gNB-2 reachable IP
gNB-1 gNB_XnAPConfig.gNB_ID          =  gNB-2 gNB_ID
gNB-2 gNB_XnAPConfig.gNB_IP_address  =  gNB-1 reachable IP
gNB-2 gNB_XnAPConfig.gNB_ID          =  gNB-1 gNB_ID
```

XnSetup is initiated at gNB startup. If either side lists a wrong IP or gNB_ID, the SCTP association forms but XnSetup is rejected, and Xn handover is silently unavailable.

### Group U — gNB Identity Uniqueness (HARD: AMF rejects PathSwitch or Xn Setup)

```
gNB-1 gNB_ID    ≠   gNB-2 gNB_ID
gNB-1 nr_cellid ≠   gNB-2 nr_cellid
gNB-1 physCellId ≠  gNB-2 physCellId
```

Two gNBs with the same `gNB_ID` will cause the AMF to treat them as the same node, merging their UE contexts incorrectly. This is the most common mistake when creating a second gNB config by copying the first.

### Group V — Data Forwarding Reachability (SOFT: data loss during HO)

```
gNB-1 GNB_IPV4_ADDRESS_FOR_NGU  must be reachable from gNB-2
gNB-2 GNB_IPV4_ADDRESS_FOR_NGU  must be reachable from gNB-1
```

During Xn handover, the source gNB (gNB-1) forwards buffered DL data directly to the target gNB (gNB-2) over a temporary GTP-U tunnel. Both N3 addresses must be mutually reachable — not just reachable from the UPF.

---

## 7. N2 Fallback — Xn Failure Scenario

When Xn is configured but fails mid-handover, the gNB falls back to AMF-mediated N2 handover. This section documents when and how this happens.

### 7.1 Failure Scenarios That Trigger N2 Fallback

| Scenario | Trigger | Fallback behavior |
|---|---|---|
| Xn SCTP association lost before HO | `HandoverRequest` cannot be sent | gNB sends `HandoverRequired` to AMF via N2 |
| `HandoverRequest` rejected by target | Target gNB sends `HandoverPreparationFailure` | gNB sends `HandoverRequired` to AMF |
| T304 expiry with no RAC response | UE fails RACH on target | UE initiates RRC re-establishment on any cell |
| Target gNB rejects due to load | `HandoverPreparationFailure.cause = overload` | Source gNB may retry or fall back to N2 |

### 7.2 N2 Fallback Signaling (Abbreviated)

```
gNB-1 (Source)                    AMF                    gNB-2 (Target)
      │                             │                          │
      │── HandoverRequired ────────►│   [Xn failed]            │
      │   targetID: gNB-2           │                          │
      │   cause: Xn-failure         │                          │
      │                             │                          │
      │                             │── HandoverRequest ──────►│
      │                             │   (N2-based)             │
      │                             │                          │
      │                             │◄─ HandoverRequestAck ────│
      │                             │                          │
      │◄─ HandoverCommand ──────────│                          │
      │   (from AMF, not from gNB-2 directly)                  │
      │                             │                          │
      [UE RACH on gNB-2]            │                          │
      │                             │                          │
      │                             │◄─ PathSwitchRequest ─────│
      │                             │── PathSwitchRequestAck ─►│
      │                             │                          │
      │◄─ UEContextRelease ─────────│                          │
```

### 7.3 YAML Parameters Relevant to Fallback

| Parameter | Notes |
|---|---|
| `T_Relocprep` | Xn handover preparation timeout. If target gNB doesn't respond within this time, source triggers fallback. Default in OAI: 1000 ms. |
| `T_RelocOverall` | Overall relocation timer. If HO is not complete within this time, source releases UE. Default: 10000 ms. |

> **Best practice:** Keep Xn configured and let OAI handle fallback automatically. Do not disable Xn "for safety" — having Xn enabled with N2 as fallback gives better HO performance than N2-only because Xn preparation is faster (no AMF round-trip).

---

## 8. Common Errors

### 8.1 XnSetup Fails

**Symptom:**
```
[XnAP] XnSetup failed: cause = ...
[XnAP] No Xn association with peer gNB
```

| Cause | Fix |
|---|---|
| Wrong peer IP in `gNB_XnAPConfig` | Verify peer IP is reachable: `nc -zv <peer_IP> 38422` |
| `gNB_ID` mismatch | Peer `gNB_ID` in config must match actual peer's `gNB_ID` |
| SCTP not loaded | `sudo modprobe sctp` on both hosts |
| Firewall blocking port 38422 | `sudo ufw allow 38422/sctp` |
| Both gNBs started simultaneously | One must be listening before the other connects; add 5s delay |

**Log levels:**
```yaml
# On both gNBs:
ngap_log_level: debug
f1ap_log_level: debug   # XnAP shares logging infrastructure
```

### 8.2 `HandoverRequest` Sent but No Response

| Cause | Fix |
|---|---|
| Target gNB not ready (still starting) | Ensure both gNBs are fully up and XnSetup completed before UEs attach |
| Target gNB `gNB_ID` not in AMF's list | Both gNBs must be registered with AMF via NGSetup before Xn HO |
| Different PLMN on target | `plmn_list` must be identical on both gNBs |

### 8.3 Data Loss After Handover

**Symptom:** HO completes but UE has no data connectivity for several seconds.

| Cause | Fix |
|---|---|
| Data forwarding tunnel unreachable | Verify `GNB_IPV4_ADDRESS_FOR_NGU` is reachable between gNBs (Group V) |
| PathSwitch delayed | Check AMF log for `PathSwitchRequest` processing time |
| UPF not updated | Check SMF/UPF logs for N4 session modification after PathSwitch |
