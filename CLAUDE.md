# CLAUDE.md — invariants for `oai/` (formerly the `cerise_oai` repository)

Read [`README.md`](README.md) first for what this repository is. This file records the
rules a future agent must not violate. They were derived from real bring-ups; most
cannot be re-verified without the hardware.

## What this repository is for

Cross-testbed OAI / ORANSlice / 5G RAN knowledge. Its companion,
`oai-rfsim-handover-testbed` (private, usually cloned at
`../../oai-rfsim-handover-testbed` from this directory), holds the automation for one specific RFsim/USRP
handover testbed. Knowledge that generalises across testbeds belongs here; automation
tied to that one topology belongs there. **Never modify the companion repository from
this one.**

## Do not rewrite the technical content

The accuracy of these documents was established during live bring-ups against hardware
that is not available to you. Do not restructure, condense, or "correct" the technical
content of an existing document. If you believe something is wrong, **flag it; do not
change it.** No live testbed, USRP, OAI build, or docker environment is available —
this is a documentation and tooling repository only.

## The `_general` vs `_testbed` split

Both `docs/` and `configs/` use this suffix pair, and each suffix is a promise:

- **`_general` guarantees vendor-neutrality.** Safe to reuse in any environment.
  Parameters are documented by valid range and by *why* the value matters, never by a
  value to copy. The `_general` config templates carry deliberate placeholders —
  `dl_carrierBandwidth: <RBs>`, `initialDLBWPlocationAndBandwidth: <val>` — so they
  cannot be launched unedited. **These placeholders are correct. Never fill them in to
  make a tool pass.**
- **`_testbed` guarantees concreteness for this hardware only.** Correct here, possibly
  destructive elsewhere. Never copy a `_testbed` file to another environment unedited.

Three files sit outside the convention and are testbed-specific despite carrying
neither suffix: `configs/gnb_annotated.{yaml,conf}`, `configs/gnb_rfsim.{yaml,conf}`,
and `configs/ue_rfsim.yaml`. Treat them as `_testbed`.

**Promotion is the one sanctioned edit direction:** when a fix proves hardware- and
version-neutral, move it from the `_testbed` file into the matching `_general` file.
Never the reverse.

## Values that are specific to this hardware

These must **never** be presented as general defaults, quoted in a `_general` document,
or offered as a starting point for someone else's testbed:

| Value | Setting |
|---|---|
| `192.168.40.2` | USRP X310, on a 10 GbE NIC with the XG FPGA image |
| `192.168.70.132` | AMF |
| `192.168.70.129`, interface `demo-oai` | gNB N2/N3 |
| Band 78 TDD, SBX/UBX daughterboard | this X310 only |
| 106 PRB @ 30 kHz SCS (40 MHz), `locationAndBandwidth` 28875 | |
| SSB NR-ARFCN 640704, Point A 639996 | |
| DDDSUUU, 5 ms | TDD pattern; the UE config must match exactly |
| `max_rxgain: 75` | X310 SBX/UBX on Band 78 — a daughterboard- and band-specific number |
| `att_tx: 0`, `att_rx: 0` | correct **only** with no physical attenuators in the path |
| `ra_ResponseWindow: 10` | needed for X310 OTA latency; the OAI default of 4 is not a bug everywhere |
| `pusch_proc_threads: 8` | sized to this host's core count |
| MCC 001 / MNC 01, TAC 1 | must match the AMF |
| `/home/nobre/oranslice2/ORANSlice/rrmPolicy.json` | `SliceConf` path |

`att_rx: 14` is the single most expensive value in this repository's history: it broke
Msg3 while leaving PRACH detection healthy, and the misdiagnosis is recorded in
`docs/oai_troubleshooting_testbed.md` §1. Do not reintroduce it as an example value
without the surrounding warning.

## Never commit

- **3GPP, ETSI, or O-RAN specification documents**, or any other copyrighted corpus.
  Redistribution is restricted. Reference specs by number and version instead — e.g.
  "TS 38.213 Table 13-1" — which is how the existing documents do it.
- **Diagnostic collector output.** Every collector writes real hardware identifiers:
  IMEI, USRP and modem serials, hostnames, MAC addresses, container logs. `.gitignore`
  covers all five output directory patterns (`fn990_diag_*/`, `flexric_diag_*/`,
  `oai_cn_diag_*/`, `oai_gnb_diag_*/`, `oai_workstation_diag_*/`), the `*_diag_*/`
  catch-all, and the tarballs. If you add a collector, add its pattern in the same
  commit. Note that `.gitignore` comments must be on their own lines — git treats a
  trailing `#` as part of the pattern.
- **Large binaries.**

`fn990_diag_20260602_171626/` is tracked, predating those rules. Leave it in place and
unmodified: a deletion commit would not remove it from history, and rewriting history
is the owner's call, not an agent's.

## Git rules

- **Stage explicitly by path.** Never `git add -A` or `git add .`.
- **Do not push** unless explicitly asked. Commit locally.
- **Do not rewrite history or force-push.** This repository was public from 2026-04-24
  to 2026-08-17 and is now private; anything already pushed is already out.
- **Do not change the repository's GitHub visibility.** Keep it private.
- A background tool auto-commits to `main` on a timer with `.` as the message. Unrelated
  changes may therefore appear in the working tree or the log at any time. Do not
  assume everything uncommitted is yours, and check `git status` before staging.

## Validation

Before committing a config change:

```bash
./scripts/check_all_configs.sh
```

This runs `scripts/validate_gnb_yaml.py` over every `configs/*.yaml`. It **currently
exits non-zero**, and none of the twelve failures is a bad config: five `_general`
templates crash the validator on their placeholders (a validator bug at
`validate_gnb_yaml.py:279` and `:292`), five configs are deltas that are not standalone
by design, and two are not gNB configs at all. `scripts/README.md` breaks this down.
Compare against that known baseline rather than expecting a clean run.

**Never edit a config to make the validator pass.** A `_testbed` config may be recording
reality, and a `_general` config is a template by design. The validator needs PyYAML
despite being otherwise stdlib-only.

## Extend-contract

- **New troubleshooting entry** → add a `## Pn —` section to
  `docs/oai_troubleshooting_testbed.md` with all five fields (symptom as the literal log
  text, confirmed cause, fix, why it recurs, do not chase), then add its log string to
  **both** indexes: §2 of that file and the quick-reference table in `README.md`. An
  entry missing from either index will not be found, which is the failure mode this
  repository exists to prevent.
- **New reference doc** → add it to the `docs/` table in the `README.md` repository map,
  in the same commit.
- **New script** → document it in `scripts/README.md` (what it checks or collects, exact
  invocation, output, whether it needs root or live hardware) and add it to the
  `scripts/` table in `README.md`. If it is a collector, add its output pattern to
  `.gitignore`.
- **A fix that proves hardware- or version-neutral** → promote it from the `_testbed`
  file into the matching `_general` file.

## The catalogue and the references overlap on purpose

`docs/oai_troubleshooting_testbed.md` is indexed by **symptom**;
`docs/oai_gnb_yaml_{general,testbed}.md` §3 are indexed by **parameter**. They cover
the same failures deliberately, because those are two different lookups. **Do not merge
or deduplicate them.** The YAML references are authoritative for parameter *values*;
the catalogue is authoritative for the *confirmed cause* and the dead ends. Each side
points at the other — keep both pointers working.
