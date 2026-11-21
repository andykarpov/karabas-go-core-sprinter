# Sprinter Sp2000 core for Karabas Go / Mini / Mini G, ISE 14.7 (docs/minig.md).
#
#   make                  = make minig (Ф1: Mini G only; the Go / Mini tops come in Ф3)
#   make minig            synthesis, implementation, bitstream, sprinter.kg
#   make minig-xst        one step: <board>-xst (.ngc), <board>-impl (.bin), <board>-core (.kg)
#   make minig-report     LUTs, slices, block RAMs and the timing result of the last build
#   make clean            the intermediate files
#
# Inputs per board: karabas_<board>.prj (the source list, the shared modules as "../modules/rtl/..."), .xst,
# .ucf, .ut. A step runs again when one of its inputs is newer than its output.
#
# The BIOS ROM is not in git (docs/roms.md): the .kg takes roms/kg/sp2k-3.04.rom, copied from $(ROM) at pack time
# (default: the local image of the MAME set, docs/roms.md 1.1).

ISE_SETTINGS ?= /opt/Xilinx/14.7/ISE_DS/settings64.sh
SHELL = /bin/bash
.SHELLFLAGS = -e -o pipefail -c
XIL = source $(ISE_SETTINGS) > /dev/null;

PART = xc6slx25-ftg256-2
BOARDS = minig
KG = sprinter.kg
JSON = core.json
ROM ?= $(HOME)/Downloads/karabas-sd-sprinter/roms/mame-named/sp2k-3.04.rom
ROM_KG = roms/kg/sp2k-3.04.rom
# map / par as core-p4096; cost table 2 first (karabas-go-notes map-cost-table-2-first); -mt 2: the PC is shared
MAP_T_minig = 2
MAP_OPT = -logic_opt off -ol high -xe n -xt 0 -register_duplication off -r 4 -global_opt off -mt 2 -detail -ir off -pr b -lc off -power off
PAR_OPT = -ol high -xe n -mt 2
INCLUDES = $(wildcard ../modules/rtl/mcu/*.vh) $(wildcard rtl/acex/mif/*.hex)

.PHONY: all clean $(BOARDS) $(BOARDS:=-xst) $(BOARDS:=-impl) $(BOARDS:=-core) $(BOARDS:=-report)

all: minig

$(ROM_KG):
	@[ -s "$(ROM)" ] || { echo "no BIOS image $(ROM) (docs/roms.md 1.1; set ROM=...)"; exit 1; }
	mkdir -p roms/kg
	cp "$(ROM)" $@

define board
SRC_$(1) := $$(shell sed -n 's/^[a-z]* work "\(.*\)"/\1/p' karabas_$(1).prj)

karabas_$(1).ngc: karabas_$(1).prj karabas_$(1).xst $$(SRC_$(1)) $(INCLUDES)
	mkdir -p xst/projnav.tmp
	$(XIL) xst -intstyle ise -ifn karabas_$(1).xst -ofn karabas_$(1).syr

karabas_$(1).bin: karabas_$(1).ngc karabas_$(1).ucf karabas_$(1).ut
	$(XIL) ngdbuild -intstyle ise -dd _ngo -nt timestamp -uc karabas_$(1).ucf -p $(PART) karabas_$(1).ngc karabas_$(1).ngd
	$(XIL) map -intstyle ise -p $(PART) -w $(MAP_OPT) -t $(MAP_T_$(1)) -o karabas_$(1)_map.ncd karabas_$(1).ngd karabas_$(1).pcf
	$(XIL) par -w -intstyle ise $(PAR_OPT) karabas_$(1)_map.ncd karabas_$(1).ncd karabas_$(1).pcf
	$(XIL) trce -intstyle ise -v 3 -s 2 -n 3 -fastpaths -xml karabas_$(1).twx karabas_$(1).ncd -o karabas_$(1).twr karabas_$(1).pcf -ucf karabas_$(1).ucf
	$(XIL) bitgen -intstyle ise -f karabas_$(1).ut karabas_$(1).ncd

kg_$(1).stamp: karabas_$(1).bin $(JSON) $(ROM_KG)
	python3 make_core.py $(JSON) $(KG) --boards $(1)
	touch $$@

$(1): kg_$(1).stamp
$(1)-xst: karabas_$(1).ngc
$(1)-impl: karabas_$(1).bin
$(1)-core: kg_$(1).stamp
$(1)-report:
	@grep -E "Number of (Slice LUTs|Slice Registers|occupied Slices|RAMB16BWERs|RAMB8BWERs):" karabas_$(1)_map.mrp
	@grep -E "constraints? (was|were) met|constraints? not met|Timing Score" karabas_$(1).par | sort -u
endef
$(foreach b,$(BOARDS),$(eval $(call board,$(b))))

clean:
	rm -f kg_*.stamp
	rm -rf xst _ngo _xmsgs xlnx_auto_0_xdb iseconfig
	rm -f $(foreach b,$(BOARDS),$(addprefix karabas_$(b),.ngc .ngd .ngr .syr .lso .bld .pcf .ncd _map.ncd _map.ngm \
		_map.map _map.mrp _map.xrpt .par .pad _pad.csv _pad.txt .twr .twx .unroutes .xpi .ptwx .bgn .bit .drc \
		_bitgen.xwbt _summary.xml _usage.xml _xst.xrpt _ngdbuild.xrpt _par.xrpt _guide.ncd))
