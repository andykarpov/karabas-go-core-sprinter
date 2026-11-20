#!/usr/bin/env python3
"""Read an Altera MIF the way MAX+plus II does and write it as a plain MIF (one address per line, for Quartus 13)
or as a $readmemh file (one hex word per line, all DEPTH words).

MAX+plus II accepts "addr : v1 v2 v3 ... ;" (values at addr, addr+1, ...), "[a..b] : v;" ranges and % comments %;
Quartus 13 rejects the list form ("illegal syntax").

usage: mif.py {mif|hex} IN OUT
"""
import re
import sys


def parse(text):
    text = re.sub(r"%[^%]*%", " ", text)          # % comments %
    text = re.sub(r"--[^\n]*", " ", text)         # -- comments
    head, _, body = text.partition("CONTENT")
    hdr = dict((k.upper(), v.strip().upper()) for k, v in re.findall(r"(\w+)\s*=\s*([^;]+);", head))
    depth, width = int(hdr["DEPTH"]), int(hdr["WIDTH"])
    ar = {"HEX": 16, "DEC": 10, "BIN": 2, "OCT": 8, "UNS": 10}[hdr.get("ADDRESS_RADIX", "HEX")[:3]]
    dr = {"HEX": 16, "DEC": 10, "BIN": 2, "OCT": 8, "UNS": 10}[hdr.get("DATA_RADIX", "HEX")[:3]]
    body = body.split("BEGIN", 1)[1].rsplit("END", 1)[0]
    mem = [0] * depth
    for stmt in body.split(";"):
        stmt = stmt.strip()
        if not stmt:
            continue
        addr, _, vals = stmt.partition(":")
        addr, vals = addr.strip(), vals.split()
        m = re.fullmatch(r"\[\s*(\w+)\s*\.\.\s*(\w+)\s*\]", addr)
        if m:
            a, b = int(m.group(1), ar), int(m.group(2), ar)
            for i in range(a, b + 1):
                mem[i] = int(vals[(i - a) % len(vals)], dr)
        else:
            a = int(addr, ar)
            for i, v in enumerate(vals):
                mem[a + i] = int(v, dr)
    mask = (1 << width) - 1
    return depth, width, [v & mask for v in mem]


def main():
    fmt, src, dst = sys.argv[1:4]
    depth, width, mem = parse(open(src, encoding="latin-1").read())
    nd = (width + 3) // 4
    with open(dst, "w") as f:
        if fmt == "hex":
            f.writelines("%0*x\n" % (nd, v) for v in mem)
        else:
            f.write("DEPTH = %d;\nWIDTH = %d;\nADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\nCONTENT BEGIN\n" % (depth, width))
            f.writelines("%x : %0*x;\n" % (i, nd, v) for i, v in enumerate(mem))
            f.write("END;\n")


if __name__ == "__main__":
    main()
