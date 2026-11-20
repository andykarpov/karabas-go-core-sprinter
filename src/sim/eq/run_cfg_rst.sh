#!/bin/sh
# Configuration reset of sp_acex (CFG_RST), ours against ours: tb_cfg_rst (three scenarios of cpu_acex.asm in
# parallel, then the two mutations that must fail). About 1-2 minutes. Debug: vvp -n build/tb_cfg_rst.vvp +scen=N [+stop]
set -eu
cd "$(dirname "$0")"
mkdir -p build
A=../../rtl/acex C=../../rtl/cpu
python3 -I cfg_regs.py $A build/cfg_regs.vh fresh dut
SJASM=${SJASM:-$(command -v sjasmplus || echo /opt/sjasmplus/sjasmplus)}
"$SJASM" --nologo --raw=build/cfg_rst_prog.bin cpu_acex.asm > build/cfg_rst_prog.sjasm.log || { cat build/cfg_rst_prog.sjasm.log; exit 1; }
python3 -I -c 'import sys; d = open(sys.argv[1], "rb").read(); open(sys.argv[2], "w").write("".join("%02x\n" % b for b in d))' \
	build/cfg_rst_prog.bin build/cfg_rst_prog.hex
../cpu/t80_v.sh ../cpu/build
iverilog -g2005 -o build/tb_cfg_rst.vvp -s tb_cfg_rst tb_cfg_rst.v $A/sp_acex.v $A/sp_dcp.v $A/sp_video2.v \
	$A/sp_acceler.v $A/sp_ay.v $A/sp_kbd.v $A/sp_mouse.v $C/sp_z84c15.v $C/sp_sio_ch.v $C/sp_ctc_ch.v $C/sp_pio_port.v \
	../cpu/build/t80pa.v 2>build/tb_cfg_rst.log || { grep -v 'coerced\|sorry: procedural continuous' build/tb_cfg_rst.log; exit 1; }
for s in 0 1 2; do vvp -n build/tb_cfg_rst.vvp +scen=$s > build/tb_cfg_rst_$s.txt 2>&1 & done
for m in 1 2; do vvp -n build/tb_cfg_rst.vvp +scen=0 +mut=$m +stop > build/tb_cfg_rst_mut$m.txt 2>&1 & done; wait
for s in 0 1 2; do echo "scenario $s:"; grep -v '\$finish' build/tb_cfg_rst_$s.txt; done
for m in 1 2; do
	if grep -q 'tb_cfg_rst: 0 errors' build/tb_cfg_rst_mut$m.txt; then echo "mutation $m: NOT DETECTED"; exit 1; fi
	echo "mutation $m: detected ($(grep -m1 'reg \|RAM ' build/tb_cfg_rst_mut$m.txt | sed 's/^ *//'))"
done
