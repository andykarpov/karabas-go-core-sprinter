`timescale 1ns / 1ps
/*-------------------------------------------------------------------------------------------------------------------
-- Sprinter Sp2000 core for the Karabas Mini rev.G (docs/minig.md)
--
-- The machine is rtl/top/sp_machine.v (board free); this top gives it the board:
-- Clocks: one PLL on CLK_50MHZ, VCO 50 * 37 / 2 = 925 MHz (as core-p4096 / core-baseconf):
--   clk_sys 84.09 MHz (/11) = CLK of sp_machine (2 x the 42 MHz of the original: ACEX, MAX, T80pa by enables, SRAM and
--     SDRAM controllers; SDR_CLK = clk_sys inverted, an ODDR2 inside sp_sdram);
--   clk_bus 28.03 MHz (/33) = clk_sys / 3, edges aligned: the MCU link, the OSD, the read side of the line doubler,
--     HDMI in the mode of the core, the DAC;
--   clk_8 7.97 MHz (/116): FT_CLK_OUT (every Mini / Mini G core must drive it) and DCM_CLKGEN of HDMI.
-- SRAM (2 x IS61WV20488, 16 bits): video RAM, ROM (BIOS 3.04 from the .kg), fastram (sp_sram).
-- SDRAM: the 4 MB DRAM of the original (sp_sdram). FLASH_CS_N = 0: the SDRAM ~CS of the Mini rev G2.
-- Video: WR_COL + palette shadow -> sp_vout (14 MHz dots, line doubler) -> OSD -> HDMI (kg_hdmi_ft).
-- Input: PS/2 set 2 bytes of the MCU -> AT frames on the XA lines of the ACEX + SIO A; USB mouse -> MS serial line
--   + SIO B (sp_kbd_tx, sp_ms_tx).
-- Sound: the I2S of the ACEX (AY + CBL) -> sp_i2s_rx -> PCM5102 + HDMI audio.
-- Not yet (bus idle): WD1793 + floppies, IDE, DS12887 RTC, tape, ISA.
------------------------------------------------------------------------------------------------------------------*/

module karabas_minig_top (
	//------------------ global clock --------
	input wire 				CLK_50MHZ,

	//------------------ esp8266 uart --------
	inout wire 				UART_RX,
	inout wire 				UART_TX,
	inout wire 				UART_CTS,

	//------------------ sram ----------------
	output wire [20:0] 	MA,
	inout wire [15:0] 	MD,
	output wire [1:0] 	MWR_N,
	output wire [1:0] 	MRD_N,

	//------------------ sdram ---------------
	output wire [1:0] 	SDR_BA,
	output wire [12:0] 	SDR_A,
	output wire 			SDR_CLK,
	output wire [1:0] 	SDR_DQM,
	output wire 			SDR_WE_N,
	output wire 			SDR_CAS_N,
	output wire 			SDR_RAS_N,
	inout wire [15:0] 	SDR_DQ,

	//------------------ sd2 -----------------
	output wire 			SD_CS_N,
	output wire 			SD_CLK,
	inout wire 				SD_DI,
	inout wire 				SD_DO,
	input wire 				SD_DET_N,

	//------------------ ft812 rgb + sync ----
	input wire [7:0] 		VGA_R,
	input wire [7:0] 		VGA_G,
	input wire [7:0] 		VGA_B,
	input wire 				VGA_HS,
	input wire 				VGA_VS,

	//------------------ dvi / hdmi ----------
	output wire [3:0] 	TMDS_P,
	output wire [3:0] 	TMDS_N,

	//------------------ ft812 spi and ctl ---
	inout wire 				FT_SPI_CS_N,
	inout wire 			FT_SPI_SCK,
	input wire 				FT_SPI_MISO,
	inout wire 			FT_SPI_MOSI,
	input wire 				FT_INT_N,
	input wire 				FT_CLK,
	input wire 				FT_DE,
	output wire 			FT_CLK_OUT,

	//------------------ cf card -------------
	output wire [2:0] 	WA,
	output wire [1:0] 	WCS_N,
	output wire 			WRD_N,
	output wire 			WWR_N,
	output wire 			WRESET_N,
	inout wire [15:0] 	WD,

	//------------------ analog in/out -------
	output wire 			TAPE_OUT,
	input wire 				TAPE_IN,

	//------------------ i2s dac -------------
	output wire          DAC_BCK,
	output wire          DAC_WS,
	output wire          DAC_DAT,

	//------------------ adc -----------------
	output wire 			ADC_CLK,
	inout wire 				ADC_BCK,
	inout wire 				ADC_LRCK,
	input wire 				ADC_DOUT,

	//------------------ esp32 i2s and cs ----
	inout wire           ESP32_SPI_CS_N,
	input wire           ESP32_PCM_BCK,
	input wire           ESP32_PCM_RLCK,
	input wire           ESP32_PCM_DAT,

	//------------------ mcu spi -------------
	input wire 				MCU_CS_N,
	input wire 				MCU_SCK,
	input wire 				MCU_MOSI,
	output wire 			MCU_MISO,
	inout wire [5:0] 		MCU_IO,  // [0] burst cs_n, [1] the link v2 interrupt, [2] sd2 cs_n, [3] ft cs_n

	//------------------ midi ----------------
	output wire 			MIDI_TX,

	//------------------ optional flash ------
	output wire 			FLASH_CS_N,
	input wire  			FLASH_DO,
	output wire 			FLASH_DI,
	output wire 			FLASH_SCK,
	output wire 			FLASH_WP_N,
	output wire 			FLASH_HOLD_N
);

// T3 (FLASH_CS_N) = 0: the ~CS of the SDRAM on the Mini rev G2 (karabas-go-notes mini-g2-sdram-cs)
assign FLASH_CS_N   = 1'b0;
assign FLASH_DI     = 1'b1;
assign FLASH_SCK    = 1'b0;
assign FLASH_WP_N   = 1'b1;
assign FLASH_HOLD_N = 1'b1;

assign ESP32_SPI_CS_N = 1'b1;
assign UART_RX = 1'bz;
assign UART_TX = 1'bz;
assign UART_CTS = 1'bz;
assign SD_CS_N = 1'b1;
assign SD_CLK = 1'b0;
assign SD_DI = 1'bz;
assign SD_DO = 1'bz;
assign MIDI_TX = 1'b1;
// CF card: not used yet (IDE in Ф2), the card deselected
assign WA = 3'b000;
assign WCS_N = 2'b11;
assign WRD_N = 1'b1;
assign WWR_N = 1'b1;
assign WRESET_N = 1'b1;
assign WD = 16'hZZZZ;
// ADC: not used
assign ADC_CLK = 1'b0;
assign ADC_BCK = 1'bz;
assign ADC_LRCK = 1'bz;

// ---------- clocks: VCO 50 * 37 / 2 = 925 MHz: clk_sys /11 84.09, clk_8 /116 7.97, clk_bus /33 28.03
wire clk_sys, clk_8mhz, clk_bus, clk_bus_pll;
wire locked, areset;
wire [5:0] pll_clk;
kg_pll #(
	.DIVCLK_DIVIDE(2), .CLKFBOUT_MULT(37),
	.CLKOUT0_DIVIDE(11), .CLKOUT1_DIVIDE(116), .CLKOUT2_DIVIDE(33), .CLKOUT3_DIVIDE(77),
	.BUFG_MASK(6'b001011)
) pll (
	.clk_in			(CLK_50MHZ),
	.rst				(1'b0),
	.clk_out			(pll_clk),
	.locked			(locked)
);
assign clk_sys = pll_clk[0];
assign clk_8mhz = pll_clk[1];
assign clk_bus_pll = pll_clk[2];
BUFG bufg_clk_bus(.I(clk_bus_pll), .O(clk_bus));

// the FT812 must always get a clock (karabas-go-notes ft-clk-out-required)
ODDR2 u_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8mhz), .C1(~clk_8mhz), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

assign areset = ~locked;

// ---------- MCU (link v2) ----------
wire mcu_int;
assign MCU_IO[1] = mcu_int;
assign MCU_IO[0] = 1'bz;
assign MCU_IO[5:2] = 4'bzzzz;

// MCU_SCK on a global buffer (see core-tsconf); FT_SPI_SCK takes it before the BUFG
wire mcu_sck_ibufg, mcu_sck;
IBUFG ibufg_mcu_sck(.I(MCU_SCK), .O(mcu_sck_ibufg));
BUFG bufg_mcu_sck(.I(mcu_sck_ibufg), .O(mcu_sck));

wire [7:0] ps2_code;
wire ps2_kind, ps2_wr;
wire [7:0] ms_x, ms_y, ms_z, ms_b;
wire ms_wr;
wire [5:0] mcu_btns;
wire mcu_busy, dvi_only;
wire osd_wr, osd_en, osd_zoom;
wire [11:0] osd_waddr;
wire [7:0] osd_wdata;
wire [23:0] osd_fg, osd_bg;
wire [1:0] osd_alpha, osd_place;
wire [4:0] osd_px, osd_ph;
wire [3:0] osd_py;
wire [5:0] osd_pw;
wire mcu_ft_spi_on, mcu_ft_vga_on, mcu_ft_reset, mcu_ft_sck, mcu_ft_mosi, mcu_ft_cs_n;
wire [1:0] ld_kind;
wire ld_active, ld_wr;
wire [31:0] ld_addr;
wire [7:0] ld_data;

localparam SW_N = 2;
wire [SW_N*8-1:0] softsw;

kg_mcu2 #(
	.CAPS(16'h0000),
	.SW_N(SW_N),
	.CS_FILTER(3),
	.ENABLE_OSD(1),
	.ENABLE_IMG(0),
	.ENABLE_PORTS(4'b0000),
	.ENABLE_RTC(0),
	.ENABLE_AUX(0),
	.ENABLE_FT(1),
	.ENABLE_SD2(0)
) mcu(
	.CLK				(clk_bus),
	.N_RESET			(~areset),
	.MCU_SCK			(mcu_sck),
	.MCU_MOSI		(MCU_MOSI),
	.MCU_MISO		(MCU_MISO),
	.MCU_SS			(MCU_CS_N),
	.MCU_INT			(mcu_int),
	.MCU_SPI_FT_SS	(MCU_IO[3]),
	.MCU_SPI_SD2_SS(1'b1),
	.SW				(softsw),
	.SW_WR			(),
	.SW_INDEX		(),
	.SW_VALUE		(),
	.HW_ID			(),
	.DVI_ONLY		(dvi_only),
	.CORE_BUILD		(),
	.FW_BUILD		(),
	.BUSY				(mcu_busy),
	.BTNS				(mcu_btns),
	.RELOAD_REQ		(1'b0),
	.RELOAD_CORE	(8'd0),
	.BK_MOUNT		(1'b0),
	.BK_FLUSHED		(1'b0),
	.BK_SLOT			(3'd0),
	.BK_SIZE			(32'd0),
	.BK_KIND			(8'd0),
	.BK_RESULT		(8'd0),
	.KBD				(),
	.KBD_WR			(),
	.PS2_CODE		(ps2_code),
	.PS2_KIND		(ps2_kind),
	.PS2_WR			(ps2_wr),
	.MS_X				(ms_x),
	.MS_Y				(ms_y),
	.MS_Z				(ms_z),
	.MS_B				(ms_b),
	.MS_WR			(ms_wr),
	.JOY_L			(),
	.JOY_R			(),
	.JOY_WR			(),
	.PS2_CMD			(16'h0000),
	.PS2_CMD_WR		(1'b0),
	.LD_KIND			(ld_kind),
	.LD_SLOT			(),
	.LD_SIZE			(),
	.LD_START		(),
	.LD_ACTIVE		(ld_active),
	.LD_END			(),
	.LD_ADDR			(ld_addr),
	.LD_DATA			(ld_data),
	.LD_WR			(ld_wr),
	.LD_READY		(1'b1),          // sp_ld_bridge queues the bytes (16 entries)
	.OSD_WR			(osd_wr),
	.OSD_WADDR		(osd_waddr),
	.OSD_WDATA		(osd_wdata),
	.OSD_EN			(osd_en),
	.OSD_FG			(osd_fg),
	.OSD_BG			(osd_bg),
	.OSD_ALPHA		(osd_alpha),
	.OSD_PX			(osd_px),
	.OSD_PY			(osd_py),
	.OSD_PW			(osd_pw),
	.OSD_PH			(osd_ph),
	.OSD_PLACE		(osd_place),
	.OSD_ZOOM		(osd_zoom),
	.SDC_IMG_MOUNTED(),
	.SDC_IMG_SIZE	(),
	.SDC_RD			(8'd0),
	.SDC_WR			(8'd0),
	.SDC_SECTOR		(32'd0),
	.SDC_BUSY		(),
	.SDC_DONE		(),
	.SDC_ERROR		(),
	.SDC_SLOT		(),
	.SDC_BYTE_IN_STROBE(),
	.SDC_BYTE_ADDR	(),
	.SDC_BYTE_IN_DATA(),
	.SDC_BYTE_OUT_DATA(8'd0),
	.IMG_WP			(),
	.IMG_PHYS_WR	(),
	.IMG_PHYS		(),
	.IMG_FLUSH		(),
	.FDD_CHNG_WR	(),
	.FDD_CHNG		(),
	.FDD_CHNG_REQ	(1'b0),
	.FDD_CHNG_DS	(2'd0),
	.IMG_ACTIVE		(),
	.PORT_OUT_DATA	(),
	.PORT_OUT_WR	(),
	.PORT_OUT_READY(4'b1111),
	.PORT_IN_DATA	(32'd0),
	.PORT_IN_WR		(4'b0000),
	.PORT_CFG		(128'd0),
	.PORT_IN_FULL	(),
	.PORT_STAT		(),
	.PORT_STAT_WR	(),
	.RTC_A			(8'd0),
	.RTC_DI			(8'd0),
	.RTC_CS			(1'b1),
	.RTC_WR_N		(1'b1),
	.MATRIX_CMD		(),
	.MATRIX_CMD_WR	(),
	.DEBUG_ADDR		(16'd0),
	.DEBUG_DATA		(16'd0),
	.RTC_DO			(),
	.FT_SPI_ON		(mcu_ft_spi_on),
	.FT_VGA_ON		(mcu_ft_vga_on),
	.FT_RESET		(mcu_ft_reset),
	.FT_SCK			(mcu_ft_sck),
	.FT_MOSI			(mcu_ft_mosi),
	.FT_MISO			(FT_SPI_MISO),
	.FT_CS_N			(mcu_ft_cs_n),
	.SD2_SCK			(),
	.SD2_MOSI		(),
	.SD2_MISO		(1'b1),
	.SD2_CS_N		()
);

// the FT812 belongs to the mcu (its menus): the core does not use it
assign FT_SPI_CS_N = mcu_ft_spi_on ? mcu_ft_cs_n : 1'b1;
assign FT_SPI_SCK = mcu_ft_spi_on ? mcu_sck_ibufg : 1'b1;
assign FT_SPI_MOSI = mcu_ft_spi_on ? mcu_ft_mosi : 1'b1;

// ---------- OSD switches (core.json "osd" "index"): switch n = softsw[n*8 +: 8] ----------
wire sw_reset = softsw[0];               // 0 Reset (Menu+F12): the RESET button of the board = reconfiguration

// ---------- the ROM loader (kind 0: the BIOS image of core.json "roms") ----------
wire ld_rom_act = ld_active && ld_kind == 2'd0;
// the machine waits in reset from the power-up until the first ROM load has ended
reg rom_loaded = 1'b0, ld_rom_act_p = 1'b0;
always @(posedge clk_bus) begin
	ld_rom_act_p <= ld_rom_act;
	if (ld_rom_act_p && !ld_rom_act) rom_loaded <= 1'b1;
end
wire ldb_req, ldb_ack, ldb_busy;
wire [20:0] ldb_a;
wire [1:0] ldb_be;
wire [15:0] ldb_d;
sp_ld_bridge ldb(.CLK(clk_sys), .LD_WR(ld_wr), .LD_ROM(ld_rom_act), .LD_ADDR(ld_addr[17:0]), .LD_DATA(ld_data),
	.REQ(ldb_req), .A(ldb_a), .BE(ldb_be), .D(ldb_d), .ACK(ldb_ack), .BUSY(ldb_busy), .OVF());

// machine reset = the RESET button of the original (the MAX /RESET: the ACEX erased and loaded again by the BIOS):
// the PLL, no ROM yet, the ROM loading, the mcu busy, OSD Reset, the board button 1
reg rst_bus = 1'b1;
always @(posedge clk_bus) rst_bus <= areset | !rom_loaded | ld_rom_act | mcu_busy | sw_reset | mcu_btns[0];
reg [2:0] rst_sys = 3'b111;
always @(posedge clk_sys) rst_sys <= {rst_sys[1:0], rst_bus | ldb_busy};
wire epm_res_n = !rst_sys[2];

// ---------- keyboard and mouse ----------
wire kbd_cc, kbd_dd, mouse_d;
wire [7:0] rxa_d, rxb_d;
wire rxa_stb, rxa_rdy, rxb_stb, rxb_rdy;
sp_kbd_tx kbd_tx(.CLK(clk_sys), .RESET(areset), .PS2_WR(ps2_wr && !ps2_kind), .PS2_CODE(ps2_code),
	.KBD_CC(kbd_cc), .KBD_DD(kbd_dd), .RX_D(rxa_d), .RX_STB(rxa_stb), .RX_RDY(rxa_rdy), .OVF());
sp_ms_tx ms_tx(.CLK(clk_sys), .RESET(areset), .MS_WR(ms_wr), .MS_X(ms_x), .MS_Y(ms_y), .MS_B(ms_b[2:0]),
	.MOUSE_D(mouse_d), .RX_D(rxb_d), .RX_STB(rxb_stb), .RX_RDY(rxb_rdy));

reg tape_in_r = 1'b0;
always @(posedge clk_sys) tape_in_r <= TAPE_IN;

// ---------- the machine ----------
wire [15:0] sram_do, sram_dt, sram_di;
wire [15:0] sdr_do, sdr_dt, sdr_di;
wire wr_col, sinc_h, sinc_v;
wire [31:0] pal_q;
wire dac_data, dac_ws, dac_bck;
wire [1:0] cfg_state;
sp_machine #(
	.MIF_DCP("rtl/acex/mif/dcp.hex"), .MIF_AY("rtl/acex/mif/ay.hex"), .MIF_KBD("rtl/acex/mif/kbd_ini2.hex")
) machine (
	.CLK(clk_sys), .EPM_RES_N(epm_res_n), .PW_GOOD(1'b1),
	.SRAM_A(MA), .SRAM_D_O(sram_do), .SRAM_D_T(sram_dt), .SRAM_D_I(sram_di), .SRAM_WE_N(MWR_N), .SRAM_OE_N(MRD_N),
	.LD_REQ(ldb_req), .LD_A(ldb_a), .LD_BE(ldb_be), .LD_D(ldb_d), .LD_ACK(ldb_ack),
	.SD_CLK(SDR_CLK), .SD_CKE(), .SD_CS_N(), .SD_RAS_N(SDR_RAS_N), .SD_CAS_N(SDR_CAS_N), .SD_WE_N(SDR_WE_N),
	.SD_BA(SDR_BA), .SD_A(SDR_A), .SD_DQM(SDR_DQM), .SD_DQ_O(sdr_do), .SD_DQ_T(sdr_dt), .SD_DQ_I(sdr_di),
	.KBD_CC(kbd_cc), .KBD_DD(kbd_dd), .MOUSE_D(mouse_d), .TAPE_IN(tape_in_r), .FDD_W(1'b1), .FDD_CH(1'b1),
	.TAPE_OUT(TAPE_OUT),
	.RXA_D(rxa_d), .RXA_STB(rxa_stb), .RXA_RDY(rxa_rdy), .RXB_D(rxb_d), .RXB_STB(rxb_stb), .RXB_RDY(rxb_rdy),
	.PA_I(8'hFF), .PA_O(), .PB_I(8'hFF), .PB_O(),
	.PER_D(16'hFFFF), .PER_OE(1'b0), .MD(), .HDD_C(), .FDD_C(), .HD_A(), .WR_PDOS(), .WG_WR_N(), .WG_RD_N(),
	.CMOS_DWR(), .CMOS_AS(), .CMOS_DRD(), .XHD_RES(), .XHD_WR(), .XHD_RD(), .XHD1_CS(), .XHD2_CS(), .FDD_1440(),
	.WR_COL(wr_col), .PAL_Q(pal_q), .VA(), .SINC_H(sinc_h), .SINC_V(sinc_v), .T320(),
	.DAC_DATA(dac_data), .DAC_WS(dac_ws), .DAC_BCK(dac_bck), .TURBO_LED(),
	.CFG_STATE(cfg_state), .CFG_HASH(), .CFG_BYTES(), .CFG_PERS(), .CFG_UNKNOWN()
);

// SRAM and SDRAM data pins: the output enables per bit (ODDR2 / IOB flip-flops inside the controllers)
genvar gi;
generate
	for (gi = 0; gi < 16; gi = gi + 1) begin : g_io
		IOBUF io_md (.O(sram_di[gi]), .IO(MD[gi]), .I(sram_do[gi]), .T(sram_dt[gi]));
		IOBUF io_dq (.O(sdr_di[gi]), .IO(SDR_DQ[gi]), .I(sdr_do[gi]), .T(sdr_dt[gi]));
	end
endgenerate

// ---------- sound: the I2S of the ACEX -> samples ----------
wire [15:0] snd_l, snd_r;
sp_i2s_rx i2s_rx(.CLK(clk_sys), .BCK(dac_bck), .WS(dac_ws), .DATA(dac_data), .LEFT(snd_l), .RIGHT(snd_r));
reg [15:0] audio_l = 16'd0, audio_r = 16'd0;
always @(posedge clk_bus) begin
	audio_l <= snd_l;
	audio_r <= snd_r;
end

kg_pcm5102 #(.DIV_BITS(2)) PCM5102(
	.clk				(clk_bus),
	.reset			(areset),
	.left				(audio_l),
	.right			(audio_r),
	.din				(DAC_DAT),
	.bck				(DAC_BCK),
	.lrck				(DAC_WS)
);

// ---------- video: WR_COL dots, line doubler, OSD, HDMI ----------
wire [7:0] video_r, video_g, video_b, osd_r, osd_g, osd_b;
wire video_hs, video_vs, video_de, osd_hs, osd_vs, osd_de;
sp_vout vout(.CLK(clk_sys), .WR_COL(wr_col), .PAL_Q(pal_q), .SINC_H(sinc_h), .SINC_V(sinc_v),
	.ON(cfg_state == 2'd3), .CLK28(clk_bus), .R(video_r), .G(video_g), .B(video_b), .HS(video_hs), .VS(video_vs),
	.DE(video_de));

kg_l2_osd_overlay overlay(
	.wclk				(clk_bus),
	.osd_wr			(osd_wr),
	.osd_waddr		(osd_waddr),
	.osd_wdata		(osd_wdata),
	.osd_en			(osd_en),
	.osd_fg			(osd_fg),
	.osd_bg			(osd_bg),
	.osd_alpha		(osd_alpha),
	.osd_px			(osd_px),
	.osd_py			(osd_py),
	.osd_pw			(osd_pw),
	.osd_ph			(osd_ph),
	.osd_place		(osd_place),
	.osd_zoom		(osd_zoom),
	.icon_on			(8'd0),
	.icon_act		(8'd0),
	.clk				(clk_bus),
	.rgb_i			({video_r, video_g, video_b}),
	.hs_i				(video_hs),
	.vs_i				(video_vs),
	.de_i				(video_de),
	.rgb_o			({osd_r, osd_g, osd_b}),
	.hs_o				(osd_hs),
	.vs_o				(osd_vs),
	.de_o				(osd_de)
);

// FT_CLK: the pixel clock of the FT812 (the menus of the mcu on HDMI)
wire ft_clk_ibufg, ft_clk_int;
IBUFG ibufg_ft_clk(.I(FT_CLK), .O(ft_clk_ibufg));
BUFG bufg_ft_clk(.I(ft_clk_ibufg), .O(ft_clk_int));

kg_hdmi_ft #(.CLKRATE(28030303), .REF_MHZ(8'd28), .SAMPLERATE(48000), .OUTPUT_REG(1)) hdmi_top(
	.clk				(ft_clk_int),
	.clk_ref			(clk_bus),
	.clk_ref_pll	(clk_bus_pll),
	.clk_8			(clk_8mhz),
	.reset			(areset),
	.vga_rgb			({osd_r, osd_g, osd_b}),
	.vga_hs			(osd_hs),
	.vga_vs			(osd_vs),
	.vga_de			(osd_de),
	.ft_rgb			({VGA_R, VGA_G, VGA_B}),
	.ft_hs			(VGA_HS),
	.ft_vs			(VGA_VS),
	.ft_de			(FT_DE),
	.ft_sel			(mcu_ft_vga_on),
	.audio_en		(~dvi_only),
	.audio_l			(audio_l),
	.audio_r			(audio_r),
	.tmds_p			(TMDS_P),
	.tmds_n			(TMDS_N),
	.freq				()
);

endmodule
