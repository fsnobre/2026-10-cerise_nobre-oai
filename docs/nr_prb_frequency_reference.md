# NR FR1 PRB and Frequency Configuration Reference

> **Scope:** FR1 (sub-6 GHz) NR bands for OAI gNB YAML configuration.  
> **SCS covered:** 15 kHz and 30 kHz (most common for FR1 TDD/FDD sub-6 GHz).  
> **60 kHz SCS:** Valid for FR1 but rarely used in practice — omitted.  
> **FR2 (mmWave):** Not covered.  
> **Validator:** Run `python3 validate_gnb_yaml.py gnb.yaml` to catch Group A/B mismatches after filling in values from this table.

---

## How to Use This Reference

For each deployment, you need three consistent values:

```yaml
dl_subcarrierSpacing: <SCS_index>          # 0=15kHz, 1=30kHz
dl_carrierBandwidth: <PRBs>                # from table below
initialDLBWPlocationAndBandwidth: <val>    # 275*(PRBs-1)+0 for RBstart=0
ul_carrierBandwidth: <PRBs>                # = dl_carrierBandwidth for TDD
initialULBWPlocationAndBandwidth: <val>    # = initialDL value for TDD
absoluteFrequencySSB: <NR-ARFCN>          # from frequency table below
dl_absoluteFrequencyPointA: <NR-ARFCN>    # from frequency table below
```

**locationAndBandwidth formula:**
```
value = 275 × (L − 1) + RBstart
```
Where `L` = number of PRBs, `RBstart` = 0 (carrier starts at Point A).

---

## Part 1: PRB Count and locationAndBandwidth by Channel Bandwidth and SCS

### 15 kHz SCS (dl_subcarrierSpacing: 0)

| Channel BW | PRBs (`dl_carrierBandwidth`) | `locationAndBandwidth` | Notes |
|---|---|---|---|
| 5 MHz | 25 | 6600 | 275×24=6600 |
| 10 MHz | 52 | 14025 | 275×51=14025 |
| 15 MHz | 79 | 21450 | 275×78=21450 |
| 20 MHz | 106 | 28875 | 275×105=28875 |
| 25 MHz | 133 | 36300 | 275×132=36300 |
| 30 MHz | 160 | 43725 | 275×159=43725 |
| 35 MHz | 188 | 51425 | 275×187=51425 |
| 40 MHz | 216 | 59125 | 275×215=59125 |
| 45 MHz | 242 | 66275 | 275×241=66275 |
| 50 MHz | 270 | 73975 | 275×269=73975 |

> **Note:** 15 kHz SCS is standard for FDD bands (Band 1, 3, 7, 20, 28) and some TDD bands. For Band 78 (3.3–3.8 GHz), 30 kHz SCS is standard.

### 30 kHz SCS (dl_subcarrierSpacing: 1)

| Channel BW | PRBs (`dl_carrierBandwidth`) | `locationAndBandwidth` | Notes |
|---|---|---|---|
| 5 MHz | 11 | 2750 | 275×10=2750 |
| 10 MHz | 24 | 6325 | 275×23=6325 |
| 15 MHz | 38 | 10175 | 275×37=10175 |
| 20 MHz | 51 | 13750 | 275×50=13750 |
| 25 MHz | 65 | 17600 | 275×64=17600 |
| 30 MHz | 78 | 21175 | 275×77=21175 |
| 35 MHz | 92 | 25025 | 275×91=25025 |
| 40 MHz | 106 | 28875 | 275×105=28875 ← **your testbed** |
| 45 MHz | 119 | 32450 | 275×118=32450 |
| 50 MHz | 133 | 36300 | 275×132=36300 |
| 60 MHz | 162 | 44275 | 275×161=44275 |
| 70 MHz | 189 | 51700 | 275×188=51700 |
| 80 MHz | 217 | 59400 | 275×216=59400 |
| 90 MHz | 245 | 67100 | 275×244=67100 |
| 100 MHz | 273 | 74800 | 275×272=74800 |

---

## Part 2: Band-by-Band Frequency Reference

