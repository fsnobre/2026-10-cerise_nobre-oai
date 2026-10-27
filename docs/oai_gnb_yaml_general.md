# OAI gNB YAML Configuration Reference

> **Scope:** General reference for any OAI `nr-softmodem` deployment.  
> **Stack:** OAI `develop` branch, YAML config format, monolithic SA gNB.  
> **Not covered:** CU/DU split (F1), O-RU fronthaul (eCPRI/FHAPI).

---

## Tier Definitions

Every parameter in this document is classified as one of:

| Tier | Meaning |
|---|---|
| **Required** | OAI crashes, asserts, or refuses to start without it. No safe default exists. |
| **Recommended** | OAI starts and runs without it, but behaviour may be wrong, unpredictable, or silently broken. A default exists but it is either incorrect for most deployments or context-dependent. |
| **Optional** | Has a safe, correct default. Only needed to override that default. |

---

## 1. Top-Level Blocks

```
Active_gNBs     Required   — which entry in gNBs[] is active
gNBs[]          Required   — identity, cell config, AMF address, network interfaces
MACRLCs[]       Required   — MAC/RLC layer
L1s[]           Required   — PHY layer
RUs[]           Required   — radio unit / RF frontend
Asn1_verbosity  Optional   — ASN.1 trace verbosity; default "none"
security        Recommended — ciphering/integrity; has defaults but should be explicit
log_config      Optional   — all modules default to "info"
THREAD_STRUCT   Recommended — defaults to PARALLEL_SINGLE_THREAD, which is inadequate for OTA
```

---

## 2. Parameter Reference

### 2.1 Identity & Core Connectivity (`gNBs[]`)

| Parameter | Tier | Notes |
|---|---|---|
| `gNB_ID` | Required | 20-bit identifier. Must match AMF config. |
| `gNB_name` | Required | Referenced by `Active_gNBs`. |
| `tracking_area_code` | Required | Range: 1–16777215. Must match AMF TAC — NGAP setup fails otherwise, but gNB starts. |
| `plmn_list[].mcc` | Required | Mobile Country Code. Test PLMN: 001. |
| `plmn_list[].mnc` | Required | Mobile Network Code. Test PLMN: 01. |
| `plmn_list[].mnc_length` | Required | 2 or 3. |
| `plmn_list[].snssaiList` | Required | At least one `{sst, sd}` entry. |
| `nr_cellid` | Required | 36-bit NR Cell Identity. Unique per PLMN. |
| `amf_ip_address[].ipv4` | Required | AMF N2 interface IP. Without it, SCTP cannot connect. |
| `NETWORK_INTERFACES.GNB_INTERFACE_NAME_FOR_NG_AMF` | Recommended | OAI auto-detects if absent, but may bind the wrong interface on multi-homed hosts. |
| `NETWORK_INTERFACES.GNB_IPV4_ADDRESS_FOR_NG_AMF` | Recommended | Same fallback behaviour as above. |
| `NETWORK_INTERFACES.GNB_INTERFACE_NAME_FOR_NGU` | Recommended | Same. Without it, N3 GTP-U traffic may go out the wrong interface, causing silent TEID drops. |
| `NETWORK_INTERFACES.GNB_IPV4_ADDRESS_FOR_NGU` | Recommended | Same. |
| `NETWORK_INTERFACES.GNB_PORT_FOR_S1U` | Optional | Always 2152 per 3GPP spec. OAI hardcodes this. |

---

### 2.2 Cell-Level Physical Parameters (`gNBs[]`)

| Parameter | Tier | Default | Range / Notes |
|---|---|---|---|
| `min_rxtxtime` | Recommended | 6 | Slots between RX and TX response. 6 for 10 GbE, 8 for 1 GbE. Default is usually correct but depends on transport. |
| `do_SRS` | Optional | 0 | Enables UL sounding. Recommended to set 1 for connected-mode channel tracking. |
| `do_CSIRS` | Optional | 0 | Enables CSI-RS. Recommended to set 1 for DL channel quality feedback. |
| `pdsch_AntennaPorts` | Optional | 1 | DL antenna ports. 1=SISO. |
| `pusch_AntennaPorts_XP` | Optional | 1 | UL antenna ports. |

---

