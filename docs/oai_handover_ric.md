# OAI RIC-Triggered Handover — Configuration and Signaling Reference

> **Scope:** Handover decisions driven by the nearRT-RIC via E2SM-RC (Control Style 3, Action ID 1) and E2SM-KPM (for UE measurement reporting). Covers both reactive (xApp responds to KPM indications) and predictive (xApp uses NWDAF mobility analytics for preemptive decisions).  
> **Stack:** OAI gNB + FlexRIC nearRT-RIC + E2SM-KPM v2/v3 + E2SM-RC.  
> **Relation to autonomous HO:** RIC-triggered HO overrides or supplements the autonomous A3 trigger. Both can coexist — the xApp can either disable autonomous HO and take full control, or act as an additional decision layer on top of A3.

---

## 1. Architecture

```
                    ┌─────────────────────────────────────┐
                    │         FlexRIC nearRT-RIC           │
                    │  (WS-FlexRIC)                        │
                    │                                      │
                    │  ┌───────────────────────────────┐   │
                    │  │  KPM xApp (E2SM-KPM)          │   │
                    │  │  Subscribes: RSRP/RSRQ per UE │   │
                    │  │  Receives: RIC Indication       │   │
                    │  └───────────────┬───────────────┘   │
                    │                  │ triggers           │
                    │  ┌───────────────▼───────────────┐   │
                    │  │  RC xApp (E2SM-RC)             │   │
                    │  │  Sends: RIC Control            │   │
                    │  │  Action: Handover Control      │   │
                    │  └───────────────────────────────┘   │
                    └──────────────┬──────────────────────┘
                                   │ E2 (SCTP port 36421)
                    ┌──────────────▼──────────────────────┐
                    │           gNB                        │
                    │  E2 agent (embedded in nr-softmodem) │
                    │  Exposes: KPM RAN function           │
                    │  Exposes: RC RAN function            │
                    └─────────────────────────────────────┘
```

---

## 2. E2 Configuration Parameters

### 2.1 E2 Agent Parameters in gNB YAML

| Parameter | Tier | Notes |
|---|---|---|
| `NETWORK_INTERFACES.GNB_IPV4_ADDRESS_FOR_E2` | Required | gNB IP for E2 SCTP connection toward RIC. |
| `e2_agent.near_ric_ip_addr` | Required | FlexRIC nearRT-RIC IP address. |
| `e2_agent.sm_dir` | Required | Path to service model shared library directory. e.g. `/usr/local/lib/flexric/`. |
| `e2_agent.e2ap_version` | Recommended | E2AP version: `E2AP_V2` or `E2AP_V3`. Must match FlexRIC build. |

### 2.2 E2SM-KPM Subscription Parameters

These are set in the xApp code, not in the gNB YAML. Documented here for cross-reference.

| E2SM-KPM parameter | xApp value | gNB behavior |
|---|---|---|
| `reportingPeriod` | e.g. 100 ms | gNB sends KPM indication every 100 ms per subscribed UE |
| `granulPeriod` | e.g. 100 ms | Measurement granularity period |
| Measurement items | `RSRP`, `RSRQ`, `SINR`, `CQI` | gNB populates these from L1 measurements |
| `RAN_function_id` | KPM function ID | OAI FlexRIC: typically 2 |

### 2.3 E2SM-RC Control Parameters (Handover Control)

**Control Style 3 — Connected Mode Mobility Control**  
**Action ID 1 — Handover Control**

The xApp sends a `RIC Control Request` with:

| E2SM-RC IE | Type | Maps to gNB action |
|---|---|---|
| `RIC Control Header.ueID` | RNTI or AMF-UE-NGAP-ID | Identifies the UE to handover |
| `RIC Control Header.controlActionID` | `1` (Handover Control) | Triggers HO procedure |
| `RIC Control Message.targetCellInfo.nrCGI` | PLMN + NR Cell Identity | Target cell for handover |
| `RIC Control Message.targetCellInfo.nrPCI` | Physical Cell ID | Target `physCellId` |
| `RIC Control Ack` | Success/Failure | gNB confirms HO initiated or reports failure cause |

**nrCGI encoding:**
```
nrCGI = PLMN-Identity (3 bytes, BCD encoded) || NR-Cell-Identity (36 bits)
```
For your testbed:
- PLMN: MCC=001, MNC=01 → `00 F1 01` (BCD)
- Target cell NR-Cell-Identity: `nr_cellid` value from target gNB config, zero-padded to 36 bits

---

## 3. Reactive RIC-Triggered Handover

### 3.1 Decision Loop

