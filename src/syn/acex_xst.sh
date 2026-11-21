#!/bin/bash
# XST gate of the translated ACEX alone (no PAR): LUTs, RAM inference, Fmax estimate on the Mini G part.
# usage: acex_xst.sh   -> build/sp_acex.syr
set -e
cd "$(dirname "$0")"
mkdir -p build/xst/projnav.tmp
cd build
A=../../rtl/acex
cp $A/mif/*.hex .
for f in sp_acex sp_dcp sp_video2 sp_acceler sp_ay sp_kbd sp_mouse; do echo "verilog work \"$A/$f.v\""; done > sp_acex.prj
cat > sp_acex.xst <<X
set -tmpdir "xst/projnav.tmp"
set -xsthdpdir "xst"
run
-ifn sp_acex.prj
-ofn sp_acex
-ofmt NGC
-p xc6slx25-2-ftg256
-top sp_acex
-opt_mode Speed
-opt_level 1
-iobuf NO
-keep_hierarchy Soft
-ram_extract Yes
-rom_extract Yes
-shreg_extract YES
-fsm_extract YES
-reduce_control_sets Auto
X
. ${ISE_SETTINGS:-/opt/Xilinx/14.7/ISE_DS/settings64.sh} >/dev/null
xst -intstyle silent -ifn sp_acex.xst -ofn sp_acex.syr >/dev/null || { grep -i 'error' sp_acex.syr | head -20; exit 1; }
grep -E 'Number of Slice (LUTs|Registers)|Block RAM|RAMB|Minimum period|Maximum Frequency|WARNING:Xst:(1710|1895|2677|737|2404)' sp_acex.syr | sort | uniq -c | sort -rn | head -30
