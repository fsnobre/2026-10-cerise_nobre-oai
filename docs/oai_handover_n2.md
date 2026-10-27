# OAI Inter-gNB N2 Handover — Configuration and Signaling Reference

> **Scope:** AMF-mediated handover between two gNBs with no direct Xn interface. The AMF coordinates the entire handover procedure as intermediary.  
> **When to use:** No Xn configured (simpler setup, slower HO), or as understood fallback path.  
> **Performance vs Xn:** N2 adds one AMF round-trip (~1–5 ms in lab) to handover preparation. For research on HO latency, Xn is preferable. N2 is useful when Xn is unavailable or when you need the AMF to have full visibility of every HO.

---

## 1. Architecture

```
WS-gnb1 (source)          AMF (WS-CN)          WS-gnb2 (target)
  physCellId=0               │                    physCellId=1
        │                    │                          │
        │──HandoverRequired──►│                          │
        │                    │──HandoverRequest─────────►│
        │                    │◄─HandoverRequestAck───────│
        │◄─HandoverCommand───│                           │
        │                    │                           │
  [UE RACH on gNB-2]         │                           │
        │                    │◄──PathSwitchRequest────────│
        │                    │───PathSwitchRequestAck────►│
        │◄─UEContextRelease──│                           │
```

**Key difference from Xn:** The source gNB sends `HandoverRequired` to the AMF. The AMF then contacts the target gNB, gets `HandoverRequestAck`, and sends `HandoverCommand` back to the source. No direct gNB-to-gNB communication during handover preparation.

---

## 2. Configuration Changes for N2 Handover

N2 handover requires **less** configuration than Xn because there is no Xn setup block. The critical additions are:

### 2.1 No `gNB_XnAPConfig` Block

Simply omit `gNB_XnAPConfig` from both gNB configs. OAI will use N2 as the sole inter-gNB handover path.

### 2.2 Both gNBs Must Register with the Same AMF

| Requirement | Notes |
|---|---|
| Same `amf_ip_address` on both gNBs | Both connect to the same AMF. |
| Same `tracking_area_code` | Both gNBs in the same TA, or configured with TACs the AMF accepts. |
| Same `plmn_list` | Both gNBs must serve the same PLMN. |
| Different `gNB_ID` | Must be unique — same rule as Xn. |
| Different `nr_cellid` | Must be unique per gNB. |

### 2.3 Measurement Configuration

Identical to intra-gNB and Xn cases — each gNB configures its UEs to measure the other gNB's cell via `neighbour_cell_configuration`. See `oai_handover_intra_gnb.md` Section 2.1 for parameter details.

### 2.4 N2 Handover Timer Parameters

| Parameter | Tier | Default | Notes |
|---|---|---|---|
| `T_Relocprep` | Recommended | 1000 ms | Time source gNB waits for `HandoverCommand` from AMF after sending `HandoverRequired`. If AMF doesn't respond in time, HO is cancelled. |
| `T_RelocOverall` | Recommended | 10000 ms | Overall N2 HO timer from `HandoverRequired` to completion. |

---

## 3. Signaling Flow — N2 Handover (Parameter Level)

