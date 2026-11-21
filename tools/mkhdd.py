#!/usr/bin/env python3
"""Build a bootable Sprinter (DSS) hard disk image from a directory tree (HDD Master / Slave of the core).

What BIOS 3.04 and the DSS boot loader need (docs/storage.md, section 4a):
- absolute sectors 1..3 (LBA 1..3, after the MBR): the DSS loader (#600 bytes, starts with "Starting...\\0").
  The BIOS reads LBA 1, compares "Starting...\\0" and jumps into it; without it: "Start from Hard disk...fail".
  The loader is the tail of DSS BOOT.EXE (= what "BOOT C:" writes) or sectors 1..3 of a DSS boot floppy / disk;
- MBR partition entry 0 (the loader looks at entry 0 only), type 01 / 04 / 06 / 0E, its LBA start and size;
- FAT16 (or FAT12) with 512-byte sectors, media F8, "FAT16" at #36 of the boot sector;
- SYSTEM.DOS in the root (the loader reads it), SYSTEM.EXE in the root (the shell DSS starts).

Geometry: 16 heads, 63 sectors (hdf_ata without RDB); the size is rounded down to whole cylinders (1008 sectors).

usage: mkhdd.py [--size-mb N] [--loader FILE] OUT.img TREE
  --loader: BOOT.EXE of DSS, or a DSS boot floppy / disk image (sectors 1..3); default TREE/BIN/BOOT.EXE.
Needs mkfs.fat and mtools (mcopy, mmd).
"""
import argparse
import os
import subprocess
import sys
import tempfile

SEC = 512
HEADS, SPT = 16, 63
CYL = HEADS * SPT
PART_LBA = SPT                      # partition from track 1 (head 1 sector 1)
SYSID = b"Starting...\x00"
LOADER_LEN = 0x600
FIRST = ["SYSTEM.DOS", "SYSTEM.EXE", "SYSTEM.BAT"]


def find_ci(d, name):
    for n in os.listdir(d):
        if n.upper() == name.upper():
            return os.path.join(d, n)
    return None


def get_loader(path):
    data = open(path, "rb").read()
    if data[SEC:SEC + len(SYSID)] == SYSID and len(data) >= SEC + LOADER_LEN:   # disk image: sectors 1..3
        return data[SEC:SEC + LOADER_LEN]
    i = data.rfind(SYSID)                                                     # BOOT.EXE: the loader is its tail
    if i >= 0 and len(data) - i == LOADER_LEN:
        return data[i:]
    sys.exit("no DSS loader (\"Starting...\" + #600 bytes) in " + path)


def chs(lba):
    c, r = divmod(lba, CYL)
    h, s = divmod(r, SPT)
    if c > 1023:
        return bytes([0xFE, 0xFF, 0xFF])
    return bytes([h, ((c >> 2) & 0xC0) | (s + 1), c & 0xFF])


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--size-mb", type=int, default=64)
    ap.add_argument("--loader")
    ap.add_argument("out")
    ap.add_argument("tree")
    a = ap.parse_args()

    tree = a.tree
    for n in FIRST[:2]:
        if not find_ci(tree, n):
            sys.exit(n + " missing in " + tree)
    lpath = a.loader
    if not lpath:
        b = find_ci(tree, "BIN")
        lpath = b and find_ci(b, "BOOT.EXE")
        if not lpath:
            sys.exit("no BIN/BOOT.EXE in the tree: give --loader")
    loader = get_loader(lpath)

    total = (a.size_mb * 1024 * 1024 // SEC) // CYL * CYL
    psize = total - PART_LBA
    if psize < 16 * 1024 * 1024 // SEC:
        sys.exit("too small for FAT16")
    # FAT16: 4085..65524 clusters; the smallest cluster that fits (2 KB minimum)
    spc = 4
    while psize // spc > 65000:
        spc *= 2
    if spc > 128:
        sys.exit("too big for FAT16 with 64 KB clusters")

    with tempfile.TemporaryDirectory() as tmp:
        part = os.path.join(tmp, "part.img")
        subprocess.run(["mkfs.fat", "-F", "16", "-s", str(spc), "-S", str(SEC), "-h", str(PART_LBA),
                        "-g", "%d/%d" % (HEADS, SPT), "-M", "0xF8", "-n", "DSS", "-C", part,
                        str(psize * SEC // 1024)], check=True, stdout=subprocess.DEVNULL)
        env = dict(os.environ, MTOOLS_SKIP_CHECK="1", MTOOLS_NO_VFAT="1")   # 8.3 names only, as DSS writes them
        names = sorted(os.listdir(tree), key=lambda n: (n.upper() not in FIRST,
                                                         FIRST.index(n.upper()) if n.upper() in FIRST else 0,
                                                         n.upper()))
        for n in names:     # SYSTEM.* first: the root entries and the first clusters
            subprocess.run(["mcopy", "-i", part, "-s", "-p", "-m", "-Q", os.path.join(tree, n), "::/"],
                           check=True, env=env)
        p = open(part, "rb").read()
    p += bytes(psize * SEC - len(p))        # mkfs.fat counts 1 KB blocks: an odd last sector stays outside FAT

    mbr = bytearray(SEC)
    e = bytes([0x00]) + chs(PART_LBA) + bytes([0x06]) + chs(total - 1) + \
        PART_LBA.to_bytes(4, "little") + psize.to_bytes(4, "little")
    mbr[0x1BE:0x1CE] = e
    mbr[0x1B8:0x1BC] = os.urandom(4)        # disk signature
    mbr[510:512] = b"\x55\xAA"
    gap = bytearray((PART_LBA - 1) * SEC)
    gap[0:LOADER_LEN] = loader
    with open(a.out, "wb") as f:
        f.write(mbr)
        f.write(gap)
        f.write(p)
    assert os.path.getsize(a.out) == total * SEC
    print("%s: %d sectors (%d cylinders x %d x %d), FAT16 at LBA %d, %d sectors / cluster, loader from %s"
          % (a.out, total, total // CYL, HEADS, SPT, PART_LBA, spc, lpath))


if __name__ == "__main__":
    main()
