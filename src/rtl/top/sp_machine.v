// Sprinter Sp2000: the machine without the board (docs/machine.md). CPU (sp_z84c15), the ACEX (sp_acex), the MAX
// (sp_max), the memory controllers (sp_sram: video RAM, ROM, fastram, palette shadow; sp_sdram: the DRAM), the
// latches of the board on the MA bus (control word to the MAX, IDE register, INT / NMI / TURBO, TAPE_OUT), the XA
// multiplexer, and the configuration path of the original: after every reset of the MAX the ACEX is empty, the CPU
// runs from ROM page 0x0C on the 14 MHz clock of the MAX and pours the bitstream bit by bit (WR_CNF, D0); here the
// stream is received, counted and hashed, and at its end the ACEX (the translated 3.03a, or k30 by the hash) is released.
// Board-specific parts (PLL, pins, the MCU link, HDMI, the ROM loader) are in the board top; the peripherals not made
// yet (the FDD data separator, RTC) are ports marked TODO. The storage controllers (IDE, WD1793 on SD images:
// board/sp_storage.v, docs/storage.md) sit outside on the MAX strobes and the MD bus (PER_D / PER_OE).
//
// Clock: CLK = 84 MHz; CE / CE_N (the edges of the original 42 MHz) are made here, CE first after power-up.
//
// Configuration (docs/machine.md 3):
// - The MAX /RESET (power-on: PW_GOOD at the first frame sync; the button EPM_RES_N; port 2E = the control word
//   1011/000) is nCONFIG of the ACEX. Ours: CFG_RST of sp_acex (every register and RAM to the configuration state) from
//   the MAX /RESET to the end of the stream. The original does not reset the CPU there (the ACEX pins float, the CPU
//   wanders into the FF-filled loader page: RST 38 -> JP 0); here the MAX /RESET is also the CPU /RESET (as MAME does).
//   It also clears the MA latches, which ends the 2E control word.
// - While the ACEX is empty: CPU clock = CLKZZ of the MAX (14 MHz; its edges fall on CE and CE_N, it is resampled at
//   CE_N for sp_z84c15), memory by CS0 / CS1 of the Z84C15 (R176 / R177 to CS_ROM / CS_CASH): CS0 = ROM at
//   0x30000 + A[15:0] (RA14 / RA15 = A14 / A15 through R84 / R85, RA16 / RA17 pulled up), CS1 = fastram at A[15:0];
//   no /WAIT, no INT / NMI (pulled up), the DRAM idle (sp_sdram refreshes by itself).
// - Every CPU memory write is a configuration clock (WR_CNF = !(/WR | /MR), MAX 10K_CLK / 10K_D0): the receiver takes
//   10K_D0 at each 10K_CLK rise (LSB first), counts the bits and makes the MAME hash: the sum of the first 4096 written
//   bytes (the whole data bus), byte n shifted by 8 * (n mod 4) (sprinter.cpp bootstrap_w). The stream ends after
//   CFG_BITS + CFG_INIT clocks (59 215 bytes of an EP1K30 + the initialisation clocks).
// - Release: the reloads of sp_acex done (CFG_DONE) and the SDRAM ready, at a CE. The ACEX starts in its power-up
//   state: it holds /RESET for three CT4 periods (SOFT_RES) and the CPU starts again from 0 in the configured map. The
//   power-up XACS pulse of the chip (its first XACS ends the load mode of the MAX) is made here: XACS low for one
//   CE + CE_N at the release.
// - Personality: chosen at the release from a table of known MAME hashes and held until the next release (sp_acex is
//   in CFG_RST meanwhile). The MAME hash covers only the first 512 bytes (mostly FF): different builds of one design
//   differ in it, different designs may collide (2.16 = 2.17), so every known build is listed. 1 = k30 (BIOS 3.05 /
//   3.06 and other k30 builds): sp_acex PERS_K30; 2 = SCROLL (Thunder in the Deep) when the hash is 3861cfa4 and
//   CSBR[3:0] = 0 (the bitstream came from fastram), as MAME: a hook only, the 3.03a runs; else 0 (standard 3.03a).
//   CFG_UNKNOWN: none of the table (OSD message); 3.03a runs. CFG_FNV: FNV-1a 32 over the data bus of every
//   configuration write of the stream (CFG_BITS writes, 8 per bitstream byte), as unreal-ng (SCROLL: c0fa3055):
//   for the log / OSD only, the selection is by the MAME table.
module sp_machine #(
	parameter        MIF_DCP   = "dcp.hex",
	parameter        MIF_AY    = "ay.hex",
	parameter        MIF_KBD   = "kbd_ini2.hex",
	parameter [31:0] CFG_BITS  = 32'd473720,      // 59 215 bytes x 8: the EP1K30 bitstream
	parameter [31:0] CFG_INIT  = 32'd10,          // DCLK after the last bit (the ACEX 1K initialisation)
	parameter [15:0] SD_INIT   = 16'd8400,        // sp_sdram power-up wait (100 us at 84 MHz)
	parameter        XHD_RES_ON_HSYNC = 0,        // simulation: the power-on reset ends after a line, not a frame
	parameter        SIM_X     = 0
) (
	input             CLK,            // 84 MHz
	input             EPM_RES_N,      // the reset button (J2): MAX /RESET -> reconfiguration
	input             PW_GOOD,        // power good (1 on the boards)
	// ---- SRAM (2 x IS61WV20488: video RAM, ROM, fastram; sp_sram)
	output     [20:0] SRAM_A,
	output     [15:0] SRAM_D_O,
	output     [15:0] SRAM_D_T,
	input      [15:0] SRAM_D_I,
	output      [1:0] SRAM_WE_N,
	output      [1:0] SRAM_OE_N,
	// the ROM loader (the board: the MCU writes the BIOS image into the SRAM; sp_sram LD_*)
	input             LD_REQ,
	input      [20:0] LD_A,
	input       [1:0] LD_BE,
	input      [15:0] LD_D,
	output            LD_ACK,
	// ---- SDRAM (the DRAM of the ACEX; sp_sdram)
	output            SD_CLK,
	output            SD_CKE,
	output            SD_CS_N,
	output            SD_RAS_N,
	output            SD_CAS_N,
	output            SD_WE_N,
	output      [1:0] SD_BA,
	output     [12:0] SD_A,
	output      [1:0] SD_DQM,
	output     [15:0] SD_DQ_O,
	output     [15:0] SD_DQ_T,
	input      [15:0] SD_DQ_I,
	// ---- XA multiplexer inputs (TODO: PS/2 keyboard and mouse lines from the MCU, tape)
	input             KBD_CC,         // PS/2 clock / data of the keyboard (idle 1)
	input             KBD_DD,
	input             MOUSE_D,        // MS serial mouse (idle 1)
	input             TAPE_IN,
	input             FDD_W,          // TODO: WD1793 / drive lines of the multiplexer
	input             FDD_CH,
	output            TAPE_OUT,       // XA2 latched by WR_AWG (DD16)
	// ---- Z84C15 serial / PIO (TODO: the SIO streams are the AT keyboard / mouse of DSS)
	input       [7:0] RXA_D,
	input             RXA_STB,
	output            RXA_RDY,
	input       [7:0] RXB_D,
	input             RXB_STB,
	output            RXB_RDY,
	input       [7:0] PA_I,
	output      [7:0] PA_O,
	input       [7:0] PB_I,
	output      [7:0] PB_O,
	// ---- peripherals on the MD bus (IDE, WD1793, DS12887: sp_storage and sp_cmos outside): their read data and the
	// strobes of the MAX. The 8-bit devices (type 7 ports: WD1793, #FF, CMOS) are read from MD[15:8], IDE as a word.
	input      [15:0] PER_D,          // read data of the selected peripheral
	input             PER_OE,         // ... drives MD (from its read strobe to the end of the I/O cycle)
	output     [15:0] MD,             // the MD bus (write data of the peripherals)
	output      [3:0] HDD_C,          // control word latched from MA (DD11 and its pair)
	output      [2:0] FDD_C,
	output      [2:0] HD_A,           // IDE register
	output      [1:0] WG_A,           // MA[1:0] of the control word (A6..A5 of the port): the WD1793 register
	output            RD_KMPS,        // the read strobe of the KP11 multiplexer (#FF: INTRQ / DRQ when FDD_C0 = 1)
	output            IORQ_N,         // the CPU /IORQ (the end of an I/O cycle)
	output            CPU_RES_N,      // the CPU /RESET line
	output            WR_PDOS,
	output            WG_WR_N,
	output            WG_RD_N,
	output            CMOS_DWR,
	output            CMOS_AS,
	output            CMOS_DRD,
	output            XHD_RES,
	output            XHD_WR,
	output            XHD_RD,
	output      [2:1] XHD1_CS,
	output      [2:1] XHD2_CS,
	output            FDD_1440,       // MAX 10K_D0 in the working mode
	// ---- video (TODO: the output stage: pixel / palette path of VIDEO2 to the line doubler)
	output            WR_COL,         // palette DAC strobe (the pixel clock of the original)
	output     [31:0] PAL_Q,          // palette entry of the current VA (sp_sram shadow)
	output     [15:0] VA,
	output            SINC_H,
	output            SINC_V,
	output            T320,           // 1: 320 lines, 0: 312
	// ---- sound: I2S of the ACEX (AY + CBL)
	output            DAC_DATA,
	output            DAC_WS,
	output            DAC_BCK,
	output            TURBO_LED,      // MA14 latched (!TURBO)
	// ---- configuration status (OSD)
	output      [1:0] CFG_STATE,      // 0 erased (MAX /RESET), 1 loading, 2 waiting for the reloads, 3 running
	output     [31:0] CFG_HASH,       // MAME hash of the last stream
	output     [31:0] CFG_FNV,        // FNV-1a 32 of the whole stream (all CFG_BITS writes)
	output     [16:0] CFG_BYTES,      // bytes received (saturates)
	output reg  [1:0] CFG_PERS = 2'd0, // personality chosen at the release: 0 standard 3.03a, 1 k30, 2 SCROLL (hook)
	output reg        CFG_UNKNOWN = 1'b0
);
	// ================= CE / CE_N: CE at the first edge
	reg ph = 1'b0;
	always @(posedge CLK) ph <= ~ph;
	wire ce = ~ph, ce_n = ph;

	// ================= CPU
	wire m1_n, rf_n, io_n, wr_n, rd_n, mr_n, halt_n, m1_nx, rf_nx, io_nx, wr_nx, rd_nx, mr_nx, cpu_doe, int_rd;
	wire [15:0] a, a_nx; wire [7:0] cpu_do; wire cs0, cs1; wire [7:0] csbr, mcr;
	wire zclk, zclk_nx, z_wait_n, z_res_n;
	wire max_clkzz, max_clkzz_oe, max_aud, max_sinc1, max_sinc2, max_kclk, max_kd0;
	reg  int_l = 1'b0, nmi_l = 1'b0;
	wire [7:0] d_bus;
	sp_z84c15 CPU(.CLK(CLK), .CE(ce), .CE_N(ce_n), .CLKZ1(zclk), .CLKZ1_NX(zclk_nx), .RESET_N(z_res_n),
		.WAIT_N(z_wait_n), .INT_N(~int_l), .NMI_N(~nmi_l), .M1_N(m1_n), .RF_N(rf_n), .IO_N(io_n), .WR_N(wr_n),
		.RD_N(rd_n), .MR_N(mr_n), .HALT_N(halt_n), .A(a), .D_O(cpu_do), .D_OE(cpu_doe), .M1_N_NX(m1_nx),
		.RF_N_NX(rf_nx), .IO_N_NX(io_nx), .WR_N_NX(wr_nx), .RD_N_NX(rd_nx), .MR_N_NX(mr_nx), .A_NX(a_nx), .D_I(d_bus),
		.INT_RD(int_rd), .CS0(cs0), .CS1(cs1), .CSBR(csbr), .MCR(mcr), .RXA_D(RXA_D), .RXA_STB(RXA_STB),
		.RXA_RDY(RXA_RDY), .RXB_D(RXB_D), .RXB_STB(RXB_STB), .RXB_RDY(RXB_RDY), .CTSA(1'b0), .DCDA(1'b0),
		.CTSB(1'b1), .DCDB(1'b0), .WR5A(), .WR5B(), .TRG0(max_aud), .ZC0(), .PA_I(PA_I), .PA_O(PA_O), .PA_OE(),
		.PB_I(PB_I), .PB_O(PB_O), .PB_OE());

	// ================= ACEX
	wire        on;                                 // the ACEX is configured and running
	wire        cfg_rst, cfg_done;
	wire  [7:0] x_do; wire x_doe, x_clkz, x_clkz_nx, x_wait_oe, x_res_oe, x_cs_rom, x_cs_cash, x_wr_col;
	wire [17:14] x_ra; wire [1:0] x_vcs; wire [15:0] x_va; wire [3:0] x_vwr, x_vdoe;
	wire  [7:0] x_vd0o, x_vd1o, x_vd2o, x_vd3o, s_vd0, s_vd1, s_vd2, s_vd3;
	wire [15:0] x_mdo; wire x_mdoe; wire [14:0] x_ma; wire [1:0] x_ras; wire [3:0] x_cas; wire x_we;
	wire        x_xacs, x_xaoe, x_sxa, x_rdxa, x_awg, x_kmps, x_dwg; wire [2:0] x_xao, xa_in;
	wire  [2:0] x_ct; wire [17:1] x_va_nx, x_va_atr; wire [3:0] x_vwr_nx; wire [15:0] x_va_mod;
	wire        x_mode_rq, x_mlo_rq, x_atr_zx, x_pix_rq, x_sel_rom, x_sel_cash; wire [1:0] x_mca;
	wire [15:0] md_bus;
	wire        max_res_c, xa3;
	// the MAX /RESET (nCONFIG of the ACEX and the CPU /RESET here) through a register: in the original an
	// asynchronous open-drain line; combinational it made a path MA latch -> MAX decode -> ACEX reset -> /WE ->
	// SDRAM command longer than one CLK (PAR, Ф1.4). One CLK later does not matter for a reset of 0.5 s.
	reg         max_res_n = 1'b0;
	always @(posedge CLK) max_res_n <= max_res_c;
	sp_acex #(.MIF_DCP(MIF_DCP), .MIF_AY(MIF_AY), .MIF_KBD(MIF_KBD)) ACEX(.CLK(CLK), .CE(ce), .CE_N(ce_n),
		.M1_N(m1_n), .RF_N(rf_n), .IO_N(io_n), .WR_N(wr_n), .RD_N(rd_n), .MR_N(mr_n),
		.M1_N_NX(m1_nx), .RF_N_NX(rf_nx), .IO_N_NX(io_nx), .WR_N_NX(wr_nx), .RD_N_NX(rd_nx), .MR_N_NX(mr_nx),
		.A(a), .D_I(d_bus), .D_O(x_do), .D_OE(x_doe), .CLKZ1(x_clkz), .CLKZ1_NX(x_clkz_nx), .WAIT_N_OE(x_wait_oe),
		.RESET_N_I(max_res_n), .RESET_N_OE(x_res_oe), .CS_ROM(x_cs_rom), .CS_CASH(x_cs_cash), .RA(x_ra),
		.V_CS(x_vcs), .VA(x_va), .V_WR(x_vwr), .VD0_I(s_vd0), .VD1_I(s_vd1), .VD2_I(s_vd2), .VD3_I(s_vd3),
		.VD0_O(x_vd0o), .VD1_O(x_vd1o), .VD2_O(x_vd2o), .VD3_O(x_vd3o), .VD_OE(x_vdoe), .WR_COL(x_wr_col),
		.DAC_DATA(DAC_DATA), .DAC_WS(DAC_WS), .DAC_BCK(DAC_BCK), .MD_I(md_bus), .MD_O(x_mdo), .MD_OE(x_mdoe),
		.MA(x_ma), .RAS_(x_ras), .CAS_(x_cas), .WE_N(x_we), .XACS(x_xacs), .XA_I(xa_in), .XA_O(x_xao),
		.XA_OE(x_xaoe), .XA3(xa3), .SXA(x_sxa), .RDXA(x_rdxa), .WR_AWG(x_awg), .RD_KMPS(x_kmps), .WR_DWG(x_dwg),
		.CT_PH(x_ct), .VA_NX(x_va_nx), .V_WR_NX(x_vwr_nx), .VA_MOD(x_va_mod), .MODE_RQ(x_mode_rq), .MLO_RQ(x_mlo_rq),
		.VA_ATR(x_va_atr), .ATR_ZX(x_atr_zx), .PIX_RQ(x_pix_rq), .MCA(x_mca), .SEL_ROM(x_sel_rom),
		.SEL_CASH(x_sel_cash), .CFG_RST(cfg_rst), .CFG_DONE(cfg_done), .PERS_K30(CFG_PERS == 2'd1));

	// ================= the latches of the board on MA (DD11, DD16 and the one of HDD_C0 / FDD_C): taken at the rise
	// of WR_AWG (MA as before the edge), cleared by the CPU /RESET line
	// karabas: MA[1:0] (the WD1793 register, A6..A5 of the port) latched with them; on the board the WD1793 takes its
	// A0 / A1 elsewhere (not traced on the schematic), for the register-level model the control word carries them
	reg  [14:0] ma_l = 15'd0;
	reg   [2:0] xa_l = 3'd0;
	reg         awg_p = 1'b1;
	reg  [14:0] ma_p = 15'd0;
	reg   [2:0] xa_p = 3'd0;
	always @(posedge CLK) begin
		awg_p <= on ? x_awg : 1'b1;              // R73 pulls WR_AWG up while the ACEX is empty
		ma_p  <= x_ma[14:0];
		xa_p  <= x_xaoe ? x_xao : xa_in;
		if (~z_res_n) begin ma_l <= 15'd0; xa_l <= 3'd0; end
		else if (on & ~awg_p & x_awg) begin ma_l <= ma_p; xa_l <= xa_p; end
	end
	always @* begin int_l = ma_l[13]; nmi_l = ma_l[12]; end
	assign HDD_C     = ma_l[8:5];
	assign FDD_C     = ma_l[4:2];
	assign HD_A      = ma_l[11:9];
	assign WG_A      = ma_l[1:0];
	assign TURBO_LED = ma_l[14];
	assign TAPE_OUT  = xa_l[2];

	// ================= MAX
	reg  xacs_pulse = 1'b0;
	sp_max #(.XHD_RES_ON_HSYNC(XHD_RES_ON_HSYNC)) MAX(.CLK(CLK), .CE(ce), .CE_N(ce_n), .EPM_RES(EPM_RES_N),
		.PW_GOOD(PW_GOOD), .HDD_C(HDD_C), .FDD_C(FDD_C), .XACS(on ? (x_xacs & ~xacs_pulse) : 1'b1),
		.WR_CNF(~(wr_n | mr_n)), .D0(d_bus[0]), .CLK14(), .CLKZZ_O(max_clkzz), .CLKZZ_OE(max_clkzz_oe), .AUD(max_aud),
		.SINC_H(SINC_H), .SINC_V(SINC_V), .SINC(), .SINC_1(max_sinc1), .SINC_2(max_sinc2), .CONF_X_N(max_res_c),
		.K_CLK(max_kclk), .K_D0(max_kd0), .WR_PDOS(WR_PDOS), .WG_WR_N(WG_WR_N), .WG_RD_N(WG_RD_N),
		.CMOS_DWR(CMOS_DWR), .CMOS_AS(CMOS_AS), .CMOS_DRD(CMOS_DRD), .HD_DIR(), .HD_CS(), .XHD_RES(XHD_RES),
		.XHD_WR(XHD_WR), .XHD_RD(XHD_RD), .XHD1_CS(XHD1_CS), .XHD2_CS(XHD2_CS), .T320_O(T320));
	assign FDD_1440 = max_kd0;
	assign RD_KMPS  = on ? x_kmps : 1'b1;
	assign IORQ_N   = io_n;
	assign CPU_RES_N = z_res_n;

	// ================= CPU clock, /RESET, /WAIT
	// CLKZZ (XCT1 of the MAX) changes at CE and CE_N; sp_z84c15 wants a clock that changes at CE_N with its next
	// value: CLKZZ resampled at CE_N (the edge of CLKZZ at a CE moves to the next CE_N: high 2 CLK, low 4)
	reg  zz_r = 1'b0;
	always @(posedge CLK) if (ce_n) zz_r <= max_clkzz;
	assign zclk    = on ? x_clkz : zz_r;
	assign zclk_nx = on ? x_clkz_nx : max_clkzz;
	assign z_res_n = max_res_n & ~(on & x_res_oe);
	// memory of the empty ACEX: ROM by CS0, fastram by CS1 (the CPU pins), refresh excluded
	wire mreq_u  = ~mr_n & rf_n;
	wire u_rom   = mreq_u & cs0 & ~cs1;
	wire u_fast  = mreq_u & cs1;
	wire [7:0] s_q; wire s_rdy, s_wait_n;
	// /WAIT: the ACEX (when running) AND sp_sram (a ROM / fastram byte that would come late; the original has no such
	// wait, the SRAM was fast enough: a safety net, on 14 / 21 MHz it does not fire in the tests)
	assign z_wait_n = (on ? ~x_wait_oe : 1'b1) & s_wait_n;

	// ================= data buses (the line keeps its last value when nobody drives: the bus capacitance the ACEX
	// relies on at a strobe edge, docs of sp_acex). D0..D7 have pull-ups on the board (docs/machine.md 2): a CPU read
	// (/RD low) or INTA that nobody drives gives FF, as in MAME. BIOS 3.04 reads ALL_MODE back by IN #204E (code 00:
	// the ACEX does not drive D), clears bit 0 around its ZX screen output and writes the value read back: with the
	// last bus value (the opcode 78 of IN A,(C)) the accelerator went off and Flex Navigator drew one line of each
	// vertical fill / glyph (docs/memtiming.md 8).
	wire mem_rd = on ? ((~x_cs_rom | (~x_cs_cash & (x_ra[17:16] == 2'b01))) & ~rd_n) : ((u_rom | u_fast) & ~rd_n);
	wire d_pull = ~rd_n | (~m1_n & ~io_n);
	reg  [7:0] d_keep = 8'hFF;
	assign d_bus = cpu_doe ? cpu_do : (on & x_doe) ? x_do : mem_rd ? s_q : d_pull ? 8'hFF : d_keep;
	always @(posedge CLK) d_keep <= d_bus;
	wire [15:0] sd_q; wire [1:0] sd_drv;
	reg  [15:0] md_keep = 16'hFFFF;
	wire [15:0] md_per = PER_OE ? PER_D : md_keep;
	assign md_bus = (on & x_mdoe) ? x_mdo :
	                {sd_drv[1] ? sd_q[15:8] : md_per[15:8], sd_drv[0] ? sd_q[7:0] : md_per[7:0]};
	always @(posedge CLK) md_keep <= md_bus;
	assign MD = md_bus;

	// ================= XA multiplexer (SXA selects the half, it drives XA while RDXA is low)
	wire [3:0] mux_v = x_sxa ? {max_sinc2, max_sinc1, FDD_CH, FDD_W} : {MOUSE_D, TAPE_IN, KBD_DD, KBD_CC};
	reg  [2:0] xa_keep = 3'b111;
	assign xa_in = ~x_rdxa ? mux_v[2:0] : x_xaoe ? x_xao : xa_keep;
	assign xa3   = mux_v[3];
	always @(posedge CLK) xa_keep <= xa_in;

	// ================= memory controllers
	// while the ACEX is empty: a free-running CT phase (5 6 0 1 2 4) for the slot plan, no video requests
	reg  [2:0] ct_f = 3'd5;
	always @(posedge CLK) if (ce) case (ct_f)
		3'd5: ct_f <= 3'd6; 3'd6: ct_f <= 3'd0; 3'd0: ct_f <= 3'd1; 3'd1: ct_f <= 3'd2; 3'd2: ct_f <= 3'd4;
		default: ct_f <= 3'd5;
	endcase
	wire [2:0] m_ct = on ? x_ct : ct_f;
	sp_sram #(.SIM_X(SIM_X)) SRAM(.CLK(CLK), .CE(ce), .CE_N(ce_n), .CT(m_ct), .VA_NX(x_va_nx),
		.V_WR_NX(on ? x_vwr_nx : 4'hF), .VA_MOD(x_va_mod), .MODE_RQ(on & x_mode_rq), .MLO_RQ(on & x_mlo_rq),
		.VA_ATR(x_va_atr), .ATR_ZX(on & x_atr_zx), .PIX_RQ(on & x_pix_rq), .VD0_O(x_vd0o), .VD1_O(x_vd1o),
		.VD2_O(x_vd2o), .VD3_O(x_vd3o), .VA(x_va), .VD0_I(s_vd0), .VD1_I(s_vd1), .VD2_I(s_vd2), .VD3_I(s_vd3),
		.PAL_Q(PAL_Q), .A(a), .RA(on ? x_ra : {cs1 ? 2'b01 : 2'b11, a[15:14]}),
		.SEL_ROM(on ? x_sel_rom : cs0 & ~cs1), .SEL_CASH(on ? x_sel_cash : cs1), .RF_N(rf_n), .MR_N(mr_n),
		.WR_N(wr_n), .CS_CASH(on ? x_cs_cash : ~u_fast), .CPU_D(d_bus), .CPU_FLUSH(1'b0), .CPU_Q(s_q),
		.CPU_RDY(s_rdy), .CPU_WAIT_N(s_wait_n), .LD_REQ(LD_REQ), .LD_A(LD_A), .LD_BE(LD_BE), .LD_D(LD_D), .LD_ACK(LD_ACK), .WB_OVF(),
		.SRAM_A(SRAM_A), .SRAM_D_O(SRAM_D_O), .SRAM_D_T(SRAM_D_T), .SRAM_D_I(SRAM_D_I), .SRAM_WE_N(SRAM_WE_N),
		.SRAM_OE_N(SRAM_OE_N));
	wire sd_rdy;
	sp_sdram #(.INIT_WAIT(SD_INIT)) SDRAM(.CLK(CLK), .CE(ce), .CE_N(ce_n), .CT(m_ct), .RAS_N(x_ras[0]),
		.CAS_N(x_cas), .WE_N(x_we), .MA(x_ma[11:0]), .MCA(x_mca), .MD_O(x_mdo), .MD_Q(sd_q), .MD_DRV(sd_drv),
		.RDY(sd_rdy), .AUX_REQ(1'b0), .AUX_ACK(), .SD_CLK(SD_CLK), .SD_CKE(SD_CKE), .SD_CS_N(SD_CS_N),
		.SD_RAS_N(SD_RAS_N), .SD_CAS_N(SD_CAS_N), .SD_WE_N(SD_WE_N), .SD_BA(SD_BA), .SD_A(SD_A), .SD_DQM(SD_DQM),
		.SD_DQ_O(SD_DQ_O), .SD_DQ_T(SD_DQ_T), .SD_DQ_I(SD_DQ_I));
	assign WR_COL = x_wr_col;
	assign VA     = x_va;

	// ================= configuration receiver
	localparam [1:0] S_ERASED = 2'd0, S_LOAD = 2'd1, S_WAIT = 2'd2, S_ON = 2'd3;
	reg  [1:0] st = S_ERASED;
	reg [31:0] bits = 32'd0;
	reg [12:0] wn = 13'd0;                           // writes hashed (4096 = all)
	reg [31:0] hash = 32'd0;
	reg [16:0] nbytes = 17'd0;
	reg        kclk_p = 1'b0;
	reg  [1:0] xp = 2'd0;
	wire       k_rise = max_kclk & ~kclk_p;
	// personality table (docs/machine.md 3). Standard: the stock bitstreams of BIOS 2.12 ... 3.04 (ROM 0x30100 /
	// sprinter-bios/ALTERA) and the LDCONF streams 3.00 / 3.03 / 3.03a
	wire       h_known = (hash == 32'h75ecdfc7) | (hash == 32'he0b976fe) | (hash == 32'hd1993271) |
	                     (hash == 32'hce9a3671) | (hash == 32'hd0953276) | (hash == 32'hb051ab62) |
	                     (hash == 32'h78eddfc6) | (hash == 32'hb152a961);
	wire       h_scroll = hash == 32'h3861cfa4;
	// k30 (upstream/tt-sprinter-bios src/altera/acex/k30): 5aa954b6 = BIOS 3.05 / 3.06 EP1K30 (ROM 187f4382, df18c931,
	// 2d46deaf); ae54ab61 (MAME 3.05 fe1c2685), 49861031, fffc0208: other k30 builds
	wire       h_k30 = (hash == 32'h5aa954b6) | (hash == 32'hae54ab61) | (hash == 32'h49861031) | (hash == 32'hfffc0208);
	// FNV-1a: h = (h ^ d) * 01000193 (= 2^24 + 2^8 + 2^7 + 2^4 + 2^1 + 1), in two CLK after the write (writes are
	// ~100 CLK apart)
	reg [31:0] fnv = 32'h811c9dc5, fnv_x = 32'd0, fnv_s1 = 32'd0, fnv_s2 = 32'd0;
	reg  [1:0] fnv_st = 2'd0;
	always @(posedge CLK) begin
		kclk_p <= max_kclk;
		xacs_pulse <= 1'b0;
		if (xp != 2'd0) begin xacs_pulse <= 1'b1; xp <= xp - 2'd1; end
		if (~max_res_n) begin
			st <= S_ERASED;
			bits <= 32'd0; wn <= 13'd0; hash <= 32'd0; nbytes <= 17'd0;
			fnv <= 32'h811c9dc5; fnv_st <= 2'd0;
		end else case (st)
			S_ERASED: st <= S_LOAD;
			S_LOAD: begin
				if (k_rise & max_clkzz_oe) begin
					bits <= bits + 32'd1;
					if (bits < CFG_BITS) begin fnv_x <= fnv ^ {24'd0, d_bus}; fnv_st <= 2'd1; end
					if (bits[2:0] == 3'd7 & ~nbytes[16]) nbytes <= nbytes + 17'd1;
					if (~wn[12]) begin
						wn <= wn + 13'd1;
						case (wn[1:0])
							2'd0: hash <= hash + {24'd0, d_bus};
							2'd1: hash <= hash + {16'd0, d_bus, 8'd0};
							2'd2: hash <= hash + {8'd0, d_bus, 16'd0};
							default: hash <= hash + {d_bus, 24'd0};
						endcase
					end
				end
				if (bits >= CFG_BITS + CFG_INIT) st <= S_WAIT;
			end
			S_WAIT: if (cfg_done & sd_rdy & ce_n) begin   // the next edge (the first of the running ACEX) is a CE
				st <= S_ON;
				xp <= 2'd2;
				CFG_PERS <= h_k30 ? 2'd1 : (h_scroll & (csbr[3:0] == 4'd0)) ? 2'd2 : 2'd0;   // TODO: SCROLL personality
				CFG_UNKNOWN <= ~(h_known | h_scroll | h_k30);
			end
			default: ;
		endcase
		if (max_res_n) case (fnv_st)
			2'd1: begin
				fnv_s1 <= fnv_x + {fnv_x[30:0], 1'b0} + {fnv_x[27:0], 4'd0};
				fnv_s2 <= {fnv_x[24:0], 7'd0} + {fnv_x[23:0], 8'd0} + {fnv_x[7:0], 24'd0};
				fnv_st <= 2'd2;
			end
			2'd2: begin fnv <= fnv_s1 + fnv_s2; fnv_st <= 2'd0; end
			default: ;
		endcase
	end
	assign on        = st == S_ON;
	assign cfg_rst   = ~on;
	assign CFG_STATE = st;
	assign CFG_HASH  = hash;
	assign CFG_FNV   = fnv;
	assign CFG_BYTES = nbytes;
endmodule
