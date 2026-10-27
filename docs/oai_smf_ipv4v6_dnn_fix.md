# OAI SMF — IPv4v6 PDU Session Rejected as "unknown requested DNN"

> **Scope:** A local fix to the OAI 5G Core SMF (`develop` branch, source obtained 21/04/2026, changed 05/05/2026) that lets a commercial UE requesting an IPv4v6 PDU session use a DNN configured as IPv4-only.
> **When to use:** The UE registers with the AMF, but the SMF rejects every PDU session with 5GSM cause `0x1b` even though its log says `DNN matched!`.
> **Written:** 27/10/2026, as a record of the May 2026 work. The modified source file is not published here because of the OAI SMF licence (`LicenseRef-CSSL-1.0`).

---

## 1. Symptom

A Telit FN990 attached to an OAI gNB (USRP X310) and to the slicing 5G Core registered with the AMF, but the SMF rejected the PDU session. The SMF log showed:

```text
Requested DNN: internet
DNN matched!
unknown requested DNN internet
PDU Session Establishment Reject (5GSM Cause: 0x1b)
```

`0x1b` is "missing or unknown DNN". The DNN name did match, which is what made the log confusing.

---

## 2. Root cause

The FN990 requests a PDU session of type **IPv4v6**. The DNN was configured in the SMF as **IPv4**.

The DNN validation in `src/smf_app/smf_config.cpp` only accepted the DNN when the requested PDU session type was *equal* to the configured one. With IPv4v6 requested and IPv4 configured, the function returned "not found" right after logging `DNN matched!`. The SMF then reported an unknown DNN before its later logic could pick IPv4 for the session.

The problem was reproduced in RFsim by setting `type = "IPv4v6"` in the OAI NR-UE PDU session (`scenario_cerise` in [`scenarios/README.md`](../scenarios/README.md)), which isolated it from the radio side.

---

## 3. Fix

Two cases were added to the DNN validation, after the existing equality check:

| Requested type | Configured DNN type | Before | After |
|---|---|---|---|
| IPv4v6 | IPv4 | rejected (`0x1b`) | accepted; SMF selects IPv4 |
| IPv4v6 | IPv6 | rejected (`0x1b`) | accepted; SMF selects IPv6 |
| any | same type | accepted | accepted (unchanged) |

Each new case logs a warning (`DNN … requested as IPv4v6, but configured as IPv4-only; accepting DNN match and letting SMF select IPv4`). Address selection itself was not changed.

---

## 4. Result

- The FN990 received `PDU Session Establishment Accept` and an IPv4 address.
- The SMF was rebuilt as a local Docker image and used in the slicing scenarios:

| Image | Used in |
|---|---|
| `oai-smf:ipv4v6-dnn-fallback` | `scenario_cerise_new_smf` ([`scenarios/README.md`](../scenarios/README.md)) |
| `oai-smf:ipv4v6-dnn-fallback-smf_context-fix` | `scenario_cerise_new_smf_context_fix` and both SMFs of [`slicing_radio_fn990_testbed`](../scenarios/slicing_radio_fn990_testbed/docker-compose.yaml) |

---

## 5. Alternatives without the patched SMF (not tested here)

- Configure the UE to request IPv4 only, as the OAI NR-UE configs in this repository do. With a commercial UE this is not always possible, which is why the SMF was changed.
- Configure the DNN as `IPV4V6` in the SMF and in the subscriber data.
