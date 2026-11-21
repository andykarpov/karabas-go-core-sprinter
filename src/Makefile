# Sprinter Sp2000 core for Karabas Go / Mini / Mini G, ISE 14.7 (docs/minig.md).
#
#   make                  = make minig; make go / make mini: the other boards (their tops come from tools/mktop.py)
#   make minig            synthesis, implementation, bitstream, sprinter.kg (BIOS 3.06, the only one supported)
#   make minig-xst        one step: <board>-xst (.ngc), <board>-impl (.bin), <board>-core (.kg)
#   make minig-report     LUTs, slices, block RAMs and the timing result of the last build
#   make minig-pack ROM=<bios.rom> KG=<out.kg> [CMOS=<256-byte image>] [ID=<core id>] [NAME=<menu name>]
#                         test only (unsupported BIOS versions): another .kg from the bitstream already built (no ISE
#                         step): the BIOS image <bios.rom> as
#                         roms/kg/<its name>, the CMOS image as eeprom_init; ID / NAME give it its own entry in the
#                         boot menu and its own /config/<id>.eep (the CMOS of another BIOS differs, docs/rtc.md 8.3).
#                         e.g. BIOS 3.04: make minig-pack ROM=.../sp2k-3.04.rom KG=t304.kg CMOS=roms/cmos_default.bin
#                           ID=t304 NAME="Sprinter 3.04 test"
#   make clean            the intermediate files
#
# Inputs per board: karabas_<board>.prj (the source list, the shared modules as "../modules/rtl/..."), .xst,
# .ucf, .ut. A step runs again when one of its inputs is newer than its output.
#
# The BIOS ROM of the .kg is src/roms/sp2k-3.06-hf2.rom (in git, docs/roms.md).

ISE_SETTINGS ?= /opt/Xilinx/14.7/ISE_DS/settings64.sh
SHELL = /bin/bash
.SHELLFLAGS = -e -o pipefail -c
XIL = source $(ISE_SETTINGS) > /dev/null;

PART = xc6slx25-ftg256-2
BOARDS = go mini minig
KG_DEFAULT = sprinter.kg
KG ?= $(KG_DEFAULT)
CMOS ?=
ID ?=
NAME ?=
JSON = core.json
# the BIOS of the .kg (in git): BIOS 3.06 Hotfix 2 (docs/roms.md); ROM= only for minig-pack
ROM_KG = roms/sp2k-3.06-hf2.rom
# map / par as core-p4096; cost table 2 first (karabas-go-notes map-cost-table-2-first); -mt 2: the PC is shared
MAP_T_go = 2
MAP_T_mini = 2
MAP_T_minig = 2
MAP_OPT = -logic_opt off -ol high -xe n -xt 0 -register_duplication off -r 4 -global_opt off -mt 2 -detail -ir off -pr b -lc off -power off
PAR_OPT = -ol high -xe n -mt 2
INCLUDES = $(wildcard ../modules/rtl/mcu/*.vh) $(wildcard rtl/acex/mif/*.hex) $(wildcard rtl/fdd/vg93/*.vh) rtl/fdd/vg93/vg93-microcode-rom.hex

.PHONY: all clean $(BOARDS) $(BOARDS:=-xst) $(BOARDS:=-impl) $(BOARDS:=-core) $(BOARDS:=-report) $(BOARDS:=-pack)

all: minig

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
# another BIOS / CMOS from the existing bitstream (never runs ISE): a core.json copy in roms/kg/
$(1)-pack:
	@[ -s karabas_$(1).bin ] || { echo "no karabas_$(1).bin: build it first (make $(1))"; exit 1; }
	@[ -n "$(KG)" ] && [ "$(KG)" != "$(KG_DEFAULT)" ] || { echo "set KG=<out.kg> (not $(KG_DEFAULT))"; exit 1; }
	@[ -s "$(ROM)" ] || { echo "no BIOS image $(ROM) (set ROM=...)"; exit 1; }
	mkdir -p roms/kg
	cp "$(ROM)" "roms/kg/$(notdir $(ROM))"
	python3 -I -c 'import json, sys; c = json.load(open(sys.argv[1])); r = sys.argv[3]; c["roms"][0]["filename"] = "roms/kg/" + r; \
		c.update({k: v for k, v in (("eeprom_init", sys.argv[4]), ("id", sys.argv[5]), ("name", sys.argv[6])) if v}); \
		json.dump(c, open(sys.argv[2], "w"), indent=4)' $(JSON) roms/kg/$(basename $(KG)).json "$(notdir $(ROM))" "$(CMOS)" "$(ID)" "$(NAME)"
	python3 make_core.py roms/kg/$(basename $(KG)).json $(KG) --boards $(1)

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