```
UE           gNB-1 (Source, WS-gnb1)       AMF (WS-CN)      gNB-2 (Target, WS-gnb2)
 │                      │                       │                      │
 │                      │◄──NGSetup────────────►│◄──NGSetup────────────│
 │                      │   (both at startup)   │   gNB_ID=0xe01       │
 │                      │   gNB_ID=0xe00        │                      │
 │                      │   nr_cellid, plmn     │   nr_cellid, plmn    │
 │                      │                       │                      │
 │◄─RRCReconfiguration──┤                       │                      │
 │  [MeasConfig A3]     │                       │                      │
 │  (same as Xn/intra)  │  ← A3 parameters      │                      │
 │                      │  ← neighbour_cell_cfg  │                      │
 │                      │                       │                      │
 │  [A3 condition met]  │                       │                      │
 │                      │                       │                      │
 │──MeasurementReport──►│                       │                      │
 │                      │                       │                      │
 │           [gNB-1 decides: HO to gNB-2]       │                      │
 │           [No Xn → must use N2]              │                      │
 │                      │                       │                      │
 │                      │──HandoverRequired────►│                      │
 │                      │  Cause: radioNetwork  │                      │
 │                      │  targetID:            │                      │
 │                      │    gNB_ID=0xe01       │  ← target gNB_ID     │
 │                      │    nr_cellid          │  ← target nr_cellid  │
 │                      │    TAI                │  ← target TAC        │
 │                      │  source-to-Target:    │                      │
 │                      │    UE context         │                      │
 │                      │    RRC HO preparation │                      │
 │                      │    DRB configs        │                      │
 │                      │  directForwardingPath │                      │
 │                      │    NotAvailable       │  ← no Xn             │
 │                      │                       │                      │
 │                      │         [AMF selects target gNB-2]           │
 │                      │         [based on targetID + TAI]            │
 │                      │         [verifies UE subscription]           │
 │                      │                       │                      │
 │                      │                       │──HandoverRequest────►│
 │                      │                       │  UE context          │
 │                      │                       │  Security context    │
 │                      │                       │  DRB list            │
 │                      │                       │  targetCell:         │
 │                      │                       │    physCellId=1      │  ← target physCellId
 │                      │                       │                      │
 │                      │                       │         [gNB-2 admits]
 │                      │                       │         [prepares RACH]
 │                      │                       │         [allocates resources]
 │                      │                       │                      │
 │                      │                       │◄─HandoverRequestAck──│
 │                      │                       │  RRC container:      │
 │                      │                       │    RRCReconfiguration│
 │                      │                       │    mobilityControl:  │
 │                      │                       │      physCellId=1    │
 │                      │                       │      t304=T304       │  ← T304 (gNB-2)
 │                      │                       │      ra-Preamble     │
 │                      │                       │  admittedBearers     │
 │                      │                       │                      │
 │                      │◄─HandoverCommand──────│                      │
 │                      │  (AMF wraps gNB-2's   │                      │
 │                      │   RRC container)      │                      │
 │                      │                       │                      │
 │◄─RRCReconfiguration──┤                       │                      │
 │  [HandoverCommand]   │                       │                      │
 │  mobilityControl:    │                       │                      │
 │    targetPhysCellId=1│                       │                      │
 │    t304=T304         │                       │                      │
 │    ra-PreambleIndex  │                       │                      │
 │    targetCarrierFreq │  ← target absFreqSSB  │                      │
 │                      │                       │                      │
 │  [T304 starts]       │                       │                      │
 │                      │                       │                      │
 │  [No direct data     │                       │                      │
 │   forwarding —       │                       │                      │
 │   data via UPF only] │                       │                      │
 │                      │                       │                      │
 │──RACH Msg1 ─────────────────────────────────────────────────────►  │
 │  dedicated preamble  │                       │                      │
 │                      │                       │                      │
 │◄─RACH Msg2 (RAR) ───────────────────────────────────────────────   │
 │                      │                       │                      │
 │──RRCReconfigComplete────────────────────────────────────────────►  │
 │  [T304 stops]        │                       │                      │
 │                      │                       │                      │
 │                      │                       │◄─PathSwitchRequest───│
 │                      │                       │  newAMF-UE-NGAP-ID   │
 │                      │                       │  targetCellInfo      │
 │                      │                       │                      │
 │                      │                       │  [AMF updates UPF]   │
 │                      │                       │  [N4 PDR/FAR update] │
 │                      │                       │                      │
 │                      │                       │──PathSwitchReqAck───►│
 │                      │                       │  [UPF TEID updated]  │
 │                      │                       │                      │
 │                      │◄─UEContextRelease─────│                      │
 │                      │  (AMF releases        │                      │
 │                      │   source context)     │                      │
 │                      │                       │                      │
 │                      │──UEContextRelease─────►                      │
 │                      │  Complete             │                      │
```

**Critical parameter dependencies in this flow:**

