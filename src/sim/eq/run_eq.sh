#!/bin/sh
# Equivalence tests of the translated ACEX / MAX modules against the reference netlists of the original AHDL.
# usage: run_eq.sh [kbd ...]   (default: all); builds the reference netlists when missing (docs/refsim.md)
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
T=${*:-kbd mouse ay}
for t in $T; do
	case $t in
		kbd) run kbd "$(ref KBD303 KBD 303A)" ../../rtl/acex/sp_kbd.v ;;
		mouse) run mouse "$(ref MOUSE303 MOUSE 303A)" ../../rtl/acex/sp_mouse.v ;;
		ay) # test variant of the AY microprogram RAM: counters start at 0 (ay_test_mif.py)
			[ -s build/ay_t/ay_t.hex ] || python3 -I ay_test_mif.py ../../../upstream/tt-sp2000-acex/AY.MIF build/ay_t
			run ay "$(ref AY303T AY "$PWD/build/ay_t")" ../../rtl/acex/sp_ay.v ;;
		*) echo "unknown test $t"; exit 1 ;;
	esac
done
