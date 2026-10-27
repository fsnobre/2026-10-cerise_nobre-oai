# OAI gNB YAML — Testbed Reference

> **Testbed:** Band 78 · 40 MHz · 30 kHz SCS · 106 PRB · USRP X310 · ORANSlice NVS  
> **Stack:** OAI `develop` + ORANSlice patches + FlexRIC nearRT-RIC  
> **Host OS:** Ubuntu 24.04 · Kernel: lowlatency recommended

---

## Tier Definitions

| Tier | Meaning |
|---|---|
| **Required** | OAI crashes, asserts, or refuses to start without it. No safe default exists. |
| **Recommended** | OAI starts without it but behaviour may be wrong or silently broken. A default exists but is incorrect for this testbed. |
| **Optional** | Has a safe, correct default. Only set to override. |

---

## 1. Fixed Values for This Testbed

These are determined by the hardware (X310, Band 78, 40 MHz) and must not be changed unless you change bands or channel bandwidth.

| Parameter | Value | Reason |
|---|---|---|
| `dl_subcarrierSpacing` | 1 (30 kHz) | Band 78 TDD standard |
| `ul_subcarrierSpacing` | 1 (30 kHz) | Must match DL for TDD |
| `dl_carrierBandwidth` | 106 | 40 MHz @ 30 kHz SCS |
| `ul_carrierBandwidth` | 106 | Must equal DL for TDD |
| `initialDLBWPlocationAndBandwidth` | 28875 | 275×(106−1)+0 = 28875 |
| `initialULBWPlocationAndBandwidth` | 28875 | Same |
| `absoluteFrequencySSB` | 640704 | 3319.20 MHz SSB center (NR-ARFCN) |
| `dl_absoluteFrequencyPointA` | 639996 | 3300.60 MHz Point A |
| `ul_frequencyBand` | 78 | TDD: same band as DL |
| `msg1_SubcarrierSpacing` | 1 | Must match data SCS for FR1 sub-6 GHz |
| `prach_RootSequenceIndex_PR` | 2 | NR short preamble (L=139) for FR1 |
| `ssb_PositionsInBurst_PR` | 2 | FR1 3–6 GHz requires medium (up to 4 SSBs) |
| `bands` | [78] | X310 with SBX/UBX daughterboard |
| `GNB_PORT_FOR_S1U` | 2152 | Fixed by 3GPP spec |
| `subcarrierSpacing` | 1 | Must match `dl_subcarrierSpacing` |
| `referenceSubcarrierSpacing` | 1 | Must match `dl_subcarrierSpacing` |
| `initialDLBWPsubcarrierSpacing` | 1 | Must match `dl_subcarrierSpacing` |
| `initialULBWPsubcarrierSpacing` | 1 | Must match `ul_subcarrierSpacing` |

> If you switch to 20 MHz (51 PRBs): change `dl/ul_carrierBandwidth` to 51 and both `locationAndBandwidth` values to 13750. Everything in this table that is SCS-derived stays the same.

---

## 2. Tuneable Parameters

### 2.1 Identity — must match your CN deployment

```yaml
gNB_ID: 0xe00
tracking_area_code: 1    # Must match AMF tac
plmn_list:
  - mcc: 001
    mnc: 01
    mnc_length: 2
    snssaiList:
      - sst: 1
        sd: 0x00001      # Slice 1
      - sst: 1
        sd: 0x000002     # Slice 2 (add one entry per slice in rrmPolicy.json)
```

> Each `{sst, sd}` entry here must also appear in the AMF `supported_slice_list` and in `rrmPolicy.json`. A mismatch in any of these three places causes a NGAP setup failure or silent slice misrouting.

---

### 2.2 Network Interfaces — must match your host networking

| Parameter | Tier | Your value | Notes |
|---|---|---|---|
| `GNB_INTERFACE_NAME_FOR_NG_AMF` | Recommended | `demo-oai` | OAI auto-detects if absent but WS-CN has multiple interfaces. Always set explicitly. |
| `GNB_IPV4_ADDRESS_FOR_NG_AMF` | Recommended | `192.168.70.129` | Same fallback risk. |
| `GNB_INTERFACE_NAME_FOR_NGU` | Recommended | `demo-oai` | Missing → GTP-U N3 traffic may exit the wrong interface silently. |
| `GNB_IPV4_ADDRESS_FOR_NGU` | Recommended | `192.168.70.129` | Same. |
| `amf_ip_address[].ipv4` | Required | `192.168.70.132` | AMF container IP. Without it, SCTP never connects. |