### 2.3 Serving Cell Config Common (`servingCellConfigCommon[]`)

Broadcast in SIB1. Getting these wrong prevents UEs from camping on the cell.

#### Frequency

| Parameter | Tier | Notes |
|---|---|---|
| `absoluteFrequencySSB` | Required | SSB center in NR-ARFCN. What UEs scan for during cell search. |
| `dl_absoluteFrequencyPointA` | Required | Lowest subcarrier reference (Point A) in NR-ARFCN. |
| `dl_offstToCarrier` | Optional | Offset from Point A to first carrier RB. Default 0, almost always 0. |
| `dl_subcarrierSpacing` | Required | 0=15k 1=30k 2=60k 3=120k. Must be consistent — see Section 4. |
| `dl_carrierBandwidth` | Required | **Number of RBs in the carrier, not MHz.** See table below. Must equal BWP L value — see Section 4, Group A. |
| `ul_frequencyBand` | Required | NR band number. For TDD, same band as DL. |
| `ul_offstToCarrier` | Optional | Default 0. |
| `ul_subcarrierSpacing` | Required | Must match `dl_subcarrierSpacing` for TDD — see Section 4, Group B. |
| `ul_carrierBandwidth` | Required | Same rules as `dl_carrierBandwidth`. Must match DL for TDD. |
| `pMax` | Optional | Max UE TX power (dBm). Default per band spec. |

**Carrier bandwidth lookup (30 kHz SCS):**

| Channel BW | RBs (`dl_carrierBandwidth`) | `locationAndBandwidth` (RBstart=0) |
|---|---|---|
| 10 MHz | 25 | 275×24 = **6600** |
| 20 MHz | 51 | 275×50 = **13750** |
| 40 MHz | 106 | 275×105 = **28875** |
| 50 MHz | 133 | 275×132 = **36300** |

> **Formula:** `locationAndBandwidth = 275 × (L − 1) + RBstart`

#### Initial BWP

| Parameter | Tier | Notes |
|---|---|---|
| `initialDLBWPlocationAndBandwidth` | Required | Encodes {RBstart, L}. L **must** match `dl_carrierBandwidth`. |
| `initialDLBWPsubcarrierSpacing` | Required | Must match `dl_subcarrierSpacing`. |
| `initialDLBWPcontrolResourceSetZero` | Required | CORESET#0 index. Valid values depend on SCS + carrier BW (TS 38.213 Table 13-1). |
| `initialDLBWPsearchSpaceZero` | Optional | Search Space #0 index. Default 0 is almost always correct. |
| `initialULBWPlocationAndBandwidth` | Required | Same formula. L must match `ul_carrierBandwidth`. |
| `initialULBWPsubcarrierSpacing` | Required | Must match `ul_subcarrierSpacing`. |

#### RACH

| Parameter | Tier | Default | Range | Notes |
|---|---|---|---|---|
| `prach_ConfigurationIndex` | Required | — | 0–255 | PRACH format and periodicity. TS 38.211 Table 6.3.3.2-2. |
| `prach_msg1_FDM` | Optional | 0 | 0–3 | Frequency occasions: 0=×1, 1=×2, 2=×4, 3=×8. |
| `prach_msg1_FrequencyStart` | Optional | 0 | 0–(BW-1) | PRB offset for PRACH occasions. |
| `zeroCorrelationZoneConfig` | Required | — | 0–15 | Needed for preamble sequence generation. Higher = larger cell support, fewer orthogonal sequences. |
| `preambleReceivedTargetPower` | Required | — | −202 to −60 dBm | No safe default. UE ramps TX power toward this value. |
| `preambleTransMax` | Required | — | 0–10 → 3,4,5,6,7,8,10,20,50,100,200 | Max preamble retransmissions. |
| `powerRampingStep` | Required | — | 0–3 → 0,2,4,6 dB | TX power ramp per retry. |
| `ra_ResponseWindow` | Recommended | **4** | 1,2,4,8,10,20,40,80 slots | Default (4) is too tight for SDR hardware OTA. Always set explicitly. Use 10 for USRP. |
| `ra_ContentionResolutionTimer` | Required | — | 0–7 → 8,16,...,64 ms | Msg4 deadline. Value 7 = 64 ms. |
| `ssb_perRACH_OccasionAndCB_PreamblesPerSSB_PR` | Required | — | 1–8 | SSB-to-RACH-occasion ratio type. 4=one. |
| `ssb_perRACH_OccasionAndCB_PreamblesPerSSB` | Required | — | 0–15 → 4,8,...,64 | CB preambles per SSB. |
| `prach_RootSequenceIndex_PR` | Required | — | 1=L839, 2=L139 | Determines valid index range — see Section 4, Group D. |
| `prach_RootSequenceIndex` | Required | — | 0–837 (L839) / 0–137 (L139) | Starting root sequence. |
| `msg1_SubcarrierSpacing` | Required | — | 0–3 | Must be consistent with `dl_subcarrierSpacing` for FR1 sub-6 GHz. |
| `restrictedSetConfig` | Required | — | 0–2 | 0=unrestricted (normal). |
| `msg3_DeltaPreamble` | Required | — | −1 to 8 | Msg3 power offset vs preamble (dB). |
| `p0_NominalWithGrant` | Required | — | −202 to 24 dBm | Nominal P0 for PUSCH power control. |