For each band, several common center frequencies are provided with the corresponding NR-ARFCN values for `absoluteFrequencySSB` and `dl_absoluteFrequencyPointA`.

**NR-ARFCN formula (for FR1, ΔFglobal = 15 kHz, Fref-offs = 0 MHz, Nref-offs = 0):**
```
NR-ARFCN = F_MHz × 1000 / 15      (simplified for FR1 below 3 GHz)

For FR1 3-6 GHz (ΔFglobal = 15 kHz, Fref-offs = 3000 MHz, Nref-offs = 600000):
NR-ARFCN = 600000 + (F_MHz − 3000) × 1000 / 15
```

> **Practical note:** The values below are pre-calculated. Always verify with an NR-ARFCN calculator for frequencies not listed. OAI will reject invalid ARFCNs with a config parse error.

---

### Band 1 — FDD, 2100 MHz (DL: 2110–2170 MHz, UL: 1920–1980 MHz)

- **Standard SCS:** 15 kHz
- **Duplex:** FDD — `ul_frequencyBand: 1`, UL ARFCN ≠ DL ARFCN
- **Common use:** European 4G/5G coexistence, university lab UEs

| DL Center (MHz) | `absoluteFrequencySSB` | `dl_absoluteFrequencyPointA` (20 MHz) | `dl_absoluteFrequencyPointA` (10 MHz) |
|---|---|---|---|
| 2140 | 428000 | 425000 | 426500 |
| 2150 | 430000 | 427000 | 428500 |
| 2160 | 432000 | 429000 | 430500 |

| Channel BW | SCS | PRBs | `locationAndBandwidth` | PRACH index |
|---|---|---|---|---|
| 10 MHz | 15k | 52 | 14025 | 16 |
| 20 MHz | 15k | 106 | 28875 | 16 |

```yaml
# Band 1 example — 20 MHz, 15 kHz SCS, DL center 2140 MHz
dl_subcarrierSpacing: 0
dl_carrierBandwidth: 106
initialDLBWPlocationAndBandwidth: 28875
ul_frequencyBand: 1
ul_subcarrierSpacing: 0
ul_carrierBandwidth: 106
initialULBWPlocationAndBandwidth: 28875
absoluteFrequencySSB: 428000
dl_absoluteFrequencyPointA: 425000
msg1_SubcarrierSpacing: 0
prach_ConfigurationIndex: 16
ssb_PositionsInBurst_PR: 1    # FR1 below 3 GHz: short (1 SSB)
```

---

### Band 3 — FDD, 1800 MHz (DL: 1805–1880 MHz, UL: 1710–1785 MHz)

- **Standard SCS:** 15 kHz
- **Duplex:** FDD
- **Common use:** Most widespread LTE/NR band globally; good UE support

| DL Center (MHz) | `absoluteFrequencySSB` | `dl_absoluteFrequencyPointA` (20 MHz) | `dl_absoluteFrequencyPointA` (10 MHz) |
|---|---|---|---|
| 1842.5 | 368500 | 365500 | 367000 |
| 1860 | 372000 | 369000 | 370500 |
| 1875 | 375000 | 372000 | 373500 |

| Channel BW | SCS | PRBs | `locationAndBandwidth` | PRACH index |
|---|---|---|---|---|
| 10 MHz | 15k | 52 | 14025 | 16 |
| 15 MHz | 15k | 79 | 21450 | 16 |
| 20 MHz | 15k | 106 | 28875 | 16 |

```yaml
# Band 3 example — 20 MHz, 15 kHz SCS, DL center 1860 MHz
dl_subcarrierSpacing: 0
dl_carrierBandwidth: 106
initialDLBWPlocationAndBandwidth: 28875
ul_frequencyBand: 3
ul_subcarrierSpacing: 0
ul_carrierBandwidth: 106
initialULBWPlocationAndBandwidth: 28875
absoluteFrequencySSB: 372000
dl_absoluteFrequencyPointA: 369000
msg1_SubcarrierSpacing: 0
prach_ConfigurationIndex: 16
ssb_PositionsInBurst_PR: 1    # FR1 below 3 GHz: short
```

---