```yaml
NETWORK_INTERFACES:
  GNB_INTERFACE_NAME_FOR_NG_AMF: demo-oai
  GNB_IPV4_ADDRESS_FOR_NG_AMF: 192.168.70.129
  GNB_INTERFACE_NAME_FOR_NGU: demo-oai
  GNB_IPV4_ADDRESS_FOR_NGU: 192.168.70.129
  GNB_PORT_FOR_S1U: 2152
amf_ip_address:
  - ipv4: 192.168.70.132
```

> When you migrate to Kubernetes, these addresses change to pod/service IPs on the CNI overlay. The interface names will change too (from `demo-oai` to whatever the CNI creates).

---

### 2.3 RACH — most impactful for OTA stability

| Parameter | Tier | Value | Notes |
|---|---|---|---|
| `prach_ConfigurationIndex` | Required | 98 | Format B4, TDD, 30 kHz SCS |
| `prach_msg1_FDM` | Optional | 0 | 1 frequency occasion |
| `prach_msg1_FrequencyStart` | Optional | 0 | |
| `zeroCorrelationZoneConfig` | Required | 13 | ~1.5 km cell radius |
| `preambleReceivedTargetPower` | Required | -96 | Increase toward -90 if preambles are consistently missed |
| `preambleTransMax` | Required | 6 | = 8 attempts. Increase to 7 (=20) for noisy RF |
| `powerRampingStep` | Required | 1 | 2 dB per retry |
| `ra_ResponseWindow` | Recommended | **10** | Default (4) is too tight for X310 OTA. This was the primary RA failure cause. |
| `ra_ContentionResolutionTimer` | Required | 7 | 64 ms |
| `ssb_perRACH_OccasionAndCB_PreamblesPerSSB_PR` | Required | 4 | 1:1 SSB-to-occasion ratio |
| `ssb_perRACH_OccasionAndCB_PreamblesPerSSB` | Required | 14 | 60 CB preambles |
| `prach_RootSequenceIndex` | Required | 1 | Valid for PR=2 (L=139, range 0–137) |
| `restrictedSetConfig` | Required | 0 | Unrestricted |
| `msg3_DeltaPreamble` | Required | 1 | |
| `p0_NominalWithGrant` | Required | -90 | |

**Symptom → parameter tuning guide:**

| Symptom | Parameter | Action |
|---|---|---|
| Preamble detected but RAR never sent | `ra_ResponseWindow` | Increase to 10 |
| RAR sent but Msg3 never decoded | `max_rxgain` + `att_rx` | Increase gain; verify `att_rx=0` |
| UE exhausts preambles | `preambleTransMax` | Increase to 7 (=20 attempts) |
| Multiple UEs collide on same preamble | `ssb_perRACH_OccasionAndCB_PreamblesPerSSB` | Increase |
| `cannot find free CCE for Msg2` | CORESET#0 config or NVS scheduler | See Section 3.2 |

---

### 2.4 TDD Pattern

Your testbed uses the **DDDSUUU** 5 ms pattern. Two valid variants:

```
Variant A (your YAML — more robust OTA):
  nrofDownlinkSlots: 7  nrofDownlinkSymbols: 6
  nrofUplinkSlots: 2    nrofUplinkSymbols: 4
  Guard = 14 - 6 - 4 = 4 symbols

Variant B (original ORANSlice .conf — higher DL capacity):
  nrofDownlinkSlots: 7  nrofDownlinkSymbols: 10
  nrofUplinkSlots: 2    nrofUplinkSymbols: 2
  Guard = 14 - 10 - 2 = 2 symbols
```

Variant A has more guard time for TX→RX switching, which is safer with the X310's RF path switching latency. Variant B squeezes more DL symbols into the special slot.

> **Critical:** Whatever variant you use, the **UE config must use the same pattern**. A mismatch between gNB and UE TDD patterns causes the UE to transmit during the gNB's DL period and receive during the gNB's UL period — the link will not work.

---

### 2.5 RF / USRP X310

