#!/bin/sh
# Unit test of sp_z84c15: tb_z84c15 runs z84c15_test.asm (sjasmplus) on T80pa (a ghdl --synth netlist, t80_v.sh).
# usage: run_cpu.sh        (a few seconds)
set -eu
cd "$(dirname "$0")"
mkdir -p build
SJASM=${SJASM:-$(command -v sjasmplus || echo /opt/sjasmplus/sjasmplus)}
"$SJASM" --nologo --raw=build/z84c15_test.bin z84c15_test.asm > build/sjasm.log || { cat build/sjasm.log; exit 1; }
python3 -I -c 'import sys; d = open(sys.argv[1], "rb").read(); open(sys.argv[2], "w").write("".join("%02x\n" % b for b in d))' \
	build/z84c15_test.bin build/z84c15_test.hex
./t80_v.sh build
R=../../rtl/cpu
iverilog -g2012 -o build/tb_z84c15.vvp -s tb_z84c15 tb_z84c15.v $R/sp_z84c15.v $R/sp_sio_ch.v $R/sp_ctc_ch.v \
	$R/sp_pio_port.v build/t80pa.v 2> build/tb_z84c15.log || { cat build/tb_z84c15.log; exit 1; }
vvp -n build/tb_z84c15.vvp | grep -v '\$finish'
