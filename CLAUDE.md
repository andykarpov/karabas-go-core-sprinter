# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

A PetersPlus Sprinter Sp2000 core for the Karabas Go, Mini and Mini G boards (Xilinx Spartan-6 XC6SLX25, ISE 14.7, XST). Docs, in Russian: `docs/PLAN.md` (sources, decisions, phases). Follow the phases; record a changed decision in PLAN.md.

User decisions (2026-11-20): translate the original AHDL (ACEX EP1K30 + MAX EPM7064, version "2.18") into Verilog; no AHDL in the core, the AHDL is the reference (compiled by Quartus into a netlist for equivalence sims). Reconfiguration: one bitstream with several personalities (standard + the Thunder in the Deep game config), selected by the hash of the bitstream the BIOS streams into the ACEX, as MAME does. Try every BIOS (2.13 ... 3.06). Public repo.

## Layout

- `modules/`: submodule `karabas-go-modules` (kg_* board modules).
- `upstream/sprinter-hard` (branch `quartus2`: `Quartus2/ACEX`, `Quartus2/MAX`, `MaxPlus2/`), `upstream/sprinter-bios`, `upstream/sprinter-dos`, `upstream/sprinter-apps`: submodules of gitlab.com/sprinter-computer.
- `upstream/mame/` (not in git): `tools/fetch_mame.sh`, MAME `sprinter.cpp` at a pinned commit.

## Rules of the core

The rules of the other karabas-go cores apply: standard video timing with syncs always present, `FT_CLK_OUT` about 8 MHz on Mini / Mini G, Go `FDC_*` outputs 0 when unused, Mini / Mini G drive T3 (`FLASH_CS_N`) = 0, OSD switch index = item position unless `"index"`, an OSD value shows 10 characters at most, FL slots 0..7 only, Verilog-2001 for XST, imported code marked `karabas:`.

- Translation: one Verilog module per AHDL subdesign, same signal names where possible, a comment with the AHDL file / line for non-obvious parts. Everything synchronous on one fast clock with enables: no derived or ripple clocks, no LCELL delays, no internal tristates.
- Sims run in seconds; long runs only after asking the user.
- **Ask the user before every check on the board** (and the HDMI capture). Ask before a firmware flash.
- One branch per phase of `docs/PLAN.md`, one PR at its end.
- Heavy builds: Mini G only while working on one feature, all boards for a release; map with cost table 2 first.

## Memory

The Claude Code memory of this repo is shared with all karabas-go repos: `~/.claude/projects/<this project>/memory` is a symlink to `../karabas-go-notes` (private repo `andykarpov/karabas-go-notes`). Its `MEMORY.md` is split by repo; commit and push it after every memory change.
