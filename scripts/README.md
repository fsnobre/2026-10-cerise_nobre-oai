# `scripts/` — validator, collectors, host tuner

Eight scripts. One validates configs statically, five collect diagnostics from a live
system, one tunes a USRP host, and one runs the validator across the whole repo.

Every invocation below is written from the **repository root**.

| Script | Kind | Needs live hardware | Needs root |
|---|---|---|---|
| [`validate_gnb_yaml.py`](#validate_gnb_yamlpy) | static check | no | no |
| [`check_all_configs.sh`](#check_all_configssh) | static check | no | no |
| [`collect_oai_gnb_diag.sh`](#collect_oai_gnb_diagsh) | collector | yes | only for `--pcap` |
| [`collect_oai_cn_diag.sh`](#collect_oai_cn_diagsh) | collector | yes | only for `--pcap` |
| [`collect_flexric_diag.sh`](#collect_flexric_diagsh) | collector | yes | only for `--pcap` |
| [`collect_oai_workstation_diag.sh`](#collect_oai_workstation_diagsh) | collector (wrapper) | yes | only for `--pcap` |
| [`collect_fn990.sh`](#collect_fn990sh) | collector | yes (Telit FN990) | yes, in practice |
| [`oai_usrp_perf_tune.sh`](#oai_usrp_perf_tunesh) | host tuner | yes (NIC) | only for `--apply` |

> **Collector output is git-ignored.** Every collector writes real hardware
> identifiers — IMEI, USRP and modem serials, hostnames, MAC addresses, container
> logs. `.gitignore` covers all five output directory patterns plus the tarballs.
> Scrub output before sharing it or attaching it to an issue.

---

## `validate_gnb_yaml.py`

Read-only static validator for OAI gNB **YAML** configs. It encodes rules that
otherwise exist only as prose in `docs/oai_gnb_yaml_{general,testbed}.md` §4 —
Groups A–I — so a config error fails loudly instead of waiting to be remembered.

**Requires PyYAML.** Despite being otherwise stdlib-only, it does `import yaml` and
exits 2 with an install hint if PyYAML is absent. It is not a zero-dependency script.

```bash
python3 scripts/validate_gnb_yaml.py configs/gnb_du_testbed.yaml
python3 scripts/validate_gnb_yaml.py configs/gnb_du_testbed.yaml --strict
python3 scripts/validate_gnb_yaml.py configs/gnb_du_testbed.yaml --json
```

CLI surface — this is the whole of it, taken from `main()`:

| Argument | Meaning |
|---|---|
| `config` (positional, required) | Path to the gNB YAML file. |
| `--strict` | Treat ORANSlice-specific warnings as errors; also print the `OK` lines, which are suppressed otherwise. |
| `--json` | Emit findings as a JSON array instead of coloured text. |

**Output:** findings sorted `ERROR` → `WARN` → `INFO`, each tagged with its group
(`Group A (Carrier/BWP)`, `RACH`, `Group G (RF)`, …), then a summary count and a
`PASS` / `PASS WITH WARNINGS` / `FAIL` verdict. Colour is emitted only to a TTY.

**Exit codes:** `0` no errors · `1` one or more errors · `2` file not found, YAML parse
failure, top-level document is not a mapping, or PyYAML missing.

**What it checks:** presence of the `Active_gNBs` / `gNBs` / `MACRLCs` / `L1s` / `RUs`
blocks; identity and `plmn_list` / `snssaiList` completeness; `NETWORK_INTERFACES` and
`amf_ip_address`; SCS consistency across all seven SCS fields (Group B); carrier
bandwidth ↔ `locationAndBandwidth` arithmetic, `275×(L−1)+RBstart` (Group A); TDD
special-slot symbol budget and slots-per-period (Group C); PRACH root-sequence range
against the format (Group D); SSB positions against the band (Group E); `att_tx` /
`att_rx` / `max_rxgain` / `sdr_addrs` coherence (Group G); `parallel_config` and
`pusch_proc_threads` (Group H); the monolithic transport-preference chain (Group I);
plus `ra_ResponseWindow`, `min_rxtxtime`, `do_SRS` and `do_CSIRS`.

It is CU/DU-aware: several checks relax when `amf_ip_address` is absent (DU) or
`local_rf: no` (CU in F1 split mode).

**Known limitations — read before trusting a failure:**

- It only understands YAML. `configs/*.conf` are OAI libconfig files and exit 2.
- It expects a **complete, standalone** gNB config. The delta/overlay configs in
  `configs/` (`gnb_*_handover_*.yaml`, `gnb_xn_gnb*.yaml`) intentionally contain only
  the parameters they change, so it reports every absent block as an error.
- It is a **gNB** validator. `ue_rfsim.yaml` (nr-UE) and `oairu_emulated_general.yaml`
  (O-RU) have entirely different schemas and cannot pass.
- **It crashes on the annotated `_general` templates.** `L_dl` / `L_ul` are assigned
  inside an `isinstance` guard at lines 276 and 289 but compared outside it at lines
  279 and 292, so a placeholder such as `dl_carrierBandwidth: <RBs>` raises
  `UnboundLocalError` instead of reaching the "placeholder values detected" branch the
  code already contains. Unfixed deliberately — see the repository README's open items.

---

## `check_all_configs.sh`

The repository's validation suite: runs `validate_gnb_yaml.py` over every
`configs/*.yaml` and exits non-zero if any of them reports an error. Read-only; it
never edits a config.

```bash
./scripts/check_all_configs.sh                # validate configs/*.yaml
./scripts/check_all_configs.sh --verbose      # also print each validator report
./scripts/check_all_configs.sh --dir path/    # validate a different directory
./scripts/check_all_configs.sh -- --strict    # pass flags through to the validator
```

| Argument | Meaning |
|---|---|
| `--verbose`, `-v` | Print each validator report, indented, under its result line. |
| `--dir PATH` | Validate `PATH/*.yaml` instead of `configs/`. |
| `--` | Everything after this is forwarded to `validate_gnb_yaml.py`. |
| `-h`, `--help` | Usage. |

**Output:** one line per config — `PASS`, `FAIL` or `SKIP` — carrying the validator's
own summary counts, then a total. A crash is reported as `validator CRASHED:` with the
exception, distinctly from a validation failure, so the two are never confused.
`.conf` files are listed as `SKIP` because the validator cannot read libconfig.

**Exit codes:** `0` all clean · `1` at least one config errored or failed to parse ·
`2` harness problem (no `python3`, validator or directory missing).

A `FAIL` is not automatically a bad config. See the validator's limitations above: an
annotated `_general` template, a delta overlay, and a non-gNB config all fail for
reasons that are correct behaviour on the config's part. **Do not edit a config to
make this suite pass.**

---

## `collect_oai_gnb_diag.sh`

Read-only diagnostics for an OAI gNB host or container. Changes no configuration.

```bash
./scripts/collect_oai_gnb_diag.sh
./scripts/collect_oai_gnb_diag.sh --compose docker-compose-gnb.yaml --container oai-gnb
./scripts/collect_oai_gnb_diag.sh --usrp-iface enp1s0f0 --pcap 20
./scripts/collect_oai_gnb_diag.sh --amf-ip 192.168.70.132 --gnb-ip 172.16.2.56
```

| Argument | Default | Meaning |
|---|---|---|
| `--compose FILE` | `docker-compose-gnb.yaml` | Compose file to inspect. |
| `--container NAME` | `oai-gnb` | Container name hint. |
| `--gnb-conf PATH` | — | gNB config to copy into the bundle. |
| `--usrp-iface IFACE`, `--iface` | — | USRP NIC. Repeatable. |
| `--pcap SECONDS` | `0` (off) | Capture N2 SCTP and N3 GTP-U. **Needs sudo.** |
| `--amf-ip IP`, `--gnb-ip IP` | — | Reachability targets. |
| `--since DURATION` | `30m` | Log window. |
| `--out-parent DIR` | `.` | Where the output directory is created. |
| `--full-logs` | off | Include complete container logs, not just the recent window. |
| `-h`, `--help` | | Prints the header block. |

**Output:** `oai_gnb_diag_<YYYYmmdd_HHMMSS>/` plus `oai_gnb_diag_<ts>.tar.gz` beside
it — numbered `.txt` files per command, a `config/` copy, `container_inspect/`,
`container_logs_recent/`, `container_logs_full/`, `container_exec/`, and `00_run.log`.

---

## `collect_oai_cn_diag.sh`

Read-only diagnostics for an OAI 5G Core docker-compose host. Changes no CN
configuration. Attempts a read-only subscriber lookup against the MySQL container,
trying a small list of well-known dev credentials.

```bash
./scripts/collect_oai_cn_diag.sh
./scripts/collect_oai_cn_diag.sh --compose docker-compose.yaml --imsi 001010000000002
./scripts/collect_oai_cn_diag.sh --pcap 20 --full-logs --workdir /opt/oai-cn5g
```

| Argument | Default | Meaning |
|---|---|---|
| `--compose FILE` | `docker-compose.yaml` | Compose file to inspect. |
| `--imsi VALUE`, `--supi` | — | Subscriber to look up in `oai_db`. |
| `--since DURATION` | `30m` | Log window. |
| `--pcap SECONDS` | `0` (off) | Capture NGAP/SBI/PFCP and GTP-U. **Needs sudo.** |
| `--out-parent DIR` | `.` | Where the output directory is created. |
| `--workdir DIR` | — | Directory to run compose commands from. |
| `--full-logs` | off | Include complete container logs. |
| `--mysql-db NAME` | `oai_db` | Subscriber database name. |
| `-h`, `--help` | | Prints the header block. |

**Output:** `oai_cn_diag_<timestamp>/` plus a matching `.tar.gz`, laid out like the gNB
collector.

---

## `collect_flexric_diag.sh`

Read-only diagnostics for a FlexRIC nearRT-RIC host: RIC process state, E2 agent
connections, xApp status, service-model availability, recent logs. Handles FlexRIC
running either in a container or as a bare process.

```bash
./scripts/collect_flexric_diag.sh
./scripts/collect_flexric_diag.sh --compose docker-compose-ric.yaml
./scripts/collect_flexric_diag.sh --flexric-bin /usr/local/bin/nearRT-RIC --pcap 15
./scripts/collect_flexric_diag.sh --since 60m --full-logs
./scripts/collect_flexric_diag.sh --bare-process
```

| Argument | Default | Meaning |
|---|---|---|
| `--compose FILE` | `docker-compose-ric.yaml` | Compose file to inspect. |
| `--flexric-bin PATH` | — | RIC binary, for a non-container deployment. |
| `--flexric-conf PATH` | `/usr/local/etc/flexric/flexric.conf` | RIC config to capture. |
| `--xapp-pattern PATTERN` | `xapp` | Process/container match for xApps. |
| `--ric-port PORT` | `36421` | E2AP listen port. |
| `--e2-port PORT` | `36422` | Second E2 port to check. |
| `--since DURATION` | `30m` | Log window. |
| `--pcap SECONDS` | `0` (off) | Capture SCTP on the E2 ports. **Needs sudo.** |
| `--out-parent DIR` | `.` | Where the output directory is created. |
| `--full-logs` | off | Include complete container logs. |
| `--bare-process` | off | FlexRIC is a plain process, not a container. |
| `-h`, `--help` | | Prints the header block. |

**Output:** `flexric_diag_<timestamp>/` plus a matching `.tar.gz`.

---

## `collect_oai_workstation_diag.sh`

Wrapper that runs the gNB and CN collectors — and optionally the FlexRIC one — in a
single bundle, for when everything shares one workstation. Makes no changes itself and
contains no `sudo`; root is only needed by the child collectors' `--pcap`.

```bash
./scripts/collect_oai_workstation_diag.sh
./scripts/collect_oai_workstation_diag.sh --gnb-compose docker-compose-gnb.yaml --cn-compose docker-compose.yaml
./scripts/collect_oai_workstation_diag.sh --usrp-iface enp1s0f0 --imsi 001010000000002 --pcap 20
./scripts/collect_oai_workstation_diag.sh --with-flexric --flexric-compose docker-compose-ric.yaml
```

Child scripts are resolved next to this one; override with `--gnb-script`,
`--cn-script`, `--flexric-script`. FlexRIC is collected **only** with
`--with-flexric` *and* the script present. Remaining arguments —
`--gnb-compose`, `--cn-compose`, `--flexric-compose`, `--gnb-container`,
`--imsi`/`--supi`, `--since`, `--pcap`, `--usrp-iface`/`--iface`, `--amf-ip`,
`--gnb-ip`, `--workdir`, `--out-parent`, `--full-logs` — are passed through with the
same meanings as above.

**Output:** `oai_workstation_diag_<timestamp>/` plus a matching `.tar.gz`, containing
each child collector's bundle.

---

## `collect_fn990.sh`

Unified diagnostics for the **Telit FN990** M.2 COTS modem — the reference commercial
UE. Auto-detects the AT-command path: `mmcli` first, then `expect` + `picocom` on a
detected `/dev/ttyUSBx`; with neither, AT is skipped and every other section still
runs. Also auto-detects the `wwan*` / `wwp*` interface.

Uses `sudo` directly for `mmcli` and `stty`, so in practice run it with root available.

```bash
./scripts/collect_fn990.sh
./scripts/collect_fn990.sh --mode at-only
./scripts/collect_fn990.sh --mode full --pcap 15
./scripts/collect_fn990.sh --iface wwp0s21f0u2i12 --at /dev/ttyUSB2
./scripts/collect_fn990.sh --mode full --no-ping
```

| Argument | Default | Meaning |
|---|---|---|
| `--mode MODE` | `full` | `full`, `at-only` (USB + AT, ~30 s), or `connectivity` (no AT). Anything else exits 1. |
| `--iface NAME` | auto-detected | Modem WAN interface. |
| `--at PORT` | auto-detected | AT serial port. |
| `--pcap SECONDS` | `0` (off) | Packet capture duration. |
| `--ping-count N` | `10` | Pings per target. |
| `--dns1 IP` / `--dns2 IP` | `1.1.1.1` / `8.8.8.8` | DNS test targets. |
| `--host NAME` | `www.google.com` | Connectivity test host. |
| `--at-delay SECONDS` | `0.5` | Delay between AT commands. |
| `--no-ping` | off | Skip the long ping tests. |
| `-h`, `--help` | | Prints the header block. |

**Output:** unlike the other collectors, a single Markdown report —
`fn990_diag_<timestamp>/fn990_report_<timestamp>.md` plus `run.log`, and **no
tarball**. A quick-summary section precedes verbatim diagnostic sections.

> The report contains the modem's **IMEI** and the collecting host's hostname.
> `fn990_diag_20260602_171626/` in the repository root is one such run, committed
> before these ignore rules existed. Treat every new run as sensitive.

---

## `oai_usrp_perf_tune.sh`

Conservative host-performance checker and tuner for an OAI/USRP box — the fix for the
`L` flood and UHD overflow in `docs/oai_troubleshooting_testbed.md` §P3. **Check-only
by default**; `--apply` performs runtime-safe changes and requires root. It is
idempotent, installs nothing, and does not edit GRUB, disable SMT, or touch kernel
mitigations. Risky BIOS/GRUB changes are reported, never applied.

```bash
./scripts/oai_usrp_perf_tune.sh --iface enp1s0f0 --check
sudo ./scripts/oai_usrp_perf_tune.sh --iface enp1s0f0 --apply --persist-sysctl --rtprio
sudo ./scripts/oai_usrp_perf_tune.sh --iface enp1s0f0 --apply --idle-disable --irq-affinity 8,9,10,11
./scripts/oai_usrp_perf_tune.sh --print-oai-hints
```

| Argument | Default | Meaning |
|---|---|---|
| `--check` | default mode | Report only, change nothing. |
| `--apply` | | Apply runtime-safe tuning. **Requires root**; exits 1 otherwise. |
| `--iface IFACE` | — | USRP NIC. Repeatable for multiple NICs. |
| `--mtu N` | `9000` | Target MTU (jumbo frames). |
| `--ring N` | `4096` | RX/TX ring size. |
| `--buffers BYTES` | `62500000` | Socket buffer size. |
| `--governor GOV` | `performance` | CPU frequency governor. |
| `--idle-disable` | off | `cpupower idle-set -D 0`. Opt-in only — never applied by default. |
| `--persist-sysctl` | off | Write `/etc/sysctl.d/99-oai-usrp-perf.conf`. |
| `--rtprio` | off | Create the `usrp` group, add the user, write rtprio limits. |
| `--nm-unmanaged` | off | Ask NetworkManager to release the NICs at runtime. |
| `--persist-nm-unmanaged` | off | Persist that by MAC address. |
| `--core-forwarding` | off | Enable IPv4 forwarding, for an OAI core host. |
| `--irq-affinity CPU_LIST` | — | Pin NIC IRQs, e.g. `8,9,10,11`. Requires `--iface`. |
| `--print-oai-hints` | off | Print OAI command-line and config hints, then exit. |
| `--yes` | off | Skip the `--apply` confirmation prompt. |
| `--quiet` | off | Less output. |
| `-h`, `--help` | | Full usage block. |

**Output:** a colourised check/apply report on stdout. Creates no bundle directory.
With `--persist-sysctl` or `--persist-nm-unmanaged` it writes files under `/etc`.

Note that MTU, ring, sysctl, governor and idle-state changes revert on reboot unless
persisted. `--idle-disable` deliberately requires opting in: an earlier version applied
it silently.
