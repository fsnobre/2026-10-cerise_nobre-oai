# OAI Intra-gNB Handover — Configuration and Signaling Reference

> **Scope:** Handover between two cells managed by the same gNB process (same nr-softmodem instance). No Xn or N2 signaling — the handover decision and execution happen entirely within one gNB.  
> **Applicability:** Your two-cell testbed (WS-gnb1 running two cells, or one cell per workstation with shared gNB context).  
> **Trigger:** A3 event (neighbor RSRP better than serving by `a3Offset` + `hysteresis` for `timeToTrigger` ms).  
> **RIC involvement:** Optional. Without RIC: autonomous A3-triggered. With RIC: E2SM-RC Control Style 3 overrides the A3 decision — covered in `oai_handover_ric.md`.

---

## 1. Architecture

```
                    ┌─────────────────────────────────────────┐
                    │              gNB (one process)           │
                    │                                          │
                    │  Cell 0 (physCellId=0)                   │
                    │  ← UE currently attached here            │
                    │                                          │
                    │  Cell 1 (physCellId=1)                   │
                    │  ← UE handover target                    │
                    │                                          │
                    │  No Xn, no N2 for HO decision            │
                    │  AMF notified via Path Switch after HO   │
                    └─────────────────────────────────────────┘
```

**Key constraint:** Both cells must be configured in the same gNB YAML (multiple entries in `servingCellConfigCommon`, or two separate `gNBs` entries with the same `gNB_ID`). OAI intra-gNB handover does not require any inter-process communication.

---

## 2. Configuration Parameters

### 2.1 Measurement Configuration

Measurement configuration is set in the `gNBs` block and controls what the gNB instructs UEs to measure and when to report.

| Parameter | Tier | Location | Notes |
|---|---|---|---|
| `do_MeasurementConfig` | Recommended | `gNBs[]` | `1` = enable measurement config in RRCReconfiguration. Default 0 = no measurements, no handover. |
| `measurement_events` | Recommended | `gNBs[]` | List of event types to configure. For A3: `["A3"]`. |
| `A3_event.a3Offset` | Required (for A3) | `gNBs[]` | RSRP offset (dB × 2, i.e. 6 = 3 dB). UE reports when neighbor RSRP > serving RSRP + offset. Range: −30 to 30 (−15 to 15 dB). Starting point: 6 (3 dB). |
| `A3_event.hysteresis` | Required (for A3) | `gNBs[]` | Hysteresis to prevent ping-pong (dB × 2). Range: 0–30 (0–15 dB). Typical: 2 (1 dB). |
| `A3_event.timeToTrigger` | Required (for A3) | `gNBs[]` | Time condition must be met before report sent (ms). Values: 0,40,64,80,100,128,160,256,320,480,512,640,1024,1280,2560,5120. Typical OTA: 160 ms. |
| `A3_event.reportAmount` | Optional | `gNBs[]` | Number of reports: 1,2,4,8,16,32,64,infinity. Default: 1. |
| `A3_event.reportInterval` | Optional | `gNBs[]` | Interval between reports if `reportAmount > 1` (ms). |
| `A3_event.reportOnLeave` | Optional | `gNBs[]` | `1` = send report when condition no longer met. Useful for ping-pong detection. |

### 2.2 Neighbor Cell List

The gNB must know about its neighbor cells to include them in the UE's measurement config.

| Parameter | Tier | Notes |
|---|---|---|
| `neighbour_cell_configuration` | Required | List of neighbor cells. Without this, UE has no cells to measure toward. |
| `neighbour_cell_configuration[].physCellId` | Required | Physical cell ID of the neighbor. Must match the target cell's `physCellId`. |
| `neighbour_cell_configuration[].absoluteFrequencySSB` | Required | SSB ARFCN of the neighbor. |
| `neighbour_cell_configuration[].dl_subcarrierSpacing` | Required | Neighbor SCS. |
| `neighbour_cell_configuration[].dl_frequencyBand` | Required | Neighbor NR band. |

### 2.3 Handover Decision Parameters

| Parameter | Tier | Notes |
|---|---|---|
| `enable_x2` | Optional | `0` for intra-gNB. Not needed — kept for completeness. |
| `T304` | Recommended | Handover execution timer (ms). UE must complete random access on target cell within T304. Values: 50,100,150,200,500,1000,2000. Default: 2000 ms. For OTA: 1000 ms is safer. |
| `T310` | Recommended | Radio link failure detection timer (ms). Values: 0,50,100,200,500,1000,2000. Default: 1000 ms. |
| `N310` | Recommended | Out-of-sync threshold (consecutive OOS indications before T310 starts). Values: 1,2,3,4,6,8,10,20. |
| `N311` | Recommended | In-sync threshold (consecutive IS indications to stop T310). Values: 1,2,3,4,5,6,8,10. |

---

## 3. A3 Event — Parameter-Level Explanation

