#!/usr/bin/env python3
"""The first content of /config/sprinter.eep (core.json eeprom_init, 256 bytes): the DS12887 CMOS as the BIOS
leaves it after "INSTALL DEFAULT VALUES", with a valid checksum, so the first start shows no CHECKSUM ERROR.
docs/rtc.md 8.3.

  cmos_default.bin  BIOS 3.04 (the ROM of core.json): its defaults, checksum #0E..#1F
  cmos_306.bin      BIOS 3.06 (tt-sprinter-bios SETUP/SETTINGS.asm DEFVAL + SETDEF): checksum #0E..#20

The two BIOS differ (values of #0E #10 #1B #1D and the checksum length), one image cannot be the defaults of both.
--both: the 3.04 values with #20 = #03, which makes the 3.04 and the 3.06 checksums equal (#09). 3.06 reads #20
through the SecIDE masks (bits 4-7, AUTOIDE.asm), but SETTINGS.asm has HD1STP / HD2STP ... in the low bits: not
shown harmless for 3.06, not tested there (no image).

The 3.04 values: MAME 0.264 (sprinter, BIOS v3.04.253) after its first start with an empty CMOS; MAME accepts an
image with other values and the recomputed 18-byte sum and rewrites the defaults for a wrong sum (2026-11-21).

usage: mk_cmos.py [--both] [out_dir]   (default: the directory of this script)
"""
import os
import sys


def checksum(cmos, count):
    """CHEKSUM of SETUP: H = #DE, for each byte L from #0E: H = rlc(H - L) - L."""
    h = 0xDE
    for i in range(0x0E, 0x0E + count):
        a = (h - cmos[i]) & 0xFF
        a = ((a << 1) | (a >> 7)) & 0xFF
        h = (a - cmos[i]) & 0xFF
    return h


def image(defaults, count, extra=()):
    cmos = bytearray(256)
    # 00-09: a valid BCD time (the firmware sends its own clock over it); 24 h, BCD
    cmos[0x00:0x0A] = bytes([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x05, 0x01, 0x01, 0x26])
    cmos[0x0A] = 0x26          # 32 768 Hz, 1024 Hz SQW rate (CMOS.EXE, BIOS 3.06 CMOSINIT)
    cmos[0x0B] = 0x02          # 24 h, BCD, no interrupts
    cmos[0x0D] = 0x80          # VRT (read-only; the core answers #80 anyway)
    cmos[0x0E:0x0E + len(defaults)] = bytes(defaults)
    for a, v in extra:
        cmos[a] = v
    cmos[0x32] = 0x20          # century, BCD
    cmos[0x3F] = checksum(cmos, count)
    return cmos


# 3.04: #0E MEM / options = SAFERAM + EXTBIOS + SDELAY1 (#68), #0F keyboard TDL250 + TRATE30, #10 SDIDE1 + ASDFDD2,
# #11 FDD 720 / 720, IDE auto, #12-#1A 0, #1B TURBON + SPRIN (#07), #1C BAS128, #1D REBOOTM, #1E 0, #1F screen #77
V304 = [0x68, 0x07, 0x12, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x07, 0x00, 0x02, 0x00, 0x77]
# 3.06: #0E SAVERAM + SETBOOTSOUND + SDELAY1 (#4A), #10 SDIDE1 + ASDFDD1, #1B 0 (SETDEF clears it after DEFVAL),
# #1C Basic128, #1D REBOOTM + 4 (load ZX ROMs by the ZX flag), #20 secondary IDE auto
V306 = [0x4A, 0x07, 0x02, 0x00, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x00, 0x00, 0x06, 0x00, 0x77, 0x00]


def main():
    args = sys.argv[1:]
    both = "--both" in args
    args = [a for a in args if a != "--both"]
    out = args[0] if args else os.path.dirname(os.path.abspath(__file__))
    c304 = image(V304, 18, [(0x20, 0x03)] if both else ())
    c306 = image(V306, 19)
    assert c304[0x3F] == 0x09 and checksum(c306, 19) == c306[0x3F]
    if both:
        assert checksum(c304, 19) == c304[0x3F]
    with open(os.path.join(out, "cmos_both.bin" if both else "cmos_default.bin"), "wb") as f:
        f.write(c304)
    if not both:
        with open(os.path.join(out, "cmos_306.bin"), "wb") as f:
            f.write(c306)
    print("3.04%s: checksum %02X (19-byte sum %02X); 3.06: checksum %02X" %
          (" (#20 = 03)" if both else "", c304[0x3F], checksum(c304, 19), c306[0x3F]))


if __name__ == "__main__":
    main()
