#!/bin/sh
# Equivalence tests of the translated ACEX / MAX modules against the reference netlists of the original AHDL.
# usage: run_eq.sh [kbd ...] [+frame]   (acexm: not in the default set)   (default: all; +frame = whole frames where a test supports it, minutes); builds the reference netlists when missing (docs/refsim.md)
# k30 personality (PERS_K30 = 1 against the k30 netlists, docs/versions.md): dcp_k30 video2_k30 acex_k30 acexm_k30
#   (not in the default set); acex_k30_mut: each k30 line forced back to 3.03a must fail.
# SCEN="0 2": the scenarios of acex / acexm / acex_k30 / acexm_k30, one after another (unset: all three in parallel).
set -eu
cd "$(dirname "$0")"
S=${QUARTUS_SIM_LIB:-/opt/altera/quartus/eda/sim_lib}
R=../ahdl
mkdir -p build
K30=$R/build/src_k30/src/altera/acex/k30
ref() { [ -s "$R/build/$1/simulation/modelsim/$2.vo" ] || "$R/build_ref.sh" "$3" "$2" "$1" >/dev/null; echo "$R/build/$1/simulation/modelsim/$2.vo"; }
# the k30 sources are extracted by build_ref.sh K30 (the whole ACEX); modules from that directory
refk() { [ -d "$K30" ] || "$R/build_ref.sh" K30 SP2_ACEX K30 >/dev/null; ref "$1" "$2" "$PWD/$K30"; }
# build <tb> [-o <name>] [-DK30] <sources>: build/tb_eq_<name>.vvp
build() {
	t=$1; shift; o=$t
	[ "$1" = -o ] && { o=$2; shift 2; }
	iverilog -g2005 -o build/tb_eq_$o.vvp -s tb_eq_$t tb_eq_$t.v "$@" "$S/cycloneive_atoms.v" "$S/altera_primitives.v" 2>build/tb_eq_$o.log \
		|| { grep -v 'coerced\|sorry: procedural continuous' build/tb_eq_$o.log; exit 1; }
}
run() { build "$@"; o=$1; [ "$2" = -o ] && o=$3; vvp -n build/tb_eq_$o.vvp | grep -v '\$finish'; }
# scenarios of a whole-ACEX bench (build/tb_eq_<name>.vvp): SCEN one by one, else 0 1 2 in parallel
scen() {
	if [ -n "${SCEN:-}" ]; then
		for s in $SCEN; do echo "scenario $s:"; vvp -n build/tb_eq_$1.vvp +scen=$s 2>&1 | grep -v '\$finish'; done
	else
		for s in 0 1 2; do vvp -n build/tb_eq_$1.vvp +scen=$s > build/tb_eq_$1_$s.txt 2>&1 & done; wait
		for s in 0 1 2; do echo "scenario $s:"; grep -v '\$finish' build/tb_eq_$1_$s.txt; done
	fi
}
A=../../rtl/acex; M=../../rtl/mem
ACEX="$A/sp_acex.v $A/sp_dcp.v $A/sp_video2.v $A/sp_acceler.v $A/sp_ay.v $A/sp_kbd.v $A/sp_mouse.v"
MEM="$M/sp_sram.v $M/sp_sdram.v mem/sram_is61.v mem/sdram_mt48.v mem/oddr2.v"
T=${*:-kbd mouse ay max video2 acceler dcp acex}
for t in $T; do
	case $t in
		kbd) run kbd "$(ref KBD303 KBD 303A)" ../../rtl/acex/sp_kbd.v ;;
		mouse) run mouse "$(ref MOUSE303 MOUSE 303A)" ../../rtl/acex/sp_mouse.v ;;
		ay) # test variant of the AY microprogram RAM: counters start at 0 (ay_test_mif.py)
			[ -s build/ay_t/ay_t.hex ] || python3 -I ay_test_mif.py ../../../upstream/tt-sp2000-acex/AY.MIF build/ay_t
			run ay "$(ref AY303T AY "$PWD/build/ay_t")" ../../rtl/acex/sp_ay.v ;;
		max) # test variant: XHD_RES on SINC_H (reset ends after a line); the same in ours by XHD_RES_ON_HSYNC
			if [ ! -s build/max_t/SP2_MAX.TDF ]; then
				mkdir -p build/max_t
				sed 's/XHD_RES[[:space:]]*= DFF(PW_GOOD,SINC_V,,);/XHD_RES = DFF(PW_GOOD,SINC_H,,);/' \
					../../../upstream/sprinter-hard/MaxPlus2/MAX/SP2_MAX.TDF > build/max_t/SP2_MAX.TDF
				grep -q 'DFF(PW_GOOD,SINC_H' build/max_t/SP2_MAX.TDF || { echo "max_t: patch failed"; exit 1; }
			fi
			# the RS latches of EXP cells loop forever in zero delay: 1 ps on their outputs (vo_loop_delay.py)
			python3 -I vo_loop_delay.py "$(ref MAX_T SP2_MAX "$PWD/build/max_t")" build/max_t.vo 'THDD|NO_HDD|T320|TURBING|RDAT_X' 2>/dev/null
			run max build/max_t.vo ../../rtl/acex/sp_max.v ;;
		video2) run video2 "$(ref VID303 VIDEO2 303A)" ../../rtl/acex/sp_video2.v ;;
		acceler) run acceler "$(ref ACC303 ACCELER 303A)" ../../rtl/acex/sp_acceler.v ;;
		dcp) run dcp "$(ref DCP303 DCP 303A)" ../../rtl/acex/sp_dcp.v ;;
		acex) # the whole ACEX (top + submodules) against BASE_303; three scenarios (bus / 3.5 MHz, CBL, soft
			# reset / keyboard). Debug: vvp -n build/tb_eq_acex.vvp +scen=N [+stop] [+dbg=<ns>] [+cdbg=<ns>] [+tdbg]
			build acex "$(ref BASE_303 BASE_303 303A)" $ACEX
			scen acex ;;
		acexm) # the same, our module on its memory: sp_sram + SRAM models, sp_sdram + SDRAM model (mem/), pad delays
			build acexm -I. "$(ref BASE_303 BASE_303 303A)" $ACEX $MEM
			scen acexm ;;
		dcp_k30) run dcp -o dcp_k30 -DK30 "$(refk DCPK30 DCP)" $A/sp_dcp.v ;;
		video2_k30) run video2 -o video2_k30 -DK30 "$(refk VIDK30 VIDEO2)" $A/sp_video2.v ;;
		acex_k30) # sp_acex with PERS_K30 = 1 against the k30 netlist (top SP2_ACEX)
			build acex -o acex_k30 -DK30 "$(ref K30 SP2_ACEX K30)" $ACEX
			scen acex_k30 ;;
		acexm_k30)
			build acexm -o acexm_k30 -DK30 -I. "$(ref K30 SP2_ACEX K30)" $ACEX $MEM
			scen acexm_k30 ;;
		acex_k30_mut) # mutations: one k30 line back to 3.03a (tb_eq_acex.v +mut); each must give errors
			build acex -o acex_k30 -DK30 "$(ref K30 SP2_ACEX K30)" $ACEX
			for m in ${MUT:-1:0 2:0 3:0 4:2 5:2 6:2 7:0 8:2 9:0}; do
				r=$(vvp -n build/tb_eq_acex_k30.vvp +scen=${m#*:} +mut=${m%:*} +stop 2>&1 | grep 'tb_eq_acex:\|first mismatch')
				case "$r" in *" 0 errors"*) echo "mutation ${m%:*} (scenario ${m#*:}): NOT caught";;
					*) echo "mutation ${m%:*} (scenario ${m#*:}): caught: $(echo "$r" | head -1)";; esac
			done ;;
		*) echo "unknown test $t"; exit 1 ;;
	esac
done