#### PUCCH

| Parameter | Tier | Default | Notes |
|---|---|---|---|
| `pucchGroupHopping` | Optional | 0 | 0=none, 1=group, 2=sequence. |
| `hoppingId` | Optional | — | Cell-specific hopping ID. |
| `p0_nominal` | Optional | — | Nominal P0 for PUCCH power control. |

#### SSB

| Parameter | Tier | Default | Notes |
|---|---|---|---|
| `ssb_PositionsInBurst_PR` | Required | — | OAI crashes without it. 1=short(1), 2=medium(4), 3=long(8/64). Must match frequency band — see Section 4, Group E. |
| `ssb_PositionsInBurst_Bitmap` | Required | — | Bitmap of active SSBs. Must be consistent with PR. |
| `ssb_periodicityServingCell` | Recommended | 2 (20 ms) | Default is 20 ms, which is correct for most cases. Set explicitly for clarity. |
| `ssPBCH_BlockPower` | Recommended | — | SSB TX power (dBm). Affects UE open-loop power control. Should match actual TX power. |

#### Cell-Level SCS & TDD

| Parameter | Tier | Notes |
|---|---|---|
| `subcarrierSpacing` | Recommended | Cell-level SCS, must match `dl_subcarrierSpacing`. OAI derives it if absent but being explicit avoids ambiguity. |
| `dmrs_TypeA_Position` | Optional | 0=symbol2 (default), 1=symbol3. |
| `referenceSubcarrierSpacing` | Recommended | SCS for TDD timing reference. Must match `dl_subcarrierSpacing` — see Section 4, Group B. |
| `dl_UL_TransmissionPeriodicity` | Required | 0=0.5ms 1=0.625ms 2=1ms 3=1.25ms 4=2ms 5=2.5ms 6=5ms 7=10ms |
| `nrofDownlinkSlots` | Required | Full DL slots per period. |
| `nrofDownlinkSymbols` | Required | DL symbols in special slot. Must satisfy: DL + guard + UL = 14 — see Section 4, Group C. |
| `nrofUplinkSlots` | Required | Full UL slots per period. |
| `nrofUplinkSymbols` | Required | UL symbols in special slot. |

**Common TDD patterns at 30 kHz SCS, 5 ms period (10 slots):**

| Pattern | DL slots | DL syms | Guard | UL syms | UL slots | DL:UL |
|---|---|---|---|---|---|---|
| DDDSUUU | 7 | 6 | 4 | 4 | 2 | ~3:1 |
| DDDDSUU | 7 | 10 | 2 | 2 | 2 | ~4:1 |
| DDSUUU  | 6 | 6 | 4 | 4 | 3 | ~2:1 |

---

### 2.4 SCTP

| Parameter | Tier | Notes |
|---|---|---|
| `SCTP_INSTREAMS` | Optional | Default 2. Controls SCTP stream count for N2. |
| `SCTP_OUTSTREAMS` | Optional | Default 2. |

---

### 2.5 MAC/RLC (`MACRLCs[]`)

