#!/usr/bin/env python3
"""Makes rtl/karabas_go_top.v and rtl/karabas_mini_top.v from rtl/karabas_minig_top.v (change Mini G, then run
this; the two tops are not edited by hand). After core-p4096 src/tools/mktop.py. The machine, kg_mcu2, the OSD,
the sound and the disks are those of Mini G; the ports of a board come from its top as it is (the first time from
--ports BOARD=FILE: the top of that board in core-p4096); the board glue is replaced:

Mini: no PCM5102 (sigma-delta AUDIO_L / AUDIO_R), no ESP32 PCM (ESP_RESET_N / ESP_BOOT_N), MCU_SCK and FT_CLK
  not on clock pins, MCU_IO[3:0], FT_RESET, MIDI_CLK 12 MHz and MIDI_RESET_N, HDMI audio at 44.1 kHz.
Go: no HDMI, no FT_CLK_OUT, no ADC (no PCM1808 on the Go: zeros in the mix): the FPGA and the FT812 share the video DAC (VGA_*, V_CLK = inverted pixel clock
  of bus_ce or FT_CLK, FT_OE_N), the syncs by the OSD item VGA Sync (index 2, Go only); MCU_SCK not on a clock
  pin, INT of link v2 on MCU_SPI_IO[0], the FT812 select on MCU_SPI_FT_CS_N; the floppy connector outputs 0 (no
  physical drive yet), the beeper off, MIDI_CLK 12 MHz, DAC_LRCK / DAC_MUTE.

Every replacement must match once, else this stops.  Run in src/:  python3 tools/mktop.py [BOARD=FILE ...]
"""
import os
import re
import sys

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")


def sub(s, old, new, what):
    if s.count(old) != 1:
        sys.exit("mktop.py: %s: %d matches of %r" % (what, s.count(old), old[:70]))
    return s.replace(old, new)


def cut(s, start, end, new, what):
    """replace from start up to and including end (both must be there once)"""
    if s.count(start) != 1:
        sys.exit("mktop.py: %s: %d matches of %r" % (what, s.count(start), start[:70]))
    i = s.index(start)
    j = s.index(end, i) + len(end)
    return s[:i] + new + s[j:]


def ports_of(text, board):
    i = text.index("module karabas_%s_top" % board)
    m = re.compile(r"\n[ \t]*\);").search(text, i)      # the end of the port list (may be indented)
    return text[i:m.start()] + "\n);"


PCM_START = "kg_pcm5102 #(.DIV_BITS(2)) PCM5102("
PCM_END = "	.lrck				(DAC_WS)\n);\n"
CLK12 = ("wire clk_sys, clk_8mhz, clk_bus, clk_bus_pll;", "wire clk_sys, clk_8mhz, clk_bus, clk_bus_pll, clk_12mhz;")
CLK12A = ("assign clk_bus_pll = pll_clk[2];\n", "assign clk_bus_pll = pll_clk[2];\nassign clk_12mhz = pll_clk[3];\n")
MIDI = ("// the clock of the MIDI synth SAM2695 (12 MHz) and its reset\n"
        "ODDR2 u_midi_clk (.Q(MIDI_CLK), .C0(clk_12mhz), .C1(~clk_12mhz), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));\n"
        "assign MIDI_RESET_N = 1'b1;\n")


