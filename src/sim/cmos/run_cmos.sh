#!/bin/sh
# DS12887 / CMOS (docs/rtc.md): sp_cmos.
# usage: run_cmos.sh [unit|machine]
#   unit (default, ~1 min): tb_cmos.v, sp_cmos + kg_mcu2 (RTC_COALESCE 1, RTC_SEND_LIMIT 128) + a model of the
#     firmware (rtc_mode 0) on the SPI link; the image src/roms/cmos_default.bin as the .eep
#   machine (~1-2 min): tb_cmos_machine.v, sp_machine (BIOS 3.04 ACEX loader, short stream) + sp_cmos: OUT / IN of
#     the CPU through the DCP and the MAX; ARGS=+storage reads through the stage of sp_storage (the board top),
#     ARGS=+trace shows every strobe edge with MD
# Env: KGM = karabas-go-modules (default the submodule ../../../modules; RTC_COALESCE needs modules with it),
#      ROM = the BIOS image (machine; default ~/Downloads/karabas-sd-sprinter/roms/mame-named/sp2k-3.04.rom)
set -eu
cd "$(dirname "$0")"
WHAT=${1:-unit}
KGM=${KGM:-../../../modules}
R=../../rtl
mkdir -p build
case $WHAT in
	unit)
		python3 -I ../../roms/mk_cmos.py build >/dev/null
		python3 -I -c 'import sys; d = open(sys.argv[1], "rb").read(); open(sys.argv[2], "w").write("".join("%02x\n" % b for b in d))' build/cmos_default.bin build/cmos_default.hex
		M="$KGM/rtl/mcu"
		K="$M/kg_mcu2.v $M/kg_l2_link.v $M/kg_l2_sys.v $M/kg_l2_hid.v $M/kg_l2_load.v $M/kg_l2_osd.v $M/kg_l2_img.v \
			$M/kg_l2_port.v $M/kg_l2_rtc.v $M/kg_l2_aux.v $KGM/rtl/mem/kg_sdpram.v $KGM/rtl/mem/kg_dist_sdpram.v"
		iverilog -g2005 -Wno-timescale -o build/tb_cmos.vvp -s tb_cmos tb_cmos.v $R/board/sp_cmos.v $K 2>build/iverilog.log \
			|| { cat build/iverilog.log; exit 1; }
		time vvp -n build/tb_cmos.vvp ;;
	machine)
		ROM=${ROM:-$HOME/Downloads/karabas-sd-sprinter/roms/mame-named/sp2k-3.04.rom}
		[ -s "$ROM" ] || { echo "no ROM image $ROM"; exit 1; }
		python3 -I -c 'import sys; d = open(sys.argv[1], "rb").read(); open(sys.argv[2], "w").write("".join("%02x\n" % b for b in d))' "$ROM" build/rom.hex
		../cpu/t80_v.sh ../cpu/build
		SRC="tb_cmos_machine.v $R/board/sp_cmos.v $R/top/sp_machine.v $R/acex/sp_acex.v $R/acex/sp_dcp.v $R/acex/sp_video2.v \
			$R/acex/sp_acceler.v $R/acex/sp_ay.v $R/acex/sp_kbd.v $R/acex/sp_mouse.v $R/acex/sp_max.v $R/cpu/sp_z84c15.v \
			$R/cpu/sp_sio_ch.v $R/cpu/sp_ctc_ch.v $R/cpu/sp_pio_port.v $R/mem/sp_sram.v $R/mem/sp_sdram.v ../eq/mem/oddr2.v \
			../cpu/build/t80pa.v"
		iverilog -g2005 -o build/tb_cmos_machine.vvp -s tb_cmos_machine $SRC 2>build/iverilog.log \
			|| { cat build/iverilog.log; exit 1; }
		time vvp -n build/tb_cmos_machine.vvp ${ARGS:-} ;;
	*) echo "unknown test $WHAT"; exit 1 ;;
esac
