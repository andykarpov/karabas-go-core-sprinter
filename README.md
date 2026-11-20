# Sprinter core for Karabas Go / Mini / Mini G

A core of the PetersPlus Sprinter Sp2000 (Z84C15 at 21 MHz, Altera ACEX + MAX, 4 MB RAM, 256 KB video RAM, Estex DSS) for the Karabas Go board family (Xilinx Spartan-6 XC6SLX25). The original AHDL of the Sprinter PLDs is translated into Verilog.

Status: work in progress, nothing to run yet. The plan is in `docs/PLAN.md` (Russian).

## Sources

- `upstream/sprinter-*`: the Sprinter hardware, BIOS, DOS and application sources of [gitlab.com/sprinter-computer](https://gitlab.com/sprinter-computer) (submodules).
- `tools/fetch_mame.sh`: the MAME Sprinter driver (BSD-3-Clause), a behavioural reference, fetched into `upstream/mame/`.

## Credits and licence

The Verilog of the ACEX / MAX logic is translated from the AHDL of Ivan Mak / Peters Plus (configuration 2.18, [gitlab.com/sprinter-computer/hard](https://gitlab.com/sprinter-computer/hard)) and the reconstructed AHDL of Anatoliy Belyanskiy (Tolik-Trek): configurations 2.06-3.03a ([github.com/Tolik-Trek/SP2000-ACEX](https://github.com/Tolik-Trek/SP2000-ACEX)), the k30 configuration of BIOS 3.05+ ([zxgit.org/Tolik-Trek/Sprinter-BIOS](https://zxgit.org/Tolik-Trek/Sprinter-BIOS)) and the SCROLL configuration of Thunder in the Deep ([github.com/Tolik-Trek/Scroll_CNF](https://github.com/Tolik-Trek/Scroll_CNF)).

Our files: GPL-3 (`LICENSE`). The Sprinter firmware, ROMs and software belong to their authors.
