# Slicing Consistency Notes for FN990

This scenario keeps two active slices:

- Slice1: SST=128 / SD=000080 / DNN=default
- Slice2: SST=1 / SD=000001 / DNN=internet

The removed slice was:

- Slice3: SST=130 / SD=000082 / DNN=oai.ipv4 / vpp-upf-slice3

The FN990 is expected to use slice2:

- PLMN: 00101
- TAC: 1
- SST: 1
- SD: 000001
- DNN/APN: internet
- PDU session type: IPv4
- IMSI: 001010000000002

The FN990 should use APN `internet`, not `oai`, for this scenario.

Suggested modem AT commands for later lab use:

```text
AT+CGDCONT=1,"IP","internet"
AT+CGDCONT=2
AT+CGDCONT=3
AT+COPS=1,2,"00101",12
```

Do not start the OAI nrUE at the same time as the FN990 if both are configured with IMSI `001010000000002`.

The current database has a subscriber for slice1 and the FN990 subscriber for slice2.

If the FN990 still sees Vivo, the modem is not selecting or seeing the OAI PLMN/cell. Do not change the gNB to Vivo's frequency. Instead verify OAI gNB broadcast, RF power/gain, antennas, PLMN, SSB frequency, and scan results.

The gNB RF/ARFCN values were intentionally left unchanged.
