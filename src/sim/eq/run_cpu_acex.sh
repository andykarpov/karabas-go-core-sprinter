#!/bin/sh
# sp_z84c15 on the ACEX: tb_cpu_acex runs cpu_acex.asm (sjasmplus) on the CPU, which drives sp_acex and the BASE_303
# netlist; four scenarios in parallel (about 2-3 minutes; SCEN="3" for a subset). Debug: vvp -n build/tb_cpu_acex.vvp +scen=N [+stop] [+dbg=<ns>]
set -eu
cd "$(dirname "$0")"
S=${QUARTUS_SIM_LIB:-/opt/altera/quartus/eda/sim_lib}
R=../ahdl
mkdir -p build
VO=$R/build/BASE_303/simulation/modelsim/BASE_303.vo
[ -s "$VO" ] || "$R/build_ref.sh" 303A BASE_303 BASE_303 >/dev/null
SJASM=${SJASM:-$(command -v sjasmplus || echo /opt/sjasmplus/sjasmplus)}
"$SJASM" --nologo --raw=build/cpu_acex.bin cpu_acex.asm > build/cpu_acex.sjasm.log || { cat build/cpu_acex.sjasm.log; exit 1; }
python3 -I -c 'import sys; d = open(sys.argv[1], "rb").read(); open(sys.argv[2], "w").write("".join("%02x\n" % b for b in d))' \
	build/cpu_acex.bin build/cpu_acex.hex
../cpu/t80_v.sh ../cpu/build
A=../../rtl/acex C=../../rtl/cpu
iverilog -g2005 -o build/tb_cpu_acex.vvp -s tb_cpu_acex tb_cpu_acex.v "$VO" $A/sp_acex.v $A/sp_dcp.v $A/sp_video2.v \
	$A/sp_acceler.v $A/sp_ay.v $A/sp_kbd.v $A/sp_mouse.v $C/sp_z84c15.v $C/sp_sio_ch.v $C/sp_ctc_ch.v $C/sp_pio_port.v \
	../cpu/build/t80pa.v "$S/cycloneive_atoms.v" "$S/altera_primitives.v" 2>build/tb_cpu_acex.log \
	|| { grep -v 'coerced\|sorry: procedural continuous' build/tb_cpu_acex.log; exit 1; }
SCEN=${SCEN:-0 1 2 3}
for s in $SCEN; do vvp -n build/tb_cpu_acex.vvp +scen=$s > build/tb_cpu_acex_$s.txt 2>&1 & done; wait
for s in $SCEN; do echo "scenario $s:"; grep -v '\$finish\|readmemh' build/tb_cpu_acex_$s.txt; done