```
Serving cell RSRP (dB)
        │
        │    ┌─── a3Offset (e.g. 3 dB = a3Offset:6)
        │    │
        │    │    ┌─── hysteresis (e.g. 1 dB = hysteresis:2)
        │    ▼    ▼
        │  ──────────────────── trigger threshold
        │
        ▼  Neighbor RSRP must exceed this line for timeToTrigger ms
           before UE sends MeasurementReport
```

**Entry condition (A3):**
```
Mn + Ofn + Ocn − Hys > Ms + Ofs + Ocs + Off
```
Where:
- `Mn` = neighbor cell measurement (RSRP)
- `Ms` = serving cell measurement (RSRP)
- `Off` = `a3Offset` / 2 (converted from IE encoding to dB)
- `Hys` = `hysteresis` / 2
- `Ofn`, `Ocs`, etc. = frequency and cell offsets (typically 0)

**YAML → RRC IE mapping:**

| YAML parameter | 3GPP RRC IE | Notes |
|---|---|---|
| `A3_event.a3Offset` | `ReportConfigNR.a3-Offset` | Encoded as integer: value = dB × 2. IE range: −30 to 30. |
| `A3_event.hysteresis` | `EventTriggerConfig.hysteresis` | Encoded as integer: value = dB × 2. |
| `A3_event.timeToTrigger` | `EventTriggerConfig.timeToTrigger` | Enum: ms0, ms40, ms64, ..., ms5120. |
| `A3_event.reportAmount` | `ReportConfigNR.reportAmount` | Enum: r1, r2, r4, r8, r16, r32, r64, infinity. |
| `neighbour_cell_configuration[].physCellId` | `CellsToAddMod.physCellId` | Included in `measObjectNR.cellsToAddModList`. |
| `neighbour_cell_configuration[].absoluteFrequencySSB` | `MeasObjectNR.absoluteFrequencySSB` | One `measObject` per frequency. |

---

## 4. Signaling Flow — Intra-gNB A3 Handover (Parameter Level)

```
UE                          gNB (Cell 0 = Source)         gNB (Cell 1 = Target)
 │                                    │                              │
 │  ◄── RRCReconfiguration ───────────┤                              │
 │      [MeasConfig]                  │                              │
 │      measObjectNR:                 │                              │
 │        absoluteFrequencySSB        │  ← absoluteFrequencySSB      │
 │          = neighbour_cell[0]       │    from neighbour_cell_config │
 │        cellsToAddModList:          │                              │
 │          physCellId=1              │  ← neighbour physCellId      │
 │      reportConfigNR:               │                              │
 │        eventId: eventA3            │  ← measurement_events: A3   │
 │        a3-Offset = a3Offset        │  ← A3_event.a3Offset        │
 │        hysteresis = hysteresis     │  ← A3_event.hysteresis      │
 │        timeToTrigger = TTT         │  ← A3_event.timeToTrigger   │
 │      ──────────────────────────────│                              │
 │                                    │                              │
 │  [UE measures Cell 1 RSRP]         │                              │
 │  [A3 condition met for TTT ms]     │                              │
 │                                    │                              │
 │  ──── MeasurementReport ──────────►│                              │
 │       measId → eventA3             │                              │
 │       measResultServingCell:       │                              │
 │         rsrpResult (Cell 0)        │                              │
 │       measResultNeighCells:        │                              │
 │         physCellId=1               │                              │
 │         rsrpResult (Cell 1)        │                              │
 │                                    │                              │
 │                         [gNB decides: HO to Cell 1]              │
 │                         Decision uses:                            │
 │                         - a3Offset met ✓                         │
 │                         - hysteresis cleared ✓                   │
 │                         - T304 timer prepared                     │
 │                           (T304 = config T304 value)              │
 │                                    │                              │
 │  ◄── RRCReconfiguration ───────────┤                              │
 │      [HandoverCommand]             │                              │
 │      mobilityControlInfo:          │                              │
 │        targetPhysCellId=1          │  ← target physCellId        │
 │        carrierFreq (Cell 1 ARFCN)  │  ← target absoluteFreqSSB  │
 │        t304 = T304                 │  ← T304 config value        │
 │        rach-ConfigDedicated:       │                              │
 │          ra-PreambleIndex          │  ← dedicated preamble       │
 │          rach-Occasion             │  ← target RACH config       │
 │      radioResourceConfigCommon:    │                              │
 │        [Cell 1 SIB1 parameters]    │  ← Cell 1 serving cell cfg  │
 │                                    │                              │
 │  [T304 starts]                     │                              │
 │                                    │                              │
 │  ──── RACH Msg1 (preamble) ───────────────────────────────────►  │
 │       dedicated preamble index     │                              │
 │                                    │                              │
 │  ◄─── RACH Msg2 (RAR) ────────────────────────────────────────   │
 │       TA command                   │                              │
 │       UL grant for Msg3            │                              │
 │                                    │                              │
 │  ──── RRCReconfigurationComplete ─────────────────────────────►  │
 │       [T304 stops]                 │                              │
 │                                    │                              │
 │                                    │    [gNB internal path switch]│
 │                                    │    Cell 0 → Cell 1 context   │
 │                                    │    PDCP SN maintained        │
 │                                    │                              │
 │                         [AMF notified via]                        │
 │                         PathSwitchRequest (N2)                    │
 │                         [UPF tunnel updated]                      │
 │                                    │                              │
 │  ◄── RRCReconfiguration ───────────────────────────────────────   │
 │      [Post-HO reconfiguration]     │                              │
 │      [New DRB config if needed]    │                              │
```

