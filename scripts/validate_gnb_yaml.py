#!/usr/bin/env python3
"""
validate_gnb_yaml.py

Read-only validator for OAI gNB YAML configuration files.
Checks for parameter inconsistencies, missing required fields,
and known bad values. Covers Groups A-I from the testbed reference doc.

Usage:
  python3 validate_gnb_yaml.py gnb.yaml
  python3 validate_gnb_yaml.py gnb.yaml --strict
  python3 validate_gnb_yaml.py gnb.yaml --json

Exit codes:
  0 = no errors (warnings may be present)
  1 = one or more errors found
  2 = file not found / parse failure
"""

import sys
import re
import argparse
import json as _json
from pathlib import Path

try:
    import yaml
except ImportError:
    print("ERROR: PyYAML not installed. Run: pip3 install pyyaml --break-system-packages", file=sys.stderr)
    sys.exit(2)

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

RESET   = "\033[0m"
RED     = "\033[0;31m"
YELLOW  = "\033[0;33m"
GREEN   = "\033[0;32m"
BLUE    = "\033[0;34m"
CYAN    = "\033[0;36m"

def _colored(color, msg):
    if sys.stdout.isatty():
        return f"{color}{msg}{RESET}"
    return msg

findings = []   # list of {"level": "ERROR"|"WARN"|"INFO", "group": str, "msg": str}

def error(group, msg):
    findings.append({"level": "ERROR", "group": group, "msg": msg})

def warn(group, msg):
    findings.append({"level": "WARN",  "group": group, "msg": msg})

def info(group, msg):
    findings.append({"level": "INFO",  "group": group, "msg": msg})

def ok(msg):
    findings.append({"level": "OK",    "group": "",    "msg": msg})

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

RA_RESPONSE_WINDOW_MAP = {1:1, 2:2, 4:4, 8:8, 10:10, 20:20, 40:40, 80:80}
PREAMBLE_TRANS_MAX_MAP = {0:3,1:4,2:5,3:6,4:7,5:8,6:10,7:20,8:50,9:100,10:200}
POWER_RAMPING_STEP_MAP = {0:0, 1:2, 2:4, 3:6}

