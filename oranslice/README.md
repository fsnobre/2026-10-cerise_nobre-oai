# `oranslice/` — local changes to the ORANSlice clones

Snapshot taken on 2026-10-26 of the uncommitted work in two clones of
[`wineslab/ORANSlice`](https://github.com/wineslab/ORANSlice). Both clones were at
upstream commit `b9bcc9b17fbecfc1041072a7b8d0f01ae874aba2` (2025-12-11). The clones
were on the **Mini PC** (`mininobre`):

| Directory here | Clone on the Mini PC |
|---|---|
| `ORANSlice/` | `~/Documents/OAI/ORANSlice` |
| `oranslice2/` | `~/Documents/OAI/oranslice2/ORANSlice`. This is the main one: `SliceConf` in the testbed configs points at `oranslice2/ORANSlice/rrmPolicy.json`. |

None of this was captured from the X310 lab machine. That machine may hold newer
versions of the same files.

## Contents of each directory

- `local-changes.patch`: `git diff` of the tracked files, relative to `BASE_COMMIT`.
- `untracked/`: the small untracked files, at their path inside the clone. These are
  the `rrmPolicy*.json` files, `docker-compose-legacy-modified.yml`, and, in
  `ORANSlice/` only, `oai_slicing_usrpX310.conf` and `iperf.txt`.

Restore the snapshot onto a fresh clone:

```bash
git clone https://github.com/wineslab/ORANSlice && cd ORANSlice
git checkout "$(cat <this dir>/BASE_COMMIT)"
git apply <this dir>/local-changes.patch
cp -a <this dir>/untracked/. .
```

## What the patches change

| File | `ORANSlice/` | `oranslice2/` |
|---|---|---|
| `oai_ran/openair2/LAYER2/NR_MAC_gNB/gNB_scheduler_dlsch.c` | Re-enables `nr_update_slice_policy()` every 128 frames (`(frame & 127) == 0 && slot == 0`). Upstream ships it commented out. | Same change |
| `oai_cn/oai-cn5g-legacy/conf/config.yaml` | Log level `debug` → `info` | Same change |
| `oai_cn/oai-cn5g-legacy/database/oai_db.sql` | IMSI `001010000010777` moved to slice `sst 1 / sd 0x00002`, DNN `oai2` | Same change |
| `oai_cn/oai-cn5g-legacy/docker-compose-legacy.yml` | `external: true` commented out | Same change, and the DB init script switched to `oai_db2_Felipe.sql` |
| `ORANSlice.gnb.sa.band78.fr1.106PRB.usrpx310.conf` | Small edits | 51-line edit, including `SliceConf = "/home/nobre/oranslice2/ORANSlice/rrmPolicy.json"` and the AMF `preference` line commented out |

Without the scheduler change, the slice policy is probably read only once at start-up,
so edits to `rrmPolicy.json` made while the gNB is running would be ignored. This has
not been confirmed on hardware, and `docs/oai_troubleshooting_testbed.md` P4 does not
mention it.

## What is not here

- **The database dumps** `oai_db2_Felipe.sql`, `oai_db_bkp.sql` and `oai_db_bkp2.sql`.
  They hold a non-default Ki/OPc (valores removidos desta cópia) for IMSIs
  `001010000000001` and `…002`. They are kept outside git in
  `Obsidian/Privadas/CERISE/ORANSlice-db/<clone>/`, at the same relative paths. The
  same Ki/OPc is already committed in `oai/scenarios/*/database/oai_db2.sql` and in
  `oai/scenarios/*/gnb/nr-ue.conf`. Because the rfsim UE uses it, it may be a lab test
  key rather than a physical SIM's; this is not confirmed.
- **`oai_cn/oai-cn5g-fed/`, `protobuf-c/` and the `ran_build/` output.** These come
  from upstream clones or rebuilds and can be recreated.