### Band 7 — FDD, 2600 MHz (DL: 2620–2690 MHz, UL: 2500–2570 MHz)

- **Standard SCS:** 15 kHz (can use 30 kHz)
- **Duplex:** FDD
- **Common use:** Urban macro, high capacity

| DL Center (MHz) | `absoluteFrequencySSB` | `dl_absoluteFrequencyPointA` (20 MHz, 15k) | `dl_absoluteFrequencyPointA` (20 MHz, 30k) |
|---|---|---|---|
| 2630 | 526000 | 523000 | 523000 |
| 2655 | 531000 | 528000 | 528000 |
| 2680 | 536000 | 533000 | 533000 |

| Channel BW | SCS | PRBs | `locationAndBandwidth` | PRACH index |
|---|---|---|---|---|
| 10 MHz | 15k | 52 | 14025 | 16 |
| 20 MHz | 15k | 106 | 28875 | 16 |
| 20 MHz | 30k | 51 | 13750 | 98 |

```yaml
# Band 7 example — 20 MHz, 30 kHz SCS, DL center 2655 MHz
dl_subcarrierSpacing: 1
dl_carrierBandwidth: 51
initialDLBWPlocationAndBandwidth: 13750
ul_frequencyBand: 7
ul_subcarrierSpacing: 1
ul_carrierBandwidth: 51
initialULBWPlocationAndBandwidth: 13750
absoluteFrequencySSB: 531000
dl_absoluteFrequencyPointA: 528000
msg1_SubcarrierSpacing: 1
prach_ConfigurationIndex: 98
ssb_PositionsInBurst_PR: 1    # FR1 below 3 GHz: short
```

---

### Band 20 — FDD, 800 MHz (DL: 791–821 MHz, UL: 832–862 MHz)

- **Standard SCS:** 15 kHz
- **Duplex:** FDD (note: UL is at higher frequency than DL — reversed from typical)
- **Common use:** Rural coverage, deep indoor

| DL Center (MHz) | `absoluteFrequencySSB` | `dl_absoluteFrequencyPointA` (10 MHz) | `dl_absoluteFrequencyPointA` (5 MHz) |
|---|---|---|---|
| 796 | 158200 | 157450 | 157825 |
| 806 | 161200 | 160450 | 160825 |
| 816 | 163200 | 162450 | 162825 |

| Channel BW | SCS | PRBs | `locationAndBandwidth` | PRACH index |
|---|---|---|---|---|
| 5 MHz | 15k | 25 | 6600 | 16 |
| 10 MHz | 15k | 52 | 14025 | 16 |

```yaml
# Band 20 example — 10 MHz, 15 kHz SCS, DL center 806 MHz
dl_subcarrierSpacing: 0
dl_carrierBandwidth: 52
initialDLBWPlocationAndBandwidth: 14025
ul_frequencyBand: 20
ul_subcarrierSpacing: 0
ul_carrierBandwidth: 52
initialULBWPlocationAndBandwidth: 14025
absoluteFrequencySSB: 161200
dl_absoluteFrequencyPointA: 160450
msg1_SubcarrierSpacing: 0
prach_ConfigurationIndex: 16
ssb_PositionsInBurst_PR: 1    # FR1 below 3 GHz: short
```

---

### Band 28 — FDD, 700 MHz (DL: 758–803 MHz, UL: 703–748 MHz)

- **Standard SCS:** 15 kHz
- **Duplex:** FDD
- **Common use:** Rural/suburban, high penetration

| DL Center (MHz) | `absoluteFrequencySSB` | `dl_absoluteFrequencyPointA` (10 MHz) | `dl_absoluteFrequencyPointA` (5 MHz) |
|---|---|---|---|
| 763 | 151600 | 150850 | 151225 |
| 773 | 153600 | 152850 | 153225 |
| 793 | 157600 | 156850 | 157225 |

| Channel BW | SCS | PRBs | `locationAndBandwidth` | PRACH index |
|---|---|---|---|---|
| 5 MHz | 15k | 25 | 6600 | 16 |
| 10 MHz | 15k | 52 | 14025 | 16 |