| Parameter | Tier | Value | Notes |
|---|---|---|---|
| `local_rf` | Required | yes | |
| `nb_tx` / `nb_rx` | Required | 1 | SISO |
| `bands` | Required | [78] | |
| `eNB_instances` | Required | [0] | |
| `max_rxgain` | Required | 75 | Starting point. Tune ±5 dB. See table below. |
| `att_tx` | Optional | **0** | 0 for OTA. Non-zero only with physical attenuators in TX path. |
| `att_rx` | Optional | **0** | Same. Your original YAML had 14 here — this is what was killing Msg3. |
| `max_pdschReferenceSignalPower` | Recommended | -27 | Affects UE UL power control. Should reflect actual TX power. |
| `sdr_addrs` | Required | see below | |

```yaml
sdr_addrs: "addr=192.168.40.2,clock_source=internal,time_source=internal,send_frame_size=8000,recv_frame_size=8000"
```

**`max_rxgain` tuning (X310 SBX/UBX, Band 78):**

| Range | Effect |
|---|---|
| < 60 dB | Msg3 and PUSCH decode failures; UEs attach briefly then drop |
| 65–80 dB | Normal operating range |
| > 85 dB | ADC saturation; noise floor rises; RACH false alarms increase |

**`sdr_addrs` fields:**

| Field | Tier | Value | Notes |
|---|---|---|---|
| `addr` | Required | `192.168.40.2` | X310 IP on 10 GbE port |
| `clock_source` | Recommended | `internal` | Always set explicitly. Change to `external` when you add an OctoClock. |
| `time_source` | Recommended | `internal` | Must match `clock_source`. |
| `send_frame_size` | Optional | 8000 | Reduces UHD TX latency vs default 1472 bytes. |
| `recv_frame_size` | Optional | 8000 | Same for RX. |

---

### 2.6 MAC / ORANSlice Scheduler

| Parameter | Tier | Value | Notes |
|---|---|---|---|
| `tr_s_preference` | Required | `local_L1` | Must match L1s transport |
| `tr_n_preference` | Required | `local_RRC` | Monolithic gNB |
| `pusch_TargetSNRx10` | Optional | 200 | 20 dB |
| `pucch_TargetSNRx10` | Optional | 200 | 20 dB |
| `ul_prbblack_SNR_threshold` | Optional | 10 | dB |
| `ulsch_max_frame_inactivity` | Optional | 5 | 1 is too aggressive for lab. 5–10 frames is safer. 0 disables. |
| `SliceConf` | Required (ORANSlice) | path to rrmPolicy.json | Without this, NVS scheduler is disabled and xApp slice commands do nothing. |

---

### 2.7 L1 Processing

| Parameter | Tier | Value | Notes |
|---|---|---|---|
| `tr_n_preference` | Required | `local_mac` | Must match MACRLCs transport |
| `prach_dtx_threshold` | Optional | 120 | |
| `pucch0_dtx_threshold` | Optional | 100 | |
| `odfm_offset_divisor` | Optional | 8 | Correct for X310 at 30 kHz SCS |
| `pusch_proc_threads` | Recommended | 8 | Default (1) is inadequate for 106 PRBs. Set to physical core count on WS-gnb. |

---

### 2.8 Threading

| Parameter | Tier | Value | Notes |
|---|---|---|---|
| `parallel_config` | Recommended | `PARALLEL_RU_L1_SPLIT` | Default (`PARALLEL_SINGLE_THREAD`) cannot sustain 106 PRBs @ 30 kHz OTA. |
| `worker_config` | Optional | `WORKER_ENABLE` | |

| Config | Use when |
|---|---|
| `PARALLEL_SINGLE_THREAD` | RFsim only |
| `PARALLEL_RU_L1_SPLIT` | OTA, single UE or light load |
| `PARALLEL_RU_L1_TRX_SPLIT` | OTA, multiple UEs, 106 PRBs under load |

---

### 2.9 Logging by Phase

**Initial bring-up:**
```yaml
log_config:
  global_log_level: info
  mac_log_level: debug     # Full RA state machine
  ngap_log_level: debug    # AMF handshake and PDU session setup
  rrc_log_level: debug     # RRC Setup / Reconfiguration
```

**Stable experiment run:**
```yaml
log_config:
  global_log_level: info
  # Do not use debug on phy/mac during live OTA — causes timing misses
```

**Diagnosing TA/UL instability:**
```yaml
log_config:
  phy_log_level: debug    # Raw TA measurements (very verbose — offline only)
  mac_log_level: debug    # TA command generation
  # Do not run both simultaneously OTA
```

