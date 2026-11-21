#!/bin/sh
# tb_storage: IDE (hdf_ata) and the WD1793 (sp_fdd / wd1793) on images, through the CPU, the ACEX and the MAX
# (docs/storage.md 7). usage: run_storage.sh [verilator|iverilog]; ARGS="+trd" (drive B = TRD), "+timing" (strobe
# timing), "+bios +cmos +pc +img0=<file> +img4=<file>" (the BIOS itself, a CMOS model, real images); STOP_MS=<ms>
# (default 120). The BIOS image is local ($ROM, as run_machine.sh): its loader pours the stream.
set -eu
cd "$(dirname "$0")"
SIM=${1:-verilator} ARGS=${ARGS:-} STOP_MS=${STOP_MS:-120}
ROM=${ROM:-$HOME/Downloads/karabas-sd-sprinter/roms/mame-named/sp2k-3.04.rom}
mkdir -p build
[ -s "$ROM" ] || { echo "no ROM image $ROM"; exit 1; }
SJASM=${SJASM:-$(command -v sjasmplus || echo /opt/sjasmplus/sjasmplus)}
"$SJASM" --nologo --raw=build/storage.bin --lst=build/storage.lst storage.asm > build/storage.sjasm.log \
	|| { cat build/storage.sjasm.log; exit 1; }
hex() { python3 -I -c 'import sys; d = open(sys.argv[1], "rb").read(); open(sys.argv[2], "w").write("".join("%02x\n" % b for b in d))' "$1" "$2"; }
hex "$ROM" build/rom.hex
hex build/storage.bin build/storage.hex
hex ../../roms/cmos_default.bin build/cmos.hex
../cpu/t80_v.sh ../cpu/build
R=../../rtl
SRC="tb_storage.v $R/top/sp_machine.v $R/acex/sp_acex.v $R/acex/sp_dcp.v $R/acex/sp_video2.v $R/acex/sp_acceler.v \
	$R/acex/sp_ay.v $R/acex/sp_kbd.v $R/acex/sp_mouse.v $R/acex/sp_max.v $R/cpu/sp_z84c15.v $R/cpu/sp_sio_ch.v \
	$R/cpu/sp_ctc_ch.v $R/cpu/sp_pio_port.v $R/mem/sp_sram.v $R/mem/sp_sdram.v ../eq/mem/oddr2.v ../cpu/build/t80pa.v \
	$R/board/sp_storage.v $R/fdd/sp_fdd.v $R/fdd/wd1793.v ../../../modules/rtl/mcu/hdf_ata.v"
DEF="-DSTOP_MS=$STOP_MS"
case $SIM in
	iverilog)
		iverilog -g2005 -o build/tb_storage.vvp -s tb_storage $DEF $SRC 2>build/iverilog.log \
			|| { cat build/iverilog.log; exit 1; }
		time vvp -n build/tb_storage.vvp $ARGS ;;
	verilator)
		verilator --binary --timing -O3 --x-assign fast --x-initial fast -Wno-fatal -Wno-lint -Wno-style \
			-Wno-MULTIDRIVEN -Wno-TIMESCALEMOD -Wno-SYNCASYNCNET --top-module tb_storage $DEF \
			-Mdir build/vl -o tb_storage $SRC >build/verilator.log 2>&1 || { tail -30 build/verilator.log; exit 1; }
		time build/vl/tb_storage $ARGS ;;
	*) echo "unknown simulator $SIM"; exit 1 ;;
esac
