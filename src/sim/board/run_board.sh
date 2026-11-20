#!/bin/sh
# Smoke test of the board glue (tb_board.v, docs/minig.md 7): loader bridge -> SRAM -> CPU start -> ACEX release,
# video (sp_vout), keyboard (sp_kbd_tx), sound (sp_i2s_rx, iverilog only).
# usage: run_board.sh [iverilog|verilator] [CFG_BITS] [RUN_US]
#   iverilog (default): the loader page only (512 bytes through the bridge), CFG_BITS 256: ~1 min
#   verilator: the whole 256 KB through the bridge (65 ms of model time) and the keyboard with its shipped timing
#   (make + break, KBD_REAL); RUN_US 6000 there
# The ROM image is local (not in git): $ROM, default ~/Downloads/karabas-sd-sprinter/roms/mame-named/sp2k-3.04.rom
set -eu
cd "$(dirname "$0")"
SIM=${1:-iverilog} BITS=${2:-256} US=${3:-300}
ROM=${ROM:-$HOME/Downloads/karabas-sd-sprinter/roms/mame-named/sp2k-3.04.rom}
mkdir -p build
[ -s "$ROM" ] || { echo "no ROM image $ROM"; exit 1; }
python3 -I -c 'import sys; d = open(sys.argv[1], "rb").read(); open(sys.argv[2], "w").write("".join("%02x\n" % b for b in d))' "$ROM" build/rom.hex
../cpu/t80_v.sh ../cpu/build
R=../../rtl
SRC="tb_board.v $R/top/sp_machine.v $R/acex/sp_acex.v $R/acex/sp_dcp.v $R/acex/sp_video2.v $R/acex/sp_acceler.v \
	$R/acex/sp_ay.v $R/acex/sp_kbd.v $R/acex/sp_mouse.v $R/acex/sp_max.v $R/cpu/sp_z84c15.v $R/cpu/sp_sio_ch.v \
	$R/cpu/sp_ctc_ch.v $R/cpu/sp_pio_port.v $R/mem/sp_sram.v $R/mem/sp_sdram.v $R/board/sp_ld_bridge.v \
	$R/board/sp_kbd_tx.v $R/board/sp_vout.v $R/board/sp_i2s_rx.v ../eq/mem/oddr2.v ../cpu/build/t80pa.v"
DEF="-DCFG_BITS_T=$BITS -DRUN_US=$US"
case $SIM in
	iverilog)
		iverilog -g2005 -o build/tb_board.vvp -s tb_board $DEF $SRC 2>build/iverilog.log || { cat build/iverilog.log; exit 1; }
		time vvp -n build/tb_board.vvp ;;
	verilator)
		verilator --binary --timing -O3 --x-assign fast --x-initial fast -Wno-fatal -Wno-lint -Wno-style \
			-Wno-MULTIDRIVEN -Wno-TIMESCALEMOD -Wno-SYNCASYNCNET --top-module tb_board $DEF -DLOAD_ALL -DKBD_REAL \
			-Mdir build/vl -o tb_board $SRC >build/verilator.log 2>&1 || { tail -30 build/verilator.log; exit 1; }
		time build/vl/tb_board ;;
	*) echo "unknown simulator $SIM"; exit 1 ;;
esac