**Diagnosing GTP-U/PDCP:**
```yaml
log_config:
  pdcp_log_level: debug
  ngap_log_level: debug
  # CN: docker logs oai-smf | grep -i teid
  #     docker logs oai-upf | grep -i "far\|pdr\|teid"
```

---

## 3. Errors Specific to This Testbed

> **The symptom-first view of this material lives in
> [`oai_troubleshooting_testbed.md`](oai_troubleshooting_testbed.md).** That file is
> indexed by the literal log string OAI emits, covers P1–P10 rather than the four
> below, and adds the misdiagnosis record and the P1→P8 causal chain. Use it when you
> are holding a log. Use this section when you are holding a parameter: **this
> reference remains authoritative for parameter values** for this testbed. The two
> overlap on purpose and are not meant to be merged.

### 3.1 X310 Clock Drift — `Invalid timing advance offset`

**Symptom:**
```
[NR_MAC] Invalid timing advance offset for RNTI XXXX
```
Repeats for the same RNTI. Associated with PDCP discard floods on that UE.

**Cause:** The X310 TCXO drifts without an external reference. Over minutes, the measured round-trip time changes enough that the computed TA exceeds the valid range (0–3846 × 16 Ts).

**Mitigations without external clock:**
- Ensure `clock_source=internal,time_source=internal` is explicit in `sdr_addrs`.
- Keep experiment duration short before drift accumulates.
- Restart the gNB to reset the timing reference between experiments.

**Permanent fix:** Connect OctoClock-G or GPSDO 10 MHz output to X310 REF IN, then:
```yaml
sdr_addrs: "addr=192.168.40.2,clock_source=external,time_source=external,..."
```
With a multi-cell testbed (WS-gnb1 + WS-gnb2), both X310s must share the same reference signal.

---

### 3.2 ORANSlice: Slice Commands Have No Effect

**Symptom:** xApp completes subscribe/indicate/control/delete cycle successfully (`Test xApp run SUCCESSFULLY`) but PRB allocation in the gNB does not change.

**Cause:** `SliceConf` missing from `MACRLCs`. OAI is running the default round-robin scheduler, not the NVS scheduler. The E2SM-RC control message is received and acknowledged, but the NVS handler is never invoked.

**Fix:** Add to `MACRLCs`:
```yaml
SliceConf: "/home/nobre/oranslice2/ORANSlice/rrmPolicy.json"
```

**Verify:** At gNB startup you should see:
```
[MAC] Loading slice configuration from /path/to/rrmPolicy.json
```
If absent: path is wrong, file is malformed, or the ORANSlice build was not used.

---

### 3.3 N2 Setup Failure

**Symptom:**
```
[NGAP] NG Setup failure
```

| Check | Command |
|---|---|
| `tracking_area_code` matches AMF | `docker exec oai-amf cat /openair-amf/etc/amf.conf \| grep tac` |
| `mcc`/`mnc` matches AMF | Same file, PLMN section |
| `snssaiList` in AMF | Same file, `supported_slice_list` |
| AMF reachable | `ping 192.168.70.132` from WS-CN |
| `demo-oai` interface up | `ip addr show demo-oai` |

```yaml
ngap_log_level: debug    # Shows NGSetupRequest and failure cause code
```

---

### 3.4 `L` Flood at 106 PRBs

**Symptom:** Persistent `LLLLLLL` at startup or under load on WS-gnb.

**Root cause:** 106 PRBs @ 30 kHz SCS = 46.08 MSps = FFT size 2048. Each 0.5 ms slot requires a full DL/UL cycle. `PARALLEL_SINGLE_THREAD` cannot sustain this.

**Fix sequence (apply in order, stop when `L` disappears):**

1. `parallel_config: PARALLEL_RU_L1_SPLIT` in `THREAD_STRUCT`
2. `pusch_proc_threads: 8` in `L1s`
3. Launch flags: `--usrp-tx-thread-config 1 --thread-pool 0,2,4,6`
4. `sudo cpupower frequency-set -g performance`
5. Disable C-states: add `intel_idle.max_cstate=1` to kernel cmdline
6. If still present: temporarily drop to 51 PRBs (20 MHz) to verify the RF path works, then return to 106

> **51 vs 106 PRBs for ORANSlice experiments:** If your research focuses on slicing control logic rather than peak throughput, 51 PRBs halves the FFT size and CPU load, making the testbed more stable. All carrier/BWP parameters must be consistently updated (see Section 4, Group A).

