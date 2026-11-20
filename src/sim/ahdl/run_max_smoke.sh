#!/bin/sh
# Build the MAX reference netlist if needed and run the smoke test (seconds; +frame = two frames, ~4 min).
set -eu
cd "$(dirname "$0")"
V=build/SP2_MAX/simulation/modelsim/SP2_MAX.vo
[ -s "$V" ] || ./build_ref.sh MAX SP2_MAX
S=${QUARTUS_SIM_LIB:-/opt/altera/quartus/eda/sim_lib}
iverilog -g2005 -o build/tb_max_smoke.vvp -s tb_max_smoke tb_max_smoke.v "$V" "$S/cycloneive_atoms.v" "$S/altera_primitives.v" 2>/dev/null
vvp -n build/tb_max_smoke.vvp "$@"