| Parameter | Tier | Default | Notes |
|---|---|---|---|
| `tr_s_preference` | Required | — | Transport to L1. `local_L1` for monolithic. Must match L1s — see Section 4, Group I. |
| `tr_n_preference` | Required | — | Transport to RRC. `local_RRC` for monolithic. |
| `pusch_TargetSNRx10` | Optional | 200 | Target UL SNR ×10 (200 = 20 dB). |
| `pucch_TargetSNRx10` | Optional | 200 | Target PUCCH SNR ×10. |
| `ul_prbblack_SNR_threshold` | Optional | — | PRBs below this SNR (dB) are blacklisted. |
| `ulsch_max_frame_inactivity` | Optional | 0 | Frames of UL silence before UE release. 0=disabled. Value 1 is aggressive for lab use. |
| `SliceConf` | Optional (Required for ORANSlice) | — | Path to `rrmPolicy.json`. Without it, NVS scheduler is disabled and xApp slice commands have no effect. |

---

### 2.6 L1 (`L1s[]`)

| Parameter | Tier | Default | Notes |
|---|---|---|---|
| `tr_n_preference` | Required | — | Transport to MAC. `local_mac` for monolithic. Must match MACRLCs — see Section 4, Group I. |
| `prach_dtx_threshold` | Optional | 120 | PRACH energy detection threshold (linear). |
| `pucch0_dtx_threshold` | Optional | 100 | PUCCH format 0 detection threshold. |
| `pusch_proc_threads` | Recommended | 1 | Default (1) is insufficient for 106 PRBs with multiple UEs. Set to physical core count. |
| `odfm_offset_divisor` | Optional | 8 | OFDM timing correction divisor. 8 is correct for most USRP deployments. |

---

### 2.7 Radio Unit (`RUs[]`)

| Parameter | Tier | Default | Notes |
|---|---|---|---|
| `local_rf` | Required | — | `yes` for integrated RF (USRP). `no` for split RU. |
| `nb_tx` | Required | — | TX antenna count. |
| `nb_rx` | Required | — | RX antenna count. |
| `bands` | Required | — | NR band list, e.g. `[78]`. |
| `eNB_instances` | Required | — | Maps RU to gNB instance. `[0]` for single gNB. |
| `sdr_addrs` | Required | — | UHD device string. OAI cannot find the USRP without it. |
| `max_rxgain` | Required | — | UHD RX gain (dB). No safe default — depends on daughterboard and band. |
| `att_tx` | Optional | 0 | Software TX attenuation (dB). 0 for OTA, non-zero for cabled bench with physical attenuators. |
| `att_rx` | Optional | 0 | Same rule as `att_tx`. |
| `max_pdschReferenceSignalPower` | Recommended | — | Reference signal power (dBm) used for UE path loss estimation. Affects open-loop power control. |

**`sdr_addrs` key fields:**

| Key | Tier | Notes |
|---|---|---|
| `addr` | Required | USRP IP address. |
| `type` | Optional | e.g. `x300`. Speeds up device discovery. |
| `clock_source` | Recommended | `internal`, `external`, `gpsdo`. OAI assumes internal if absent, but being explicit prevents UHD surprises. |
| `time_source` | Recommended | Same values. Should match `clock_source`. |
| `send_frame_size` | Optional | UHD TX frame size (bytes). 8000 reduces TX latency on 10 GbE. |
| `recv_frame_size` | Optional | UHD RX frame size (bytes). Same. |

---

### 2.8 Threading (`THREAD_STRUCT`)

| Parameter | Tier | Default | Notes |
|---|---|---|---|
| `parallel_config` | Recommended | `PARALLEL_SINGLE_THREAD` | Default is inadequate for OTA. Use `PARALLEL_RU_L1_SPLIT` as minimum, `PARALLEL_RU_L1_TRX_SPLIT` for high load. |
| `worker_config` | Optional | `WORKER_ENABLE` | Keep enabled. |

---

### 2.9 Security

The entire `security` block is **Recommended**. OAI has defaults (`nea0`, `nia2`) but they should be set explicitly since security configuration has deployment-wide implications.

| Parameter | Default | Notes |
|---|---|---|
| `ciphering_algorithms` | `[nea0]` | Preference list. `nea0` = null (lab/debug, Wireshark-readable). `nea2` = AES-128 (production). |
| `integrity_algorithms` | `[nia2, nia0]` | `nia2` is mandatory for 5G NR. |
| `drb_ciphering` | `yes` | Applies ciphering to data bearers. |
| `drb_integrity` | `no` | Integrity on DRBs is optional per 3GPP and computationally expensive. |