def mini(b):
    b = sub(b, "assign ESP32_SPI_CS_N = 1'b1;\n", "assign ESP_RESET_N = 1'bz;\nassign ESP_BOOT_N = 1'bz;\n", "esp")
    b = sub(b, *CLK12, "clk12")
    b = sub(b, *CLK12A, "clk12 assign")
    b = sub(b, "ODDR2 u_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8mhz), .C1(~clk_8mhz), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));\n",
            "ODDR2 u_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8mhz), .C1(~clk_8mhz), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));\n"
            + MIDI, "midi clk")
    b = sub(b, "assign MCU_IO[5:2] = 4'bzzzz;\n", "assign MCU_IO[3:2] = 2'bzz;\n", "mcu io")
    b = cut(b, "// MCU_SCK on a global buffer", "BUFG bufg_mcu_sck(.I(mcu_sck_ibufg), .O(mcu_sck));\n",
            "// MCU_SCK is not on a clock pin of the Mini (CLOCK_DEDICATED_ROUTE = FALSE in the ucf)\n"
            "wire mcu_sck = MCU_SCK;\n", "mcu sck")
    b = sub(b, "assign FT_SPI_SCK = mcu_ft_spi_on ? mcu_sck_ibufg : 1'b1;\n",
            "assign FT_SPI_SCK = mcu_ft_spi_on ? mcu_ft_sck : 1'b1;\nassign FT_RESET = ~mcu_ft_reset;\n", "ft sck")
    b = sub(b, "SAMPLERATE(48000)", "SAMPLERATE(44100)", "hdmi rate")
    b = cut(b, PCM_START, PCM_END,
            "// sigma-delta DACs (AUDIO_L / AUDIO_R): the samples (two's complement) as offset binary, 12 bits\n"
            "kg_sigma_delta_dac #(.MSBI(15)) dac_l(.clk(clk_bus), .reset(areset),\n"
            "	.din({2'b00, !audio_l[15], audio_l[14:4], 2'b00}), .dout(AUDIO_L));\n"
            "kg_sigma_delta_dac #(.MSBI(15)) dac_r(.clk(clk_bus), .reset(areset),\n"
            "	.din({2'b00, !audio_r[15], audio_r[14:4], 2'b00}), .dout(AUDIO_R));\n", "dac")
    return b


def go(b):
    b = cut(b, "// T3 (FLASH_CS_N) = 0", "assign FLASH_CS_N   = 1'b0;\n",
            "// the configuration flash is not used: its select high\nassign FLASH_CS_N   = 1'b1;\n", "flash")
    b = sub(b, "assign ESP32_SPI_CS_N = 1'b1;\n",
            "assign ESP_RESET_N = 1'bz;\nassign ESP_BOOT_N = 1'bz;\nassign BEEPER = 1'b0;\n"
            "// the floppy connector: no physical drive yet (all outputs 0 = inactive behind the inverters)\n"
            "assign FDC_DRIVE = 2'b00;\nassign FDC_MOTOR = 1'b0;\nassign FDC_DIR = 1'b0;\nassign FDC_STEP = 1'b0;\n"
            "assign FDC_WDATA = 1'b0;\nassign FDC_WGATE = 1'b0;\nassign FDC_SIDE_N = 1'b0;\n", "esp")
    b = cut(b, "// ---------- ADC (PCM1808", "// ---------- ADC end\n",
            "// no ADC on the Go\nwire [15:0] adc_mix_l = 16'd0, adc_mix_r = 16'd0;\n", "adc")
    b = sub(b, *CLK12, "clk12")
    b = sub(b, *CLK12A, "clk12 assign")
    b = cut(b, "// the FT812 must always get a clock", "ODDR2 u_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8mhz), .C1(~clk_8mhz), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));\n",
            MIDI.replace("its reset\n", "its reset; the Go has no FT_CLK_OUT (the FT812 has a crystal)\n") +
            "// V_CLK of the video DAC: the pixel clock (clk_bus) inverted, from clk_sys (bus_ce, as core-p4096)\n"
            "wire v_clk;\nbus_ce bus_ce(.clk_sys(clk_sys), .clk_bus(clk_bus), .ce(), .v_clk(v_clk));\n", "ft clk")
    b = cut(b, "assign MCU_IO[1] = mcu_int;\n", "assign MCU_IO[5:2] = 4'bzzzz;\n",
            "assign MCU_SPI_IO[0] = mcu_int;   // INT of link v2 on N9\nassign MCU_SPI_IO[1] = 1'bz;\n", "mcu io")
    b = cut(b, "// MCU_SCK on a global buffer", "BUFG bufg_mcu_sck(.I(mcu_sck_ibufg), .O(mcu_sck));\n",
            "// MCU_SCK is not on a clock pin of the Go (CLOCK_DEDICATED_ROUTE = FALSE in the ucf)\n"
            "wire mcu_sck = MCU_SCK, mcu_sck_ibufg = MCU_SCK;\n", "mcu sck")
    b = sub(b, "	.MCU_SPI_FT_SS	(MCU_IO[3]),", "	.MCU_SPI_FT_SS	(MCU_SPI_FT_CS_N),", "ft ss")
    b = sub(b, "assign FT_SPI_MOSI = mcu_ft_spi_on ? mcu_ft_mosi : 1'b1;\n",
            "assign FT_SPI_MOSI = mcu_ft_spi_on ? mcu_ft_mosi : 1'b1;\n"
            "// the FT812 and the FPGA share the video DAC: the FT812 drives it when the firmware asks (its menus)\n"
            "assign FT_OE_N = !mcu_ft_vga_on;\n", "ft oe")
    b = sub(b, "wire sw_reset = softsw[0];",
            "wire [1:0] vga_sync_pos = softsw[2*8 +: 2];  // 2 VGA Sync (Go only): bit 0 +H, bit 1 +V (0 = -H -V)\n"
            "wire sw_reset = softsw[0];", "vga sync")
    b = cut(b, "// FT_CLK: the pixel clock of the FT812", "	.freq				()\n);\n",
            "// the VGA DAC: the picture of the core with the OSD, or the FT812 (its pins high impedance then)\n"
            "assign VGA_R = mcu_ft_vga_on ? 8'bZZZZZZZZ : osd_r;\n"
            "assign VGA_G = mcu_ft_vga_on ? 8'bZZZZZZZZ : osd_g;\n"
            "assign VGA_B = mcu_ft_vga_on ? 8'bZZZZZZZZ : osd_b;\n"
            "assign VGA_HS = mcu_ft_vga_on ? 1'bZ : osd_hs ^ ~vga_sync_pos[0];   // positive syncs of sp_vout\n"
            "assign VGA_VS = mcu_ft_vga_on ? 1'bZ : osd_vs ^ ~vga_sync_pos[1];\n"
            "assign V_CLK = mcu_ft_vga_on ? FT_CLK : v_clk;\n", "hdmi")
    b = sub(b, PCM_START, "kg_pcm5102 #(.DIV_BITS(1)) PCM5102(", "dac div")
    b = sub(b, PCM_END, "	.lrck				(DAC_LRCK)\n);\nassign DAC_MUTE = 1'b1;   // 1 = not muted\n", "dac")
    return b