---

## 4. Parameter Dependencies and Compliance

### Group A — Carrier ↔ BWP (HARD: malformed RRC or assert)

For this testbed the values are fixed, but if you change bandwidth:

```
dl_carrierBandwidth  ←→  initialDLBWPlocationAndBandwidth
ul_carrierBandwidth  ←→  initialULBWPlocationAndBandwidth
dl_carrierBandwidth  =   ul_carrierBandwidth  (TDD)
```

| Bandwidth | `dl/ul_carrierBandwidth` | `locationAndBandwidth` |
|---|---|---|
| 20 MHz | 51 | 13750 |
| 40 MHz | 106 | 28875 |

Setting one without the other produces a valid-looking config that causes UEs to receive a contradictory RRC configuration.

---

### Group B — SCS Chain (HARD: assert on mismatch)

All of these must equal 1 (30 kHz) for this testbed:

```
dl_subcarrierSpacing = ul_subcarrierSpacing
                     = initialDLBWPsubcarrierSpacing
                     = initialULBWPsubcarrierSpacing
                     = msg1_SubcarrierSpacing
                     = subcarrierSpacing
                     = referenceSubcarrierSpacing
```

Any single mismatch causes an OAI assert at startup.

---

### Group C — TDD Pattern Arithmetic (SOFT: accepted but RF fails)

OAI does not validate this at startup. Violations produce a slot structure that violates 3GPP timing.

```
Rule 1: nrofDownlinkSymbols + nrofUplinkSymbols ≤ 14
         Guard = 14 - DL_syms - UL_syms  (must be ≥ 1)

Rule 2: nrofDownlinkSlots + nrofUplinkSlots + 1 ≤ slots_per_period
         At 30 kHz SCS, 5 ms period: slots_per_period = 10
         This testbed: 7 + 2 + 1 = 10 ✓
```

**Additional constraint for this testbed:** The UE config must use the **identical** TDD pattern. A gNB/UE mismatch is accepted by both sides at startup but causes the uplink and downlink to collide at the RF level.

---

### Group D — PRACH Root Sequence ↔ Format (HARD: preamble detection fails)

This testbed uses `prach_RootSequenceIndex_PR: 2` (L=139, short format). Valid index range: **0–137**.

```
prach_RootSequenceIndex: 1   ✓ (within 0–137)
prach_RootSequenceIndex: 200 ✗ (out of range for L=139)
```

`prach_ConfigurationIndex: 98` is valid for format B4 at 30 kHz SCS with TDD. If you change the configuration index, verify it is listed in TS 38.211 Table 6.3.3.2-2 for your SCS and TDD periodicity combination.

---

### Group E — SSB ↔ Band (SOFT: UEs may not find cell)

Band 78 (3.3–3.8 GHz) is FR1 3–6 GHz, which requires `ssb_PositionsInBurst_PR: 2` (medium, up to 4 SSBs). This testbed uses `ssb_PositionsInBurst_Bitmap: 1`, meaning only SSB #0 is active — correct and minimal.

```
ssb_PositionsInBurst_PR: 2     ← required for Band 78
ssb_PositionsInBurst_Bitmap: 1 ← only SSB #0 active (valid)
```

Setting PR=1 (short) for Band 78 is technically accepted but limits SSB density in a way that may reduce cell search reliability.

---

### Group F — CN Identity Alignment (SOFT: gNB starts, NGAP/registration fails)

Three-way consistency required for ORANSlice:

```
gNB snssaiList  ←→  AMF supported_slice_list  ←→  rrmPolicy.json slice definitions
```

Additionally:
```
tracking_area_code  ←→  AMF tac
mcc / mnc           ←→  AMF PLMN list
```

The gNB starts without these matching. Failures appear only during UE registration or slice activation.

---

### Group G — RF Gain Coherence (SOFT: functional but degraded)

```
att_tx = att_rx = 0       when operating OTA (no physical attenuators)
att_tx = att_rx = N dB    only when physical N dB attenuators are in the RF path
max_rxgain: 75            starting point for X310 SBX Band 78
ssPBCH_BlockPower: -25    should match actual TX output power in dBm
```

