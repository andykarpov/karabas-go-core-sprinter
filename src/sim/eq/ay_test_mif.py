#!/usr/bin/env python3
"""Test variant of AY.MIF for tb_eq_ay: the workspace 10..1F (tone / noise / envelope counters, FFFF after power-up,
so the first wrap takes ~800 000 clocks) starts at 0, so tones and envelopes run within the seconds of a sim.
Writes OUT_DIR/AY.MIF (for the reference build, with AY.TDF / AY.INC copied there) and OUT_DIR/ay_t.hex (ours).
usage: ay_test_mif.py AY.MIF OUT_DIR"""
import os
import shutil
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "../../../tools"))
import mif  # noqa: E402

src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
depth, width, mem = mif.parse(open(src, encoding="latin-1").read())
for a in range(0x10, 0x20):
    if mem[a] == 0xFF:
        mem[a] = 0
with open(os.path.join(out, "ay_t.hex"), "w") as f:
    f.writelines("%02x\n" % v for v in mem)
with open(os.path.join(out, "AY.MIF"), "w") as f:
    f.write("DEPTH = %d;\nWIDTH = %d;\nADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\nCONTENT BEGIN\n" % (depth, width))
    f.writelines("%x : %02x;\n" % (i, v) for i, v in enumerate(mem))
    f.write("END;\n")
d = os.path.dirname(os.path.abspath(src))
for n in ("AY.TDF", "AY.INC"):
    shutil.copy(os.path.join(d, n), out)
