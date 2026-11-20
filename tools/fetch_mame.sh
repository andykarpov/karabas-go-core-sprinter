#!/bin/sh
# Fetch the MAME Sprinter driver (behavioural reference, BSD-3-Clause) into upstream/mame/ (not in git).
set -eu
cd "$(dirname "$0")/.."
C=4873b416e7ed574e1823110b8b4ee6a6f8e0afc5
B=https://raw.githubusercontent.com/mamedev/mame/$C
mkdir -p upstream/mame
for f in src/mame/sinclair/sprinter.cpp src/mame/layout/sprinter.lay \
         src/devices/cpu/z80/z84c015.cpp src/devices/cpu/z80/z84c015.h; do
	o=upstream/mame/$(basename "$f")
	[ -s "$o" ] || curl -sfL -o "$o" "$B/$f"
done
echo "mame $C ok"
