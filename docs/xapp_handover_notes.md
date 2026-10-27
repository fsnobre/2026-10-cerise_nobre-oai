# xApp Handover Notes — E2SM-RC IE Mapping and A3 Threshold Tuning

> **Stack:** ORANSlice xApp (E2SM-RC Control Style 3, Action ID 1) + FlexRIC KPM.  
> **Reference:** `oai_handover_ric.md` for full signaling flow.

---

## 1. E2SM-KPM — What the xApp Receives

The KPM subscription for handover monitoring should request per-UE RSRP measurements.

**Subscription parameters (in xApp code):**

```python
# KPM subscription — relevant fields
report_style = 1                  # Per-UE measurement report
reporting_period = 100            # ms — balance between reaction speed and overhead
granul_period = 100               # ms
measurement_items = [
    "RSRP",                       # Reference Signal Received Power (serving cell)
    "RSRQ",                       # Reference Signal Received Quality
    "SINR",                       # Signal-to-Interference-plus-Noise Ratio
]
```

**KPM Indication content per UE:**

| KPM field | Type | Maps to |
|---|---|---|
| `ueID.gnbUEID.amfUeNgapId` | uint64 | AMF-assigned UE ID |
| `ueID.gnbUEID.guami` | PLMN+AMF | Which gNB/AMF the UE is on |
| `measData.measRecord[0].integer` | int | RSRP value (dBm offset encoding) |
| `measInfo.measName.value` | string | "RSRP", "RSRQ", etc. |
| `granulPeriod` | uint32 | Measurement period |

**RSRP encoding:** KPM reports RSRP as an integer. OAI uses the 3GPP NR encoding:  
`RSRP_dBm = reported_value − 156` (range: 0=−156 dBm to 127=−29 dBm)

---

## 2. E2SM-RC Control — What the xApp Sends

**RIC Control Header (E2SM-RC v1/v2):**

```c
// Style 3, Action ID 1 — Handover Control
RIC_ControlHeader_Format1 {
    ueID: <RNTI or AMF-UE-NGAP-ID>    // identifies which UE to handover
    controlActionID: 1                  // Action ID 1 = Handover Control
}
```

**RIC Control Message:**

```c
RIC_ControlMessage_Format1 {
    RAN_ParameterID: 1                  // targetCellInfo
    RAN_ParameterValue: {
        nrCGI: {
            PLMN_Identity: 0x00F101     // MCC=001, MNC=01 (BCD: 00-F1-01)
            NR_CellIdentity: <nr_cellid shifted to 36 bits>
        }
        nrPCI: <physCellId>            // target cell physCellId
    }
}
```

**nrCGI construction for your testbed:**

```python
# PLMN encoding: MCC=001, MNC=01
# BCD encoding: MCC digit 1=0, digit 2=0, digit 3=1
#               MNC digit 1=F (padding), digit 2=0, digit 3=1
# Byte 1: (MCC-digit2 << 4) | MCC-digit1 = 0x00
# Byte 2: (MNC-digit1 << 4) | MCC-digit3 = 0xF1
# Byte 3: (MNC-digit3 << 4) | MNC-digit2 = 0x10
plmn_identity = bytes([0x00, 0xF1, 0x10])

# NR Cell Identity: nr_cellid from target gNB config, 36-bit value
# WS-gnb1 cell: nr_cellid=12345678, physCellId=0
# WS-gnb2 cell: nr_cellid=12345679, physCellId=1
target_nr_cellid = 12345679      # WS-gnb2 nr_cellid
target_phys_cell_id = 1          # WS-gnb2 physCellId

nrcgi = {
    "plmn": plmn_identity,
    "nrCellIdentity": target_nr_cellid
}
```

---

## 3. A3 Threshold Tuning for RIC-Controlled HO

### RIC-only mode

```yaml
# In gNB YAML:
A3_event:
  a3Offset: 28        # 14 dB — autonomous HO never fires in a normal lab
  hysteresis: 2
  timeToTrigger: 160
```

```python
# In xApp:
# All HO decisions come from xApp RSRP delta check
RSRP_DELTA_THRESHOLD_DB = 3.0   # dB — trigger HO when neighbor is 3 dB better
DECISION_HYSTERESIS_DB = 1.0    # dB — prevent ping-pong
DECISION_PERSISTENCE_MS = 200   # ms — condition must persist before RIC Control sent
```

### RIC + A3 fallback mode

```yaml
# In gNB YAML:
A3_event:
  a3Offset: 6         # 3 dB — normal A3 threshold
  hysteresis: 2
  timeToTrigger: 320  # Longer than normal — give xApp time to act first
```

```python
# In xApp:
# xApp uses same threshold as A3 but acts faster (lower persistence)
RSRP_DELTA_THRESHOLD_DB = 3.0
DECISION_PERSISTENCE_MS = 100   # Half of A3 timeToTrigger — xApp wins the race
```

---

## 4. RNTI Lifecycle in OAI KPM

OAI exposes the C-RNTI in KPM indications. Important lifecycle events that affect the xApp:

| Event | KPM behavior | xApp action needed |
|---|---|---|
| UE initial attach | New RNTI appears in KPM indications | Begin tracking this RNTI |
| UE handover (intra-gNB) | RNTI may change after HO | Re-map after RRCReconfigComplete |
| UE handover (inter-gNB) | RNTI disappears from source gNB | xApp on target gNB picks it up |
| UE context release | RNTI disappears from all indications | Stop tracking, clean up state |
| RLF + re-establishment | New RNTI assigned | Treat as new UE |

**Practical implication:** For inter-gNB RIC-triggered HO, you need one xApp instance per gNB (or one xApp subscribed to all gNBs), and the xApp must correlate `amfUeNgapId` across gNBs to track UE continuity across handovers.

---

## 5. Measuring HO Latency from xApp

To measure the end-to-end RIC-triggered HO latency:

```python
# In xApp:
import time

t_kpm_indication = None   # time KPM indication received
t_ric_control_sent = None # time RIC Control sent
t_ric_control_ack = None  # time RIC Control Ack received

# After HO: use post-HO KPM indication timestamp as proxy for completion
# Full latency = t_rrc_reconfiguration_complete − t_kpm_indication
# (requires correlating gNB logs with xApp timestamps)

# Approximate breakdown:
# KPM → xApp decision:  ~1-5 ms (xApp processing)
# xApp → RIC Control:   ~1-2 ms (E2AP encoding + SCTP)
# RIC → gNB:            ~1-2 ms (SCTP + E2AP decode)
# gNB HO execution:     ~10-50 ms (RACH procedure on target)
# Total typical:        ~15-60 ms
```

---

## 6. Connecting to Your UPF Placement Research

The xApp is the control point for your research loop. The decision engine architecture:

```
KPM Indication (RSRP, CellID, RNTI)
    +
NWDAF UE_MOBILITY (predictedLocations, moveDirection)
    ↓
State vector: [serving_rsrp, neighbor_rsrp, current_cell, predicted_cell,
               upf_location, ho_preparation_latency, ...]
    ↓
DRL/MILP Decision Engine
    ↓
Action 1: Trigger handover → E2SM-RC Control → gNB
Action 2: Relocate UPF → ORAN O1/A1 → SMF/UPF
Action 3: Do nothing
    ↓
Reward: RSRP improvement + UPF proximity + HO interruption time
```

The `xapp_kpm_rc` in ORANSlice is your starting point. The decision engine slots in between the KPM indication handler and the RC control sender.
