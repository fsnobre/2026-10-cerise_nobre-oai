# scenarios/ — complete OAI 5G Core slicing deployments

Whole docker-compose deployments (5G Core + gNB + UE), as run in the lab. They are
**`_testbed`**: concrete values for this hardware, never defaults for another
environment (see the convention in [`../README.md`](../README.md)). Unlike
`configs/`, they are not deltas on `gnb_annotated.yaml`, and `check_all_configs.sh`
does not scan them.

Imported on 2026-10-26 from the laptop's `~/Documents/OAI/Slicing/scenario_cerise*`
(April–May 2026). Logs and `results/` were left out on purpose: they are run output
with subscriber identities, and the rule for diagnostic output in
[`../CLAUDE.md`](../CLAUDE.md) applies to them too.

The credentials in these files (MySQL `test`/`linux`, the subscriber key/OPc in
`database/oai_db2.sql` and `gnb/nr-ue.conf`, PLMN 001/01) are the public OAI tutorial
defaults. Nothing here is a real SIM secret.

| Directory | What it is |
|---|---|
| [`slicing_rfsim_3slices_testbed/`](slicing_rfsim_3slices_testbed/) | Three slices under RFsim. Each slice has its own SMF and UPF (`oai-upf-slice1`, `oai-upf-slice2` and `vpp-upf-slice3`), plus NSSF and two NRFs. `docker-compose.yaml` is the core, `docker-compose-gnb-ue.yaml` adds the RFsim gNB and nr-UE (`gnb/gnb.yaml`, `gnb/nr-ue.conf`). `gnb/docker-compose.yaml` runs the same gNB over a USRP with `gnb/gNB_SA_n78_106PRB.2x2_usrpn310.conf`. Source: `scenario_cerise_funcionando`. |
| [`slicing_radio_fn990_testbed/`](slicing_radio_fn990_testbed/) | Two slices (slice3 removed) over a real radio, with the Telit FN990 as UE on slice2. Read [`README_slicing_consistency_FN990.md`](slicing_radio_fn990_testbed/README_slicing_consistency_FN990.md) before you start. Source: `scenario_cerise_radio_mod`, identical to `scenario_cerise_radio.zip`. |

## Variants that were not imported

The other laptop folders are copies of `slicing_rfsim_3slices_testbed` with one change
each. These are the configs that differ, apart from logs:

| Laptop folder | Difference from `slicing_rfsim_3slices_testbed` |
|---|---|
| `scenario_cerise` | `gnb/nr-ue.conf`: PDU session `type = "IPv4v6"` instead of `"IPv4"` |
| `scenario_cerise_new_smf` | IPv4v6 as above, and `oai-smf-slice2` uses a locally built image `oai-smf:ipv4v6-dnn-fallback` instead of `oaisoftwarealliance/oai-smf:develop` |
| `scenario_cerise_new_smf_context_fix` | Same as `new_smf`, with image `oai-smf:ipv4v6-dnn-fallback-smf_context-fix` |
| `scenario_cerise_telit_replicado` | IPv4v6 as above, and `conf/slicing_slice2_config.yaml` sets `use_local_subscription_info: no`, so the SMF takes subscription data from the UDM |

## Recorded result

`results/` in all four RFsim folders has the same content, an iperf run with one UE per
slice. Slices A and B carried 9.95 Mbit/s UDP with no loss over 20 s. Slice C carried
99.8 Mbit/s with no loss.