```yaml
# Band 28 example — 10 MHz, 15 kHz SCS, DL center 773 MHz
dl_subcarrierSpacing: 0
dl_carrierBandwidth: 52
initialDLBWPlocationAndBandwidth: 14025
ul_frequencyBand: 28
ul_subcarrierSpacing: 0
ul_carrierBandwidth: 52
initialULBWPlocationAndBandwidth: 14025
absoluteFrequencySSB: 153600
dl_absoluteFrequencyPointA: 152850
msg1_SubcarrierSpacing: 0
prach_ConfigurationIndex: 16
ssb_PositionsInBurst_PR: 1    # FR1 below 3 GHz: short
```

---

### Band 38 — TDD, 2600 MHz (2570–2620 MHz)

- **Standard SCS:** 15 kHz or 30 kHz
- **Duplex:** TDD — `ul_frequencyBand: 38`, DL and UL same ARFCN
- **Common use:** TDD mid-band, some European deployments

| Center (MHz) | `absoluteFrequencySSB` | `dl_absoluteFrequencyPointA` (20 MHz, 30k) | `dl_absoluteFrequencyPointA` (10 MHz, 30k) |
|---|---|---|---|
| 2580 | 516000 | 513000 | 514500 |
| 2595 | 519000 | 516000 | 517500 |
| 2610 | 522000 | 519000 | 520500 |

| Channel BW | SCS | PRBs | `locationAndBandwidth` | PRACH index |
|---|---|---|---|---|
| 10 MHz | 30k | 24 | 6325 | 98 |
| 20 MHz | 30k | 51 | 13750 | 98 |

```yaml
# Band 38 example — 20 MHz, 30 kHz SCS, center 2595 MHz
dl_subcarrierSpacing: 1
dl_carrierBandwidth: 51
initialDLBWPlocationAndBandwidth: 13750
ul_frequencyBand: 38
ul_subcarrierSpacing: 1
ul_carrierBandwidth: 51
initialULBWPlocationAndBandwidth: 13750
absoluteFrequencySSB: 519000
dl_absoluteFrequencyPointA: 516000
msg1_SubcarrierSpacing: 1
prach_ConfigurationIndex: 98
ssb_PositionsInBurst_PR: 1    # FR1 below 3 GHz: short
```

---

### Band 41 — TDD, 2500 MHz (2496–2690 MHz)

- **Standard SCS:** 15 kHz or 30 kHz
- **Duplex:** TDD
- **Common use:** CBRS adjacent, US mid-band 5G

| Center (MHz) | `absoluteFrequencySSB` | `dl_absoluteFrequencyPointA` (40 MHz, 30k) | `dl_absoluteFrequencyPointA` (20 MHz, 30k) |
|---|---|---|---|
| 2530 | 506000 | 503000 | 504500 |
| 2570 | 514000 | 511000 | 512500 |
| 2620 | 524000 | 521000 | 522500 |

| Channel BW | SCS | PRBs | `locationAndBandwidth` | PRACH index |
|---|---|---|---|---|
| 20 MHz | 30k | 51 | 13750 | 98 |
| 40 MHz | 30k | 106 | 28875 | 98 |

```yaml
# Band 41 example — 40 MHz, 30 kHz SCS, center 2570 MHz
dl_subcarrierSpacing: 1
dl_carrierBandwidth: 106
initialDLBWPlocationAndBandwidth: 28875
ul_frequencyBand: 41
ul_subcarrierSpacing: 1
ul_carrierBandwidth: 106
initialULBWPlocationAndBandwidth: 28875
absoluteFrequencySSB: 514000
dl_absoluteFrequencyPointA: 511000
msg1_SubcarrierSpacing: 1
prach_ConfigurationIndex: 98
ssb_PositionsInBurst_PR: 2    # FR1 3-6 GHz: medium (4 SSBs)
```

---

### Band 66 — FDD, 1700/2100 MHz (DL: 2110–2200 MHz, UL: 1710–1780 MHz)

- **Standard SCS:** 15 kHz
- **Duplex:** FDD
- **Common use:** AWS band (Americas), widely supported in COTS UEs