---

### 2.10 Log Config

Entirely **Optional** — all modules default to `info`. Only set explicitly to change a specific module.

```yaml
log_config:
  global_log_level: info    # Catch-all: none|error|warn|info|debug|trace
  hw_log_level: info        # UHD/RF hardware
  phy_log_level: info       # L1: PRACH, PDSCH, PUSCH, PUCCH
  mac_log_level: info       # MAC scheduler, RA procedure
  rlc_log_level: info       # RLC segmentation/reassembly
  pdcp_log_level: info      # PDCP sequence numbering, ciphering
  rrc_log_level: info       # RRC connection, reconfiguration
  ngap_log_level: info      # N2 (AMF ↔ gNB)
  f1ap_log_level: info      # F1 (CU-DU split only)
```

> **Warning:** `debug` or `trace` on `phy_log_level` or `mac_log_level` generates enough output to cause timing misses OTA. Use only for offline post-mortem analysis, not during live experiments.

---

## 3. Common Errors, Causes, and Fixes

> **The symptom-first view of this material lives in
> [`oai_troubleshooting_testbed.md`](oai_troubleshooting_testbed.md).** That file is
> indexed by the literal log string OAI emits and records, for each failure, the
> *confirmed* cause plus a "do not chase" line. Use it when you are holding a log.
> Use this section when you are holding a parameter: **this reference remains
> authoritative for parameter values**, ranges, and tiers. The two overlap on purpose
> and are not meant to be merged.

### 3.1 RA Failure: Msg3 Never Received

**Symptoms:**
```
[NR_MAC] Random Access 0 failed at state WAIT_Msg3 (Reached msg3 max harq rounds)
[NR_MAC] no RA proc for RNTI 0xXXXX in Msg3/PUSCH
[NR_MAC] exceeded RA window: preamble at X.Y now X.Z (diff N), ra_ResponseWindow 4/10 slots
```

| Cause | Fix |
|---|---|
| `ra_ResponseWindow` too small (default 4) | Set `ra_ResponseWindow: 10` |
| `att_tx`/`att_rx` non-zero for OTA | Set both to 0 |
| `max_rxgain` too low | Increase toward 75–80 dB for USRP Band 78 |
| `PARALLEL_SINGLE_THREAD` — scheduling misses | Set `parallel_config: PARALLEL_RU_L1_SPLIT` |
| `dl_carrierBandwidth` ≠ BWP L value | Make consistent (Section 4, Group A) |
| NVS slice scheduler blocking Msg3 grant | Verify RA grants bypass per-slice PRB cap |

**Log levels:**
```yaml
mac_log_level: debug    # Full RA state machine
phy_log_level: debug    # PRACH detection energy, slot timing
```
**CN check:** If Msg3 succeeds but RRC Setup fails, check AMF for NGAP `InitialUEMessage` — PLMN/TAC mismatch appears here, not in the gNB log.

---

### 3.2 Unknown TEID

**Symptoms:**
```
[GTPU] Received a incoming packet on unknown teid (XXXXXXXX) Dropping!
```

| Cause | Fix |
|---|---|
| UE reconnected, old PDU session not torn down | Check SMF/UPF logs for dangling session; restart CN |
| RA failed mid-session — UE released but UPF still forwarding | Fix RA failure (Section 3.1) |
| `GNB_IPV4_ADDRESS_FOR_NGU` wrong or interface missing | Verify N3 reachability between gNB and UPF |
| N2 PDU session setup message lost | Check `ngap_log_level: debug` for `PDUSessionResourceSetupRequest` |

**Log levels:**
```yaml
ngap_log_level: debug
```
**CN check:** `docker logs oai-smf 2>&1 | grep -i teid` and `docker logs oai-upf 2>&1 | grep -i "far\|pdr\|teid"`.

---

### 3.3 Invalid Timing Advance Offset

**Symptoms:**
```
[NR_MAC] Invalid timing advance offset for RNTI XXXX
```

