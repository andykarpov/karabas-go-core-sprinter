#!/bin/sh
# Compile an original AHDL design with Quartus 13 (docker image karabas-quartus:13.0sp1) for Cyclone IV E and write
# a functional Verilog netlist: the reference for the equivalence sims.
# usage: build_ref.sh [SRC] [TOP] [NAME]    output build/<NAME>/simulation/modelsim/<TOP>.vo
#   SRC: a directory of .TDF / .INC / .MIF, or an alias:
#     ACEX, MAX  upstream/sprinter-hard MaxPlus2/ACEX, MaxPlus2/MAX (2.18, default ACEX; the MIFs of Quartus2/ are damaged)
#     303A       upstream/tt-sp2000-acex (3.03a, top BASE_303)
#     K30        upstream/tt-sprinter-bios at 085ef3c src/altera/acex/k30 (BIOS 3.05+, top SP2_ACEX; extracted)
#     SCROLL     upstream/tt-scroll-cnf/src (game config, top SCROLL)
#   NAME: build directory (default TOP; give one when two sources share a top name)
set -eu
cd "$(dirname "$0")"
U=../../../upstream
SRC=${1:-ACEX}; TOP=${2:-SP2_ACEX}
case "$SRC" in
	ACEX|MAX) SRC=$U/sprinter-hard/MaxPlus2/$SRC ;;
	303A) SRC=$U/tt-sp2000-acex ;;
	SCROLL) SRC=$U/tt-scroll-cnf/src ;;
	K30) mkdir -p build/src_k30; git -C $U/tt-sprinter-bios archive 085ef3c src/altera/acex/k30 | tar -x -C build/src_k30
	     SRC=build/src_k30/src/altera/acex/k30 ;;
esac
B=build/${3:-$TOP}
mkdir -p "$B"
for f in "$SRC"/*.TDF "$SRC"/*.tdf "$SRC"/*.INC "$SRC"/*.inc "$SRC"/*.MIF "$SRC"/*.mif; do [ -e "$f" ] && cp "$f" "$B"/; done
# MAX+plus II MIF list syntax ("addr : v1 v2 ...") is illegal for Quartus 13: rewrite one address per line
for f in "$B"/*.MIF "$B"/*.mif; do [ -e "$f" ] && python3 -I ../../../tools/mif.py mif "$f" "$f"; done
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