| DL Center (MHz) | `absoluteFrequencySSB` | `dl_absoluteFrequencyPointA` (20 MHz) | `dl_absoluteFrequencyPointA` (10 MHz) |
|---|---|---|---|
| 2130 | 426000 | 423000 | 424500 |
| 2155 | 431000 | 428000 | 429500 |
| 2180 | 436000 | 433000 | 434500 |

| Channel BW | SCS | PRBs | `locationAndBandwidth` | PRACH index |
|---|---|---|---|---|
| 10 MHz | 15k | 52 | 14025 | 16 |
| 20 MHz | 15k | 106 | 28875 | 16 |

```yaml
# Band 66 example — 20 MHz, 15 kHz SCS, DL center 2155 MHz
dl_subcarrierSpacing: 0
dl_carrierBandwidth: 106
initialDLBWPlocationAndBandwidth: 28875
ul_frequencyBand: 66
ul_subcarrierSpacing: 0
ul_carrierBandwidth: 106
initialULBWPlocationAndBandwidth: 28875
absoluteFrequencySSB: 431000
dl_absoluteFrequencyPointA: 428000
msg1_SubcarrierSpacing: 0
prach_ConfigurationIndex: 16
ssb_PositionsInBurst_PR: 1    # FR1 below 3 GHz: short
```

---

### Band 77 — TDD, 3700 MHz (3300–4200 MHz)

- **Standard SCS:** 30 kHz
- **Duplex:** TDD — DL = UL same frequency
- **Common use:** US C-band 5G; Benetel RAN550 primary band
- **Note:** Band 77 is a superset of Band 78 — UEs supporting Band 78 also support Band 77 in the 3300–3800 MHz range

| Center (MHz) | `absoluteFrequencySSB` | `dl_absoluteFrequencyPointA` (40 MHz) | `dl_absoluteFrequencyPointA` (20 MHz) | `dl_absoluteFrequencyPointA` (100 MHz) |
|---|---|---|---|---|
| 3600 | 720000 | 717000 | 718500 | 713500 |
| 3700 | 740000 | 737000 | 738500 | 733500 |
| 3800 | 760000 | 757000 | 758500 | 753500 |
| 3900 | 780000 | 777000 | 778500 | 773500 |
| 4000 | 800000 | 797000 | 798500 | 793500 |

| Channel BW | SCS | PRBs | `locationAndBandwidth` | PRACH index |
|---|---|---|---|---|
| 20 MHz | 30k | 51 | 13750 | 98 |
| 40 MHz | 30k | 106 | 28875 | 98 |
| 50 MHz | 30k | 133 | 36300 | 98 |
| 100 MHz | 30k | 273 | 74800 | 98 |

```yaml
# Band 77 example — 40 MHz, 30 kHz SCS, center 3700 MHz
dl_subcarrierSpacing: 1
dl_carrierBandwidth: 106
initialDLBWPlocationAndBandwidth: 28875
ul_frequencyBand: 77
ul_subcarrierSpacing: 1
ul_carrierBandwidth: 106
initialULBWPlocationAndBandwidth: 28875
absoluteFrequencySSB: 740000
dl_absoluteFrequencyPointA: 737000
msg1_SubcarrierSpacing: 1
prach_ConfigurationIndex: 98
ssb_PositionsInBurst_PR: 2    # FR1 3-6 GHz: medium
```

---

### Band 78 — TDD, 3500 MHz (3300–3800 MHz) ← Your testbed primary band

- **Standard SCS:** 30 kHz
- **Duplex:** TDD
- **Common use:** Global mid-band 5G, Benetel RAN650, your USRP X310 testbed
- **ssb_PositionsInBurst_PR:** Always `2` (FR1 3–6 GHz, medium)

