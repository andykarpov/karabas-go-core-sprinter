#!/bin/sh
# sp_machine from power-up through the ACEX configuration load to the configured CPU (tb_machine), BIOS 3.04.
# usage: run_machine.sh [iverilog|verilator] [CFG_BITS] [RUN_US]
#   defaults: iverilog 4096 100 (512 bytes of the stream = the whole MAME hash; ~2.5 min);
#   the full stream: run_machine.sh verilator 473720 100 (build ~45 s + ~3 min)
# The ROM image is local (not in git): $ROM, default ~/Downloads/karabas-sd-sprinter/roms/mame-named/sp2k-3.04.rom
# (docs/roms.md 1.1: = MAME sp2k-3.04, zxgit 2000/fw/bios/sp2k-3.04.253.bin).
# Env: ROM=<image>; ARGS="+reset" / "+p2e" (a second boot by the reset button / by the port 2E control word: must repeat the
# first), "+scroll" (the game configuration from fastram: hash 3861cfa4, personality 2), "+trace" (every M1),
# "+hash=5aa954b6 +pers=1" (the expected hash / personality: BIOS 3.06, k30; default 78eddfc6 / 0 = 3.04);
# STOP=<us> end the run there; PROG=<us> progress interval; BUILD_ONLY=1 build only (then run the binary from here).
set -eu
cd "$(dirname "$0")"
SIM=${1:-iverilog} BITS=${2:-4096} US=${3:-100} ARGS=${ARGS:-}
ROM=${ROM:-$HOME/Downloads/karabas-sd-sprinter/roms/mame-named/sp2k-3.04.rom}
mkdir -p build
[ -s "$ROM" ] || { echo "no ROM image $ROM"; exit 1; }
hex() { python3 -I -c 'import sys; d = open(sys.argv[1], "rb").read(); open(sys.argv[2], "w").write("".join("%02x\n" % b for b in d))' "$1" "$2"; }
hex "$ROM" build/rom.hex
hex "../../../upstream/tt-scroll-cnf/original bitstream/SCROLL.ACX" build/scroll.hex
../cpu/t80_v.sh ../cpu/build
R=../../rtl
SRC="tb_machine.v $R/top/sp_machine.v $R/acex/sp_acex.v $R/acex/sp_dcp.v $R/acex/sp_video2.v $R/acex/sp_acceler.v \
	$R/acex/sp_ay.v $R/acex/sp_kbd.v $R/acex/sp_mouse.v $R/acex/sp_max.v $R/cpu/sp_z84c15.v $R/cpu/sp_sio_ch.v \
	$R/cpu/sp_ctc_ch.v $R/cpu/sp_pio_port.v $R/mem/sp_sram.v $R/mem/sp_sdram.v ../eq/mem/oddr2.v ../cpu/build/t80pa.v"
DEF="-DCFG_BITS_T=$BITS -DRUN_US=$US ${STOP:+-DSTOP_US=$STOP} ${PROG:+-DPROG_US=$PROG}"
case $SIM in
	iverilog)
		iverilog -g2005 -o build/tb_machine.vvp -s tb_machine $DEF $SRC 2>build/iverilog.log \
			|| { cat build/iverilog.log; exit 1; }
		[ -n "${BUILD_ONLY:-}" ] || time vvp -n build/tb_machine.vvp $ARGS ;;
	verilator)
		# the T80 netlist of ghdl has many unused / width warnings: lint off; zero-delay models, --timing for the testbench
		verilator --binary --timing -O3 --x-assign fast --x-initial fast -Wno-fatal -Wno-lint -Wno-style \
			-Wno-MULTIDRIVEN -Wno-TIMESCALEMOD -Wno-SYNCASYNCNET --top-module tb_machine $DEF \
			-Mdir build/vl -o tb_machine $SRC >build/verilator.log 2>&1 || { tail -30 build/verilator.log; exit 1; }
		[ -n "${BUILD_ONLY:-}" ] || time build/vl/tb_machine $ARGS ;;
	*) echo "unknown simulator $SIM"; exit 1 ;;
esac