| Cause | Fix |
|---|---|
| SDR internal clock drift (no external reference) | Add external 10 MHz + PPS; or accept degraded TA stability |
| `clock_source`/`time_source` absent from `sdr_addrs` | Add `clock_source=internal,time_source=internal` explicitly |
| `do_SRS: 0` — no UL sounding for TA tracking | Set `do_SRS: 1` |
| `PARALLEL_SINGLE_THREAD` causing gNB timing jitter | Switch to `PARALLEL_RU_L1_SPLIT` |

**Log levels:**
```yaml
phy_log_level: debug    # Raw TA measurements per slot (very verbose)
mac_log_level: debug    # TA command generation
```
**CN check:** Not needed — purely a RAN-layer timing issue.

---

### 3.4 PDCP Discard Flood

**Symptoms:**
```
[PDCP] discard NR PDU rcvd_count=X, entity->rx_deliv Y, sdu_in_list 0
```
`rcvd_count` << `rx_deliv` means the PDCP RX window advanced past the arriving PDU's sequence number.

| Cause | Fix |
|---|---|
| UL radio link failures → late RLC retransmissions | Fix underlying RF/timing issue (Sections 3.1, 3.3) |
| UE going out of coverage | Physical/RF |

**Log levels:**
```yaml
pdcp_log_level: debug   # RX window state per bearer
rlc_log_level: debug    # Retransmission counts
```
**CN check:** Check for GTP-U retransmission storms: `tcpdump -i <N3_iface> udp port 2152`. If the same sequence is retransmitted repeatedly, the root cause is on the N3 path.

---

### 3.5 `cannot find free CCE for Msg2`

**Symptoms:**
```
[NR_MAC] UE RNTI XXXX: cannot find free CCE for Msg2!
```
PDCCH CCE pool exhausted; RAR cannot be scheduled.

| Cause | Fix |
|---|---|
| Multiple simultaneous RA attempts | Normal under load; increase `ssb_perRACH_OccasionAndCB_PreamblesPerSSB` |
| `initialDLBWPcontrolResourceSetZero` misconfigured | Verify CORESET#0 index for SCS + BW (TS 38.213 Table 13-1) |
| Slice scheduler limiting PDCCH (ORANSlice) | RA resources must be excluded from NVS slice budget |
| `PARALLEL_SINGLE_THREAD` — PDCCH scheduling falls behind | Switch to `PARALLEL_RU_L1_SPLIT` |

**Log levels:**
```yaml
mac_log_level: debug
```

---

### 3.6 `L` (Late) and `ERROR_CODE_OVERFLOW`

**Symptoms:**
```
[HW]  LLLLLLLLLLLL
[UHD] ERROR_CODE_OVERFLOW
[UHD] Tx while waiting for EOB, timed out
```
`L` = TX slot submitted after its deadline. Overflow = USRP FIFO full.

| Cause | Fix |
|---|---|
| `PARALLEL_SINGLE_THREAD` cannot keep up | Switch to `PARALLEL_RU_L1_SPLIT` |
| 106 PRBs over 1 GbE link | Use 10 GbE (XG FPGA image) |
| CPU frequency scaling active | Set performance governor; disable C-states in BIOS |
| UHD / FPGA image version mismatch | Run `uhd_images_downloader` to match installed UHD |
| IRQ affinity conflict on processing cores | Add `--thread-pool 0,2,4,6` to launch command |
| `send/recv_frame_size` not tuned | Add `send_frame_size=8000,recv_frame_size=8000` to `sdr_addrs` |
| `--usrp-tx-thread-config 1` missing | Add to launch command |

**Log levels:**
```yaml
hw_log_level: debug    # UHD timing events and buffer states
```
**CN check:** Not applicable.

---

### 3.7 UE Context Release — UL Failure Timer

**Symptoms:**
```
[MAC]    UE XXXX: request release after UL failure timer expiry
[NR_RRC] received UE Context Release Request for UE Y, forwarding to AMF
[RLC]    Remove UE ZZZZ
```

| Cause | Fix |
|---|---|
| `ulsch_max_frame_inactivity: 1` too aggressive | Increase to 5–10 for lab; 0 to disable |
| TA drift causing UL to miss reception window | Fix clock/timing (Section 3.3) |
| UE out of coverage | Physical/RF |