# locationAndBandwidth = 275*(L-1) + RBstart
# We decode it: L = (val // 275) + 1, RBstart = val % 275
def decode_location_and_bandwidth(val):
    if not isinstance(val, int) or val < 0:
        return None, None
    RBstart = val % 275
    L = (val // 275) + 1
    return L, RBstart

def encode_location_and_bandwidth(L, RBstart=0):
    return 275 * (L - 1) + RBstart

# SCS index → kHz
SCS_KHZ = {0: 15, 1: 30, 2: 60, 3: 120}

# Slots per ms by SCS
SLOTS_PER_MS = {0: 1, 1: 2, 2: 4, 3: 8}

# TDD periodicity index → ms
TDD_PERIOD_MS = {0: 0.5, 1: 0.625, 2: 1.0, 3: 1.25, 4: 2.0, 5: 2.5, 6: 5.0, 7: 10.0}

# Band 78 SSB_PR requirement
BAND_TO_SSB_PR = {
    # FR1 below 3 GHz
    range(1,   100): 1,
    # FR1 3-6 GHz (band 78 = 3300-3800 MHz)
    range(77,  80):  2,
    range(41,  42):  2,
    # FR2 (mmWave)
    range(257, 263): 3,
}

def expected_ssb_pr_for_band(band):
    """Return expected ssb_PositionsInBurst_PR for a given NR band number."""
    fr2_bands = {257, 258, 260, 261}
    fr1_high_bands = {77, 78, 79, 41, 38, 39, 40, 42, 43, 48, 66}
    if band in fr2_bands:
        return 3
    if band in fr1_high_bands:
        return 2
    return 1

# ---------------------------------------------------------------------------
# Main validation
# ---------------------------------------------------------------------------

def validate(cfg: dict, strict: bool):

    # -----------------------------------------------------------------------
    # Structural: top-level required blocks
    # -----------------------------------------------------------------------
    required_blocks = ["Active_gNBs", "gNBs", "MACRLCs", "L1s", "RUs"]
    for b in required_blocks:
        if b not in cfg:
            error("Structure", f"Top-level block '{b}' is missing. OAI will crash without it.")
        else:
            ok(f"Block '{b}' present.")

    if "THREAD_STRUCT" not in cfg:
        warn("Structure", "THREAD_STRUCT block is missing. OAI defaults to PARALLEL_SINGLE_THREAD, which is inadequate for OTA.")

    if "security" not in cfg:
        warn("Structure", "security block missing. OAI has defaults but explicit configuration is recommended.")

    if "log_config" not in cfg:
        info("Structure", "log_config missing. All modules default to 'info'. This is fine.")

    if "gNBs" not in cfg or not isinstance(cfg["gNBs"], list) or len(cfg["gNBs"]) == 0:
        error("Structure", "gNBs must be a non-empty list.")
        return  # Cannot continue without gNBs

    gnb = cfg["gNBs"][0]

    # -----------------------------------------------------------------------
    # Active_gNBs must reference a valid gNB_name
    # -----------------------------------------------------------------------
    active = cfg.get("Active_gNBs", [])
    gnb_name = gnb.get("gNB_name", "")
    if isinstance(active, list) and gnb_name and gnb_name not in active:
        error("Structure", f"Active_gNBs {active} does not include gNB_name='{gnb_name}'.")
    elif gnb_name:
        ok(f"Active_gNBs references gNB_name='{gnb_name}'.")

    # -----------------------------------------------------------------------
    # Identity
    # -----------------------------------------------------------------------
    for field in ["gNB_ID", "gNB_name", "nr_cellid"]:
        if gnb.get(field) is None:
            error("Identity", f"Required field '{field}' is missing.")
    # tracking_area_code is required on CU (has AMF) but absent on DU (no AMF connection)
    has_amf = bool(gnb.get("amf_ip_address"))
    if gnb.get("tracking_area_code") is None:
        if has_amf:
            error("Identity", "tracking_area_code is missing. Required when amf_ip_address is present (CU).")
        else:
            info("Identity", "tracking_area_code absent. Correct for DU (no AMF connection). Required on CU.")

    plmn_list = gnb.get("plmn_list", [])
    if not plmn_list:
        error("Identity", "plmn_list is missing or empty.")
    else:
        for i, plmn in enumerate(plmn_list):
            for f in ["mcc", "mnc", "mnc_length"]:
                if f not in plmn:
                    error("Identity", f"plmn_list[{i}] missing '{f}'.")
            snssai = plmn.get("snssaiList", [])
            if not snssai:
                error("Identity", f"plmn_list[{i}] has empty snssaiList. At least one slice required.")
            else:
                for j, s in enumerate(snssai):
                    if "sst" not in s:
                        error("Identity", f"plmn_list[{i}].snssaiList[{j}] missing 'sst'.")

    # -----------------------------------------------------------------------
    # Network interfaces
    # -----------------------------------------------------------------------
    net = gnb.get("NETWORK_INTERFACES", {})
    if not net:
        if has_amf:
            warn("Network", "NETWORK_INTERFACES block missing. OAI will auto-detect, which may bind the wrong interface on multi-homed hosts.")
        else:
            info("Network", "NETWORK_INTERFACES block absent. Correct for DU (no N2/N3 connection).")
    else:
        for f in ["GNB_INTERFACE_NAME_FOR_NG_AMF", "GNB_IPV4_ADDRESS_FOR_NG_AMF",
                  "GNB_INTERFACE_NAME_FOR_NGU",    "GNB_IPV4_ADDRESS_FOR_NGU"]:
            if not net.get(f):
                warn("Network", f"NETWORK_INTERFACES.{f} not set. OAI auto-detects but may pick wrong interface.")
        # Check AMF address consistency
        amf_entries = gnb.get("amf_ip_address", [])
        if not amf_entries:
            error("Network", "amf_ip_address is missing. SCTP cannot connect to AMF.")

    # -----------------------------------------------------------------------
    # Serving cell config
    # -----------------------------------------------------------------------
    scc_list = gnb.get("servingCellConfigCommon", [])
    if not scc_list or not isinstance(scc_list, list):
        error("Structure", "servingCellConfigCommon is missing or not a list.")
        return
    scc = scc_list[0]

    # --- Group B: SCS chain ---
    dl_scs = scc.get("dl_subcarrierSpacing")
    ul_scs = scc.get("ul_subcarrierSpacing")
    dl_bwp_scs = scc.get("initialDLBWPsubcarrierSpacing")
    ul_bwp_scs = scc.get("initialULBWPsubcarrierSpacing")
    msg1_scs   = scc.get("msg1_SubcarrierSpacing")
    cell_scs   = scc.get("subcarrierSpacing")
    ref_scs    = scc.get("referenceSubcarrierSpacing")

    scs_fields = {
        "dl_subcarrierSpacing":          dl_scs,
        "ul_subcarrierSpacing":          ul_scs,
        "initialDLBWPsubcarrierSpacing": dl_bwp_scs,
        "initialULBWPsubcarrierSpacing": ul_bwp_scs,
        "msg1_SubcarrierSpacing":        msg1_scs,
        "subcarrierSpacing":             cell_scs,
        "referenceSubcarrierSpacing":    ref_scs,
    }

    # Required SCS fields
    for f in ["dl_subcarrierSpacing", "ul_subcarrierSpacing",
              "initialDLBWPsubcarrierSpacing", "initialULBWPsubcarrierSpacing",
              "msg1_SubcarrierSpacing"]:
        if scs_fields[f] is None:
            error("Group B (SCS)", f"Required SCS field '{f}' is missing.")

    # Recommended SCS fields
    for f in ["subcarrierSpacing", "referenceSubcarrierSpacing"]:
        if scs_fields[f] is None:
            warn("Group B (SCS)", f"'{f}' not set. OAI derives it from dl_subcarrierSpacing but being explicit avoids ambiguity.")

    # All present SCS values must match
    present_scs = {k: v for k, v in scs_fields.items() if v is not None}
    unique_scs = set(present_scs.values())
    if len(unique_scs) > 1:
        mismatches = ", ".join(f"{k}={v}" for k, v in present_scs.items())
        error("Group B (SCS)", f"SCS values are inconsistent: {mismatches}. All must be equal.")
    elif dl_scs is not None:
        scs_khz = SCS_KHZ.get(dl_scs, "?")
        ok(f"Group B: All SCS values consistent at {dl_scs} ({scs_khz} kHz).")

    # --- Group A: Carrier ↔ BWP ---
    dl_bw   = scc.get("dl_carrierBandwidth")
    ul_bw   = scc.get("ul_carrierBandwidth")
    dl_loc  = scc.get("initialDLBWPlocationAndBandwidth")
    ul_loc  = scc.get("initialULBWPlocationAndBandwidth")

    for f in ["dl_carrierBandwidth", "ul_carrierBandwidth",
              "initialDLBWPlocationAndBandwidth", "initialULBWPlocationAndBandwidth"]:
        if scc.get(f) is None:
            error("Group A (Carrier/BWP)", f"Required field '{f}' is missing.")

    if dl_bw is not None and ul_bw is not None:
        if not isinstance(dl_bw, int) or not isinstance(ul_bw, int):
            info("Group A (Carrier/BWP)", f"dl/ul_carrierBandwidth contain placeholder values — skipping numeric checks.")
        elif dl_bw != ul_bw:
            error("Group A (Carrier/BWP)", f"dl_carrierBandwidth={dl_bw} ≠ ul_carrierBandwidth={ul_bw}. Must be equal for TDD.")
        else:
            ok(f"Group A: DL/UL carrier bandwidth equal at {dl_bw} PRBs.")

    if dl_bw is not None and dl_loc is not None:
        if not isinstance(dl_bw, int) or not isinstance(dl_loc, int):
            info("Group A (Carrier/BWP)", "Placeholder values detected — skipping locationAndBandwidth numeric check.")
        else:
            pass
        if isinstance(dl_bw, int) and isinstance(dl_loc, int):
            L_dl, RBstart_dl = decode_location_and_bandwidth(dl_loc)
            expected_dl = encode_location_and_bandwidth(dl_bw)
        if L_dl != dl_bw:
            error("Group A (Carrier/BWP)",
                  f"initialDLBWPlocationAndBandwidth={dl_loc} decodes to L={L_dl} PRBs, "
                  f"but dl_carrierBandwidth={dl_bw}. Expected value: {expected_dl}.")
        else:
            ok(f"Group A: DL carrier ({dl_bw} PRBs) matches locationAndBandwidth ({dl_loc}, L={L_dl}).")

    if ul_bw is not None and ul_loc is not None:
        if not isinstance(ul_bw, int) or not isinstance(ul_loc, int):
            info("Group A (Carrier/BWP)", "Placeholder values detected in UL — skipping locationAndBandwidth numeric check.")
        else:
            L_ul, RBstart_ul = decode_location_and_bandwidth(ul_loc)
            expected_ul = encode_location_and_bandwidth(ul_bw)
        if L_ul != ul_bw:
            error("Group A (Carrier/BWP)",
                  f"initialULBWPlocationAndBandwidth={ul_loc} decodes to L={L_ul} PRBs, "
                  f"but ul_carrierBandwidth={ul_bw}. Expected value: {expected_ul}.")
        else:
            ok(f"Group A: UL carrier ({ul_bw} PRBs) matches locationAndBandwidth ({ul_loc}, L={L_ul}).")

    if dl_loc is not None and ul_loc is not None:
        if dl_loc != ul_loc:
            warn("Group A (Carrier/BWP)",
                 f"DL and UL locationAndBandwidth differ ({dl_loc} vs {ul_loc}). "
                 "This is unusual for TDD — verify it is intentional.")

    # --- Group C: TDD pattern arithmetic ---
    dl_ul_period = scc.get("dl_UL_TransmissionPeriodicity")
    nDL_slots    = scc.get("nrofDownlinkSlots")
    nDL_syms     = scc.get("nrofDownlinkSymbols")
    nUL_slots    = scc.get("nrofUplinkSlots")
    nUL_syms     = scc.get("nrofUplinkSymbols")

    tdd_fields = {
        "dl_UL_TransmissionPeriodicity": dl_ul_period,
        "nrofDownlinkSlots":  nDL_slots,
        "nrofDownlinkSymbols": nDL_syms,
        "nrofUplinkSlots":    nUL_slots,
        "nrofUplinkSymbols":  nUL_syms,
    }
    for f, v in tdd_fields.items():
        if v is None:
            error("Group C (TDD)", f"Required TDD field '{f}' is missing.")

    if all(v is not None for v in tdd_fields.values()):
        # Rule 1: special slot budget
        if nDL_syms + nUL_syms > 14:
            error("Group C (TDD)",
                  f"nrofDownlinkSymbols({nDL_syms}) + nrofUplinkSymbols({nUL_syms}) = "
                  f"{nDL_syms+nUL_syms} > 14. No guard symbols left — TX/RX would overlap.")
        elif nDL_syms + nUL_syms == 14:
            warn("Group C (TDD)",
                 f"nrofDownlinkSymbols({nDL_syms}) + nrofUplinkSymbols({nUL_syms}) = 14. "
                 "Zero guard symbols. This may cause TX→RX switching issues with USRP hardware.")
        else:
            guard = 14 - nDL_syms - nUL_syms
            ok(f"Group C: Special slot OK — {nDL_syms} DL + {guard} guard + {nUL_syms} UL = 14.")

        # Rule 2: slots per period
        if dl_scs is not None and dl_ul_period is not None:
            period_ms = TDD_PERIOD_MS.get(dl_ul_period)
            slots_per_ms = SLOTS_PER_MS.get(dl_scs, 0)
            if period_ms and slots_per_ms:
                total_slots = int(period_ms * slots_per_ms)
                used_slots  = nDL_slots + nUL_slots + 1  # +1 for special slot
                if used_slots > total_slots:
                    error("Group C (TDD)",
                          f"nrofDownlinkSlots({nDL_slots}) + nrofUplinkSlots({nUL_slots}) + 1 special = "
                          f"{used_slots} > {total_slots} slots per period "
                          f"(period={period_ms}ms, SCS={SCS_KHZ.get(dl_scs)}kHz).")
                else:
                    ok(f"Group C: Slot budget OK — {used_slots}/{total_slots} slots used per period.")

    # --- Group D: PRACH root sequence ---
    pr_type = scc.get("prach_RootSequenceIndex_PR")
    pr_idx  = scc.get("prach_RootSequenceIndex")
    prach_ci = scc.get("prach_ConfigurationIndex")

    if pr_type is None:
        error("Group D (PRACH)", "prach_RootSequenceIndex_PR is missing.")
    if pr_idx is None:
        error("Group D (PRACH)", "prach_RootSequenceIndex is missing.")

    if pr_type is not None and pr_idx is not None:
        max_idx = 837 if pr_type == 1 else 137  # L=839 → 0-837; L=139 → 0-137
        if pr_idx < 0 or pr_idx > max_idx:
            error("Group D (PRACH)",
                  f"prach_RootSequenceIndex={pr_idx} is out of range for "
                  f"prach_RootSequenceIndex_PR={pr_type} "
                  f"(max={max_idx}, format={'L=839' if pr_type==1 else 'L=139'}).")
        else:
            ok(f"Group D: Root sequence index {pr_idx} valid for PR={pr_type}.")

    if prach_ci is None:
        error("Group D (PRACH)", "prach_ConfigurationIndex is missing.")
    else:
        if prach_ci < 0 or prach_ci > 255:
            error("Group D (PRACH)", f"prach_ConfigurationIndex={prach_ci} out of range 0-255.")

    # RACH required fields with no safe default
    for f in ["zeroCorrelationZoneConfig", "preambleReceivedTargetPower",
              "preambleTransMax", "powerRampingStep", "ra_ContentionResolutionTimer",
              "ssb_perRACH_OccasionAndCB_PreamblesPerSSB_PR",
              "ssb_perRACH_OccasionAndCB_PreamblesPerSSB",
              "msg3_DeltaPreamble", "p0_NominalWithGrant",
              "restrictedSetConfig", "msg1_SubcarrierSpacing"]:
        if scc.get(f) is None:
            error("RACH", f"Required RACH field '{f}' is missing.")

    # ra_ResponseWindow — recommended, default 4 is bad for USRP OTA
    ra_rw = scc.get("ra_ResponseWindow")
    if ra_rw is None:
        warn("RACH", "ra_ResponseWindow not set. OAI defaults to 4 slots — too tight for USRP OTA. Recommend: 10.")
    elif ra_rw == 4:
        warn("RACH", "ra_ResponseWindow=4 is the OAI default but is too tight for USRP OTA hardware. Recommend: 10.")
    elif ra_rw not in RA_RESPONSE_WINDOW_MAP:
        error("RACH", f"ra_ResponseWindow={ra_rw} is not a valid 3GPP value. Valid: 1,2,4,8,10,20,40,80.")
    else:
        ok(f"RACH: ra_ResponseWindow={ra_rw}.")

    # preambleReceivedTargetPower range
    prtp = scc.get("preambleReceivedTargetPower")
    if prtp is not None and not (-202 <= prtp <= -60):
        error("RACH", f"preambleReceivedTargetPower={prtp} out of valid range -202 to -60 dBm.")

    # --- Group E: SSB ---
    ssb_pr     = scc.get("ssb_PositionsInBurst_PR")
    ssb_bitmap = scc.get("ssb_PositionsInBurst_Bitmap")
    ul_band    = scc.get("ul_frequencyBand")

    if ssb_pr is None:
        error("Group E (SSB)", "ssb_PositionsInBurst_PR is missing. OAI will crash without it.")
    if ssb_bitmap is None:
        error("Group E (SSB)", "ssb_PositionsInBurst_Bitmap is missing.")

    if ul_band is not None and ssb_pr is not None:
        expected_pr = expected_ssb_pr_for_band(ul_band)
        if ssb_pr != expected_pr:
            warn("Group E (SSB)",
                 f"ssb_PositionsInBurst_PR={ssb_pr} but Band {ul_band} typically requires PR={expected_pr}. "
                 "Verify this is intentional.")
        else:
            ok(f"Group E: ssb_PositionsInBurst_PR={ssb_pr} consistent with Band {ul_band}.")

    # Max SSBs per PR value: 1→1, 2→4, 3→8 (FR1) or 64 (FR2)
    if ssb_pr is not None and ssb_bitmap is not None:
        max_ssb_by_pr = {1: 1, 2: 4, 3: 8}  # simplified (FR2 can be 64 but bitmap fits in int)
        max_ssb = max_ssb_by_pr.get(ssb_pr, 64)
        # Bitmap value: count active bits. Bitmap=1 means only bit0 set → 1 SSB.
        bit_count = bin(ssb_bitmap).count('1')
        if bit_count > max_ssb:
            error("Group E (SSB)",
                  f"ssb_PositionsInBurst_Bitmap={ssb_bitmap} has {bit_count} active SSBs "
                  f"but ssb_PositionsInBurst_PR={ssb_pr} allows max {max_ssb}.")
        else:
            ok(f"Group E: SSB bitmap ({bit_count} active SSB(s)) consistent with PR={ssb_pr}.")

    # --- Group G: RF gain / attenuation ---
    ru_list = cfg.get("RUs", [])
    if ru_list:
        ru = ru_list[0]
        att_tx = ru.get("att_tx", 0)
        att_rx = ru.get("att_rx", 0)
        if att_tx != 0:
            warn("Group G (RF)", f"att_tx={att_tx}. Non-zero software TX attenuation reduces effective transmit power. "
                                  "Only correct if physical attenuators are in the TX path.")
        else:
            ok(f"Group G: att_tx=0 (correct for OTA).")
        if att_rx != 0:
            warn("Group G (RF)", f"att_rx={att_rx}. Non-zero RX attenuation reduces effective RX sensitivity. "
                                  "This was the primary cause of Msg3 failures in your testbed. "
                                  "Only correct if physical attenuators are in the RX path.")
        else:
            ok(f"Group G: att_rx=0 (correct for OTA).")

        max_rxgain = ru.get("max_rxgain")
        if max_rxgain is None and local_rf not in (False, "no"):
            error("Group G (RF)", "max_rxgain is missing from RUs. OAI/UHD requires this to configure the daughterboard.")
        elif max_rxgain is None and local_rf in (False, "no"):
            info("Group G (RF)", "max_rxgain absent. OK for CU (local_rf=no).")
        elif max_rxgain < 50:
            warn("Group G (RF)", f"max_rxgain={max_rxgain} dB is low. For X310 SBX Band 78, typical range is 65-80 dB. "
                                  "Low gain causes Msg3/PUSCH decode failures.")
        elif max_rxgain > 90:
            warn("Group G (RF)", f"max_rxgain={max_rxgain} dB is very high. Risk of ADC saturation and elevated noise floor.")

        local_rf = ru.get("local_rf", True)
        sdr_addrs = ru.get("sdr_addrs", "")
        if local_rf == False or str(local_rf).lower() == "no":
            if sdr_addrs:
                warn("Group G (RF)", "local_rf=no but sdr_addrs is set. sdr_addrs is ignored when local_rf=no (CU split mode).")
            else:
                info("Group G (RF)", "local_rf=no and sdr_addrs absent. Correct for CU in F1 split mode.")
        elif sdr_addrs:
            if "clock_source" not in str(sdr_addrs):
                warn("Group G (RF)", "sdr_addrs does not contain 'clock_source'. OAI assumes internal clock but being explicit prevents UHD surprises.")
            if "time_source" not in str(sdr_addrs):
                warn("Group G (RF)", "sdr_addrs does not contain 'time_source'. Should match clock_source.")
            if "addr=" not in str(sdr_addrs):
                error("Group G (RF)", "sdr_addrs does not contain 'addr='. OAI cannot find the USRP device.")
        else:
            error("Group G (RF)", "sdr_addrs is missing or empty. OAI cannot connect to the USRP.")

        ssPBCH = scc.get("ssPBCH_BlockPower")
        if ssPBCH is None:
            warn("Group G (RF)", "ssPBCH_BlockPower not set. This affects UE open-loop UL power control estimation.")

    # --- Group H: Threading ---
    thread_structs = cfg.get("THREAD_STRUCT", [])
    mac_list = cfg.get("MACRLCs", [])
    l1_list  = cfg.get("L1s", [])

    if thread_structs:
        ts = thread_structs[0]
        pc = ts.get("parallel_config", "")
        # Check if any RU has local_rf=no (CU in split mode)
        has_local_rf = any(
            r.get("local_rf", True) not in (False, "no")
            for r in cfg.get("RUs", [{}])
        )
        if pc == "PARALLEL_SINGLE_THREAD":
            if has_local_rf:
                warn("Group H (Threading)", "parallel_config=PARALLEL_SINGLE_THREAD is the default but is inadequate for OTA. "
                                             "Use PARALLEL_RU_L1_SPLIT as minimum for USRP.")
            else:
                info("Group H (Threading)", "parallel_config=PARALLEL_SINGLE_THREAD. Acceptable for CU (no local RF/real-time PHY).")
        elif pc in ("PARALLEL_RU_L1_SPLIT", "PARALLEL_RU_L1_TRX_SPLIT"):
            ok(f"Group H: parallel_config={pc} is appropriate for OTA.")
        else:
            warn("Group H (Threading)", f"parallel_config='{pc}' is unrecognised. Expected one of: "
                                         "PARALLEL_SINGLE_THREAD, PARALLEL_RU_L1_SPLIT, PARALLEL_RU_L1_TRX_SPLIT.")

    if l1_list:
        l1 = l1_list[0]
        threads = l1.get("pusch_proc_threads")
        if threads is None:
            if has_local_rf:
                warn("Group H (Threading)", "pusch_proc_threads not set in L1s. Defaults to 1, which is insufficient for 106 PRBs. "
                                             "Set to the number of physical cores on the gNB host.")
            else:
                info("Group H (Threading)", "pusch_proc_threads absent. Acceptable for CU (LDPC decoding runs on DU).")
        elif threads == 1:
            warn("Group H (Threading)", "pusch_proc_threads=1 is the default. For 106 PRBs with multiple UEs, increase to physical core count.")
        elif threads > 16:
            warn("Group H (Threading)", f"pusch_proc_threads={threads} is very high. Should not exceed physical (non-HT) core count.")
        else:
            ok(f"Group H: pusch_proc_threads={threads}.")

    # --- Group I: Transport preference chain ---
    if mac_list and l1_list:
        mac = mac_list[0]
        l1  = l1_list[0]
        mac_s = mac.get("tr_s_preference", "")
        mac_n = mac.get("tr_n_preference", "")
        l1_n  = l1.get("tr_n_preference", "")

        if not mac_s:
            error("Group I (Transport)", "MACRLCs.tr_s_preference is missing.")
        if not mac_n:
            error("Group I (Transport)", "MACRLCs.tr_n_preference is missing.")
        if not l1_n:
            error("Group I (Transport)", "L1s.tr_n_preference is missing.")

        # Monolithic chain check
        if mac_s == "local_L1" and l1_n != "local_mac":
            error("Group I (Transport)",
                  f"MACRLCs.tr_s_preference='local_L1' but L1s.tr_n_preference='{l1_n}'. "
                  "For monolithic gNB, L1s.tr_n_preference must be 'local_mac'. OAI will crash.")
        elif mac_s and l1_n:
            ok(f"Group I: Transport chain consistent ({mac_s} ↔ {l1_n}).")

        if mac.get("SliceConf") is None and strict:
            warn("Group I (ORANSlice)", "MACRLCs.SliceConf not set. Required for ORANSlice NVS scheduler. "
                                         "Without it, xApp slice commands have no effect.")

    # --- min_rxtxtime ---
    mrtt = gnb.get("min_rxtxtime")
    if mrtt is None:
        warn("Timing", "min_rxtxtime not set. Defaults to 6. Use 6 for 10 GbE X310, 8 for 1 GbE.")
    elif mrtt < 6:
        warn("Timing", f"min_rxtxtime={mrtt} is below 6. May cause scheduling misses on USRP hardware.")

    # --- do_SRS / do_CSIRS ---
    if gnb.get("do_SRS", 0) == 0:
        info("Optional", "do_SRS=0 (default). Consider enabling (1) for better UL channel tracking and TA stability.")
    if gnb.get("do_CSIRS", 0) == 0:
        info("Optional", "do_CSIRS=0 (default). Consider enabling (1) for DL channel quality feedback.")

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Validate OAI gNB YAML configuration")
    parser.add_argument("config", help="Path to gNB YAML file")
    parser.add_argument("--strict", action="store_true",
                        help="Treat ORANSlice-specific warnings as errors; also warn on optional omissions")
    parser.add_argument("--json", action="store_true",
                        help="Output findings as JSON instead of coloured text")
    args = parser.parse_args()

    path = Path(args.config)
    if not path.exists():
        print(f"ERROR: File not found: {path}", file=sys.stderr)
        sys.exit(2)

    try:
        with open(path) as f:
            cfg = yaml.safe_load(f)
    except yaml.YAMLError as e:
        print(f"ERROR: YAML parse failure: {e}", file=sys.stderr)
        sys.exit(2)

    if not isinstance(cfg, dict):
        print("ERROR: YAML file does not parse to a dictionary at the top level.", file=sys.stderr)
        sys.exit(2)

    validate(cfg, strict=args.strict)

    if args.json:
        print(_json.dumps(findings, indent=2))
    else:
        level_order = {"ERROR": 0, "WARN": 1, "INFO": 2, "OK": 3}
        level_color = {"ERROR": RED, "WARN": YELLOW, "INFO": CYAN, "OK": GREEN}

        print(_colored(BLUE, f"\n=== OAI gNB YAML Validator — {path} ===\n"))

        for f in sorted(findings, key=lambda x: level_order.get(x["level"], 99)):
            if f["level"] == "OK" and not args.strict:
                continue  # Don't clutter output with OKs unless strict
            tag = f["level"].ljust(5)
            grp = f"[{f['group']}] " if f["group"] else ""
            color = level_color.get(f["level"], RESET)
            print(_colored(color, f"  {tag} {grp}{f['msg']}"))

        errors   = [f for f in findings if f["level"] == "ERROR"]
        warnings = [f for f in findings if f["level"] == "WARN"]
        infos    = [f for f in findings if f["level"] == "INFO"]

        print()
        summary_color = RED if errors else (YELLOW if warnings else GREEN)
        print(_colored(summary_color,
              f"  Summary: {len(errors)} error(s), {len(warnings)} warning(s), {len(infos)} info(s)."))

        if errors:
            print(_colored(RED, "  Result: FAIL — fix errors before running nr-softmodem."))
            sys.exit(1)
        elif warnings:
            print(_colored(YELLOW, "  Result: PASS WITH WARNINGS — review warnings before OTA deployment."))
        else:
            print(_colored(GREEN, "  Result: PASS — no issues found."))

    # Exit 1 if any errors
    if any(f["level"] == "ERROR" for f in findings):
        sys.exit(1)

if __name__ == "__main__":
    main()
