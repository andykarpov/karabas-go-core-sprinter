#!/bin/bash
# XST gate of sp_z84c15 alone (T80pa + SIO / CTC / PIO / SCRP, no PAR): LUTs, FFs, Fmax estimate on the Mini G part.
# The CPU registers step only at CE_N where CLKZ1 changes: T80 CEN -> CEN paths have 4 CLK (47.6 ns at 21 MHz),
# CEN_n -> CEN_p 2 CLK (23.8 ns); the data from the bus (changed at CE) get 1 CLK. XST reports the worst path as if
# 1 CLK: compare it with those budgets (docs/z84c15.md 8).
# usage: z84c15_xst.sh   -> build/z84c15/sp_z84c15.syr
set -e
cd "$(dirname "$0")"
mkdir -p build/z84c15/xst/projnav.tmp
cd build/z84c15
R=../../../rtl/cpu
{ for f in T80_Pack T80_ALU T80_MCode T80_Reg T80 T80pa; do echo "vhdl work \"$R/t80/$f.vhd\""; done
  for f in sp_sio_ch sp_ctc_ch sp_pio_port sp_z84c15; do echo "verilog work \"$R/$f.v\""; done; } > sp_z84c15.prj
cat > sp_z84c15.xst <<X
set -tmpdir "xst/projnav.tmp"
set -xsthdpdir "xst"
run
-ifn sp_z84c15.prj
-ofn sp_z84c15
-ofmt NGC
-p xc6slx25-2-ftg256
-top sp_z84c15
-opt_mode Speed
-opt_level 1
-iobuf NO
-keep_hierarchy Soft
-fsm_extract YES
-reduce_control_sets Auto
X
. ${ISE_SETTINGS:-/opt/Xilinx/14.7/ISE_DS/settings64.sh} >/dev/null
xst -intstyle silent -ifn sp_z84c15.xst -ofn sp_z84c15.syr >/dev/null || { grep -i 'error' sp_z84c15.syr | head -20; exit 1; }
grep -E 'Number of Slice (LUTs|Registers)|Minimum period|Maximum Frequency' sp_z84c15.syr | sort | uniq -c
# the worst paths: within the CPU and from the outside (D_I, CLKZ1 / NX, WAIT_N: inputs of the module)
grep -A3 -E '^Timing constraint: Default (period analysis|OFFSET IN)' sp_z84c15.syr | grep -E 'Delay|Offset|Clock period' | head -4
grep -B1 -A6 '^Delay:' sp_z84c15.syr | grep -E 'Delay|Source:|Destination:' | head -9