```
gNB (every reportingPeriod ms)
  │── KPM Indication ──────────────────────────► xApp
  │   measData per UE:                            │
  │     RNTI, RSRP (serving), RSRP (neighbor)    │
  │     CellID, timestamp                         │
  │                                               │
  │                              [xApp evaluates:]│
  │                              serving RSRP     │
  │                              neighbor RSRP    │
  │                              RSRP delta > threshold?
  │                                               │
  │◄── RIC Control Request ────────────────────── │
  │    targetCellInfo.nrPCI = target physCellId   │
  │    ueID = RNTI of UE to handover              │
  │                                               │
  │  [gNB executes handover]                      │
  │  [same procedure as A3-triggered]             │
  │  [but decision is from xApp, not A3 timer]    │
  │                                               │
  │── RIC Control Ack ────────────────────────────►
      success / failure cause
```

### 3.2 xApp Decision Thresholds (Application-Level)

These are set in xApp code (Python/C++), not in the YAML. Documented for completeness:

| xApp threshold | Equivalent YAML parameter | Notes |
|---|---|---|
| `rsrp_delta_threshold` | Analogous to `a3Offset` | RSRP difference (dB) that triggers RIC control |
| `hysteresis` | `A3_event.hysteresis` | Prevents ping-pong decisions |
| `decision_interval` | Analogous to `timeToTrigger` | How long condition must persist before xApp acts |
| `reporting_period` | KPM `reportingPeriod` | Determines reaction latency |

### 3.3 A3 Coexistence Mode

You can run both autonomous A3 and RIC-triggered HO simultaneously:

| Mode | Configuration | Behavior |
|---|---|---|
| **RIC-only** | Set `a3Offset` to a very high value (e.g. 28 = 14 dB) | A3 never triggers autonomously; xApp has full control |
| **RIC + A3 fallback** | Normal `a3Offset` + active xApp | xApp acts first; A3 triggers if xApp is slow or disconnected |
| **A3 with RIC override** | Normal A3 config + xApp uses `reportOnLeave` | A3 makes decisions; xApp can cancel or redirect |

**Recommended for research:** RIC-only mode. Set `a3Offset: 28` to effectively disable autonomous A3, then all HO decisions come from the xApp. This gives clean measurement of RIC decision latency vs HO outcome.

---

## 4. Signaling Flow — Reactive RIC-Triggered Handover (Parameter Level)

```
UE          gNB (E2 agent)         FlexRIC (RIC)            xApp
 │                │                      │                     │
 │                │◄── E2 Setup ─────────┤                     │
 │                │    E2AP association   │                     │
 │                │    port 36421         │  ← e2_agent config  │
 │                │    gNB announces:     │                     │
 │                │      KPM RAN func ID  │  ← sm_dir .so file  │
 │                │      RC RAN func ID   │                     │
 │                │                      │                     │
 │                │         [xApp starts]│                     │
 │                │                      │─── KPM Subscribe ──►│
 │                │◄── RIC Subscribe ────┤                     │
 │                │    KPM Style 1        │                     │
 │                │    reportingPeriod    │  ← xApp config      │
 │                │    granulPeriod       │                     │
 │                │    measItems:         │                     │
 │                │      RSRP, RSRQ, CQI │                     │
 │                │                      │                     │
 │                │─── RIC Ind Ack ──────►│                     │
 │                │                      │                     │
 │  [UE attached] │                      │                     │
 │                │                      │                     │
 │                │─── RIC Indication ───►│──────────────────►  │
 │                │    (every 100ms)      │    measData:        │
 │                │    per-UE:            │      RNTI=0xf2a6    │
 │                │      RSRP_serving     │      RSRP_s = −85   │
 │                │      RSRP_neighbor    │      RSRP_n = −82   │
 │                │      CellID           │      delta = 3 dB   │
 │                │                      │                     │
 │                │                      │  [delta > threshold?]│
 │                │                      │  [persistent for    │
 │                │                      │   decision_interval?]│
 │                │                      │                     │
 │                │◄── RIC Control ───────┤◄────────────────────│
 │                │    Header:            │                     │
 │                │      ueID=0xf2a6      │  ← RNTI from KPM   │
 │                │      actionID=1       │  ← Handover Control │
 │                │    Message:           │                     │
 │                │      targetCell:      │                     │
 │                │        nrCGI (PLMN+   │  ← target nr_cellid │
 │                │          nr_cellid)   │                     │
 │                │        nrPCI=1        │  ← target physCellId│
 │                │                      │                     │
 │                │─── RIC Control Ack ──►│                     │
 │                │    success            │                     │
 │                │                      │                     │
 │  [gNB executes HO — same as A3 path from here]              │
 │◄─RRCReconfiguration (HandoverCommand)─┤                     │
 │  [T304 starts]  │                      │                     │
 │                 │                      │                     │
 │──RACH Msg1 ─────────────────────────────────────────────►   │
 │◄─RACH Msg2 ──────────────────────────────────────────────   │
 │──RRCReconfigComplete ──────────────────────────────────►    │
 │                 │                      │                     │
 │                 │─── RIC Indication ───►│──────────────────►  │
 │                 │    (post-HO)          │  UE now on target  │
 │                 │    RNTI=0xf2a6        │  RSRP_s improved   │
 │                 │    new serving cell   │                     │
```

