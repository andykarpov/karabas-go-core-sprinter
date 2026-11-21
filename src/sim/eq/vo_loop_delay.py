#!/usr/bin/env python3
"""Copy a reference netlist (.vo) with a 1 ps delay on the outputs of the LCELLs of combinational loops (RS latches
made of EXP / LCELL in the AHDL). In a zero-delay simulation such a loop can toggle forever in one time step (iverilog
hangs); with a delay it settles as the real cells do. Logic is unchanged.
usage: vo_loop_delay.py IN.vo OUT.vo NAME_REGEX   (cells whose instance name matches the regex)"""
import re
import sys

src, dst, pat = sys.argv[1], sys.argv[2], re.compile(sys.argv[3])
text = open(src).read()
n = 0


def fix(m):
    global n
    inst, body = m.group(1), m.group(2)
    if not pat.search(inst):
        return m.group(0)
    out = re.search(r"\.combout\((\\\S+|\w+)\s*\)", body)
    if not out:
        return m.group(0)
    net = out.group(1)
    tmp = "\\dly_%d " % n
    n += 1
    body = body.replace(out.group(0), ".combout(%s)" % tmp)
    return "wire %s;\nassign #1 %s = %s;\ncycloneive_lcell_comb %s (%s);" % (tmp, net + (" " if net.startswith("\\") else ""), tmp, inst, body)


text = re.sub(r"cycloneive_lcell_comb\s+(\\\S+|\w+)\s*\((.*?)\);", fix, text, flags=re.S)
open(dst, "w").write(text)
print("vo_loop_delay: %d cells" % n, file=sys.stderr)