| N2 Message | IE | Driven by YAML parameter |
|---|---|---|
| HandoverRequired | `targetID.gNB_ID` | target gNB `gNB_ID` (in source neighbour config) |
| HandoverRequired | `targetID.TAI` | target gNB `tracking_area_code` |
| HandoverRequest (AMF→gNB-2) | `targetCell.physCellId` | target `physCellId` |
| HandoverRequestAck | `t304` in RRC | target gNB `T304` |
| PathSwitchRequest | `targetCellInfo.nrCellId` | target `nr_cellid` |
| PathSwitchRequest | `targetCellInfo.PLMN` | target `plmn_list` |

---

## 4. N2-Only vs N2-with-Xn Comparison

| Aspect | N2-only | N2-with-Xn |
|---|---|---|
| HO preparation latency | AMF round-trip (~2–10 ms) | Direct gNB-to-gNB (~1–3 ms) |
| Data forwarding | Via UPF only (indirect) | Direct gNB-to-gNB tunnel (lower loss) |
| Config complexity | Lower (no Xn block) | Higher (Xn setup required) |
| AMF visibility | Full — AMF sees every HO | Partial — AMF sees only PathSwitch |
| Failure isolation | AMF is single point | Xn bypasses AMF for preparation |
| Useful for research | HO latency measurement, AMF-level analytics | Lower-latency HO experiments |

---

## 5. Dependency Groups for N2 HO

### Group W — AMF Registration Consistency (HARD: HandoverRequired rejected)

```
gNB-1 amf_ip_address  =  gNB-2 amf_ip_address  (same AMF)
gNB-1 plmn_list       =  gNB-2 plmn_list        (same PLMN)
gNB-1 gNB_ID         ≠  gNB-2 gNB_ID            (must differ)
gNB-1 nr_cellid      ≠  gNB-2 nr_cellid          (must differ)
```

The AMF can only route `HandoverRequired` to the correct target gNB if the target gNB is registered with a unique `gNB_ID` and `nr_cellid`. If both are the same, the AMF may route HO to the source gNB itself.

### Group X — PathSwitch Reachability (SOFT: post-HO data stall)

```
gNB-2 GNB_IPV4_ADDRESS_FOR_NGU  must be reachable from UPF
```

After PathSwitch, the UPF updates its N3 GTP-U endpoint to gNB-2. If gNB-2's N3 address is not reachable from the UPF (wrong interface, routing issue), data stalls after HO even though the control plane succeeded.

```bash
# Verify from WS-CN:
ping -c 3 <gNB-2 GNB_IPV4_ADDRESS_FOR_NGU>
# And verify from gNB-2:
ping -c 3 <UPF_N3_IP>
```

---

## 6. Common Errors

### 6.1 `HandoverRequired` Rejected by AMF

```
[NGAP] HandoverPreparationFailure received from AMF
```

| Cause | Fix |
|---|---|
| Target gNB not registered with AMF | Ensure gNB-2 is up and `NGSetupResponse` received before UEs attach to gNB-1 |
| Target `gNB_ID` unknown to AMF | Verify gNB-2's `gNB_ID` is in AMF's gNB list |
| TAC mismatch | Verify `tracking_area_code` on both gNBs is accepted by AMF |
| UE not authorized for target PLMN | Both gNBs must have identical `plmn_list` |

**Log levels:**
```yaml
ngap_log_level: debug   # Shows HandoverRequired, HandoverCommand, PathSwitchRequest
rrc_log_level: debug    # Shows UE context transfer content
```

**CN check:**
```bash
docker logs oai-amf 2>&1 | grep -i "handover\|HO\|PathSwitch"
```

### 6.2 Post-HO Data Stall

**Symptom:** RRCReconfigurationComplete received on gNB-2 but UE has no data.

| Cause | Fix |
|---|---|
| PathSwitchRequest delayed | Check AMF + SMF logs for N4 update timing |
| `GNB_IPV4_ADDRESS_FOR_NGU` wrong on gNB-2 | UPF sends DL to wrong address — check Group X |
| UPF TEID update failed | `docker logs oai-upf | grep -i "teid\|pfcp\|session"` |
