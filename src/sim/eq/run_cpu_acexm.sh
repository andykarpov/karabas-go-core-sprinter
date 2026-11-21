#!/bin/sh
# The three blocks together: tb_cpu_acexm runs cpu_acex.asm on sp_z84c15, which drives the BASE_303 netlist (ideal
# memories) and sp_acex on its own memory (sp_sram + IS61 models, sp_sdram + MT48 model, mem/); five scenarios in
# parallel (scenario 4: the vertical accelerator modes from DRAM as Flex Navigator; about 2-4 minutes; SCEN="3" for a subset). Debug: vvp -n build/tb_cpu_acexm.vvp +scen=N [+stop] [+dbg=<ns>] [+cpuref]
# REF=SCROLL: the SCROLL personality against the SCROLL netlist (outputs build/tb_cpu_acexm_scroll*).
set -eu
cd "$(dirname "$0")"
S=${QUARTUS_SIM_LIB:-/opt/altera/quartus/eda/sim_lib}
R=../ahdl
mkdir -p build
VO=$R/build/BASE_303/simulation/modelsim/BASE_303.vo
[ -s "$VO" ] || "$R/build_ref.sh" 303A BASE_303 BASE_303 >/dev/null
DEFS=; SFX=
if [ "${REF:-}" = SCROLL ]; then
	VO=$R/build/SCROLL/simulation/modelsim/SCROLL.vo
	[ -s "$VO" ] || "$R/build_ref.sh" SCROLL SCROLL SCROLL >/dev/null
	[ -s build/dcp_scroll.hex ] || python3 -I ../../../tools/mif.py hex ../../../upstream/tt-scroll-cnf/src/DCP.MIF build/dcp_scroll.hex >/dev/null
	DEFS="-DSCROLL '-DMIF_DCP_HEX=\"$PWD/build/dcp_scroll.hex\"'"; SFX=_scroll
fi
SJASM=${SJASM:-$(command -v sjasmplus || echo /opt/sjasmplus/sjasmplus)}
"$SJASM" --nologo --raw=build/cpu_acex.bin cpu_acex.asm > build/cpu_acex.sjasm.log || { cat build/cpu_acex.sjasm.log; exit 1; }
python3 -I -c 'import sys; d = open(sys.argv[1], "rb").read(); open(sys.argv[2], "w").write("".join("%02x\n" % b for b in d))' \
	build/cpu_acex.bin build/cpu_acex.hex
../cpu/t80_v.sh ../cpu/build
A=../../rtl/acex C=../../rtl/cpu M=../../rtl/mem
MEMRTL=${MEMRTL:-$M/sp_sram.v}; T=tb_cpu_acexm$SFX${TAG:-}   # (MEMRTL: a mutated copy, TAG: its output names)
eval iverilog -g2005 -I. $DEFS -o build/$T.vvp -s tb_cpu_acexm tb_cpu_acexm.v "$VO" $A/sp_acex.v $A/sp_dcp.v $A/sp_video2.v \
	$A/sp_acceler.v $A/sp_ay.v $A/sp_kbd.v $A/sp_mouse.v $C/sp_z84c15.v $C/sp_sio_ch.v $C/sp_ctc_ch.v $C/sp_pio_port.v \
	../cpu/build/t80pa.v "$MEMRTL" $M/sp_sdram.v mem/sram_is61.v mem/sdram_mt48.v mem/oddr2.v \
	"$S/cycloneive_atoms.v" "$S/altera_primitives.v" 2>build/$T.log \
	|| { grep -v 'coerced\|sorry: procedural continuous' build/$T.log; exit 1; }
SCEN=${SCEN:-0 1 2 3 4}
for s in $SCEN; do vvp -n build/$T.vvp +scen=$s ${VVPARGS:-} > build/${T}_$s.txt 2>&1 & done; wait
for s in $SCEN; do echo "scenario $s:"; grep -v '\$finish\|readmemh' build/${T}_$s.txt; done
