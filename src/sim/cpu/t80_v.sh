#!/bin/sh
# T80pa (src/rtl/cpu/t80, VHDL) as a Verilog netlist for iverilog: ghdl --synth, the recipe of core-tsconf
# (run_z80s_sim.sh). Two name fixes: the instance labels renamed (VHDL is not case sensitive: the signal ALU_Q of
# T80 and the port Q of the instance alu both become alu_q) and the escaped "\reg " after a prefix made plain; the net "do" (a SystemVerilog keyword) renamed. The
# generics are fixed in the netlist (Mode 0, IOWait 1: what sp_z84c15 uses).
# usage: t80_v.sh <out dir>   -> <out dir>/t80pa.v (rebuilt only when a VHDL source is newer)
set -eu
OUT=${1:?out dir}
T=$(cd "$(dirname "$0")/../../rtl/cpu/t80" && pwd)
mkdir -p "$OUT/t80"
cd "$OUT/t80"
if [ -s ../t80pa.v ] && [ -z "$(find "$T" -name '*.vhd' -newer ../t80pa.v)" ]; then exit 0; fi
cp "$T/T80_Pack.vhd" "$T/T80_Reg.vhd" "$T/T80_MCode.vhd" "$T/T80_ALU.vhd" .
sed 's/^\tmcode : T80_MCode/\tu_mcode : T80_MCode/; s/^\talu : T80_ALU/\tu_alu : T80_ALU/; s/^\tRegs : T80_Reg/\tu_regs : T80_Reg/' \
	"$T/T80.vhd" > T80.vhd
sed 's/^    u0 : T80/    u_t80 : T80/' "$T/T80pa.vhd" > T80pa.vhd
rm -f ./*.cf
ghdl --synth --std=08 -fsynopsys --workdir=. --out=verilog T80_Pack.vhd T80_Reg.vhd T80_MCode.vhd T80_ALU.vhd T80.vhd \
	T80pa.vhd -e t80pa > t80pa.v.tmp 2> ghdl.log || { cat ghdl.log; exit 1; }
sed -E 's/u_t80_\\reg /u_t80_reg_x/g; s/\bdo\b/do_x/g' t80pa.v.tmp > ../t80pa.v
rm -f t80pa.v.tmp