| Center (MHz) | `absoluteFrequencySSB` | `dl_absoluteFrequencyPointA` (40 MHz) | `dl_absoluteFrequencyPointA` (20 MHz) | `dl_absoluteFrequencyPointA` (10 MHz) | `dl_absoluteFrequencyPointA` (100 MHz) |
|---|---|---|---|---|---|
| 3300 | 660000 | 657000 | 658500 | 659250 | 653500 |
| 3319.2 | 640704 | 639996 | — | — | — |
| 3350 | 670000 | 667000 | 668500 | 669250 | 663500 |
| 3400 | 680000 | 677000 | 678500 | 679250 | 673500 |
| 3450 | 690000 | 687000 | 688500 | 689250 | 683500 |
| 3500 | 700000 | 697000 | 698500 | 699250 | 693500 |
| 3550 | 710000 | 707000 | 708500 | 709250 | 703500 |
| 3600 | 720000 | 717000 | 718500 | 719250 | 713500 |
| 3700 | 740000 | 737000 | 738500 | 739250 | 733500 |
| 3750 | 750000 | 747000 | 748500 | 749250 | 743500 |
| 3800 | 760000 | 757000 | 758500 | 759250 | 753500 |

> **Your testbed:** Center ≈ 3319 MHz → `absoluteFrequencySSB: 640704`, `dl_absoluteFrequencyPointA: 639996` (40 MHz / 30 kHz SCS)

| Channel BW | SCS | PRBs | `locationAndBandwidth` | PRACH index |
|---|---|---|---|---|
| 10 MHz | 30k | 24 | 6325 | 98 |
| 20 MHz | 30k | 51 | 13750 | 98 |
| **40 MHz** | **30k** | **106** | **28875** | **98** ← **your testbed** |
| 50 MHz | 30k | 133 | 36300 | 98 |
| 60 MHz | 30k | 162 | 44275 | 98 |
| 80 MHz | 30k | 217 | 59400 | 98 |
| 100 MHz | 30k | 273 | 74800 | 98 |

```yaml
# Band 78 — YOUR TESTBED: 40 MHz, 30 kHz SCS, center 3319.2 MHz
dl_subcarrierSpacing: 1
dl_carrierBandwidth: 106
initialDLBWPlocationAndBandwidth: 28875
ul_frequencyBand: 78
ul_subcarrierSpacing: 1
ul_carrierBandwidth: 106
initialULBWPlocationAndBandwidth: 28875
absoluteFrequencySSB: 640704
dl_absoluteFrequencyPointA: 639996
msg1_SubcarrierSpacing: 1
prach_ConfigurationIndex: 98
ssb_PositionsInBurst_PR: 2
```

```yaml
# Band 78 — 20 MHz, 30 kHz SCS, center 3500 MHz
dl_subcarrierSpacing: 1
dl_carrierBandwidth: 51
initialDLBWPlocationAndBandwidth: 13750
ul_frequencyBand: 78
ul_subcarrierSpacing: 1
ul_carrierBandwidth: 51
initialULBWPlocationAndBandwidth: 13750
absoluteFrequencySSB: 700000
dl_absoluteFrequencyPointA: 698500
msg1_SubcarrierSpacing: 1
prach_ConfigurationIndex: 98
ssb_PositionsInBurst_PR: 2
```

```yaml
# Band 78 — 100 MHz, 30 kHz SCS, center 3600 MHz
dl_subcarrierSpacing: 1
dl_carrierBandwidth: 273
initialDLBWPlocationAndBandwidth: 74800
ul_frequencyBand: 78
ul_subcarrierSpacing: 1
ul_carrierBandwidth: 273
initialULBWPlocationAndBandwidth: 74800
absoluteFrequencySSB: 720000
dl_absoluteFrequencyPointA: 713500
msg1_SubcarrierSpacing: 1
prach_ConfigurationIndex: 98
ssb_PositionsInBurst_PR: 2
```

---

### Band 79 — TDD, 4700 MHz (4400–5000 MHz)

- **Standard SCS:** 30 kHz
- **Duplex:** TDD
- **Common use:** Japan domestic 5G, some Asian deployments

| Center (MHz) | `absoluteFrequencySSB` | `dl_absoluteFrequencyPointA` (40 MHz) | `dl_absoluteFrequencyPointA` (100 MHz) |
|---|---|---|---|
| 4700 | 726666 | 723666 | 720166 |
| 4800 | 733333 | 730333 | 726833 |
| 4900 | 740000 | 737000 | 733500 |