**Log levels:**
```yaml
mac_log_level: debug
rrc_log_level: debug
ngap_log_level: debug
```
**CN check:** After release, verify AMF received `UEContextReleaseComplete`. If not, the core may reject the next attach as a duplicate session.

---

### 3.8 NGAP Setup Failure

**Symptoms:**
```
[NGAP] NG Setup failure
```
gNB starts and SCTP connects, but AMF rejects the setup.

| Cause | Fix |
|---|---|
| `tracking_area_code` mismatch | Must match AMF TAC |
| `mcc`/`mnc` mismatch | Must match AMF PLMN config |
| `snssaiList` entry not in AMF slice list | Add slice to AMF `supported_slice_list` |
| AMF unreachable | `ping <amf_ip>` from gNB host |

**Log levels:**
```yaml
ngap_log_level: debug    # Full NGAP message exchange
```

---

## 4. Parameter Dependencies and Compliance

This section covers parameters that must be **mutually consistent**. Setting them independently without checking compliance is the most common source of confusing runtime failures.

---

### Group A — Carrier ↔ BWP (HARD: OAI asserts or UE gets malformed RRC)

```
dl_carrierBandwidth  ←→  initialDLBWPlocationAndBandwidth (L field)
ul_carrierBandwidth  ←→  initialULBWPlocationAndBandwidth (L field)
dl_carrierBandwidth  =   ul_carrierBandwidth  (for TDD)
```

The L value embedded in `locationAndBandwidth` must equal the carrier bandwidth in RBs. They are set independently, so a mismatch is easy to introduce and OAI may not always catch it at startup — the UE receives contradictory information and fails to attach.

| `dl_carrierBandwidth` | Correct `locationAndBandwidth` | Wrong (silent failure) |
|---|---|---|
| 25 | 6600 | 13750 (declares 51-RB BWP on a 25-RB carrier) |
| 51 | 13750 | 28875 (declares 106-RB BWP on a 51-RB carrier) |
| 106 | 28875 | 13750 (declares 51-RB BWP on a 106-RB carrier) |

---

### Group B — SCS Consistency (HARD: OAI asserts on mismatch)

All of these must carry the same value:

```
dl_subcarrierSpacing
ul_subcarrierSpacing          # TDD: must match DL
initialDLBWPsubcarrierSpacing
initialULBWPsubcarrierSpacing
msg1_SubcarrierSpacing        # FR1 sub-6 GHz: must match data SCS
subcarrierSpacing             # Cell-level: must match DL
referenceSubcarrierSpacing    # TDD reference: must match DL
```

A mismatch between any pair causes either an OAI assert at startup or silent misalignment between the carrier configuration and the broadcast system information.

---

### Group C — TDD Pattern Arithmetic (SOFT: OAI accepts invalid configs, RF fails)

OAI does not validate TDD arithmetic at startup. An invalid configuration is accepted, but the resulting slot structure violates 3GPP timing rules.

**Rule 1 — Special slot budget:**
```
nrofDownlinkSymbols + nrofUplinkSymbols ≤ 14
Guard symbols = 14 - nrofDownlinkSymbols - nrofUplinkSymbols
```
Guard must be ≥ 1. A guard of 0 means TX and RX overlap — hardware may saturate.

**Rule 2 — Slots per period:**
```
slots_per_period = periodicity_ms × SCS_slots_per_ms
  where SCS_slots_per_ms: 15k→1, 30k→2, 60k→4, 120k→8

nrofDownlinkSlots + nrofUplinkSlots + 1 (special slot) ≤ slots_per_period
```

Example at 30 kHz SCS, 5 ms period: slots_per_period = 10. Valid: 7D+1S+2U = 10. Invalid: 8D+1S+2U = 11 (exceeds period).

---

### Group D — PRACH Root Sequence ↔ Format (HARD: preamble detection fails)

```
prach_RootSequenceIndex_PR = 1  →  prach_RootSequenceIndex range: 0–837
prach_RootSequenceIndex_PR = 2  →  prach_RootSequenceIndex range: 0–137
```

Setting PR=2 (short, L=139) but `prach_RootSequenceIndex = 200` is out of range — preamble sequences cannot be generated and RACH will never succeed.

