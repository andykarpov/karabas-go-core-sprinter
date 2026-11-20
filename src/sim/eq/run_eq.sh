#!/bin/sh
# Equivalence tests of the translated ACEX / MAX modules against the reference netlists of the original AHDL.
# usage: run_eq.sh [kbd ...] [+frame]   (default: all; +frame = whole frames where a test supports it, minutes); builds the reference netlists when missing (docs/refsim.md)
set -eu
cd "$(dirname "$0")"
S=${QUARTUS_SIM_LIB:-/opt/altera/quartus/eda/sim_lib}
R=../ahdl
mkdir -p build
ref() { [ -s "$R/build/$1/simulation/modelsim/$2.vo" ] || "$R/build_ref.sh" "$3" "$2" "$1" >/dev/null; echo "$R/build/$1/simulation/modelsim/$2.vo"; }
run() {
	t=$1; shift
	iverilog -g2005 -o build/tb_eq_$t.vvp -s tb_eq_$t tb_eq_$t.v "$@" "$S/cycloneive_atoms.v" "$S/altera_primitives.v" 2>build/tb_eq_$t.log \
		|| { grep -v coerced build/tb_eq_$t.log; exit 1; }
	vvp -n build/tb_eq_$t.vvp | grep -v '\$finish'
}
T=${*:-kbd mouse ay max}
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
		*) echo "unknown test $t"; exit 1 ;;
	esac
done