`att_rx: 14` (as in your original YAML) with no physical attenuator reduces the effective RX sensitivity by 14 dB. This is enough to make Msg3 decode fail consistently while RACH preamble detection (which has higher processing gain) still works — producing the exact failure pattern in your logs.

`ssPBCH_BlockPower` is broadcast in SIB1 and used by UEs for open-loop UL power control. If set significantly lower than actual TX power, UEs underestimate the path loss and transmit at too low a power level, causing systematic Msg3 and PUSCH failures.

---

### Group H — Threading Coherence (SOFT: functional but unsustainable OTA)

```
parallel_config ←→ pusch_proc_threads ←→ physical core count on WS-gnb
```

At 106 PRBs with `PARALLEL_RU_L1_SPLIT`:
- 1 thread: RU (TX/RX)
- 1 thread: L1 main loop
- N threads: PUSCH decoding (`pusch_proc_threads`)

`pusch_proc_threads` should not exceed the number of physical (non-HT) cores minus 2 reserved for RU and L1. On a typical 8-core workstation: `pusch_proc_threads: 6` is a better ceiling than 8.

---

### Group I — Transport Preference Chain (HARD: crash if inconsistent)

```yaml
# Correct for monolithic SA gNB:
MACRLCs:
  tr_s_preference: local_L1   # ← matches L1s below
  tr_n_preference: local_RRC

L1s:
  tr_n_preference: local_mac  # ← matches MACRLCs above
```

Mixing `local_*` with `f1ap` or `nfapi` causes OAI to attempt split transport to a non-existent endpoint and crash at startup.

---

## 5. Complete Minimal Working Config

