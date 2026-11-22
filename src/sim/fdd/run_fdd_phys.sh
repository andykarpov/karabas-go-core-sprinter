#!/bin/bash
# tb_fdd_phys: sp_fdd PHYS 1 (sp_fdd_phys with the VG93 model) on two drive models (fdd_model.v of core-msx2 /
# core-pcxt), verilator --timing; drive A at the nominal disk speed and 2 % off, two runs in parallel; ~1 min with the
# build. Ends with "run_fdd_phys: N errors".
set -eu
cd "$(dirname "$0")"
B=build
mkdir -p $B
R=../../rtl
verilator --binary --timing -j 4 -O3 --top-module tb_fdd_phys -Mdir $B/obj -o tb_fdd_phys -I$R/fdd/vg93 \
	+define+VG93_ROM_FILE=\"$R/fdd/vg93/vg93-microcode-rom.hex\" \
	-Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-TIMESCALEMOD \
	tb_fdd_phys.v fdd_model.v $R/fdd/sp_fdd.v $R/fdd/sp_fdd_phys.v $R/fdd/wd1793.v $R/fdd/vg93/vg93_*.v \
	> $B/build.log 2>&1 || { tail -30 $B/build.log; exit 1; }
SPEEDS=${SPEEDS:-"1.0 1.02"}
pids=()
for sp in $SPEEDS; do
	$B/obj/tb_fdd_phys +speed=$sp > $B/tb_fdd_phys_$sp.log 2>&1 &
	pids+=($!)
done
for p in "${pids[@]}"; do wait "$p" || true; done
err=0
for sp in $SPEEDS; do
	if grep -q "tb_fdd_phys: 0 errors" $B/tb_fdd_phys_$sp.log; then echo "speed $sp: ok"
	else echo "speed $sp: FAIL"; grep -E "ERROR|time out" $B/tb_fdd_phys_$sp.log | head -20; err=$((err + 1)); fi
done
echo "run_fdd_phys: $err errors"
[ $err -eq 0 ]