**Critical parameter dependencies in this flow:**

| Message | IE | Driven by YAML parameter |
|---|---|---|
| RRCReconfiguration [MeasConfig] | `absoluteFrequencySSB` in measObject | `neighbour_cell_configuration[].absoluteFrequencySSB` |
| RRCReconfiguration [MeasConfig] | `a3-Offset` | `A3_event.a3Offset` |
| RRCReconfiguration [MeasConfig] | `hysteresis` | `A3_event.hysteresis` |
| RRCReconfiguration [MeasConfig] | `timeToTrigger` | `A3_event.timeToTrigger` |
| RRCReconfiguration [HandoverCommand] | `t304` | `T304` |
| RRCReconfiguration [HandoverCommand] | `targetPhysCellId` | target cell `physCellId` |
| RRCReconfiguration [HandoverCommand] | `carrierFreq` | target cell `absoluteFrequencySSB` |
| RACH Msg1 | dedicated preamble | gNB assigns from target cell RACH config |

---

## 5. Common Errors

### 5.1 UE Never Sends MeasurementReport

| Cause | Diagnostic | Fix |
|---|---|---|
| `do_MeasurementConfig: 0` | No MeasConfig in RRCReconfiguration (check rrc_log debug) | Set `do_MeasurementConfig: 1` |
| `neighbour_cell_configuration` empty | MeasObject has no cells → UE has nothing to measure | Add neighbor cell entries |
| `a3Offset` too large | Condition never met in lab (cells too close in RSRP) | Reduce `a3Offset` to 2–4 |
| `timeToTrigger` too long | Condition met briefly but not sustained | Reduce to 64 or 100 ms for lab |
| UE does not support measurement events | Check UE capabilities in RRC log | Use a different UE |

**Log levels:**
```yaml
rrc_log_level: debug    # Shows MeasConfig content sent to UE
mac_log_level: debug    # Shows MeasurementReport reception
```

### 5.2 T304 Expiry — Handover Failure

**Symptom:**
```
[RRC] T304 expiry: handover to cell 1 failed
[RRC] Initiating RRC re-establishment
```

| Cause | Fix |
|---|---|
| Target cell RACH config mismatch | Verify target cell `prach_ConfigurationIndex` and `ra_ResponseWindow` |
| Target cell not transmitting SSB | Check target cell `ssb_PositionsInBurst_Bitmap` |
| `T304` too short for OTA | Increase to 2000 ms for lab testing |
| Dedicated preamble conflict | OAI assigns preamble from target cell RACH pool — verify `ssb_perRACH_OccasionAndCB_PreamblesPerSSB` > 1 |

### 5.3 Ping-Pong Handover

**Symptom:** UE handovers repeatedly between cells every few seconds.

| Cause | Fix |
|---|---|
| `hysteresis` too small | Increase to 4–6 (2–3 dB) |
| `timeToTrigger` too short | Increase to 256–480 ms |
| `A3_event.reportOnLeave: 1` triggering re-handover | Set `reportOnLeave: 0` |

---

## 6. Dependency Groups for Intra-gNB HO

### Group R — Measurement Config Consistency (SOFT: UE measures wrong cell)

```
neighbour_cell_configuration[].absoluteFrequencySSB  ←→  target cell absoluteFrequencySSB
neighbour_cell_configuration[].physCellId            ←→  target cell physCellId
neighbour_cell_configuration[].dl_subcarrierSpacing  ←→  target cell dl_subcarrierSpacing
```

If the neighbor cell list points to a different ARFCN than the target cell actually broadcasts on, the UE will search the wrong frequency and never find the cell.

### Group S — A3 Threshold Tuning (SOFT: too aggressive or too conservative)

```
a3Offset + hysteresis  ←→  expected RSRP delta between cells in your lab
timeToTrigger          ←→  UE velocity and measurement reporting rate
T304                   ←→  target cell RACH procedure duration
```

In a lab with cells close together, RSRP difference may be small and variable. Starting values:
- `a3Offset: 4` (2 dB), `hysteresis: 2` (1 dB), `timeToTrigger: 160`
- If no HO: reduce `a3Offset`. If ping-pong: increase `hysteresis` or `timeToTrigger`.
