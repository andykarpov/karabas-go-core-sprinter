# Sprinter Sp2000 core for Karabas Go / Mini / Mini G

[Русская версия](README.ru.md)

The PetersPlus Sprinter Sp2000 (Z84C15 at 21 MHz, Altera ACEX + MAX, 4 MB RAM, 256 KB video RAM, Estex DSS) for the Karabas Go board family (Xilinx Spartan-6 XC6SLX25). The AHDL of the Sprinter PLDs (ACEX, MAX) is translated into Verilog and checked against the netlists of the original sources in simulation (`docs/translation.md`, `docs/versions.md`, Russian).

| Board | Core file | Video | Sound |
|---|---|---|---|
| Karabas Go | `sprinter.kg` | VGA | I2S DAC |
| Karabas Mini | `sprinter.kg` | HDMI | HDMI, analog output (sigma-delta) |
| Karabas Mini G | `sprinter.kg` | HDMI | HDMI, I2S DAC (PCM5102) |

The core file is in `src/`. The BIOS is in it: **Sprinter BIOS 3.06 Hotfix 2**, the only supported BIOS version.

Status: build 26112201. Checked on a Mini G board: BIOS 3.06 HF2 and SETUP, the CMOS clock, DSS 1.70 and Flex Navigator 1.15 from a hard disk image, DSS from a floppy image, the keyboard and the mouse, Thunder in the Deep (its own ACEX configuration, with scrolling and sound). The Go and Mini builds have not been run on a board.

## Features

- **ACEX configurations** ("personalities", chosen by the hash of the configuration stream the software loads, as in MAME): 3.03a (the base), **k30** (BIOS 3.05 / 3.06) and **SCROLL** (Thunder in the Deep, `GAME_00`, `LDCONF gc.bin`). An unknown stream runs as 3.03a.
- **Machine:** Z84C15 (T80 with CTC, SIO, PIO), the ACEX with its accelerator, 4 MB of RAM (SDRAM), the video RAM, ROM and fastram in the SRAM, the MAX (syncs, reset, configuration loading).
- **Video:** the video modes of the ACEX and the palette, line-doubled to 720 x 576 at 50 Hz.
- **Sound:** AY and CBL / Covox of the ACEX.
- **Disks:** IDE primary channel, master and slave, on hard disk images (`.img`, `.hdf`, `.vhd`) on the SD card; WD1793 with drives A and B on floppy images (`.img` / `.ima` 720 KB and 1.44 MB, `.trd`).
- **Clock:** the CMOS / RTC of the BIOS on the RTC of the board, kept in `/config/sprinter.eep`.
- **Controllers:** the USB keyboard (AT scan codes), the USB mouse (serial mouse on the SIO).

Not done: the secondary IDE channel, tape, ISA, the physical floppy drive of the Go, BIOS versions other than 3.06.

## Getting started

1. Copy `sprinter.kg` (one file for Go, Mini and Mini G) to the root of the SD card of the firmware.
2. Make a folder `/sprinter` on the SD card and put a hard disk image with DSS there. A bootable image is made from a DSS tree with `tools/mkhdd.py` (clusters of 64 sectors, 132 MB or more: the DSS 1.70 loader hangs on smaller clusters, `docs/storage.md`).
3. Choose Sprinter Sp2000 in the core menu, mount the image as **HDD Master** in the OSD, then press **Menu+F12**.
4. The BIOS boots DSS from the hard disk. On the first start the BIOS may report a CMOS checksum error once and write its defaults.

"Menu" is the Windows key of the keyboard. Hold **Del** at the start for SETUP, **Alt** for the alternative boot disk. **Ctrl+Alt+Del** resets the machine, **Menu+F12** reloads the configuration (the RESET button of the original).

## OSD menu

| Item | Values | Hotkey |
|---|---|---|
| Reset | | Menu+F12 |
| Disk A, Disk B | floppy images `.img .ima .trd` | Menu+F5, Menu+F6 |
| HDD Master, HDD Slave | hard disk images `.img .hdf .vhd` | |
| VGA Sync (Go) | -H -V / +H -V / -H +V / +H +V | |

## Build

`cd src && make minig` (or `go`, `mini`), ISE 14.7; the BIOS image is `src/roms/sp2k-3.06-hf2.rom`. Simulation: `src/sim/eq/run_eq.sh` (equivalence with the Quartus netlists of the original AHDL), `src/sim/machine/run_machine.sh`.

## Sources

- `upstream/sprinter-*`: the Sprinter hardware, BIOS, DOS and application sources of [gitlab.com/sprinter-computer](https://gitlab.com/sprinter-computer) (submodules).
- `upstream/tt-*`: the AHDL of the ACEX configurations and the BIOS sources of Tolik-Trek (submodules, see below).
- `tools/fetch_mame.sh`: the MAME Sprinter driver (BSD-3-Clause), a behavioural reference, fetched into `upstream/mame/`.

## Credits and licence

The Verilog of the ACEX / MAX logic is translated from the AHDL of Ivan Mak / Peters Plus (configuration 2.18, [gitlab.com/sprinter-computer/hard](https://gitlab.com/sprinter-computer/hard)) and the reconstructed AHDL of Anatoliy Belyanskiy (Tolik-Trek): configurations 2.06-3.03a ([github.com/Tolik-Trek/SP2000-ACEX](https://github.com/Tolik-Trek/SP2000-ACEX)), the k30 configuration of BIOS 3.05+ ([zxgit.org/Tolik-Trek/Sprinter-BIOS](https://zxgit.org/Tolik-Trek/Sprinter-BIOS)) and the SCROLL configuration of Thunder in the Deep ([github.com/Tolik-Trek/Scroll_CNF](https://github.com/Tolik-Trek/Scroll_CNF)). BIOS 3.06 Hotfix 2: the Sprinter Team (the image from [unreal-ng](https://github.com/alfishe/unreal-ng)). The WD1793 is from MiSTer, the IDE is `hdf_ata` of karabas-go-modules.

Our files: GPL-3 (`LICENSE`). The Sprinter firmware, ROMs and software belong to their authors.
