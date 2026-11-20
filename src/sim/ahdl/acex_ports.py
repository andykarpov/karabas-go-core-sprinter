#!/usr/bin/env python3
"""Write the instance port list of an ACEX reference netlist for tb_acex_smoke.v: the netlists differ in the case
of the port names (2.18 / k30 lower case, 3.03a upper case) and 2.18 / k30 have XA[3:0] inout, 3.03a XA[2:0] + XA3.
usage: acex_ports.py NETLIST.vo OUT.vh"""
import re
import sys

TB = {"TG42": "tg42", "CLKZ1": "clkz1", "/WAIT": "wait_n", "/RESET": "res_n", "/M1": "1'b1", "/RF": "1'b1",
      "/IO": "1'b1", "/WR": "1'b1", "/RD": "1'b1", "/MR": "1'b1", "/HALT": "1'b1", "A": "16'hffff", "D": "d",
      "CS_ROM": "cs_rom", "CS_CASH": "cs_cash", "RA": "ra", "V_CS": "v_cs", "VA": "va", "V_WR": "v_wr",
      "VD3": "vd3", "VD2": "vd2", "VD1": "vd1", "VD0": "vd0", "WR_COL": "wr_col", "DAC_DATA": "dac_data",
      "DAC_WS": "dac_ws", "DAC_BCK": "dac_bck", "MD": "md", "MA": "ma", "RAS_": "ras_n", "CAS_": "cas_n",
      "/WE": "we_n", "XACS": "xacs", "XA": "xa", "XA3": "1'b1", "SXA": "sxa", "RDXA": "rdxa", "WR_AWG": "wr_awg",
      "RD_KMPS": "rd_kmps", "WR_DWG": "wr_dwg"}
src = open(sys.argv[1]).read()
head = src[:src.index(");")]
names = re.findall(r"^\s*(?:input|output|inout)\s+(?:\[[^\]]*\]\s*)?(\\\S+|\w+)", src, re.M)
ports = []
for n in names:
    key = n.lstrip("\\").upper()
    if key not in TB:
        sys.exit("unknown port " + n)
    if key == "XA" and re.search(r"inout\s+\[3:0\]\s+XA\b", src, re.I):
        net = "xa4"
    else:
        net = TB[key]
    ports.append(".%s(%s)" % (n + " " if n.startswith("\\") else n, net))
open(sys.argv[2], "w").write(",\n\t\t".join(ports) + "\n")
