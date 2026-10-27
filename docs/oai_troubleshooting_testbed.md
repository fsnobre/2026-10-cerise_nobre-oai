# OAI troubleshooting catalogue — this testbed

Date: 2026-08-17
Relevant topology: monolithic SA gNB, ORANSlice fork of OAI, USRP X310, Band 78,
106 PRB @ 30 kHz SCS, DDDSUUU.
Status: the RA/Msg3 blocker described below is **resolved**; the X310 clock-drift
and ORANSlice upstream-support items remain open.

Companion references in this repo: [gNB YAML — testbed](oai_gnb_yaml_testbed.md)
(the authoritative parameter values, of which this document is the symptom-first
view), [gNB YAML — general](oai_gnb_yaml_general.md),
[NR PRB / frequency reference](nr_prb_frequency_reference.md).

Validate a config against many of the rules referenced here with
`python3 scripts/validate_gnb_yaml.py <config>`.

---

## Purpose and how to use this document

This is the **centralised catalogue of recurring problems and their solutions** for
OTA work on this testbed. It exists because these failures recur across bring-ups
and the diagnosis is expensive to re-derive from logs each time.

Use it in this order:

1. Grep this file for the literal log string you are seeing.
2. Read the **confirmed cause** — not the plausible ones.
3. Check the **do not chase** line before opening any other investigation.

To extend it: add a new `## Pn —` section using the same five fields (symptom,
confirmed cause, fix, why it recurs, do not chase). Keep entries keyed on the exact
log text OAI emits, because that is what you will have in hand when you return.

---

## 1. The meta-lesson: RACH surviving does not mean the RX path is healthy

This is the single most valuable thing in the whole conversation, and the trap that
cost the most time.

The failure looked like a timing/scheduler problem and was initially diagnosed as
one. The actual cause was a single misconfigured attenuation value. The reasoning
that misled the diagnosis was:

> "Preamble energy is healthy at 32–34 dB above I0, so the RX chain works."

**That inference is wrong.** PRACH preamble detection has far more processing gain
than PUSCH. A degraded RX path decodes Msg1 cleanly and fails Msg3 consistently.
So "RACH is fine, therefore RX gain is fine, therefore this must be timing or the
slice scheduler" is a false chain — and it points the investigation at the two most
expensive things to test (clock hardware and scheduler internals) instead of the
cheapest (two config values).

**Rule for next time:** when Msg1 succeeds and Msg3 fails, suspect the RX budget
and the RA window *first*. Both are one-line config changes. Only after both are
ruled out should clock discipline or scheduler behaviour be considered.

Hypotheses that were investigated and turned out **not** to be the cause:

| Discarded hypothesis | Why it was appealing | Verdict |
|---|---|---|
| X310 TCXO drift breaking TA → Msg3 misses its window | `Invalid timing advance offset` really was in the log | Real but **separate** issue (P5); not the Msg3 cause |
| NVS slice scheduler starving the Msg3 grant of PRBs | Explained why RFsim worked and OTA did not | Not the cause; NVS was not even active (see P4) |
| NVS budget exhausting PDCCH CCEs | `cannot find free CCE for Msg2` appeared once | Incidental, single occurrence under load |

---

## 2. Symptom index

