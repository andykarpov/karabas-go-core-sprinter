#!/bin/bash
# XST gate of the translated ACEX with its memory controllers (sp_acex + sp_sram + sp_sdram, wrapper
# sp_acexm_gate.v; no PAR): LUTs, FFs, BRAM, Fmax estimate on the Mini G part. Outputs build/sp_acexm.*
# usage: acexm_xst.sh   -> build/sp_acexm.syr
set -e
cd "$(dirname "$0")"
mkdir -p build/xstm/projnav.tmp
cd build
A=../../rtl/acex
M=../../rtl/mem
cp $A/mif/*.hex .
{ for f in sp_acex sp_dcp sp_video2 sp_acceler sp_ay sp_kbd sp_mouse; do echo "verilog work \"$A/$f.v\""; done
  for f in sp_sram sp_sdram; do echo "verilog work \"$M/$f.v\""; done
  echo "verilog work \"../sp_acexm_gate.v\""; } > sp_acexm.prj
cat > sp_acexm.xst <<E
set -tmpdir "xstm/projnav.tmp"
set -xsthdpdir "xstm"
run
-ifn sp_acexm.prj
-ofn sp_acexm
-ofmt NGC
-p xc6slx25-2-ftg256
-top sp_acexm_gate
-opt_mode Speed
-opt_level 1
-iobuf NO
-keep_hierarchy Soft
-ram_extract Yes
-rom_extract Yes
-shreg_extract YES
-fsm_extract YES
-reduce_control_sets Auto
E
. ${ISE_SETTINGS:-/opt/Xilinx/14.7/ISE_DS/settings64.sh} >/dev/null
xst -intstyle silent -ifn sp_acexm.xst -ofn sp_acexm.syr >/dev/null || { grep -i 'error' sp_acexm.syr | head -20; exit 1; }
grep -E 'Number of Slice (LUTs|Registers)|Number of Block RAM|RAMB16BWER|RAMB8BWER|ODDR2  |Minimum period' sp_acexm.syr
grep -A40 'Timing constraint: Default period analysis' sp_acexm.syr | grep -E 'Source:|Destination:|Levels of Logic' | head -3