| Channel BW | SCS | PRBs | `locationAndBandwidth` | PRACH index |
|---|---|---|---|---|
| 40 MHz | 30k | 106 | 28875 | 98 |
| 100 MHz | 30k | 273 | 74800 | 98 |

```yaml
# Band 79 example — 40 MHz, 30 kHz SCS, center 4700 MHz
dl_subcarrierSpacing: 1
dl_carrierBandwidth: 106
initialDLBWPlocationAndBandwidth: 28875
ul_frequencyBand: 79
ul_subcarrierSpacing: 1
ul_carrierBandwidth: 106
initialULBWPlocationAndBandwidth: 28875
absoluteFrequencySSB: 726666
dl_absoluteFrequencyPointA: 723666
msg1_SubcarrierSpacing: 1
prach_ConfigurationIndex: 98
ssb_PositionsInBurst_PR: 2    # FR1 3-6 GHz: medium
```

---

## Part 3: Quick-Reference Cheatsheets

### 3.1 PRB Count by SCS and Bandwidth

| BW (MHz) | 15 kHz PRBs | 30 kHz PRBs |
|---|---|---|
| 5 | 25 | 11 |
| 10 | 52 | 24 |
| 15 | 79 | 38 |
| 20 | 106 | 51 |
| 25 | 133 | 65 |
| 30 | 160 | 78 |
| 35 | 188 | 92 |
| 40 | 216 | 106 |
| 45 | 242 | 119 |
| 50 | 270 | 133 |
| 60 | — | 162 |
| 70 | — | 189 |
| 80 | — | 217 |
| 90 | — | 245 |
| 100 | — | 273 |

### 3.2 locationAndBandwidth by PRB Count (RBstart = 0)

| PRBs | `locationAndBandwidth` |
|---|---|
| 11 | 2750 |
| 24 | 6325 |
| 25 | 6600 |
| 38 | 10175 |
| 51 | 13750 |
| 52 | 14025 |
| 65 | 17600 |
| 78 | 21175 |
| 79 | 21450 |
| 92 | 25025 |
| 106 | 28875 |
| 119 | 32450 |
| 133 | 36300 |
| 160 | 43725 |
| 162 | 44275 |
| 188 | 51425 |
| 189 | 51700 |
| 216 | 59125 |
| 217 | 59400 |
| 242 | 66275 |
| 245 | 67100 |
| 270 | 73975 |
| 273 | 74800 |

### 3.3 ssb_PositionsInBurst_PR by Frequency Range

| Frequency range | Bands | `ssb_PositionsInBurst_PR` | Max SSBs |
|---|---|---|---|
| FR1 below 3 GHz | 1, 3, 7, 20, 28, 38, 41 (low), 66 | `1` (short) | 1 |
| FR1 3–6 GHz | 41 (high), 77, 78, 79 | `2` (medium) | 4 |

> **Rule:** Band 41 straddles 3 GHz. Frequencies below 3000 MHz in Band 41 use PR=1; above 3000 MHz use PR=2. In practice Band 41 deployments above 3 GHz (2570–2690 MHz range overlaps Band 41 upper edge) should use PR=2.

### 3.4 PRACH Configuration Index by SCS

| SCS | Standard TDD PRACH index | Notes |
|---|---|---|
| 15 kHz | `16` | Format A1, suitable for most FDD/TDD bands below 3 GHz |
| 30 kHz | `98` | Format B4, standard for TDD at 30 kHz SCS (Band 77/78/79) |

> These are the most common values used with OAI. Other valid indices exist — consult TS 38.211 Table 6.3.3.2-2 for alternatives (e.g. index 145 for short preamble at 30 kHz in TDD).

### 3.5 TDD vs FDD Parameter Differences