```yaml
Active_gNBs:
  - gnb
Asn1_verbosity: none

gNBs:
  - gNB_ID: 0xe00
    gNB_name: gnb
    tracking_area_code: 1
    plmn_list:
      - mcc: 001
        mnc: 01
        mnc_length: 2
        snssaiList:
          - sst: 1
            sd: 0x00001
          - sst: 1
            sd: 0x000002
    nr_cellid: 12345678
    min_rxtxtime: 6
    do_SRS: 1
    do_CSIRS: 1
    pdsch_AntennaPorts: 1
    pusch_AntennaPorts_XP: 1
    servingCellConfigCommon:
      - physCellId: 0
        absoluteFrequencySSB: 640704
        dl_absoluteFrequencyPointA: 639996
        dl_offstToCarrier: 0
        dl_subcarrierSpacing: 1
        dl_carrierBandwidth: 106        # Group A: must match locationAndBandwidth
        initialDLBWPlocationAndBandwidth: 28875  # 275*(106-1)+0
        initialDLBWPsubcarrierSpacing: 1         # Group B: must match dl_subcarrierSpacing
        initialDLBWPcontrolResourceSetZero: 12
        initialDLBWPsearchSpaceZero: 0
        ul_frequencyBand: 78
        ul_offstToCarrier: 0
        ul_subcarrierSpacing: 1
        ul_carrierBandwidth: 106        # Group A: must match dl_carrierBandwidth (TDD)
        pMax: 20
        initialULBWPlocationAndBandwidth: 28875  # Group A: must match ul_carrierBandwidth
        initialULBWPsubcarrierSpacing: 1         # Group B: must match ul_subcarrierSpacing
        prach_ConfigurationIndex: 98
        prach_msg1_FDM: 0
        prach_msg1_FrequencyStart: 0
        zeroCorrelationZoneConfig: 13
        preambleReceivedTargetPower: -96
        preambleTransMax: 6
        powerRampingStep: 1
        ra_ResponseWindow: 10           # Recommended: default 4 is too tight for X310 OTA
        ra_ContentionResolutionTimer: 7
        ssb_perRACH_OccasionAndCB_PreamblesPerSSB_PR: 4
        ssb_perRACH_OccasionAndCB_PreamblesPerSSB: 14
        prach_RootSequenceIndex_PR: 2
        prach_RootSequenceIndex: 1      # Group D: must be ≤ 137 for PR=2
        msg1_SubcarrierSpacing: 1       # Group B: must match dl_subcarrierSpacing
        restrictedSetConfig: 0
        msg3_DeltaPreamble: 1
        p0_NominalWithGrant: -90
        pucchGroupHopping: 0
        hoppingId: 40
        p0_nominal: -90
        ssb_PositionsInBurst_PR: 2      # Group E: must be 2 for Band 78
        ssb_PositionsInBurst_Bitmap: 1
        ssb_periodicityServingCell: 2
        dmrs_TypeA_Position: 0
        subcarrierSpacing: 1            # Group B: must match dl_subcarrierSpacing
        referenceSubcarrierSpacing: 1   # Group B: must match dl_subcarrierSpacing
        dl_UL_TransmissionPeriodicity: 6
        nrofDownlinkSlots: 7
        nrofDownlinkSymbols: 6          # Group C: 6+4+guard(4)=14 ✓
        nrofUplinkSlots: 2
        nrofUplinkSymbols: 4            # Group C: 7+1+2=10 slots ✓
        ssPBCH_BlockPower: -25          # Group G: should reflect actual TX power
    SCTP:
      SCTP_INSTREAMS: 2
      SCTP_OUTSTREAMS: 2
    amf_ip_address:
      - ipv4: 192.168.70.132
    NETWORK_INTERFACES:
      GNB_INTERFACE_NAME_FOR_NG_AMF: demo-oai
      GNB_IPV4_ADDRESS_FOR_NG_AMF: 192.168.70.129
      GNB_INTERFACE_NAME_FOR_NGU: demo-oai
      GNB_IPV4_ADDRESS_FOR_NGU: 192.168.70.129
      GNB_PORT_FOR_S1U: 2152

MACRLCs:
  - tr_s_preference: local_L1   # Group I: must match L1s.tr_n_preference
    tr_n_preference: local_RRC
    pusch_TargetSNRx10: 200
    pucch_TargetSNRx10: 200
    ul_prbblack_SNR_threshold: 10
    ulsch_max_frame_inactivity: 5
    SliceConf: "/home/nobre/oranslice2/ORANSlice/rrmPolicy.json"

L1s:
  - tr_n_preference: local_mac  # Group I: must match MACRLCs.tr_s_preference
    prach_dtx_threshold: 120
    pucch0_dtx_threshold: 100
    odfm_offset_divisor: 8
    pusch_proc_threads: 8

RUs:
  - local_rf: yes
    nb_tx: 1
    nb_rx: 1
    att_tx: 0         # Group G: 0 for OTA
    att_rx: 0         # Group G: 0 for OTA
    bands: [78]
    max_pdschReferenceSignalPower: -27
    max_rxgain: 75
    eNB_instances: [0]
    sdr_addrs: "addr=192.168.40.2,clock_source=internal,time_source=internal,send_frame_size=8000,recv_frame_size=8000"

THREAD_STRUCT:
  - parallel_config: PARALLEL_RU_L1_SPLIT
    worker_config: WORKER_ENABLE

security:
  ciphering_algorithms: [nea0]
  integrity_algorithms: [nia2, nia0]
  drb_ciphering: yes
  drb_integrity: no

log_config:
  global_log_level: info
  hw_log_level: info
  phy_log_level: info
  mac_log_level: info
  rlc_log_level: info
  pdcp_log_level: info
  rrc_log_level: info
  ngap_log_level: debug
  f1ap_log_level: info
```

---

## 6. Launch Command

```bash
cd ~/ORANSlice/oai_ran/cmake_targets/ran_build/build

sudo nohup ./nr-softmodem \
  -O /path/to/gnb.yaml \
  --sa \
  --usrp-tx-thread-config 1 \
  --thread-pool 0,2,4,6 \
    > /var/log/oai/gnb_$(date +%Y%m%d_%H%M%S).log 2>&1 &

# sudo ./nr-softmodem \
#   -O /path/to/gnb.yaml \
#   --sa \
#   --usrp-tx-thread-config 1 \
#   --thread-pool 0,2,4,6
```

**Pre-flight checklist:**
```bash
# 1. USRP reachable and at correct IP
uhd_find_devices --args "addr=192.168.40.2"

# 2. Verify 10 GbE can sustain 106 PRB sample rate (46.08 MSps)
benchmark_rate --args "addr=192.168.40.2" \
  --rx_rate 46.08e6 --tx_rate 46.08e6 --duration 10
# Expect: 0 overflows, 0 underflows, 0 dropped

# 3. CPU governor
sudo cpupower frequency-set -g performance

# 4. CN containers running
docker ps | grep -E "oai-amf|oai-smf|oai-upf|oai-nrf"

# 5. AMF reachable
ping -c 3 192.168.70.132

# 6. demo-oai interface up
ip addr show demo-oai
```