---

## 5. Predictive RIC-Triggered Handover

### 5.1 Architecture with NWDAF

```
NWDAF                    Non-RT RIC / rApp        nearRT-RIC / xApp         gNB
  │                            │                        │                     │
  │ Nnwdaf_AnalyticsInfo       │                        │                     │
  │ Analytics: UE_MOBILITY     │                        │                     │
  │ predictedLocations[]       │                        │                     │
  │ moveDirection              │                        │                     │
  │──────────────────────────►│                        │                     │
  │                            │                        │                     │
  │                 [rApp trains model on]              │                     │
  │                 [historical KPM data]               │                     │
  │                            │                        │                     │
  │                            │── A1 Policy push ─────►│                     │
  │                            │  HO threshold policy   │                     │
  │                            │  (adjusted per UE      │                     │
  │                            │   mobility prediction) │                     │
  │                            │                        │                     │
  │                            │                        │◄── KPM Indication ──│
  │                            │                        │    RSRP + CellID    │
  │                            │                        │                     │
  │         [xApp uses A1 policy + KPM data]            │                     │
  │         [to decide preemptive HO]                   │                     │
  │                            │                        │                     │
  │                            │                        │─── RIC Control ────►│
  │                            │                        │    (before A3)       │
  │                            │                        │    preemptive HO     │
```

### 5.2 NWDAF UE_MOBILITY Analytics

The NWDAF `UE_MOBILITY` analytic (TS 29.520 Section 6.1.6.2) provides:

| NWDAF output field | Relevance to handover |
|---|---|
| `predictedLocations[]` | Future cell IDs the UE is predicted to visit |
| `moveDirection` | UE movement direction (degrees) |
| `moveSpeed` | UE speed estimate |
| `confidence` | Prediction confidence (0–100%) |
| `timeStamp` | When the prediction is valid for |

**OAI NWDAF current state:** The `UE_MOBILITY` predictive analytic requires a custom ML model. OAI's current implementation primarily has `ABNORMAL_BEHAVIOUR`. For predictive HO research, you need to:
1. Build or integrate an ML mobility model
2. Extend the NWDAF to serve `UE_MOBILITY` analytics
3. Have the rApp/xApp consume these predictions

### 5.3 gNB Configuration for Predictive HO

No additional YAML parameters beyond the reactive case. The difference is entirely in the xApp decision logic:

| Aspect | Reactive | Predictive |
|---|---|---|
| Trigger | KPM RSRP delta crosses threshold | NWDAF predicts UE will reach cell boundary |
| Timing | After A3 condition | Before A3 condition (preemptive) |
| HO execution | Same E2SM-RC Control | Same E2SM-RC Control |
| Target selection | Best RSRP neighbor | Predicted next cell from `predictedLocations` |
| Benefit | Better than autonomous A3 | Lower interruption time, UPF placement optimization |

### 5.4 Connection to Your UPF Placement Research

The predictive handover loop is the control path for your UPF placement work:

```
NWDAF UE_MOBILITY prediction
    ↓
xApp/decision engine predicts: UE will be in Cell X in T seconds
    ↓
Decision engine (MILP/DRL): should UPF be relocated?
    ↓  (if yes)
UPF relocation triggered (before HO)
    ↓
RIC Control → gNB handover (Cell X)
    ↓
UPF already at optimal location when HO completes
```

