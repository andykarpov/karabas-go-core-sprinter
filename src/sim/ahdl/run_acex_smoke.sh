#!/bin/sh
# Smoke test of a reference ACEX netlist (seconds). usage: run_acex_smoke.sh [NAME [TOP]]  default BASE_303 BASE_303
set -eu
cd "$(dirname "$0")"
N=${1:-BASE_303}; T=${2:-$N}
V=build/$N/simulation/modelsim/$T.vo
[ -s "$V" ] || ./build_ref.sh 303A BASE_303
S=${QUARTUS_SIM_LIB:-/opt/altera/quartus/eda/sim_lib}
python3 -I acex_ports.py "$V" build/$N/ports.vh
iverilog -g2005 -DTOP=$T -I build/$N -o build/tb_acex_smoke_$N.vvp -s tb_acex_smoke tb_acex_smoke.v "$V" \
	"$S/cycloneive_atoms.v" "$S/altera_primitives.v" 2>/dev/null
vvp -n build/tb_acex_smoke_$N.vvp
