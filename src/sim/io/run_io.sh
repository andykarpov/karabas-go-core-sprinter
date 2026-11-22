#!/bin/sh
# tb_io: tape in / out (port #FE through the XA multiplexer and latch) and MIDI (AY register 14 bit 2) through the CPU,
# the ACEX and the MAX (docs/PLAN.md Ф4). usage: run_io.sh [verilator|iverilog]; STOP_MS=<ms> (default 20).
# The BIOS image is local ($ROM, as run_storage.sh): its loader pours the stream. Ends with "tb_io: N errors".
set -eu
cd "$(dirname "$0")"
SIM=${1:-verilator} STOP_MS=${STOP_MS:-20}
ROM=${ROM:-$HOME/Downloads/karabas-sd-sprinter/roms/mame-named/sp2k-3.04.rom}
mkdir -p build
[ -s "$ROM" ] || { echo "no ROM image $ROM"; exit 1; }
SJASM=${SJASM:-$(command -v sjasmplus || echo /opt/sjasmplus/sjasmplus)}
"$SJASM" --nologo --raw=build/io.bin --lst=build/io.lst io.asm > build/io.sjasm.log || { cat build/io.sjasm.log; exit 1; }
hex() { python3 -I -c 'import sys; d = open(sys.argv[1], "rb").read(); open(sys.argv[2], "w").write("".join("%02x\n" % b for b in d))' "$1" "$2"; }
hex "$ROM" build/rom.hex
hex build/io.bin build/io.hex
../cpu/t80_v.sh ../cpu/build
R=../../rtl
SRC="tb_io.v $R/top/sp_machine.v $R/acex/sp_acex.v $R/acex/sp_dcp.v $R/acex/sp_video2.v $R/acex/sp_acceler.v \
	$R/acex/sp_ay.v $R/acex/sp_kbd.v $R/acex/sp_mouse.v $R/acex/sp_max.v $R/cpu/sp_z84c15.v $R/cpu/sp_sio_ch.v \
	$R/cpu/sp_ctc_ch.v $R/cpu/sp_pio_port.v $R/mem/sp_sram.v $R/mem/sp_sdram.v ../eq/mem/oddr2.v ../cpu/build/t80pa.v"
DEF="-DSTOP_MS=$STOP_MS"
case $SIM in
	iverilog)
		iverilog -g2005 -o build/tb_io.vvp -s tb_io $DEF $SRC 2>build/iverilog.log || { cat build/iverilog.log; exit 1; }
		time vvp -n build/tb_io.vvp ;;
	verilator)
		verilator --binary --timing -O3 --x-assign fast --x-initial fast -Wno-fatal -Wno-lint -Wno-style \
			-Wno-MULTIDRIVEN -Wno-TIMESCALEMOD -Wno-SYNCASYNCNET --top-module tb_io $DEF \
			-Mdir build/vl -o tb_io $SRC >build/verilator.log 2>&1 || { tail -30 build/verilator.log; exit 1; }
		time build/vl/tb_io ;;
	*) echo "unknown simulator $SIM"; exit 1 ;;
esac