Additionally, `prach_ConfigurationIndex` must be compatible with `msg1_SubcarrierSpacing` and the TDD periodicity. Not all configuration indices are valid for all SCS/periodicity combinations (TS 38.211 Table 6.3.3.2-2).

---

### Group E — SSB ↔ Band Consistency (SOFT: UEs may not find the cell)

```
ssb_PositionsInBurst_PR must match the frequency range:
  FR1 below 3 GHz  →  PR=1 (short, 1 SSB max)
  FR1 3–6 GHz      →  PR=2 (medium, 4 SSBs max)
  FR2              →  PR=3 (long, 64 SSBs max)
```

Setting PR=1 for Band 78 (3.3–3.8 GHz) limits the SSB burst to 1 entry, which is valid but sub-optimal. Setting PR=3 for FR1 declares 64 SSBs that will never be transmitted, which may confuse UE cell search.

`ssb_PositionsInBurst_Bitmap` bit count must not exceed the PR-defined maximum.

---

### Group F — CN Identity Alignment (SOFT: gNB starts, NGAP fails)

```
gNB config           ←→  AMF config
tracking_area_code   ←→  tac
mcc / mnc            ←→  PLMN list
snssaiList entries   ←→  supported_slice_list
```

For ORANSlice additionally:
```
snssaiList entries   ←→  rrmPolicy.json slice definitions
```

These mismatches do not prevent the gNB from starting. The failure manifests only when a UE tries to register: the AMF sends `NGSetupFailure` or rejects `InitialUEMessage`.

---

### Group G — RF Gain Coherence (SOFT: functional but degraded)

```
att_tx / att_rx = 0           when no physical attenuators in RF path
att_tx / att_rx = N (dB)      only when physical attenuators of N dB are inserted
max_rxgain                    must be appropriate for the daughterboard + band
ssPBCH_BlockPower             should reflect actual TX output power
```

`att_tx=14` without a physical 14 dB attenuator in the TX path effectively reduces transmitted power by 14 dB. OTA this typically means no UE can hear the gNB beyond a few centimetres.

`ssPBCH_BlockPower` is broadcast in SIB1 and used by UEs for open-loop UL power control. If it does not reflect actual TX power, UEs will miscalculate their UL transmit power, causing systematic Msg3 and PUSCH decode failures even when the downlink is working fine.

---

### Group H — Threading Coherence (SOFT: functional but unsustainable OTA)

```
parallel_config ←→ pusch_proc_threads ←→ available physical cores
```

`pusch_proc_threads` should not exceed the number of physical (non-hyperthreaded) cores available. Setting it higher than the core count causes thread contention that is worse than a lower thread count.

`PARALLEL_RU_L1_SPLIT` allocates separate threads for the RU and L1. Adding `pusch_proc_threads: 8` on top of that requires at minimum 2 (RU + L1) + 8 (PUSCH) = 10 logical threads to be useful. On a 6-core machine, `pusch_proc_threads: 4` is a better fit.

---

### Group I — Transport Preference Chain (HARD: crash if inconsistent)

```
MACRLCs.tr_s_preference  ←→  L1s  (how MAC talks to L1)
MACRLCs.tr_n_preference  ←→  RRC  (how MAC talks to RRC)
```

Valid combinations for monolithic SA gNB:

```yaml
MACRLCs:
  tr_s_preference: local_L1   # ← must match L1s being on the same process
  tr_n_preference: local_RRC

L1s:
  tr_n_preference: local_mac  # ← must match MACRLCs being on the same process
```

Mixing `local_*` with `f1ap` or `nfapi` variants on the same side of the chain causes OAI to attempt a split transport to a non-existent endpoint and crash at startup.

---

## 5. Launch Command

```bash
sudo ./nr-softmodem \
  -O /path/to/gnb.yaml \
  --sa \
  --usrp-tx-thread-config 1 \     # Dedicated UHD TX burst thread — always add for X300/X310
  --thread-pool 0,2,4,6           # Pin threads to physical cores (skip HT siblings)
```

**Pre-flight:**
- [ ] `uhd_find_devices` finds the USRP
- [ ] `benchmark_rate` at target sample rate runs without overflows
- [ ] CPU governor: `cpupower frequency-set -g performance`
- [ ] CN containers running and reachable
