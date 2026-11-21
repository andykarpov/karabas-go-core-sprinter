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
-- Storage (docs/storage.md): IDE primary master / slave = HDD images (slots 4 / 5), WD1793 drives A / B = floppy
--   images (slots 0 / 1, TRD / 720 KB / 1.44 MB) on the file mounter of the MCU (sp_storage: hdf_ata, sp_fdd).
-- Tape: TAPE_IN -> XA mux -> port FE bit 6, port FE bit 3 -> XA2 latch -> TAPE_OUT; kg_tape_monitor in the mix.
-- Not yet (bus idle): ISA.
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

// the image files of the mcu (kg_mcu2 ENABLE_IMG): floppies slots 0-1, hard disks slots 4-5 (sp_storage)
wire [7:0] sdc_img_mounted, sdc_rd, sdc_wr, img_wp;
wire [63:0] sdc_img_size;
wire [31:0] sdc_sector;
wire sdc_busy, sdc_done, sdc_error, sdc_byte_in_strobe;
wire [2:0] sdc_slot;
wire [8:0] sdc_byte_addr;
wire [7:0] sdc_byte_in_data, sdc_byte_out_data;

localparam SW_N = 4;
wire [SW_N*8-1:0] softsw;

// the configuration hash for the mcu log: changes only at a configuration load (clk_sys register, clk_bus = clk_sys / 3
// with aligned edges: a plain register path)
wire [31:0] cfg_hash;
reg  [31:0] dbg_hash = 32'd0;
always @(posedge clk_bus) dbg_hash <= cfg_hash;
wire [7:0] cmos_q, rtc_a, rtc_di, rtc_do;
wire       rtc_wr_n;
wire [23:0] matrix_cmd;          // the audio peaks (audio_peaks below)
wire       matrix_cmd_wr;
kg_mcu2 #(
	.CAPS(16'h0000),
	.SW_N(SW_N),
	.CS_FILTER(3),
	.ENABLE_OSD(1),
	.ENABLE_IMG(1),
	.ENABLE_PORTS(4'b0000),
	.ENABLE_RTC(1),
	.RTC_SEND_LIMIT(128),
	.RTC_COALESCE(1),   // SETUP saves ~150 CMOS writes in a burst (docs/rtc.md)
	.ENABLE_AUX(1),     // DEBUG_ADDR / DATA = the MAME hash of the ACEX configuration (kg_board.py debug 1 / log)
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
	.SDC_IMG_MOUNTED(sdc_img_mounted),
	.SDC_IMG_SIZE	(sdc_img_size),
	.SDC_RD			(sdc_rd),
	.SDC_WR			(sdc_wr),
	.SDC_SECTOR		(sdc_sector),
	.SDC_BUSY		(sdc_busy),
	.SDC_DONE		(sdc_done),
	.SDC_ERROR		(sdc_error),
	.SDC_SLOT		(sdc_slot),
	.SDC_BYTE_IN_STROBE(sdc_byte_in_strobe),
	.SDC_BYTE_ADDR	(sdc_byte_addr),
	.SDC_BYTE_IN_DATA(sdc_byte_in_data),
	.SDC_BYTE_OUT_DATA(sdc_byte_out_data),
	.IMG_WP			(img_wp),
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
	.RTC_A			(rtc_a),
	.RTC_DI			(rtc_di),
	.RTC_CS			(1'b1),
	.RTC_WR_N		(rtc_wr_n),
	.MATRIX_CMD		(matrix_cmd),
	.MATRIX_CMD_WR	(matrix_cmd_wr),
	.DEBUG_ADDR		(dbg_hash[31:16]),
	.DEBUG_DATA		(dbg_hash[15:0]),
	.RTC_DO			(rtc_do),
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
wire [1:0] tape_mon = softsw[3*8 +: 2];  // 3 Tape monitor (Menu+T): 0 off, 1 in, 2 out, 3 both (kg_tape_monitor)

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
wire [15:0] per_d, m_md;
wire per_oe, m_iorq_n, m_cpu_res_n, m_rd_kmps;
wire [3:0] m_hdd_c;
wire [2:0] m_fdd_c, m_hd_a;
wire [1:0] m_wg_a;
wire m_wr_pdos, m_wg_wr_n, m_wg_rd_n, m_cmos_dwr, m_cmos_as, m_cmos_drd, m_xhd_res, m_xhd_wr, m_xhd_rd, m_fdd_1440;
wire [2:1] m_xhd1_cs, m_xhd2_cs;
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
	.PER_D(per_d), .PER_OE(per_oe), .MD(m_md), .HDD_C(m_hdd_c), .FDD_C(m_fdd_c), .HD_A(m_hd_a), .WG_A(m_wg_a),
	.RD_KMPS(m_rd_kmps), .IORQ_N(m_iorq_n), .CPU_RES_N(m_cpu_res_n), .WR_PDOS(m_wr_pdos), .WG_WR_N(m_wg_wr_n),
	.WG_RD_N(m_wg_rd_n), .CMOS_DWR(m_cmos_dwr), .CMOS_AS(m_cmos_as), .CMOS_DRD(m_cmos_drd), .XHD_RES(m_xhd_res),
	.XHD_WR(m_xhd_wr), .XHD_RD(m_xhd_rd), .XHD1_CS(m_xhd1_cs), .XHD2_CS(m_xhd2_cs), .FDD_1440(m_fdd_1440),
	.WR_COL(wr_col), .PAL_Q(pal_q), .VA(), .SINC_H(sinc_h), .SINC_V(sinc_v), .T320(),
	.DAC_DATA(dac_data), .DAC_WS(dac_ws), .DAC_BCK(dac_bck), .TURBO_LED(),
	.CFG_STATE(cfg_state), .CFG_HASH(cfg_hash), .CFG_BYTES(), .CFG_PERS(), .CFG_UNKNOWN()
);

// ---------- storage: IDE and WD1793 on the image files, the read data of the peripherals on MD (docs/storage.md)
// CMOS (docs/rtc.md): sp_cmos keeps the address, sends writes to the MCU mirror (kg_l2_rtc), its read byte goes to CMOS_Q
// (on MD while m_cmos_drd is low)
sp_cmos u_cmos(.CLK(clk_sys), .MD(m_md), .CMOS_AS(m_cmos_as), .CMOS_DWR(m_cmos_dwr), .CMOS_DRD(m_cmos_drd),
	.Q(cmos_q), .OE(), .CLK_BUS(clk_bus), .RTC_A(rtc_a), .RTC_DI(rtc_di), .RTC_WR_N(rtc_wr_n), .RTC_DO(rtc_do));
sp_storage storage(.CLK(clk_sys), .CLK_BUS(clk_bus), .RESET(areset), .CPU_RES_N(m_cpu_res_n), .IORQ_N(m_iorq_n),
	.MD(m_md), .HDD_C(m_hdd_c), .FDD_C(m_fdd_c), .HD_A(m_hd_a), .WG_A(m_wg_a), .XHD_RES(m_xhd_res), .XHD_RD(m_xhd_rd),
	.XHD_WR(m_xhd_wr), .XHD1_CS(m_xhd1_cs), .XHD2_CS(m_xhd2_cs), .WG_RD_N(m_wg_rd_n), .WG_WR_N(m_wg_wr_n),
	.WR_PDOS(m_wr_pdos), .RD_KMPS(m_rd_kmps), .FDD_1440(m_fdd_1440), .CMOS_DRD(m_cmos_drd), .CMOS_Q(cmos_q),
	.PER_D(per_d), .PER_OE(per_oe),
	.SDC_IMG_MOUNTED(sdc_img_mounted), .SDC_IMG_SIZE(sdc_img_size), .SDC_RD(sdc_rd), .SDC_WR(sdc_wr),
	.SDC_SECTOR(sdc_sector), .SDC_BUSY(sdc_busy), .SDC_DONE(sdc_done), .SDC_ERROR(sdc_error), .SDC_SLOT(sdc_slot),
	.SDC_BYTE_IN_STROBE(sdc_byte_in_strobe), .SDC_BYTE_ADDR(sdc_byte_addr), .SDC_BYTE_IN_DATA(sdc_byte_in_data),
	.SDC_BYTE_OUT_DATA(sdc_byte_out_data), .IMG_WP(img_wp), .HDD_LED(), .FDD_ACTIVE());

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

// the tape monitor (modules kg_tape_monitor, as core-tsconf): TAPE_IN (the pin) and TAPE_OUT (the XA2 latch of
// sp_machine, a clk_sys register: clk_bus = clk_sys / 3 with aligned edges) heard in the mix; a level held 37 ms
// relaxes to 0 (an open input, MIC left at 1)
wire signed [15:0] tape_mon_sample;
kg_tape_monitor #(.CLK_HZ(28000000), .HOLD_US(37000), .LEVEL_IN(4096), .LEVEL_OUT(2048)) tape_monitor(
	.clk(clk_bus), .mode(tape_mon), .tape_in(TAPE_IN), .tape_out(TAPE_OUT), .in_on(), .out_on(),
	.sample(tape_mon_sample));

// the final mix (clk_bus): the sound of the ACEX + the tape monitor, saturated to 16 bits
function [15:0] sat16(input [17:0] v);   // a sum of up to four 16-bit two's complement values
	sat16 = (v[17:15] == 3'b000 || v[17:15] == 3'b111) ? v[15:0] : v[17] ? 16'h8000 : 16'h7FFF;
endfunction
wire [17:0] mix_l = {{2{snd_l[15]}}, snd_l} + {{2{tape_mon_sample[15]}}, tape_mon_sample};
wire [17:0] mix_r = {{2{snd_r[15]}}, snd_r} + {{2{tape_mon_sample[15]}}, tape_mon_sample};
reg [15:0] audio_l = 16'd0, audio_r = 16'd0;
always @(posedge clk_bus) begin
	audio_l <= sat16(mix_l);
	audio_r <= sat16(mix_r);
end

// the level meters of the mcu: the peaks of the final mix as CMD_AUDIO_PEAKS_L / _R (modules audio_peaks.v, as
// core-nanomig), on clk_bus = the clock of kg_mcu2 (MATRIX_CMD of ENABLE_AUX)
audio_peaks audio_peaks(.clk(clk_bus), .audio_l(audio_l), .audio_r(audio_r), .cmd_wr(matrix_cmd_wr), .cmd(matrix_cmd));

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