NAMES = {"go": "Karabas Go", "mini": "Karabas Mini (before rev.G)"}
NOTE = {"go": "// The Go: VGA (the video DAC, V_CLK) instead of HDMI, no FT_CLK_OUT, no ADC, the floppy connector unused.\n",
        "mini": "// The Mini: sigma-delta AUDIO_L / AUDIO_R instead of the PCM5102, HDMI audio 44.1 kHz, MCU_SCK / FT_CLK not on\n"
                "// clock pins, MIDI_CLK / MIDI_RESET_N, FT_RESET.\n"}
EDIT = {"go": go, "mini": mini}


def main():
    ports_src = dict(a.split("=", 1) for a in sys.argv[1:] if "=" in a)
    g = open(os.path.join(SRC, "rtl/karabas_minig_top.v")).read()
    i = g.index("module karabas_minig_top")
    head_comment = g[:i]
    body = g[g.index("\n);\n", i) + 4:]
    for board in ("go", "mini"):
        dst = os.path.join(SRC, "rtl/karabas_%s_top.v" % board)
        src = ports_src.get(board, dst)
        ports = ports_of(open(src).read(), board)
        hc = sub(head_comment, "for the Karabas Mini rev.G", "for the %s" % NAMES[board], "title")
        hc = hc.rstrip("\n") + "\n// karabas: made by src/tools/mktop.py from karabas_minig_top.v (do not edit it, change Mini G)\n" + NOTE[board] + "\n"
        text = hc + ports + "\n" + EDIT[board](body)
        open(dst, "w").write(text)
        print("mktop.py: rtl/karabas_%s_top.v" % board)


if __name__ == "__main__":
    main()
