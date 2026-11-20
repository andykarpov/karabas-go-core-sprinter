#!/bin/sh
# Compile the original AHDL (upstream/sprinter-hard, Quartus2/) with Quartus 13 (docker image karabas-quartus:13.0sp1)
# for Cyclone IV E and write a functional Verilog netlist per top: the reference for the equivalence sims.
# usage: build_ref.sh [ACEX|MAX] [TOP]   (default ACEX SP2_ACEX); output build/<TOP>/<TOP>.vo
set -eu
cd "$(dirname "$0")"
DIR=${1:-ACEX}; TOP=${2:-SP2_ACEX}
B=build/$TOP
mkdir -p "$B"
cp ../../../upstream/sprinter-hard/Quartus2/$DIR/*.TDF ../../../upstream/sprinter-hard/Quartus2/$DIR/*.INC "$B"/ 2>/dev/null || true
cp ../../../upstream/sprinter-hard/Quartus2/$DIR/*.MIF "$B"/ 2>/dev/null || true
# the sources were written on DOS: INCLUDE "kbd" needs kbd.inc, LPM_FILE="DCP.MIF" the upper case
for f in "$B"/*.TDF "$B"/*.INC "$B"/*.MIF; do [ -e "$f" ] || continue; l=$(basename "$f" | tr A-Z a-z); [ -e "$B/$l" ] || cp "$f" "$B/$l"; done
cat > "$B/$TOP.qsf" <<Q
set_global_assignment -name FAMILY "Cyclone IV E"
set_global_assignment -name DEVICE EP4CE115F29C7
set_global_assignment -name TOP_LEVEL_ENTITY $TOP
set_global_assignment -name AHDL_FILE $TOP.TDF
set_global_assignment -name SEARCH_PATH .
set_global_assignment -name AUTO_RESOURCE_SHARING OFF
set_global_assignment -name REMOVE_REDUNDANT_LOGIC_CELLS OFF
set_global_assignment -name EDA_SIMULATION_TOOL "ModelSim-Altera (Verilog)"
set_global_assignment -name EDA_OUTPUT_DATA_FORMAT "VERILOG HDL" -section_id eda_simulation
Q
echo "PROJECT_REVISION = \"$TOP\"" > "$B/$TOP.qpf"
docker run --rm --network none -u "$(id -u):$(id -g)" -v "$PWD/$B:/work" -w /work karabas-quartus:13.0sp1 \
	sh -c "quartus_map $TOP && quartus_eda $TOP --simulation --functional --tool=modelsim --format=verilog" > "$B/build.log" 2>&1 \
	|| { tail -40 "$B/build.log"; exit 1; }
ls "$B"/simulation/modelsim/*.vo
grep -E "Total logic elements|Total registers|Total memory bits|Info: Quartus II .* was successful" "$B"/*.map.summary "$B/build.log" || true