| Log string | Section |
|---|---|
| `Random Access 0 failed at state WAIT_Msg3 (Reached msg3 max harq rounds)` | [P1](#p1--msg3-never-decoded-ra-fails-at-wait_msg3) |
| `no RA proc for RNTI 0x… in Msg3/PUSCH` | [P1](#p1--msg3-never-decoded-ra-fails-at-wait_msg3) |
| `exceeded RA window: preamble at X.Y now X.Z … ra_ResponseWindow 4/10 slots` | [P2](#p2--preamble-detected-but-rar-never-sent) |
| `LLLLLLLL` / `ERROR_CODE_OVERFLOW` / `Tx while waiting for EOB, timed out` | [P3](#p3--l-flood-and-uhd-overflow-at-106-prb) |
| xApp reports `Test xApp run SUCCESSFULLY` but PRBs never change | [P4](#p4--oranslice-slice-control-silently-does-nothing) |
| `Invalid timing advance offset for RNTI …` | [P5](#p5--invalid-timing-advance-offset) |
| `discard NR PDU rcvd_count=X, entity->rx_deliv Y` | [P6](#p6--pdcp-discard-flood) |
| `UE …: request release after UL failure timer expiry` | [P7](#p7--premature-ue-context-release) |
| `Received a incoming packet on unknown teid (…) Dropping!` | [P8](#p8--unknown-teid-flood) |
| `cannot find free CCE for Msg2!` | [P9](#p9--cannot-find-free-cce-for-msg2) |
| `NG Setup failure` | [P10](#p10--ngap-ng-setup-failure) |

---

## P1 — Msg3 never decoded, RA fails at WAIT_Msg3

**Symptom**

```text
[NR_MAC] Random Access 0 failed at state WAIT_Msg3 (Reached msg3 max harq rounds)
[NR_MAC] no RA proc for RNTI 0x92b4 in Msg3/PUSCH
```

Repeats across multiple RNTIs. Msg1 is detected with healthy energy (32–34 dB above
I0) and Msg2/RAR is sent successfully. Only Msg3 fails.

**Confirmed cause**

`att_rx: 14` in the RU section with **no physical 14 dB attenuator in the RX path**.
Software attenuation is subtracted from real RX sensitivity, so this threw away
14 dB for nothing. That is enough to break PUSCH decode while leaving PRACH
detection working.

**Fix**

```yaml
att_tx: 0        # 0 for OTA. Non-zero ONLY with physical attenuators in TX path
att_rx: 0        # 0 for OTA. Non-zero ONLY with physical attenuators in RX path
max_rxgain: 75   # X310 SBX/UBX, Band 78 starting point
```

`max_rxgain` tuning ranges for X310 SBX/UBX on Band 78:

| Range | Effect |
|---|---|
| < 60 dB | Msg3 and PUSCH decode failures; UEs attach briefly then drop |
| 65–80 dB | Normal operating range |
| > 85 dB | ADC saturation; noise floor rises; RACH false alarms increase |

Frequently `att_rx` and `ra_ResponseWindow` (P2) are both wrong at once — fix both
before re-testing, or you will attribute a partial recovery to the wrong change.

**Why it recurs**

`att_tx`/`att_rx` are optional parameters that look like innocuous trim values, and
a config carried over from a cabled bench (where physical attenuators *were*
present) stays silently wrong once the attenuators come out. Nothing in the log
mentions attenuation.

**Do not chase:** clock discipline, the NVS scheduler, or PRB budgets until both
`att_rx: 0` and `ra_ResponseWindow: 10` are confirmed in the running config.

---

## P2 — Preamble detected but RAR never sent

**Symptom**

```text
[NR_MAC] exceeded RA window: preamble at 123.4 now 123.9 (diff 5), ra_ResponseWindow 4/10 slots
```

**Confirmed cause**

`ra_ResponseWindow` left at the default of `4`. This is too tight for X310 OTA
round-trip latency. Described in the source material as the primary RA failure
cause, alongside P1.

**Fix**

```yaml
ra_ResponseWindow: 10
```

Related RACH tuning, in order of usefulness:

| Symptom | Parameter | Action |
|---|---|---|
| Preamble detected but RAR never sent | `ra_ResponseWindow` | Increase to 10 |
| RAR sent but Msg3 never decoded | `max_rxgain` + `att_rx` | Raise gain; verify `att_rx: 0` (P1) |
| UE exhausts preambles | `preambleTransMax` | 6 → 7 (8 → 20 attempts) |
| Preambles consistently missed | `preambleReceivedTargetPower` | −96 → toward −90 |
| Multiple UEs collide on a preamble | `ssb_perRACH_OccasionAndCB_PreamblesPerSSB` | Increase |

**Why it recurs**

The OAI default is fine in RFsim and fine on a B210 at short range; it is wrong for
the X310. Every fresh config from upstream examples reintroduces it.

**Do not chase:** PRACH root sequence or `zeroCorrelationZoneConfig` — the preamble
*was* detected, so preamble configuration is already correct.

---

## P3 — `L` flood and UHD overflow at 106 PRB

**Symptom**

```text
[HW]  LLLLLLLLLLLL
[UHD] ERROR_CODE_OVERFLOW
[UHD] Tx while waiting for EOB, timed out
```

`L` = TX slot submitted after its deadline. Overflow = USRP FIFO full.

**Confirmed cause**

106 PRB @ 30 kHz SCS = 46.08 MSps, FFT 2048, a full DL/UL cycle every 0.5 ms slot.
`PARALLEL_SINGLE_THREAD` cannot sustain it.

**Fix — apply in order, stop when `L` disappears**

1. `parallel_config: PARALLEL_RU_L1_SPLIT` in `THREAD_STRUCT`
2. `pusch_proc_threads: 8` in `L1s`
3. Launch flags: `--usrp-tx-thread-config 1 --thread-pool 0,2,4,6`
4. `sudo cpupower frequency-set -g performance`
5. Disable C-states: `intel_idle.max_cstate=1` on the kernel cmdline
6. Still present: drop to 51 PRB (20 MHz) to prove the RF path, then return to 106

Also required in `sdr_addrs`: `send_frame_size=8000,recv_frame_size=8000` (default
1472 bytes adds UHD latency). Confirm the link is 10 GbE with the XG FPGA image —
106 PRB does not fit on 1 GbE.

> **Worth considering for ORANSlice work:** if the research question is slicing
> control logic rather than peak throughput, 51 PRB halves FFT size and CPU load and
> makes the testbed materially more stable. All carrier/BWP parameters must be
> updated consistently.

**Why it recurs**

Thread configuration is host-specific and does not travel with the YAML; a new
workstation or a kernel/BIOS change resets the governor and C-state assumptions.

**Diagnostic separator:** `benchmark_rate --args "addr=192.168.40.2"` showing 0
overflows/underflows proves the host+NIC+USRP path is fine and the problem is inside
OAI's threading — this distinction is what separates P3 from a genuine transport
problem.

---

## P4 — ORANSlice slice control silently does nothing

**Symptom**

The xApp completes the full subscribe → indicate → control → delete cycle and prints
`Test xApp run SUCCESSFULLY`, but PRB allocation in the gNB never changes.

**Confirmed cause**

`SliceConf` missing from `MACRLCs`. Without it OAI runs the **default round-robin
scheduler**, not NVS. The E2SM-RC control message is received and acknowledged
normally, so every layer reports success — the NVS handler is simply never invoked.

**Fix**

```yaml
MACRLCs:
  - SliceConf: "/home/nobre/oranslice2/ORANSlice/rrmPolicy.json"
```

**Verify at gNB startup:**

```text
[MAC] Loading slice configuration from /path/to/rrmPolicy.json
```

If that line is absent: wrong path, malformed JSON, or the binary is not the
ORANSlice build.

**Why it recurs**

This is the worst failure mode in the catalogue because **every observable signal
reports success**. There is no error anywhere. Only the absence of a startup log line
and the absence of a PRB change reveal it. Always confirm the startup line before
trusting any slicing measurement.

**Do not chase:** E2 subscription, RIC connectivity, or E2SM-RC encoding — an
acknowledged control message proves that entire path already works.

---

## P5 — `Invalid timing advance offset`

**Symptom**

```text
[NR_MAC] Invalid timing advance offset for RNTI f2a6
```

Repeats for the same RNTI on a connected UE; typically accompanied by PDCP discard
floods (P6) on that UE.

**Confirmed cause**

The X310 TCXO drifts with no external reference. Over minutes the measured
round-trip time changes enough that computed TA leaves the valid range
(0–3846 × 16 Ts).

**Status: open.** No external reference is currently connected.

**Mitigations without external clock**

- Set `clock_source=internal,time_source=internal` explicitly in `sdr_addrs` — never
  rely on the UHD default.
- Keep experiment runs short, before drift accumulates.
- Restart the gNB between runs to reset the timing reference.
- `do_SRS: 1` — without UL sounding there is no TA tracking.

**Permanent fix**

OctoClock-G or GPSDO 10 MHz into X310 REF IN, then:

```yaml
sdr_addrs: "addr=192.168.40.2,clock_source=external,time_source=external,send_frame_size=8000,recv_frame_size=8000"
```

For multi-cell (two X310s), **both** must share the same reference signal — chain
`REF OUT → REF IN` at minimum.

**Do not chase:** this is purely a RAN-layer timing issue. No CN check applies.
Critically, this is **not** the cause of P1 — the two coexist and were conflated.

---

## P6 — PDCP discard flood

**Symptom**

```text
[PDCP] discard NR PDU rcvd_count=334, entity->rx_deliv 770, sdu_in_list 0
```

`rcvd_count` ≪ `rx_deliv` means the PDCP RX window has advanced well past the
arriving PDU's sequence number.

**Confirmed cause**

Downstream symptom, not a root cause. UL radio link failures produce late RLC
retransmissions that arrive outside the window. Fix the underlying RF/timing issue
(P1, P5) and this clears.

**CN check if it persists after RF is healthy:** `tcpdump -i <N3_iface> udp port 2152`.
The same sequence retransmitted repeatedly points at the N3 path instead.

**Do not chase:** PDCP or RLC configuration. Treat this as an indicator, not a bug.

---

## P7 — Premature UE context release

**Symptom**

```text
[MAC]     UE 1259: request release after UL failure timer expiry
[NR_RRC]  received UE Context Release Request for UE 2, forwarding to AMF
[RLC]     Remove UE 1259
```

**Confirmed cause**

`ulsch_max_frame_inactivity: 1` is too aggressive for a lab environment, and is made
worse by any TA drift (P5) causing UL to miss its reception window.

**Fix**

```yaml
ulsch_max_frame_inactivity: 5    # 5–10 for lab; 0 disables entirely
```

**CN check:** after release, confirm the AMF received `UEContextReleaseComplete`.
If it did not, the core may reject the next attach as a duplicate session — which
then presents as an attach failure with no RAN-side explanation.

---

## P8 — Unknown TEID flood

**Symptom**

```text
[GTPU] Received a incoming packet on unknown teid (909cfd91) Dropping!
```

**Confirmed cause**

In this testbed, almost always **expected behaviour trailing a UE context release**,
not a bug. The UPF keeps forwarding downlink for a session the gNB has already torn
down. When it appears together with P1 and P7 in the same log, it is the last link in
the chain, not the problem.

Causal chain observed in the original log:

```text
att_rx: 14 (no physical attenuator)  +  ra_ResponseWindow: 4
    ↓
Msg3 never decoded → RA fails after max HARQ rounds      (P1, P2)
    ↓
UE context released after UL failure timer               (P7)
    ↓
UPF still forwarding DL for the stale session → TEID drops  (P8)
    ↓
PDCP RX window stalls → discard floods on other sessions (P6)
```

**Investigate as a real fault only when** it appears *without* RA failures. Then:

| Cause | Fix |
|---|---|
| Old PDU session not torn down after reconnect | Check SMF/UPF for a dangling session; restart CN |
| `GNB_IPV4_ADDRESS_FOR_NGU` wrong or interface missing | Verify N3 reachability gNB ↔ UPF |
| `PDUSessionResourceSetupRequest` lost | `ngap_log_level: debug` |

**CN check:** `docker logs oai-smf 2>&1 | grep -i teid` and
`docker logs oai-upf 2>&1 | grep -iE "far|pdr|teid"`.

---

## P9 — `cannot find free CCE for Msg2`

**Symptom**

```text
[NR_MAC] UE RNTI 5924: cannot find free CCE for Msg2!
```

PDCCH CCE pool exhausted, so the RAR cannot be scheduled.

**Assessment from the original log:** appeared **once**, for a single RNTI. A single
occurrence under concurrent RA load is normal and is not worth investigating. It was
initially over-read as evidence of NVS budget exhaustion — it was not (see P4: NVS
was not even running).

**Investigate only if sustained:**

| Cause | Fix |
|---|---|
| Multiple simultaneous RA attempts | Normal under load; raise `ssb_perRACH_OccasionAndCB_PreamblesPerSSB` |
| `initialDLBWPcontrolResourceSetZero` wrong | Verify CORESET#0 index for SCS + BW (TS 38.213 Table 13-1) |
| `PARALLEL_SINGLE_THREAD` — PDCCH scheduling falls behind | `PARALLEL_RU_L1_SPLIT` (P3) |

---

## P10 — NGAP NG Setup failure

**Symptom**

```text
[NGAP] NG Setup failure
```

gNB starts and SCTP connects, but the AMF rejects the setup. Always an identity
mismatch — the gNB is fine, the two configs disagree.

| Check | Command |
|---|---|
| `tracking_area_code` matches AMF | `docker exec oai-amf cat /openair-amf/etc/amf.conf \| grep tac` |
| `mcc` / `mnc` match AMF | Same file, PLMN section |
| `snssaiList` present in AMF | Same file, `supported_slice_list` |
| AMF reachable | `ping 192.168.70.132` from the CN host |
| `demo-oai` interface up | `ip addr show demo-oai` |

```yaml
ngap_log_level: debug    # shows NGSetupRequest and the failure cause code
```

---

## 3. Config values that were wrong, and what they should be

The complete delta from the original broken config. Check this table first on any new
bring-up.

| Parameter | Was | Should be | Consequence if wrong |
|---|---|---|---|
| `att_rx` | `14` | `0` | Msg3 never decodes; RACH still works (P1) |
| `att_tx` | non-zero | `0` | UE cannot hear the gNB beyond centimetres |
| `ra_ResponseWindow` | `4` (default) | `10` | RAR misses the window (P2) |
| `max_rxgain` | — | `75` | < 60 dB breaks PUSCH decode |
| `parallel_config` | `PARALLEL_SINGLE_THREAD` | `PARALLEL_RU_L1_SPLIT` | `L` flood at 106 PRB (P3) |
| `pusch_proc_threads` | — | `8` | Contributes to `L` flood |
| `SliceConf` | absent | path to `rrmPolicy.json` | NVS silently inactive (P4) |
| `ulsch_max_frame_inactivity` | `1` | `5`–`10` | Premature UE release (P7) |
| `clock_source` / `time_source` | absent | explicit `internal` | UHD default surprises; TA instability (P5) |
| `send_frame_size` / `recv_frame_size` | absent | `8000` | Extra UHD TX/RX latency (P3) |
| `do_SRS` | `0` | `1` | No UL sounding, so no TA tracking (P5) |

Launch flags that must be present for X310:

```bash
--usrp-tx-thread-config 1 --thread-pool 0,2,4,6
```

`--usrp-tx-thread-config 1` is in ORANSlice's own README for the X310 — its presence
there is an acknowledgement that this hardware needs the workaround.

---

## 4. First-five-minutes checklist

Before reading any gNB log on a fresh bring-up:

```bash
uhd_find_devices --args "addr=192.168.40.2"          # USRP reachable
benchmark_rate --args "addr=192.168.40.2" \
  --rx_rate 46.08e6 --tx_rate 46.08e6                # expect 0 overflow/underflow/dropped
cpupower frequency-info | grep governor              # expect performance
docker ps                                            # CN containers up
ping 192.168.70.132                                  # AMF reachable
ip addr show demo-oai                                # CN bridge up
```

Then, in the running gNB config, confirm: `att_rx: 0`, `att_tx: 0`,
`ra_ResponseWindow: 10`, `parallel_config: PARALLEL_RU_L1_SPLIT`, and — for slicing
work — the `[MAC] Loading slice configuration from …` startup line.

**Isolation rule:** if anything is failing, prove **vanilla OAI** works on the same
X310 with the same config before blaming ORANSlice. Until that baseline is stable,
the slicing layer is irrelevant. This one step would have shortcut most of the
original investigation.

Also verify the **TDD pattern matches between gNB and UE**. This testbed uses DDDSUUU
5 ms. A mismatch makes the UE transmit during the gNB's DL period and receive during
its UL period; the link simply will not work, with no obvious error naming the cause.

```text
Variant A (more robust OTA — guard = 14 − 6 − 4 = 4 symbols):
  nrofDownlinkSlots: 7  nrofDownlinkSymbols: 6
  nrofUplinkSlots: 2    nrofUplinkSymbols: 4

Variant B (ORANSlice original, higher DL capacity — guard = 2 symbols):
  nrofDownlinkSlots: 7  nrofDownlinkSymbols: 10
  nrofUplinkSlots: 2    nrofUplinkSymbols: 2
```

Variant A leaves more guard time for the X310's TX→RX switching latency.

---

## 5. ORANSlice upstream support: do not expect help

Findings from a web search conducted during the original conversation. **Counts are
as of that search (issue #2 dated November 2025) and will drift — re-check before
relying on them.**

- The [ORANSlice repository](https://github.com/wineslab/ORANSlice) had **1 open
  issue and no closed issues**. The single open issue asks about MTU configuration
  for a USRP X300 on 10 GbE — it is a question, not a defect report.
- **No public report exists of ORANSlice X310 OTA failures.**
- The published work used the Arena testbed (24 × USRP X310/X410 on Dell servers,
  10/100 Gbps switches) and X5G — infrastructure most users do not have.

**Practical conclusion:** this is a research code artifact, not a maintained product.
Running ORANSlice OTA on an X310 outside the wineslab group's own infrastructure is
close to unexplored territory. Do not budget time waiting on upstream responses, and
expect to file OAI/FlexRIC issues rather than ORANSlice ones — the problems in this
catalogue were all in the OAI PHY/MAC/UHD layer, not in ORANSlice's slicing logic.

---

## 6. Log levels by investigation

Raise only what you need — `phy_log_level: debug` is very verbose.

| Investigating | Set |
|---|---|
| RA state machine | `mac_log_level: debug` |
| PRACH detection energy, slot timing | `phy_log_level: debug` |
| Raw TA measurements per slot | `phy_log_level: debug` |
| TA command generation | `mac_log_level: debug` |
| UHD timing events, buffer states | `hw_log_level: debug` |
| PDCP RX window per bearer | `pdcp_log_level: debug` |
| RLC retransmission counts | `rlc_log_level: debug` |
| NGAP exchange and failure causes | `ngap_log_level: debug` |
| Context release path | `rrc_log_level: debug` + `ngap_log_level: debug` |

Note: if Msg3 succeeds but RRC Setup fails, the explanation is **not in the gNB log** —
check the AMF for NGAP `InitialUEMessage`, where PLMN/TAC mismatches surface.

---

## 7. Open items

| Item | Status |
|---|---|
| External 10 MHz / PPS reference for X310 (P5) | Open — no OctoClock/GPSDO connected. TA instability persists on long runs. |
| Both X310s sharing one reference for multi-cell | Open — required before distributed handover measurements are trustworthy. |
| Vanilla-OAI-vs-ORANSlice baseline comparison | Not recorded as run. Worth doing once and documenting, so it need not be re-argued. |
| Whether RA grants bypass the NVS per-slice PRB cap | Unverified. Became moot once P4 showed NVS was inactive, but matters once NVS is genuinely enabled. |

---

## 8. Provenance

Distilled from the troubleshooting content in this repo's own `docs/` — chiefly
section 3 of `oai_gnb_yaml_testbed.md` and `oai_gnb_yaml_general.md` — during an
ORANSlice OTA bring-up. Those files remain the authority on parameter *values*; this
document is the symptom-first index into them, and adds material they do not contain:
the log-string index, the misdiagnosis record in section 1, the P1→P8 causal chain,
and the "do not chase" lines.

Written first in `oai-rfsim-handover-testbed` (as
`docs/handoff-oranslice-x310-ota-debugging.md`) before this repository was located,
then moved here because the knowledge is cross-testbed. That repo now points here.

Values quoted are specific to this testbed: X310 at `192.168.40.2`, AMF at
`192.168.70.132`, Band 78, 106 PRB @ 30 kHz, DDDSUUU. When a symptom's fix turns out
to be hardware- or version-neutral, promote it into the `*_general.md` references
rather than leaving it only here.
