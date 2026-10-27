# oai/ — OAI / ORANSlice / 5G RAN knowledge base

> Formerly the standalone `cerise_oai` repository; merged into `cerise_nobre` with its
> full history on 2026-10-26.

Cross-testbed knowledge for OpenAirInterface work: gNB parameter references, a
symptom-indexed failure catalogue, handover notes for four different flavours, CU/DU
and 7.2x fronthaul splits, 20 annotated configs, and a static config validator. It is
the companion to **`oai-rfsim-handover-testbed`** (private), and the division of
responsibility is deliberate: **cross-testbed OAI knowledge lives here; the automation
for one specific RFsim/USRP handover testbed lives there.** If a fix turns out to be
hardware- and version-neutral, it belongs here. If it only makes sense against that one
testbed's scripts and topology, it belongs there.

---

## "I have an error"

**Grep first.** The catalogue is keyed on the literal text OAI emits, because that is
what you have in hand when you come back:

```bash
grep -rn "<the log string you are seeing>" docs/
```

Then find your line below. Every row links into
[`docs/oai_troubleshooting_testbed.md`](docs/oai_troubleshooting_testbed.md), which
carries the confirmed cause, the fix, why it recurs, and — most useful — a **do not
chase** line naming the expensive dead ends.

| Log string | Section |
|---|---|
| `Random Access 0 failed at state WAIT_Msg3 (Reached msg3 max harq rounds)` | [P1 — Msg3 never decoded](docs/oai_troubleshooting_testbed.md#p1--msg3-never-decoded-ra-fails-at-wait_msg3) |
| `no RA proc for RNTI 0x… in Msg3/PUSCH` | [P1 — Msg3 never decoded](docs/oai_troubleshooting_testbed.md#p1--msg3-never-decoded-ra-fails-at-wait_msg3) |
| `exceeded RA window: preamble at X.Y now X.Z … ra_ResponseWindow 4/10 slots` | [P2 — RAR never sent](docs/oai_troubleshooting_testbed.md#p2--preamble-detected-but-rar-never-sent) |
| `LLLLLLLL` | [P3 — `L` flood and UHD overflow](docs/oai_troubleshooting_testbed.md#p3--l-flood-and-uhd-overflow-at-106-prb) |
| `ERROR_CODE_OVERFLOW` | [P3 — `L` flood and UHD overflow](docs/oai_troubleshooting_testbed.md#p3--l-flood-and-uhd-overflow-at-106-prb) |
| `Tx while waiting for EOB, timed out` | [P3 — `L` flood and UHD overflow](docs/oai_troubleshooting_testbed.md#p3--l-flood-and-uhd-overflow-at-106-prb) |
| xApp reports `Test xApp run SUCCESSFULLY` but PRBs never change | [P4 — slice control silently does nothing](docs/oai_troubleshooting_testbed.md#p4--oranslice-slice-control-silently-does-nothing) |
| `Invalid timing advance offset for RNTI …` | [P5 — invalid timing advance offset](docs/oai_troubleshooting_testbed.md#p5--invalid-timing-advance-offset) |
| `discard NR PDU rcvd_count=X, entity->rx_deliv Y` | [P6 — PDCP discard flood](docs/oai_troubleshooting_testbed.md#p6--pdcp-discard-flood) |
| `UE …: request release after UL failure timer expiry` | [P7 — premature UE context release](docs/oai_troubleshooting_testbed.md#p7--premature-ue-context-release) |
| `Received a incoming packet on unknown teid (…) Dropping!` | [P8 — unknown TEID flood](docs/oai_troubleshooting_testbed.md#p8--unknown-teid-flood) |
| `cannot find free CCE for Msg2!` | [P9 — cannot find free CCE for Msg2](docs/oai_troubleshooting_testbed.md#p9--cannot-find-free-cce-for-msg2) |
| `NG Setup failure` | [P10 — NGAP NG Setup failure](docs/oai_troubleshooting_testbed.md#p10--ngap-ng-setup-failure) |

Two things in that file are worth reading even when nothing is broken: **§1**, which
records a misdiagnosis that cost the most time (RACH surviving does **not** mean the RX
path is healthy — Msg1 has far more processing gain than PUSCH), and **§4**, a
first-five-minutes checklist for a fresh bring-up.

If the symptom is a parameter question rather than a log line, go to the references
instead: the catalogue is indexed by *symptom*, and
[`docs/oai_gnb_yaml_testbed.md`](docs/oai_gnb_yaml_testbed.md) /
[`docs/oai_gnb_yaml_general.md`](docs/oai_gnb_yaml_general.md) are indexed by
*parameter* and remain authoritative for parameter **values**.

---

## Repository map

### `docs/` — 13 references

| File | Purpose |
|---|---|
| [`oai_troubleshooting_testbed.md`](docs/oai_troubleshooting_testbed.md) | Symptom-indexed failure catalogue, P1–P10. Start here when something is broken. |
| [`oai_gnb_yaml_general.md`](docs/oai_gnb_yaml_general.md) | Vendor-neutral gNB YAML parameter reference: every block, tiered Required/Recommended/Optional, plus dependency Groups A–I. |
| [`oai_gnb_yaml_testbed.md`](docs/oai_gnb_yaml_testbed.md) | The same reference with this testbed's concrete values, and a complete minimal working config. |
| [`nr_prb_frequency_reference.md`](docs/nr_prb_frequency_reference.md) | PRB ↔ bandwidth ↔ SCS tables, NR-ARFCN and Point A arithmetic, `locationAndBandwidth` values. |
| [`oai_handover_intra_gnb.md`](docs/oai_handover_intra_gnb.md) | Intra-gNB (inter-cell) handover: measurement config, A3 events, timers. |
| [`oai_handover_xn.md`](docs/oai_handover_xn.md) | Xn-based inter-gNB handover. |
| [`oai_handover_n2.md`](docs/oai_handover_n2.md) | N2 (AMF-routed) inter-gNB handover, for when there is no Xn. |
| [`oai_handover_ric.md`](docs/oai_handover_ric.md) | RIC-triggered handover via E2SM-RC. |
| [`xapp_handover_notes.md`](docs/xapp_handover_notes.md) | E2SM-RC IE mapping and A3 threshold/hysteresis tuning from the xApp side. |
| [`oai_f1_split_general.md`](docs/oai_f1_split_general.md) | CU/DU F1 split, vendor-neutral. |
| [`oai_f1_split_testbed.md`](docs/oai_f1_split_testbed.md) | CU/DU F1 split as deployed here. |
| [`oai_oru_fronthaul_general.md`](docs/oai_oru_fronthaul_general.md) | O-RAN 7.2x fronthaul and O-DU/O-RU configuration, vendor-neutral. |
| [`oai_oru_fronthaul_testbed.md`](docs/oai_oru_fronthaul_testbed.md) | 7.2x fronthaul with this lab's Benetel RAN550/RAN650 units. |

### `configs/` — 20 gNB / UE / O-RU configs

Naming is `gnb_<role>_<general|testbed>.{yaml,conf}`. See the convention section below.

| File(s) | Purpose |
|---|---|
| `gnb_annotated.yaml`, `gnb_annotated.conf` | The heavily annotated monolithic SA reference — Band 78, 106 PRB, X310. The `.conf` (libconfig) form exists because older ORANSlice `nr-softmodem` builds need it. Base config for every delta below. |
| `gnb_rfsim.yaml`, `gnb_rfsim.conf` | Same gNB under RFsim, with the changes from OTA marked inline. |
| `ue_rfsim.yaml` | Matching OAI nr-UE for RFsim. |
| `gnb_cu_general.yaml`, `gnb_cu_testbed.yaml` | F1 split — CU half. |
| `gnb_du_general.yaml`, `gnb_du_testbed.yaml` | F1 split — DU half. |
| `gnb_intra_handover_testbed.yaml` | Delta: intra-gNB handover. |
| `gnb_xn_gnb1_testbed.yaml`, `gnb_xn_gnb2_testbed.yaml` | Delta: Xn handover, source and target gNB. |
| `gnb_n2_handover_testbed.yaml` | Delta: N2 handover, applied to both gNBs. Differs from the Xn pair only by the absence of `gNB_XnAPConfig`. |
| `gnb_ric_handover_testbed.yaml` | Delta: RIC-triggered handover, adds the `e2_agent` block. |
| `gnb_odu_ran650_general.yaml`, `gnb_odu_ran650_testbed.yaml` | O-DU toward a Benetel RAN650 (indoor, Band 78, 4T4R) over 7.2x eCPRI. |
| `gnb_odu_ran550_general.yaml`, `gnb_odu_ran550_testbed.yaml` | O-DU toward a Benetel RAN550 (outdoor, Band 77/78, 4T4R). |
| `gnb_odu_emulated_general.yaml` | O-DU toward OAI's `oairu` software O-RU emulator, for fronthaul work without hardware. |
| `oairu_emulated_general.yaml` | The `oairu` emulator's own configuration. |

The four `gnb_*_handover_*.yaml` and two `gnb_xn_gnb*.yaml` files are **deltas, not
standalone configs**: they list only what changes on top of `gnb_annotated.yaml` and
elide the rest with `# ... (all other base parameters) ...`. Do not launch them
directly, and see the validator note below.

### `scenarios/` — 2 complete slicing deployments

Full docker-compose deployments (5G Core + gNB + UE), all `_testbed`. They are
documented in [`scenarios/README.md`](scenarios/README.md), including the variants that
were not imported.

| Directory | Purpose |
|---|---|
| `slicing_rfsim_3slices_testbed/` | Three slices under RFsim, each with its own SMF/UPF. |
| `slicing_radio_fn990_testbed/` | Two slices over a real radio, with the Telit FN990 on slice2. |

### `scripts/` — 8 tools

Fully documented in [`scripts/README.md`](scripts/README.md), including every flag.

| File | Purpose |
|---|---|
| `validate_gnb_yaml.py` | Static validator for gNB YAML — dependency Groups A–I, non-zero `att_tx`/`att_rx`, missing `clock_source`, SCS consistency, TDD arithmetic. Needs PyYAML. |
| `check_all_configs.sh` | Runs the validator over every `configs/*.yaml`. This is the repository's validation suite. |
| `collect_oai_gnb_diag.sh` | Read-only diagnostic bundle from a gNB host/container. |
| `collect_oai_cn_diag.sh` | Read-only diagnostic bundle from an OAI 5G Core compose host. |
| `collect_flexric_diag.sh` | Read-only diagnostic bundle from a FlexRIC nearRT-RIC host. |
| `collect_oai_workstation_diag.sh` | Wrapper running the gNB + CN (+ optional FlexRIC) collectors together. |
| `collect_fn990.sh` | Diagnostics for the Telit FN990 COTS modem, the reference commercial UE. |
| `oai_usrp_perf_tune.sh` | Host tuning for USRP throughput — the fix for the `L` flood in P3. Check-only unless `--apply`. |

### Other

| Path | Purpose |
|---|---|
| `fn990_diag_20260602_171626/` | Committed output of one FN990 diagnostic run. Retained as a worked example; see *Diagnostic output* below. |
| `PROMPT.md` | The agent brief that produced this README and `scripts/README.md`. |
| [`oranslice/`](oranslice/README.md) | Snapshot of the local patches and configs from the two ORANSlice clones (2026-10-26), including the re-enabled `nr_update_slice_policy()` scheduler call. The DB dumps holding SIM keys are kept outside git. |

---

## The `_general` vs `_testbed` convention

Both `docs/` and `configs/` use the same suffix pair, and the distinction is a promise
about reusability:

- **`_general`** — vendor-neutral and safe to reuse anywhere. Parameters are explained
  with their valid ranges and the reason a value matters, not with a value to copy.
  Config templates carry deliberate placeholders such as `dl_carrierBandwidth: <RBs>`
  and `initialDLBWPlocationAndBandwidth: <val>`, precisely so they cannot be launched
  unedited.
- **`_testbed`** — concrete values for *this* hardware. Correct here, and quite possibly
  destructive somewhere else. **Never copy a `_testbed` file into another environment
  unedited.**

The values that make a `_testbed` file testbed-specific:

| Value | Setting |
|---|---|
| USRP X310 | `192.168.40.2`, on a 10 GbE NIC with the XG FPGA image |
| AMF | `192.168.70.132`; gNB N2/N3 at `192.168.70.129` on interface `demo-oai` |
| Band | 78 (TDD), X310 with SBX/UBX daughterboard |
| Bandwidth | 106 PRB @ 30 kHz SCS = 40 MHz, `locationAndBandwidth` 28875 |
| Frequency | SSB NR-ARFCN 640704 (3319.20 MHz), Point A 639996 (3300.60 MHz) |
| TDD pattern | DDDSUUU, 5 ms |
| RX gain | `max_rxgain: 75`, `att_tx: 0`, `att_rx: 0` |
| PLMN | MCC 001 / MNC 01, TAC 1 |
| ORANSlice | `SliceConf` at `/home/nobre/oranslice2/ORANSlice/rrmPolicy.json` |

Three files sit **outside** the convention and are testbed-specific despite carrying
neither suffix: `gnb_annotated.{yaml,conf}`, `gnb_rfsim.{yaml,conf}` and `ue_rfsim.yaml`
all contain this lab's Band 78 / 106 PRB / X310 values. Read them as `_testbed`.

When a fix turns out to be hardware- and version-neutral, **promote** it from the
`_testbed` file into the matching `_general` one.

---

## Tooling

### Validate one config

```bash
python3 scripts/validate_gnb_yaml.py configs/gnb_du_testbed.yaml
python3 scripts/validate_gnb_yaml.py configs/gnb_du_testbed.yaml --strict   # ORANSlice warnings become errors; also shows OK lines
python3 scripts/validate_gnb_yaml.py configs/gnb_du_testbed.yaml --json     # machine-readable findings
```

One positional argument, two flags — that is the entire CLI. Exit `0` = no errors,
`1` = errors, `2` = missing file, YAML parse failure, or PyYAML not installed.

### Validate every config

```bash
./scripts/check_all_configs.sh              # the repository's validation suite
./scripts/check_all_configs.sh --verbose    # with each validator report
```

**This suite currently exits non-zero,** and not because a config is wrong. Twelve of
the eighteen YAML files fail for four structural reasons, none of which is a defect in
the config: five annotated `_general` templates crash the validator on their
placeholders (a validator bug, not a config bug); five delta configs are not standalone;
`ue_rfsim.yaml` and `oairu_emulated_general.yaml` are not gNB configs at all; and the
two `.conf` files are libconfig, which the validator cannot read. See
[`scripts/README.md`](scripts/README.md) for the breakdown. **Do not edit a config to
make the suite pass** — a `_testbed` config may be recording reality, and a `_general`
config is a template by design.

### Collect diagnostics

Each collector is read-only and changes no configuration. `--pcap` needs `sudo`;
nothing else does, except `collect_fn990.sh` (which calls `sudo mmcli` internally) and
`oai_usrp_perf_tune.sh --apply`.

```bash
./scripts/collect_oai_gnb_diag.sh --usrp-iface enp1s0f0 --amf-ip 192.168.70.132 --pcap 20
./scripts/collect_oai_cn_diag.sh --compose docker-compose.yaml --imsi 001010000000002
./scripts/collect_flexric_diag.sh --compose docker-compose-ric.yaml --since 60m
./scripts/collect_oai_workstation_diag.sh --with-flexric --usrp-iface enp1s0f0
./scripts/collect_fn990.sh --mode at-only
```

### Tune a USRP host

```bash
./scripts/oai_usrp_perf_tune.sh --iface enp1s0f0 --check                       # default: reports, changes nothing
sudo ./scripts/oai_usrp_perf_tune.sh --iface enp1s0f0 --apply --persist-sysctl --rtprio
./scripts/oai_usrp_perf_tune.sh --print-oai-hints
```

---

## Diagnostic output

Collector output is **git-ignored** because it contains real hardware identifiers —
IMEI, USRP and modem serials, hostnames, MAC addresses, and container logs.
`.gitignore` covers all five collector output directory patterns plus their tarballs.
**Scrub output before sharing it or attaching it to an issue.**

The one exception is `fn990_diag_20260602_171626/`, committed before these rules
existed. It contains the FN990's IMEI and the collecting host's hostname, and is
deliberately left in place: a deletion commit would not remove it from history, and
rewriting the history of a repository that was public from 2026-04-24 to 2026-08-17 is
a separate decision. Treat it as an open item, not as an example to follow.

---

## How to extend this repo

**A new troubleshooting entry.** Add a `## Pn —` section to
`docs/oai_troubleshooting_testbed.md` with all five fields — *symptom* (the literal log
text OAI emits), *confirmed cause* (not the plausible ones), *fix*, *why it recurs*, and
*do not chase*. Then add its log string in **both** index tables: §2 of that file, and
the quick-reference table at the top of this README. An entry that is not in both
indexes will not be found.

**A new reference doc.** Add it to the `docs/` table in this README's repository map, in
the same commit.

**A fix that proves hardware- or version-neutral.** Promote it from the `_testbed` file
into the matching `_general` file. That is the whole point of the split.

**Before committing a config change**, run the validation suite:

```bash
./scripts/check_all_configs.sh
```

Stage explicitly by path — never `git add -A` or `git add .`. Never commit collector
output, and never commit 3GPP, ETSI or O-RAN specification documents: reference them by
spec number and version instead. See [`CLAUDE.md`](CLAUDE.md) for the full set of
invariants.