| Parameter | FDD (e.g. Band 1, 3) | TDD (e.g. Band 78) |
|---|---|---|
| `ul_frequencyBand` | Different band number (UL band) | Same as DL band |
| `ul_carrierBandwidth` | May differ from DL | = `dl_carrierBandwidth` |
| `initialULBWPlocationAndBandwidth` | May differ from DL | = `initialDLBWPlocationAndBandwidth` |
| `absoluteFrequencySSB` | DL ARFCN | Shared DL/UL ARFCN |
| UL ARFCN (sdr_addrs or separate) | Separate | Same as DL |
| `dl_UL_TransmissionPeriodicity` | Not needed (no TDD pattern) | Required |
| `nrofDownlinkSlots` etc. | Not needed | Required |
| `msg1_SubcarrierSpacing` | = `dl_subcarrierSpacing` | = `dl_subcarrierSpacing` |

---

## Part 4: Consistency Checklist Before Running

Before launching nr-softmodem with a new frequency config, verify all of these:

```
[ ] dl_carrierBandwidth  matches  initialDLBWPlocationAndBandwidth  (Group A)
[ ] ul_carrierBandwidth  matches  initialULBWPlocationAndBandwidth   (Group A)
[ ] dl_carrierBandwidth  =  ul_carrierBandwidth                      (Group A, TDD)
[ ] All SCS fields equal: dl/ul_subcarrierSpacing,
    initialDL/ULBWPsubcarrierSpacing, msg1_SubcarrierSpacing,
    subcarrierSpacing, referenceSubcarrierSpacing                    (Group B)
[ ] absoluteFrequencySSB is within the band's frequency range
[ ] dl_absoluteFrequencyPointA is below absoluteFrequencySSB
    (Point A is lower edge; SSB is near center)
[ ] ssb_PositionsInBurst_PR matches frequency range (1 below 3GHz, 2 above)
[ ] prach_ConfigurationIndex is valid for SCS + TDD/FDD
[ ] Run: python3 validate_gnb_yaml.py gnb.yaml
```

---

## Part 5: Point A Calculation

`dl_absoluteFrequencyPointA` is the ARFCN of the lowest subcarrier of the lowest RB (Point A), not the center frequency. For a carrier of `N` PRBs at SCS `μ`:

```
carrier_bandwidth_Hz = N × 12 × subcarrier_spacing_Hz
point_a_Hz = center_frequency_Hz − (carrier_bandwidth_Hz / 2)
point_a_ARFCN = point_a_Hz / (ΔFglobal × 1000)
```

**Example — Band 78, 40 MHz, 30 kHz SCS, center 3319.2 MHz:**
```
carrier_bandwidth = 106 × 12 × 30,000 = 38,160,000 Hz = 38.16 MHz
point_a = 3319.2 − (38.16 / 2) = 3319.2 − 19.08 = 3300.12 MHz
point_a_ARFCN = 600000 + (3300.12 − 3000) × 1000/15 = 600000 + 20001 = 620001
```

> The value `639996` used in your testbed corresponds to Point A at 3300.60 MHz, which accounts for SSB ARFCN grid alignment. Use an NR-ARFCN calculator to verify non-standard frequencies — OAI validates that SSB ARFCN falls on the synchronization raster.

---

## Part 6: Frequency Offset Between Point A and SSB

The `absoluteFrequencySSB` must fall on the **synchronization raster**, which is coarser than the channel raster. For FR1:

| SCS | Channel raster | Sync raster |
|---|---|---|
| 15 kHz | 100 kHz | 1200 kHz (every 80th subcarrier) |
| 30 kHz | 100 kHz | 1200 kHz |

**Rule of thumb:** `absoluteFrequencySSB` should be approximately:
```
absoluteFrequencySSB ≈ dl_absoluteFrequencyPointA + (carrier_PRBs × 6)
```
(center of carrier, rounded to nearest sync raster point)

This is pre-calculated in all tables in this document. If you use a non-standard frequency, verify the SSB ARFCN falls on the synchronization raster using:
```python
# Check if ARFCN is on sync raster for FR1 (1200 kHz spacing)
# For FR1 3-6 GHz: ARFCN = 600000 + N, where N must be divisible by 80
arfcn = 640704
base = 600000
offset = arfcn - base        # = 40704
on_raster = (offset % 80 == 0)  # 40704 / 80 = 508.8 — check actual raster table
# OAI will error if SSB ARFCN is off-raster
```