The state vector for your DRL/MILP engine should fuse:
- `predictedLocations` from NWDAF (where the UE is going)
- Current serving cell RSRP from KPM (where the UE is now)
- UPF current location (which gNB's N3 it is anchored to)
- Handover preparation latency (measured from RIC Control to RRCReconfigComplete)

---

## 6. Signaling Flow — Predictive RIC-Triggered Handover

```
NWDAF         rApp/Decision Engine        xApp (nearRT-RIC)       gNB
  │                   │                          │                   │
  │──UE_MOBILITY─────►│                          │                   │
  │  prediction:      │                          │                   │
  │  UE→Cell1 in      │                          │                   │
  │  T=500ms          │                          │                   │
  │  confidence=85%   │                          │                   │
  │                   │                          │                   │
  │           [MILP/DRL decision:]               │                   │
  │           [relocate UPF? → yes]              │                   │
  │           [HO target: Cell1]                 │                   │
  │                   │                          │                   │
  │           [UPF relocation initiated]         │                   │
  │           (parallel to HO preparation)       │                   │
  │                   │                          │                   │
  │                   │──── A1 Policy ──────────►│                   │
  │                   │  lower HO threshold      │                   │
  │                   │  for this UE temporarily │                   │
  │                   │  (preemptive trigger)     │                   │
  │                   │                          │                   │
  │                   │                          │◄── KPM Indication─│
  │                   │                          │  RSRP not yet     │
  │                   │                          │  at A3 threshold  │
  │                   │                          │                   │
  │                   │                          │── RIC Control ───►│
  │                   │                          │  ueID=RNTI        │
  │                   │                          │  targetCell=Cell1 │
  │                   │                          │  (preemptive)     │
  │                   │                          │                   │
  │                   │         [HO executed — same as reactive]     │
  │                   │                          │                   │
  │                   │                          │◄── KPM Indication─│
  │                   │                          │  UE on Cell1      │
  │                   │                          │  HO complete      │
  │                   │                          │                   │
  │                   │ [UPF relocation complete]│                   │
  │                   │ [matched to HO timing]   │                   │
```

---

## 7. Dependency Groups for RIC-Triggered HO

### Group Y — E2 Service Model Consistency (HARD: subscriptions fail)

```
gNB e2_agent.sm_dir  contains  libkpm_sm.so  ←→  FlexRIC built with same KPM version
gNB e2_agent.sm_dir  contains  librc_sm.so   ←→  FlexRIC built with same RC version
gNB e2_agent.e2ap_version  =  FlexRIC E2AP_VERSION
```

The most common cause of xApp subscribe/indicate cycles failing silently is a KPM or RC version mismatch between the gNB service model libraries and the FlexRIC RIC. Both must be built from the same commit with the same CMake flags.

### Group Z — RNTI Stability During RIC Control Latency (SOFT: stale control)

```
KPM reportingPeriod  ←→  RIC Control delivery latency  ←→  UE movement speed
```

The xApp makes a decision based on a KPM indication at time T. The RIC Control arrives at the gNB at time T + latency. If the UE's RNTI changes (re-establishment) or the UE has already moved during that latency window, the RIC Control may target a stale or wrong RNTI. Mitigate by:
- Keeping `reportingPeriod` ≤ 100 ms for fast-moving UEs
- Having the xApp verify RNTI is still active in the latest KPM indication before sending RIC Control

---

## 8. Common Errors

### 8.1 RIC Control Acknowledged but HO Not Executed

**Symptom:** xApp receives `RIC Control Ack: success` but no RRCReconfiguration is sent to UE.

| Cause | Fix |
|---|---|
| Target `nrPCI` not in gNB's neighbor cell list | Add target cell to `neighbour_cell_configuration` |
| UE RNTI stale (UE re-established) | xApp must re-read RNTI from latest KPM indication |
| Target cell not reachable via Xn (for inter-gNB) | Verify Xn configured if target is different gNB |
| OAI RC handler bug | Check `rrc_log_level: debug` for RC control message processing |

### 8.2 KPM Indications Stop After HO

**Symptom:** After HO, no more KPM indications for the UE.

| Cause | Fix |
|---|---|
| KPM subscription was per-UE and UE changed RNTI after HO | xApp must re-subscribe for new RNTI |
| HO changed serving cell, measurement context reset | xApp must handle cell change events in KPM |

### 8.3 E2SM-RC Version Mismatch

**Symptom:**
```
[E2AP] RIC Control Request: unknown RAN function ID
[E2AP] Service Model not found: RC
```

**Fix:** Rebuild both OAI gNB and FlexRIC with matching E2SM-RC version. Check:
```bash
# On gNB host
strings /usr/local/lib/flexric/librc_sm.so | grep -i "version\|RC_V"
# On FlexRIC host
strings /path/to/nearRT-RIC | grep -i "version\|RC_V"
# Both must show same version
```

**Log levels:**
```yaml
# On gNB:
log_config:
  global_log_level: info
  # E2 agent uses its own logging — check OAI build for e2_log_level or similar
```
```bash
# On FlexRIC host:
./nearRT-RIC  # logs to stdout — filter for "E2AP", "RC", "KPM"
```
