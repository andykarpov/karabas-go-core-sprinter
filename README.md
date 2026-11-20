# Sprinter core for Karabas Go / Mini / Mini G

A core of the PetersPlus Sprinter Sp2000 (Z84C15 at 21 MHz, Altera ACEX + MAX, 4 MB RAM, 256 KB video RAM, Estex DSS) for the Karabas Go board family (Xilinx Spartan-6 XC6SLX25). The original AHDL of the Sprinter PLDs is translated into Verilog.

Status: work in progress, nothing to run yet. The plan is in `docs/PLAN.md` (Russian).

## Sources

- `upstream/sprinter-*`: the Sprinter hardware, BIOS, DOS and application sources of [gitlab.com/sprinter-computer](https://gitlab.com/sprinter-computer) (submodules).
- `tools/fetch_mame.sh`: the MAME Sprinter driver (BSD-3-Clause), a behavioural reference, fetched into `upstream/mame/`.

## Licence

Our files: GPL-3 (`LICENSE`). The Sprinter firmware, ROMs and software belong to their authors.
