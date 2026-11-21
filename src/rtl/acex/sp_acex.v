// Sprinter ACEX: the top of the ACEX EP1K30 configuration 3.03a (BASE_303.TDF, UPDATE = 1, MODE = "SPRINTER",
// NMI_ON = "OFF", SCREEN_OFF = "NOT_USE"): port registers, ROM / cache / ISA select, data paths, DRAM strobes, the
// sync to the MAX, keyboard / mouse lines on the XA multiplexer, INT, Covox / CBL FIFO, AY and the I2S output, around
// the submodules DCP, VIDEO2, ACCELER, AY, KBD, MOUSE. Translated from the AHDL of Ivan Mak / Peters Plus,
// reconstruction of Tolik-Trek (github.com/Tolik-Trek/SP2000-ACEX). Rules: docs/translation.md; inventory:
// docs/ahdl.md 1.1. Comments "TDF:n" are lines of BASE_303.TDF.
//
// Clock: CLK (84 MHz on the board) with CE = the rising edge of the original CLK42 and CE_N = its falling edge; they
// alternate. Every register of the original is updated at CE or CE_N; registers on derived clocks update at the CE
// where their clock rises, computed from the clock's NEXT value (docs/translation.md rule 3): their CLK42 data are
// taken with the values after this CE, data that are themselves on derived clocks with the current ones.
//
// Z80 pins: the Z80 (Z84C15) strobes are inputs in two copies: the current value (M1_N ...) and the value they take
// right after this CE (M1_N_NX ...). In the core the T80 runs at CE_N (the CLK_Z80 edge) and its outputs go through a
// register loaded at CE: the T80 outputs are *_NX, the register is the pin. The pins (and A, D_I, the external data)
// must change only right after a CE; A and the Z80 data must not change at a CE where a strobe rises (the AHDL
// latches data on the strobe edges). From the two copies the top makes every strobe event itself (/IOWR, /IORD,
// /MR fall, /M1 | /MR fall, ... and the *_EV inputs of DCP / ACCELER).
//
// Bidirectional pins are split into _I (what the other drivers put on the line; when nobody drives, the line keeps its
// last value: the bus capacitance the original relies on at a strobe edge), _O and _OE: D, MD, VD0..3, XA[2:0];
// /RESET and /WAIT are open drain (RESET_N_OE / WAIT_N_OE pull the line low; RESET_N_I = the line without us).
//
// Memory interfaces (all as the original pins; the core puts its own controllers behind them):
// - DRAM: MA (row in phases 0-1, column 2-4, peripheral control word in 5-6, MA[14..12] = !TURBO, INT, NMI latched
//   by WR_AWG), RAS_, CAS_[3..0] (byte lanes: CAS_0 / _1 = MD[7..0] / [15..8] of bank MCA1 = 0, CAS_2 / _3 of bank 1;
//   all low with RAS_ high = CBR refresh), WE_N (late write: low from the CE_N after CAS_ to the end of RAS_),
//   MD_O / MD_OE (write data, also the data of port writes to the peripherals), MD_I (read data, peripheral data).
// - video RAM: VA (32-bit word), V_WR[3..0] per byte, VDx_O / VD_OE (write data), VDx_I (read data of the VA presented at
//   CE n, needed at CE n+2 and CE_N n+3, docs/memtiming.md); WR_COL = the palette strobe of the RGB DAC latch.
// - ROM / cache / ISA: CS_ROM, CS_CASH (active low, from the fall of /MR to its rise), RA[17..14] = 16 KB page,
//   data on D_I; XACS = flash write strobe (ROM_RG4).
// - I2S: DAC_BCK = CT2 (7 MHz), DAC_WS = CTH1, DAC_DATA (16 bits per channel, MSB first).
// - XA: SXA selects the half of the external multiplexer (0: KBD_CC, KBD_DD, TAPE_IN, MOUSE_D on XA0, XA1, XA2,
//   XA3; 1: FDD_W, FDD_CH, SINC_1, SINC_2), RDXA low = the multiplexer drives XA, latched at the rise of RDXA;
//   XA_O / XA_OE (CT2): TAPE_OUT on XA2 for the TM9 latch.
//
// Deviations from a literal translation:
// - LCELL / EXP delays removed (CAS_A, CASX_, RASX_, T_RDXA, WR_TM9, /WE_OUT, PDD ...). CAS_ and MA change at the
//   same CE here as in the netlist; the core's DRAM controller does not need the address set-up the LCELLs gave.
// - Dead logic not translated: KD / NEXT_K / KEY_D / KEY_WRITE / K_DATA (KBD_DX = GND, TDF:332-357), START_UP
//   (TDF:828, SVIDEO.start_up = VCC), SYS_ENA (TDF:550), FDD_CH / FDD_W (TDF:797-798, no reader), TEST_R
//   (TDF:917, DECODE.RA unused with UPDATE = 1), MS / KBD INT and the AY channel outputs, /HALT, XA3 output.
// - DECODE./RES is constant 1 (Quartus: stuck at VCC), so SINC_1 / SINC_2 / HOLD have no reset; HOLD powers up as
//   0x77 and the other registers with a preset as 1, as in the netlist ("registers with preset signals power up
//   high"). The reset of the core must go through /RESET.
// - Events computed from next values of the reset line are not made: a register on a derived clock whose clock edge
//   comes only from /RESET changing (CBL_WR through DFF(MC_WRITE | CAS) preset) is not clocked by that change.
// - ACC_DIR1 in the clear of the page-FD register (CBL_WR, TDF:1141) is taken as is (its next value is not computed):
//   it changes only at the end of an M1 cycle, when that term cannot fall.
//
// karabas: personality k30 (PERS_K30 = 1): the configuration of BIOS 3.05 / 3.06 (upstream/tt-sprinter-bios @ 085ef3c
// src/altera/acex/k30, SP2_ACEX.TDF; docs/versions.md). k30 is the author's 2.18 with its own changes and without the
// 3.00-3.03 ones; the lines that differ are muxed here ("K30:" in the comments), PERS_K30 = 0 is 3.03a bit for bit:
//   /RESET      Ctrl+Alt+Del not gated by ALL_MODE5            KEYS.ena      VCC (ZX matrix always)
//   KEYS.int_ena ALL_MODE0 & ALL_MODE3                         NMI_X         GND (NMI_ON = "OFF")
//   CAS_A       DECODE.CAS (no write hold)                    BLK_MR        combinational (LCELL)
//   /WE         DFFE(/WE_OUT | DECODE.RAS, CLK42, , /RESET)   DIR_PORT[4]   GND (SCREEN_OFF = "NOT_USE": no blanking)
//   DCP: PN5 not set by CNF7 (PN[7..6].clrn); VIDEO2: WR_PIC.d = MODE0[5] in the mode slot.
// PERS_K30 must change only while CFG_RST is high (the personality is chosen at a configuration load).
//
// karabas: personality SCROLL (PERS_SCROLL = 1): the Game Config of Ivan Mak (2002) for Thunder in the Deep
// (upstream/tt-scroll-cnf/src, SCROLL.TDF; docs/versions.md). Its top is the 2.18 one (+ DIR_PORT[4] = RGMOD2 of 3.00)
// with its own changes, without AY and mouse; DCP / ACCELER / KBD are those of 3.03a. Lines marked "SCROLL:":
//   as k30: /RESET (no ALL_MODE5), NMI_X = GND, CAS_A, /WE, BLK_MR      KEYS.ena  !ALL_MODE0 (2.18)
//   ZX_PORT[6] .. & ALL_MODE3 (3.03a: & !ALL_MODE0)                     AY/PORTS = FF, KEMPS = FF (no AY, no mouse)
//   AY_CHS = (VCC, CBL_R[15..1]) (no AY in the sound)                   DCP: MEM[EE] = 2041; VIDEO2: the scroll grid
// KEYS.int_ena, DIR_PORT[4] as 3.03a. PERS_SCROLL = 0 is 3.03a / k30 bit for bit; not both personalities at once;
// it changes only while CFG_RST is high.
module sp_acex (
	input             CLK,
	input             CE,           // CLK42 rising
	input             CE_N,         // CLK42 falling
	// Z80
	input             M1_N,
	input             RF_N,
	input             IO_N,
	input             WR_N,
	input             RD_N,
	input             MR_N,
	input             M1_N_NX,      // the pins after this CE
	input             RF_N_NX,
	input             IO_N_NX,
	input             WR_N_NX,
	input             RD_N_NX,
	input             MR_N_NX,
	input      [15:0] A,
	input       [7:0] D_I,
	output      [7:0] D_O,
	output            D_OE,
	output            CLKZ1,        // Z80 clock (DCP CLK_Z80, changes at CE_N)
	output            CLKZ1_NX,     // its value after this CE_N (the CPU enables: rise / fall of CLKZ1)
	output            WAIT_N_OE,    // pull /WAIT low
	input             RESET_N_I,    // the /RESET line without our drive
	output            RESET_N_OE,   // pull /RESET low
	// ROM / cache / ISA
	output            CS_ROM,
	output            CS_CASH,
	output    [17:14] RA,
	// video RAM
	output      [1:0] V_CS,
	output     [15:0] VA,
	output      [3:0] V_WR,
	input       [7:0] VD0_I,
	input       [7:0] VD1_I,
	input       [7:0] VD2_I,
	input       [7:0] VD3_I,
	output      [7:0] VD0_O,
	output      [7:0] VD1_O,
	output      [7:0] VD2_O,
	output      [7:0] VD3_O,
	output      [3:0] VD_OE,
	output            WR_COL,
	// sound
	output            DAC_DATA,
	output            DAC_WS,
	output            DAC_BCK,
	// DRAM
	input      [15:0] MD_I,
	output     [15:0] MD_O,
	output            MD_OE,
	output     [14:0] MA,
	output      [1:0] RAS_,
	output      [3:0] CAS_,
	output            WE_N,
	// MAX / board
	output            XACS,
	input       [2:0] XA_I,
	output      [2:0] XA_O,
	output            XA_OE,
	input             XA3,
	output            SXA,
	output            RDXA,
	output            WR_AWG,
	output            RD_KMPS,
	output            WR_DWG,
	// karabas: early signals for the memory controllers (docs/memtiming.md 5; outputs only)
	output      [2:0] CT_PH,        // CT[2..0] (0 1 2 4 5 6): the phase of the 7 MHz memory cycle
	output     [17:1] VA_NX,        // VIDEO2: the next VA (byte address), stable at the CE_N before the CE that loads it
	output      [3:0] V_WR_NX,      // VIDEO2: V_WR of the next write slot (c0..c1), stable c10..c11
	output     [15:0] VA_MOD,       // VIDEO2: mode table word of this cycle
	output            MODE_RQ,      // VIDEO2: MODE0..2 load at c12 of this cycle
	output            MLO_RQ,       // VIDEO2: byte 0 of the mode word may be taken at c14
	output     [17:1] VA_ATR,       // VIDEO2: ZX attribute address (when ATR_ZX)
	output            ATR_ZX,       // VIDEO2: MODE0[4]
	output            PIX_RQ,       // VIDEO2: the pixel byte is taken at c8
	output            MODE_FIX,     // VIDEO2: SCROLL sync jump, the mode table halves again
	output      [1:0] MCA,          // DCP: A[1..0] of the DRAM access, from c2 to c12 (MCA1 = DRAM bank)
	output            SEL_ROM,      // the current A / RA select the ROM (PRE_ROM / PRE_CASH, before /MR falls)
	output            SEL_CASH,     // ... the cache (fastram)
	// karabas: configuration reset (docs/machine.md). In the original every reset of the MAX erases the ACEX and the
	// CPU loads the bitstream again: all registers and RAMs start from the configuration. Here CFG_RST (synchronous,
	// any length) holds every register of the ACEX and its submodules at its power-up value and reloads the RAMs the
	// logic or the CPU write (DCP MEM, KBD, AY from their MIF; the ACCELER line buffer and the CBL FIFO zero-filled);
	// CFG_DONE = the reloads have finished (CFG_RST high for at least 260 CLK). Release CFG_RST so that the next edge
	// is a CE (as at power-up). Use only in if (CFG_RST): an unconnected port (old testbenches) reads as off.
	input             CFG_RST,
	output reg        CFG_DONE = 1'b0,
	input             PERS_K30,     // karabas: 1 = the k30 configuration (BIOS 3.05 / 3.06), 0 = 3.03a; see above
	input             PERS_SCROLL   // karabas: 1 = the SCROLL configuration (Thunder in the Deep); see above
);
	parameter MIF_DCP = "dcp.hex";
	parameter MIF_AY  = "ay.hex";
	parameter MIF_KBD = "kbd_ini2.hex";

	// ================= submodule outputs
	wire  [5:0] ct, cth, ct_nxr, cth_nxr; wire [8:0] ctv; wire [6:0] ctf;
	wire        v_blank, intt, intt_nx, wr_pix;
	wire [15:0] vao; wire [7:0] vdo0, vdo1, vdo2, vdo3; wire [3:0] v_wr, v_wen; wire [1:0] v_cs;

	wire        dc_ras, dc_cas, mc_end, mc_begin, mc_type, mc_write, clk_z80, turbo, dc_wait_n, iom_n, iomm_n;
	wire  [7:0] dc_do, dcpp; wire [11:0] dc_ma, page; wire [1:0] mca; wire [3:0] type_;
	wire        dc_ram, blk_r, pn4q, v_ram, wr_dwg, wr_awg, hdd_data, hdd_flip, sp_scr, sp_sa, scr128;
	wire  [9:0] ga;
	wire        iomm_n_nx, iom_n_nx, ras_nx, mc_type_nx, clk_z80_nx, hdd_data_nx; wire [3:0] type_nx;

	wire        acc_cont, acc_gliss, acc_on, dcas, acc_blk;
	wire [15:0] acc_ao, acc_mdo; wire [7:0] acc_do, acc_gline, acc_dir;

	wire  [7:0] ay_do; wire [9:0] ay_l, ay_r;
	wire  [7:0] kbo; wire kb_reset, kb_f12, kb_ctrl, kb_alt, kb_sh, k_int;
	wire        kb_f12_nx, kb_ctrl_nx, kb_alt_nx, kb_sh_nx, k_int_qnx;
	wire  [9:0] ms_x, ms_y; wire [1:0] ms_k;

	// ================= buses (TDF:422-431): the pin = our driver when enabled, else the line
	wire  [7:0] d_bus  = D_OE ? D_O : D_I;
	wire [15:0] md_bus = MD_OE ? MD_O : MD_I;
	wire  [7:0] vd0 = VD_OE[0] ? VD0_O : VD0_I, vd1 = VD_OE[1] ? VD1_O : VD1_I;
	wire  [7:0] vd2 = VD_OE[2] ? VD2_O : VD2_I, vd3 = VD_OE[3] ? VD3_O : VD3_I;
	wire  [2:0] xa = XA_OE ? XA_O : XA_I;
	wire        reset_n = RESET_N_I & ~RESET_N_OE;

	// ================= registers of the top
	reg        rst_q = 1'b0;                 // TDF:300 DFF of the /RESET drive
	reg        iowr_q = 1'b1, iord_q = 1'b1; // TDF:314-315, prn = !/IO
	reg  [7:0] border = 8'd0;
	reg        bord_en = 1'b0;
	reg        kclk_q = 1'b0;                // KEYS.clk_k = MS.clk = DFF(CTH5)
	reg        key_io = 1'b0, keys_rf = 1'b0;
	reg        ts_q = 1'b1;                  // TEST_SWITCH = TFF(.., KB_F12, , /RESET): prn (TDF:526)
	reg  [7:0] mdp = 8'd0, hddr = 8'd0;
	reg        hsel_q = 1'b0;                // DFF(/WR, DECODE.RAS)
	reg        sys_ena2 = 1'b0;
	reg  [7:0] isa_port = 8'd0; reg isa_en = 1'b0;
	reg        sr_s1 = 1'b0, sr_s2 = 1'b0;   // SOFT_RES[].prn chain (TDF:567)
	reg  [1:0] soft_q = 2'd3;                // SOFT_RES, prn
	reg        sys_n_q = 1'b0, sys_pg_q = 1'b0;
	reg        a20_en = 1'b0;
	reg        cash_q = 1'b0, cash_en = 1'b0;
	reg  [2:0] wt_r = 3'd0; reg wz_q = 1'b0;
	reg        cs_isa_q = 1'b1, cs_romt_q = 1'b1, cs_casht_q = 1'b1;
	reg        xacs_q = 1'b1;
	reg  [7:0] rom_rg = 8'd0; reg rom_en = 1'b0, rom5c_en = 1'b0;
	reg        mctd_q = 1'b0;                // DFF(DECODE.MC_TYPE) of WR_PORT
	reg        ix_q = 1'b1, i1_q = 1'b0, i2_q = 1'b0;   // INT_X
	reg        rdxa_q = 1'b0, sxa_q = 1'b0;
	reg        kbd_cc = 1'b0, kbd_dd = 1'b0, tape_in = 1'b0, mouse_d = 1'b0, sinc_1 = 1'b0, sinc_2 = 1'b0;
	reg  [8:0] sinc_hold = 9'd0;
	reg        s1m_q = 1'b0, s1md_q = 1'b0, copyh_q = 1'b0, s2m_q = 1'b0, s2md_q = 1'b0, copyv_q = 1'b0;
	reg  [7:0] hold = 8'h77;                 // HOLD[2..0], [6..4] with prn: power up high
	reg        hold_en = 1'b0;
	reg        dos_q = 1'b1;                 // prn = /RESET
	reg        cwh_q = 1'b0;                 // CAS_WRITE_HOLD
	reg        dw_q = 1'b0;                  // DRAM_WRITE (!CLK42)
	reg        blk_mr_q = 1'b0;              // BLK_MR (3.03a: DFF on CLK42)
	reg        we_q = 1'b1;                  // K30: /WE = DFFE(/WE_OUT or DECODE.RAS, CLK42, , /RESET): prn
	reg  [7:0] rgmod = 8'd0; reg rgmod_en = 1'b0;
	reg        svwr_q = 1'b1;                // SVIDEO.wr (!CLK42), prn = /RESET
	reg  [7:0] all_mode = 8'hFF; reg am_en = 1'b0;
	reg        dac1_q = 1'b0, dac_q = 1'b0, ws_q = 1'b0, bck_q = 1'b0, audio_ch = 1'b0;
	reg [15:0] audio_r = 16'd0;
	reg  [7:0] cbl_xx = 8'd0; reg cbl_en = 1'b0;
	reg  [4:0] cbl_ctx = 5'd0;
	reg  [7:0] cbl_cnt = 8'd0;
	reg        cint_q = 1'b1;                // CBL_INT, prn
	reg        c88_q = 1'b0, pfd_q = 1'b0, mcwc_q = 1'b1;
	reg        w_q = 1'b1;                   // DFF(!CBL_WAE, !CBL_WR, , CBL_INT)
	reg  [7:0] cbl_wa = 8'd0, cbd = 8'd0;
	reg [15:0] cbl_r = 16'h8000; reg cblr_en = 1'b0;
	reg        a90_q = 1'b0, a91_q = 1'b0, aya_q = 1'b0, ayd_q = 1'b0;
	reg        cth0d_q = 1'b0, ayc_q = 1'b0;
	reg [15:0] ay_chs = 16'd0;

	// ================= Z80 strobe events (high at the CE after which the edge happens)
	wire iowr_e   = IO_N | iowr_q;           // /IOWR = DFF((/WR or /IO), CLK42, , !/IO)
	wire iowr_nx  = IO_N_NX | IO_N | WR_N;
	wire iowr_ev  = ~iowr_e & iowr_nx;
	wire iord_e   = IO_N | iord_q;
	wire iord_nx  = IO_N_NX | IO_N | RD_N;
	wire iord_ev  = ~iord_e & iord_nx;
	wire mr_fall  = MR_N & ~MR_N_NX;
	wire mr_rise  = ~MR_N & MR_N_NX;
	wire m1_rise  = ~M1_N & M1_N_NX;
	wire io_fall  = IO_N & ~IO_N_NX;
	wire wrmr_rise = ~(WR_N | MR_N) & (WR_N_NX | MR_N_NX);       // clock of the SOFT_RES start (TDF:567)
	wire wrmr_fall = (WR_N | MR_N) & ~(WR_N_NX | MR_N_NX);       // XACS clock (TDF:624)
	wire m1mr_fall = (M1_N | MR_N) & ~(M1_N_NX | MR_N_NX);       // DOS clock (TDF:844)
	wire dcp_iowr_ev  = ~(IO_N | WR_N | ~M1_N) & (IO_N_NX | WR_N_NX | ~M1_N_NX);
	wire dcp_iorel_ev = ~(IO_N | ~M1_N) & (IO_N_NX | ~M1_N_NX);

	// ================= video counters as clocks: next effective values (COPY_SINC_H forces CT5 = 0, CTH = 50)
	wire       copyh_d = ~s1m_q & s1md_q;
	wire       copyv_d = ~s2m_q & s2md_q;
	wire [5:0] ct_nx  = {copyh_d ? 1'b0 : ct_nxr[5], ct_nxr[4:0]};
	wire [5:0] cth_nx = copyh_d ? 6'd50 : cth_nxr;
	wire       ct2_rise  = ~ct[2] & ct_nx[2];
	wire       ct2_fall  = ct[2] & ~ct_nx[2];
	wire       ct4_rise  = ~ct[4] & ct_nx[4];
	wire       ct4_fall  = ct[4] & ~ct_nx[4];
	wire       cth1_fall = cth[1] & ~cth_nx[1];
	wire       cth2_rise = ~cth[2] & cth_nx[2];
	wire       cth5_rise = ~cth[5] & cth_nx[5];
	wire       clk_k_ev  = ~kclk_q & cth[5];

	// ================= port enables: DFF(DCPP == ..) (TDF:318, 559, 577, 642, 831, 967, 1058, 1095, 1140, 1194)
	wire bord_en_d  = (dcpp[7:4] == 4'hC) & (dcpp[2:0] == 3'b010);   // C2 / CA
	wire isa_en_d   = dcpp[7:4] == 4'hF;
	wire a20_en_d   = dcpp == 8'h1B;
	wire rom_en_d   = dcpp == 8'h8F;
	wire hold_en_d  = dcpp == 8'hCB;
	wire rgmod_en_d = (dcpp[7:4] == 4'hC) & (dcpp[2:0] == 3'b101);   // C5 / CD
	wire am_en_d    = dcpp == 8'hC3;
	wire cbl_en_d   = dcpp == 8'h89;
	wire c88_d      = dcpp == 8'h88;
	wire sys_ena2_d = (A[7] == 1'b0) & (A[5:0] == 6'b111100);         // 3C / 7C
	wire cash_en_d  = A[6:0] == 7'b1111011;                            // 7B / FB
	wire rom5c_d    = A[7:0] == 8'h5C;

	wire p218 = PERS_K30 | PERS_SCROLL;   // the 2.18 forms of k30 and SCROLL (/RESET, NMI_X, CAS_A, /WE, BLK_MR)

	// ================= effective values of the registers with asynchronous inputs
	wire [7:0] all_mode_e = reset_n ? all_mode : 8'hFF;               // prn = /RESET
	wire       kint_ena   = all_mode_e[0] & (~PERS_K30 | all_mode_e[3]); // KEYS.int_ena (K30: ALL_MODE0 & ALL_MODE3)
	wire [7:0] rom_rg_e   = reset_n ? rom_rg : 8'd0;
	wire [7:0] rgmod_e    = reset_n ? rgmod : 8'd0;
	wire       sys_n_e    = reset_n & sys_n_q;                         // /SYS
	wire       sys_pg_e   = reset_n & (rom_rg_e[4] | sys_pg_q);        // clrn = /RESET (wins), prn = !ROM_RG4
	wire       cash_on    = reset_n & cash_q;
	wire       ts_e       = ~reset_n | ts_q;
	wire       dos_e      = ~reset_n | dos_q;
	wire       sr_s2_e    = reset_n & sr_s2;
	wire [1:0] soft_e     = sr_s2_e ? 2'd3 : soft_q;                   // SOFT_RES[].prn = !DFF(..)
	wire       soft_reset = soft_e == 2'd0;
	wire       rst_d      = (kb_reset | (~p218 & ~all_mode_e[5])) & soft_reset;   // TDF:300 (K30, SCROLL: no ALL_MODE5 gate)
	wire       kena       = PERS_K30 | (PERS_SCROLL ? ~all_mode_e[0] : all_mode_e[1]);   // KEYS.ena (K30: VCC, SCROLL: !ALL_MODE0)
	wire       cs_isa     = MR_N | cs_isa_q;                           // prn = LCELL(Q or !/MR)
	wire       cs_romt    = MR_N | cs_romt_q;
	wire       cs_casht   = MR_N | cs_casht_q;
	wire       xacs_set   = ~xacs_q & (MR_N | ~rom_rg_e[4]);            // XACS.prn = XACS or (!/MR & ROM_RG4)
	wire       xacs_e     = xacs_q | xacs_set;
	wire       svwr_e     = ~reset_n | svwr_q;
	wire       mcwc_e     = ~reset_n | mcwc_q;

	// ================= keyboard (TDF:323-330, 526-536)
	wire ts_t = ~kb_sh_nx & ~kb_ctrl_nx & ~kb_alt_nx;
	wire f12_rise = ~kb_f12 & kb_f12_nx;

	// ================= ROM / cache / ISA (TDF:550-644)
	wire wait_orig = MR_N | ct[5] | all_mode_e[2] | ((~(v_ram & A[14] & A[15]) & ~(A[14] & ~A[15])) | turbo);
	wire pre_isa  = ~(isa_port[7:4] == 4'b1101) | ~blk_r | ~A[14] | ~A[15];
	wire pre_rom  = sys_n_e | A[14] | A[15] | cash_on;
	wire pre_cash = A[14] | A[15] | ~cash_on;
	wire isa_a20  = iowr_e | ~a20_en;
	wire wait_romx = cs_romt & cs_isa;
	wire wz_e     = ~wait_romx & wz_q;       // clrn = !WAIT_ROMX
	wire wait_rom = wait_romx | wz_e;
	reg  [3:0] isa_a;
	always @* case ({pre_rom, pre_cash})
		2'b00: isa_a = 4'b1000;                                   // error -> ISA
		2'b01: isa_a = {rom_rg_e[3] ^ ~sys_pg_e, rom_rg_e[2:0]};   // ROM
		2'b10: isa_a = {2'b01, rom_rg_e[1:0]};                     // cache
		default: isa_a = {~pre_isa, 1'b0, isa_port[2:1]};          // ISA
	endcase
	wire blk_mem  = ~pre_rom | ~pre_cash | ~pre_isa;
	wire rd_ram   = ~(MR_N | RD_N | blk_mem);
	wire blk_mwr2 = dc_ram | blk_mem;

	// ================= data paths (TDF:363-431)
	wire [7:0] kemps = PERS_SCROLL ? 8'hFF :                                 // SCROLL: no mouse, KEMPS = FF
	                   ({A[10], A[8]} == 2'b01) ? ms_x[7:0] : ({A[10], A[8]} == 2'b11) ? ~ms_y[7:0] :
	                   {6'b111111, ~ms_k[0], ~ms_k[1]};
	wire       cbl_mode = cbl_xx[7], cbl_stereo = cbl_xx[6], cbl_mode16 = cbl_xx[5], cbl_int_ena = cbl_xx[4];
	wire [7:0] cbl_cnt_e = cbl_mode ? cbl_cnt : 8'd0;                 // clrn = CBL_MODE
	wire [7:0] cbl_wa_e;
	wire       cbl_ind = cbl_cnt_e[7] ^ cbl_wa_e[7];
	wire [7:0] key_kems = type_[0] ? kemps :
	                      {(kbo[5] & ~cbl_mode) | (cbl_ind & cbl_mode), tape_in, cbl_mode & ctv[8], kbo[4:0]};
	wire [7:0] ay_ports = type_[0] ? (PERS_SCROLL ? 8'hFF : ay_do) : dc_do;   // SCROLL: no AY, AY/PORTS = FF
	reg  [7:0] pdd;
	always @* case (type_[2:1])
		2'b11: pdd = mdp;
		2'b10: pdd = key_kems;
		2'b01: pdd = ay_ports;
		default: pdd = 8'hFF;
	endcase
	assign D_O  = IO_N ? acc_do : pdd;
	assign D_OE = ~(iord_e | (dcpp[7:4] == 4'h0) | (dcpp[7:4] == 4'h3)) | rd_ram;

	// MDP clocked by DECODE./IOMM (data: DCP CLK42 registers with their next values)
	wire       mdp_ev  = ~iomm_n & iomm_n_nx;
	wire [7:0] mdp_d   = type_nx[0] ? md_bus[15:8] : (hdd_flip & hdd_data_nx) ? hddr : md_bus[7:0];
	// HDDR clocked by LCELL(/WR & (/RD or DECODE./IOMM)), enable HDD_DATA & !DECODE./IOM
	wire       hclk    = WR_N & (RD_N | iomm_n);
	wire       hclk_nx = WR_N_NX & (RD_N_NX | iomm_n_nx);
	wire       hddr_ev = ~hclk & hclk_nx & hdd_data_nx & ~iom_n_nx;
	wire       ras_rise = ~dc_ras & ras_nx;

	// ================= DRAM strobes (TDF:858-898)
	wire video_pg = page[7:4] == 4'b0101;
	wire blk_mr_d = video_pg & (page[2] | (page[3] & acc_gliss));
	wire blk_mr = p218 ? blk_mr_d : blk_mr_q;                         // K30, SCROLL: BLK_MR = LCELL(..)
	wire we_out = mc_write | blk_mr | blk_mwr2;                      // /WE_OUT
	wire cas_a  = p218 ? dc_cas : dc_cas | cwh_q;                    // K30, SCROLL: CAS_A = LCELL(DECODE.CAS)
	wire casxe0 = ~mca[0] | dcas, casxe1 = mca[0] | dcas;
	assign CAS_ = {cas_a | ~((mca[1] & casxe1) | mc_type), cas_a | ~((mca[1] & casxe0) | mc_type),
	               cas_a | ~((~mca[1] & casxe1) | mc_type), cas_a | ~((~mca[1] & casxe0) | mc_type)};
	assign RAS_ = {dc_ras, dc_ras};
	wire dw_clr = we_out | dc_ras;                                    // DRAM_WRITE.clrn = !/WE_OUT & !RAS
	wire dw_e   = ~dw_clr & dw_q;
	wire we_e   = ~reset_n | we_q;
	assign WE_N = p218 ? we_e : ~dw_e;                                // K30, SCROLL: DFFE(.., CLK42, , /RESET)
	wire wr_port = ~(IO_N | WR_N) & mctd_q;
	assign MD_O  = acc_mdo;                                           // DMDX = ACC.MDO[7..0]
	assign MD_OE = ~we_out | wr_port;

	// DOUBLE_CAS = ACC_DIR6 & !START_ACC (ACCELER:237): its next value, for the HDD_FLIP clear in DCP. ACC_DIR and
	// ACC_BLK change only at a /MR or /M1 rise, where START_ACC is 1 before and after.
	wire start_nx = MR_N_NX | ~M1_N_NX | ~RF_N_NX | ~acc_blk | ~acc_dir[0] | mc_type_nx;
	wire dcas_fall = dcas & ~(acc_dir[6] & ~start_nx);

	// ================= INT_X (TDF:751): falls at the rise of INTT & KEYS.int; preset by INTA or 2 periods of CTH2
	wire ix_set  = ~((IO_N | M1_N) & i2_q);
	wire ix_e    = ix_set | ix_q;
	wire cint_set = ~(cbl_int_ena & (IO_N | M1_N));                  // CBL_INT.prn
	wire cint_e  = cint_set | cint_q;
	wire int_x   = ~ix_e | ~cint_e;
	wire nmi_x   = ~p218 & ~all_mode_e[4] & kb_alt & ~kb_f12;        // K30, SCROLL: NMI_X = GND (NMI_ON = "OFF")
	wire [7:0] all_mode_nx = ~reset_n ? 8'hFF : (iowr_ev & am_en_d) ? d_bus : all_mode;
	wire iclk    = intt & k_int;
	wire iclk_nx = intt_nx & (~(all_mode_nx[0] & (~PERS_K30 | all_mode_nx[3])) | k_int_qnx);   // KEYS.int_ena next
	wire ix_ev   = ~iclk & iclk_nx;

	// ================= XA multiplexer, sync to the MAX (TDF:766-837)
	wire rdxa_d  = ~((ct[2:1] == 2'b11) | (ct[2:0] == 3'd0));
	wire rdxa_ev = ~rdxa_q & rdxa_d;
	wire sxa_d   = ct[3] ^ ct[2];
	assign XA_O  = {border[3], 1'b0, 1'b0};                           // TAPE_OUT, KBD_DX = GND, KBD_CX = GND
	assign XA_OE = ct[2];                                             // WR_TM9 = LCELL(CT2)
	wire s1m_d   = ~(sinc_hold[3:0] == 4'hF);
	wire s2m_d   = ~(sinc_hold[8:5] == 4'hF);

	// ================= sound (TDF:1066-1222)
	wire [10:0] ay_full_d = PERS_SCROLL ? 11'd0 :                     // SCROLL: AY_CHS = (VCC, CBL_R[15..1])
	                        cth0d_q ? {ay_r, 1'b0} : {ay_l, 1'b0};
	wire        ayc_d     = cth[1] & (cth[0] | ~ct[5]);
	wire        ay_chs_ev = ayc_q & ~ayc_d;                           // AY_CHS[].clk = !DFF(..)
	wire        audio_en  = ~ct[2] & bck_q;                           // !CT2 & DFF(CT2)
	wire [15:0] audio_r_d = audio_ch ? ay_chs : {audio_r[14:0], 1'b0};
	wire [15:0] audio_r_nx = audio_en ? audio_r_d : audio_r;

	// CBL / Covox (TDF:1087-1185)
	reg  [4:0] cbl_tab;
	always @* case (cbl_xx[3:0])
		4'd0: cbl_tab = 5'd13; 4'd1: cbl_tab = 5'd9;
		4'd8: cbl_tab = 5'd27; 4'd9: cbl_tab = 5'd19; 4'd10: cbl_tab = 5'd13; 4'd11: cbl_tab = 5'd9;
		4'd12: cbl_tab = 5'd6; 4'd13: cbl_tab = 5'd4; 4'd14: cbl_tab = 5'd3; 4'd15: cbl_tab = 5'd1;
		default: cbl_tab = 5'd0;
	endcase
	wire [7:0] cbl_xx_nx = (iowr_ev & cbl_en_d) ? d_bus : cbl_xx;
	wire [7:0] cbl_cnt_r = ~cbl_mode ? 8'd0 :
	                       ~cth1_fall ? cbl_cnt :
	                       (cbl_ctx != 5'd0) ? cbl_cnt :
	                       cbl_stereo ? cbl_cnt + 8'd2 : cbl_cnt + 8'd1;    // the register after this CE
	wire [7:0] cbl_cnt_nx = cbl_xx_nx[7] ? cbl_cnt_r : 8'd0;
	wire       cint_ev = cbl_cnt_e[6] & ~cbl_cnt_nx[6];                  // !CBL_CNT6 rises
	wire       pfd_clr = ~(cbl_int_ena & acc_dir[1]);
	wire       pfd_e   = ~pfd_clr & pfd_q;
	wire       pfd_d   = page[7:0] == 8'hFD;
	wire       cbl_wr  = (c88_q & ~iowr_e) | (pfd_e & ~mcwc_e);
	wire       pfd_nx  = ~(cbl_xx_nx[4] & acc_dir[1]) ? 1'b0 : pfd_d;
	wire       cbl_wr_nx = (c88_d & ~iowr_nx) | (pfd_nx & ~(~reset_n | mc_write | dc_cas));
	wire       cblwr_fall = cbl_wr & ~cbl_wr_nx;                         // !CBL_WR rises
	wire       w_e     = ~cint_e | w_q;                                  // prn = CBL_INT
	wire       cbl_wae = cbl_mode16 & w_e;
	wire       wa7_clr = ~(cbl_mode & cbl_int_ena & (cint_e | ~cbl_cnt_e[7]));
	wire       wa7_set = ~(cint_e | cbl_cnt_e[7]);
	wire       wa_clr  = ~(cbl_mode & cbl_int_ena & cint_e);
	assign     cbl_wa_e = {wa7_clr ? 1'b0 : wa7_set ? 1'b1 : cbl_wa[7], wa_clr ? 7'd0 : cbl_wa[6:0]};
	wire [7:0] cbl_wa_d = cbl_wa_e + 8'd1;
	wire [7:0] cbd_e   = cbl_mode16 ? cbd : 8'd0;
	// CBL: lpm_ram_dp 256 x 16, all inputs and the output registered on CLK42; read-first in a write to the address
	// being read (the netlist M9K, mixed ports "dont_care")
	reg [15:0] cbl_mem [0:255];
	reg [15:0] cbl_arr = 16'd0, cbl_q = 16'd0;
	integer i;
	initial for (i = 0; i < 256; i = i + 1) cbl_mem[i] = 16'd0;
	wire       cbl_wren  = cbl_wr & ~cbl_wae;
	reg  [8:0] rl_a = 9'd0;                  // CFG_RST: the CBL FIFO zero-fill and the CFG_DONE count
	reg  [7:0] rl_wa = 8'd0;
	reg        rl_we = 1'b0;
	wire       cbl_mwe  = rl_we | (CE & cbl_wren);
	wire [7:0] cbl_mwa  = rl_we ? rl_wa : cbl_wadr;
	wire [15:0] cbl_mwd = rl_we ? 16'd0 : cbl_data;
	wire [7:0] cbl_wadr  = (~A[15:8] & {8{~cbl_int_ena}}) ^ cbl_wa_e;
	wire [15:0] cbl_data = {acc_mdo[15] ^ cbl_mode16, acc_mdo[14:8], cbd_e};
	wire [7:0] cbl_radr  = {cbl_cnt_e[7:1], (cbl_cnt_e[0] & ~cbl_stereo) | (audio_ch & cbl_stereo)};
	wire [15:0] cbl_r_nx = ~reset_n ? 16'h8000 : cblr_en ? (cbl_mode ? cbl_q : {d_bus, 8'h00}) : cbl_r;
	wire [11:0] ay_sum   = {1'b0, ay_full_d} + {1'b1, cbl_r_nx[15:5]};

	// AY strobes (TDF:1194-1195)
	wire aya_d = iom_n | WR_N | ~a90_q;
	wire ayd_d = iom_n | WR_N | ~a91_q;

	// ================= video (TDF:978-1045)
	wire gliss    = acc_gliss & page[3] & video_pg;
	// ZX_PORT[6]: the ZX screen copy into the video RAM; SCROLL: enabled by ALL_MODE3 (3.03a: disabled by ALL_MODE0)
	wire zx_wen   = sp_scr & ~(A[13] & ~acc_gline[7]) & ~acc_gline[6] & (PERS_SCROLL ? all_mode_e[3] : ~all_mode_e[0]);

	// ================= registers
	always @(posedge CLK) begin
		if (CE) begin
			rst_q   <= rst_d;
			iowr_q  <= IO_N | WR_N;
			iord_q  <= IO_N | RD_N;
			bord_en <= bord_en_d;
			if (iowr_ev & bord_en_d) border <= d_bus;

			kclk_q <= cth[5];
			if (ct[1] & ct[2]) key_io <= IO_N | ~M1_N;
			if (ct[0]) keys_rf <= ct[2] | ~key_io;
			ts_q <= ~reset_n ? 1'b1 : (f12_rise & ts_t) ? ~ts_q : ts_q;

			if (mdp_ev) mdp <= mdp_d;
			if (ras_rise) hsel_q <= WR_N;
			if (hddr_ev) hddr <= hsel_q ? md_bus[15:8] : d_bus;

			sys_ena2 <= sys_ena2_d;
			isa_en <= isa_en_d;
			if (iowr_ev & blk_r & isa_en_d) isa_port <= d_bus;

			// SOFT_RES (TDF:304-310, 567)
			sr_s1 <= blk_r & A[14] & A[15] & (page[7:4] == 4'hA);
			sr_s2 <= ~reset_n ? 1'b0 : wrmr_rise ? (blk_r & A[14] & A[15] & (page[7:4] == 4'hA)) : sr_s2;
			if (sr_s2_e) soft_q <= 2'd3;
			else if (ct4_fall) soft_q <= (soft_q == 2'd3) ? 2'd2 : (soft_q == 2'd2) ? 2'd1 : 2'd0;

			sys_n_q  <= ~reset_n ? 1'b0 : (iowr_ev & sys_ena2_d) ? ~A[6] : sys_n_q;
			sys_pg_q <= ~reset_n ? 1'b0 : rom_rg_e[4] ? 1'b1 : (iowr_ev & sys_ena2_d & ~d_bus[1]) ? d_bus[0] : sys_pg_q;
			a20_en   <= a20_en_d;
			cash_en  <= cash_en_d;
			cash_q   <= ~reset_n ? 1'b0 : (iord_ev & cash_en_d) ? A[7] : cash_q;

			wt_r <= wait_romx ? 3'd4 : (wt_r == 3'd0) ? 3'd0 : wt_r - 3'd1;
			wz_q <= wait_romx ? 1'b0 : wt_r == 3'd0;
			cs_isa_q   <= mr_fall ? (~RF_N | pre_isa) : cs_isa;
			cs_romt_q  <= mr_fall ? (~RF_N | pre_rom | ~pre_cash) : cs_romt;
			cs_casht_q <= mr_fall ? (~RF_N | ~pre_rom | pre_cash) : cs_casht;
			xacs_q <= xacs_set ? 1'b1 : wrmr_fall ? (~rom_rg_e[4] | A[14] | A[15]) : xacs_q;

			rom_en <= rom_en_d;
			rom5c_en <= rom5c_d;
			rom_rg <= ~reset_n ? 8'd0 : (iowr_ev & (rom_en_d | (~sys_n_e & rom5c_d))) ? d_bus : rom_rg;

			mctd_q <= mc_type;

			// INT_X
			ix_q <= ix_set ? 1'b1 : ix_ev ? 1'b0 : ix_q;
			if (cth2_rise) begin i1_q <= ~int_x; i2_q <= i1_q; end

			// XA (TDF:766-800)
			rdxa_q <= rdxa_d;
			sxa_q  <= sxa_d;
			if (rdxa_ev) begin
				if (~sxa_d) begin kbd_dd <= xa[1]; kbd_cc <= xa[0]; tape_in <= xa[2]; mouse_d <= XA3; end
				else begin sinc_1 <= xa[2]; sinc_2 <= XA3; end
			end
			if (ct4_rise) sinc_hold[3:0] <= sinc_1 ? hold[3:0] : (sinc_hold[3:0] + 4'd1) | {4{~s1m_d}};
			if (cth5_rise) sinc_hold[8:4] <= sinc_2 ? {hold[7:4], 1'b0} : (sinc_hold[8:4] + 5'd1) | {5{~s2m_d}};
			s1m_q <= s1m_d; s1md_q <= s1m_q; copyh_q <= copyh_d;
			s2m_q <= s2m_d; s2md_q <= s2m_q; copyv_q <= copyv_d;
			hold_en <= hold_en_d;
			if (iowr_ev & hold_en_d) hold <= d_bus;

			dos_q <= ~reset_n ? 1'b1 :
			         m1mr_fall ? ((~(pn4q & A[13] & A[12] & (A[11:8] == 4'hD)) & dos_e) | A[14] | A[15]) : dos_q;

			// DRAM
			cwh_q  <= ~mc_write & dc_cas;
			dw_q   <= dw_e;
			blk_mr_q <= blk_mr_d;
			we_q   <= ~reset_n | we_out | dc_ras;
			svwr_q <= svwr_e;
			rgmod_en <= rgmod_en_d;
			rgmod  <= ~reset_n ? 8'd0 : (iowr_ev & rgmod_en_d) ? d_bus : rgmod;
			am_en  <= am_en_d;
			all_mode <= all_mode_nx;

			// sound
			ws_q  <= cth[1];
			bck_q <= ct[2];
			if (ct2_rise) begin dac1_q <= audio_r_nx[15]; audio_ch <= {cth_nx[0], ct_nx[5:3]} == 4'hF; end
			if (ct2_fall) dac_q <= dac1_q;
			audio_r <= audio_r_nx;

			cbl_en <= cbl_en_d;
			cbl_xx <= cbl_xx_nx;
			if (cth1_fall) cbl_ctx <= (cbl_ctx == 5'd0) ? cbl_tab : cbl_ctx - 5'd1;
			cbl_cnt <= cbl_cnt_r;
			cint_q  <= cint_set ? 1'b1 : cint_ev ? 1'b0 : cint_q;
			c88_q   <= c88_d;
			pfd_q   <= pfd_clr ? 1'b0 : pfd_d;
			mcwc_q  <= ~reset_n | mc_write | dc_cas;
			w_q     <= ~cint_e ? 1'b1 : cblwr_fall ? ~cbl_wae : w_q;
			begin : wa
				reg [7:0] v;
				v = (cblwr_fall & ~cbl_wae) ? cbl_wa_d : cbl_wa_e;
				cbl_wa <= {wa7_clr ? 1'b0 : wa7_set ? 1'b1 : v[7], wa_clr ? 7'd0 : v[6:0]};
			end
			cbd <= ~cbl_mode16 ? 8'd0 : (cblwr_fall & cbl_wae) ? acc_mdo[7:0] : cbd;
			cbl_arr <= cbl_mem[cbl_radr];
			cbl_q   <= cbl_arr;
			cblr_en <= cbl_mode | cbl_wr;
			cbl_r   <= cbl_r_nx;

			a90_q <= dcpp == 8'h90;
			a91_q <= dcpp == 8'h91;
			aya_q <= aya_d;
			ayd_q <= ayd_d;
			cth0d_q <= cth[0];
			ayc_q   <= ayc_d;
			if (ay_chs_ev) ay_chs <= {ay_sum, cbl_r_nx[4:1]};
		end
		if (CE_N) begin
			// DRAM_WRITE = DFF(!/WE_OUT & !CAS, !CLK42, (!/WE_OUT & !RAS)); SVIDEO.wr = DFF(.., !CLK42, , /RESET)
			dw_q   <= dw_clr ? 1'b0 : ~we_out & ~dc_cas;
			svwr_q <= ~reset_n ? 1'b1 : mc_write | gliss | dc_cas;
		end
		// the CBL FIFO write (CE, cbl_wren) or its zero-fill on CFG_RST; the registers take their power-up values
		if (cbl_mwe) cbl_mem[cbl_mwa] <= cbl_mwd;
		rl_we <= 1'b0;
		rl_wa <= rl_a[7:0];
		if (CFG_RST) begin
			rl_we <= ~rl_a[8];
			if (rl_a != 9'd260) rl_a <= rl_a + 9'd1;
			CFG_DONE <= rl_a == 9'd260;
			rst_q <= 1'b0; iowr_q <= 1'b1; iord_q <= 1'b1; border <= 8'd0; bord_en <= 1'b0; kclk_q <= 1'b0; key_io <= 1'b0;
			keys_rf <= 1'b0; ts_q <= 1'b1; mdp <= 8'd0; hddr <= 8'd0; hsel_q <= 1'b0; sys_ena2 <= 1'b0; isa_port <= 8'd0;
			isa_en <= 1'b0; sr_s1 <= 1'b0; sr_s2 <= 1'b0; soft_q <= 2'd3; sys_n_q <= 1'b0; sys_pg_q <= 1'b0;
			a20_en <= 1'b0; cash_q <= 1'b0; cash_en <= 1'b0; wt_r <= 3'd0; wz_q <= 1'b0; cs_isa_q <= 1'b1;
			cs_romt_q <= 1'b1; cs_casht_q <= 1'b1; xacs_q <= 1'b1; rom_rg <= 8'd0; rom_en <= 1'b0; rom5c_en <= 1'b0;
			mctd_q <= 1'b0; ix_q <= 1'b1; i1_q <= 1'b0; i2_q <= 1'b0; rdxa_q <= 1'b0; sxa_q <= 1'b0; kbd_cc <= 1'b0;
			kbd_dd <= 1'b0; tape_in <= 1'b0; mouse_d <= 1'b0; sinc_1 <= 1'b0; sinc_2 <= 1'b0; sinc_hold <= 9'd0;
			s1m_q <= 1'b0; s1md_q <= 1'b0; copyh_q <= 1'b0; s2m_q <= 1'b0; s2md_q <= 1'b0; copyv_q <= 1'b0;
			hold <= 8'h77; hold_en <= 1'b0; dos_q <= 1'b1; cwh_q <= 1'b0; dw_q <= 1'b0; blk_mr_q <= 1'b0; we_q <= 1'b1;
			rgmod <= 8'd0;
			rgmod_en <= 1'b0; svwr_q <= 1'b1; all_mode <= 8'hFF; am_en <= 1'b0; dac1_q <= 1'b0; dac_q <= 1'b0;
			ws_q <= 1'b0; bck_q <= 1'b0; audio_ch <= 1'b0; audio_r <= 16'd0; cbl_xx <= 8'd0; cbl_en <= 1'b0;
			cbl_ctx <= 5'd0; cbl_cnt <= 8'd0; cint_q <= 1'b1; c88_q <= 1'b0; pfd_q <= 1'b0; mcwc_q <= 1'b1; w_q <= 1'b1;
			cbl_wa <= 8'd0; cbd <= 8'd0; cbl_r <= 16'h8000; cblr_en <= 1'b0; a90_q <= 1'b0; a91_q <= 1'b0;
			aya_q <= 1'b0; ayd_q <= 1'b0; cth0d_q <= 1'b0; ayc_q <= 1'b0; ay_chs <= 16'd0; cbl_arr <= 16'd0;
			cbl_q <= 16'd0;
		end else begin
			rl_a <= 9'd0;
			CFG_DONE <= 1'b0;
		end
	end

	assign RESET_N_OE = ~rst_q;
	assign WAIT_N_OE  = ~(dc_wait_n & wait_rom & wait_orig);
	assign CLKZ1      = clk_z80;
	assign CLKZ1_NX   = clk_z80_nx;
	assign CS_ROM     = cs_romt;
	assign CS_CASH    = cs_casht & cs_isa & isa_a20;
	assign RA         = isa_a;
	assign XACS       = xacs_e;
	assign MA         = {~turbo, int_x, nmi_x, dc_ma};
	assign RD_KMPS    = iom_n | RD_N | ~(type_ == 4'd7);
	assign WR_DWG     = wr_dwg;
	assign WR_AWG     = wr_awg;
	assign RDXA       = rdxa_q;
	assign SXA        = sxa_q;
	assign DAC_DATA   = dac_q;
	assign DAC_WS     = ws_q;
	assign DAC_BCK    = bck_q;
	assign V_CS       = v_cs;
	assign VA         = vao;
	assign V_WR       = v_wr;
	assign VD0_O = vdo0; assign VD1_O = vdo1; assign VD2_O = vdo2; assign VD3_O = vdo3;
	assign VD_OE      = ~v_wen;
	assign WR_COL     = wr_pix;
	assign CT_PH      = ct[2:0];
	assign MCA        = mca;
	assign SEL_ROM    = ~pre_rom & pre_cash;
	assign SEL_CASH   = pre_rom & ~pre_cash;

	// ================= submodules
	sp_video2 SVIDEO(.CLK(CLK), .CE(CE), .CE_N(CE_N), .CT(ct), .CTH(cth), .CTV(ctv), .CTF(ctf), .BLANK(v_blank),
		.COPY_SINC_H(copyh_q), .COPY_SINC_V(copyv_q), .WR(svwr_e), .VAI({ga, acc_ao[9:0]}), .MDI(acc_mdo),
		.DOUBLE_CAS(dcas), .VAO(vao), .VDO0(vdo0), .VDO1(vdo1), .VDO2(vdo2), .VDO3(vdo3),
		.VDM0(vd0), .VDM1(vd1), .VDM2(vd2), .VDM3(vd3), .V_WR(v_wr), .V_WEN(v_wen), .V_CS(v_cs), .WR_PIX(wr_pix),
		.ZX_PORT({sp_sa, zx_wen, acc_gline[5:0]}),
		.DIR_PORT({border[2:0], rgmod_e[2] & ~PERS_K30, rgmod_e[0], 2'b00, scr128}), .INTT(intt),   // K30: [4] = GND
		.CT_NX(ct_nxr), .CTH_NX(cth_nxr), .INTT_NX(intt_nx),
		.VA_NX(VA_NX), .V_WR_NX(V_WR_NX), .VA_MOD(VA_MOD), .MODE_RQ(MODE_RQ), .MLO_RQ(MLO_RQ), .VA_ATR(VA_ATR),
		.ATR_ZX(ATR_ZX), .PIX_RQ(PIX_RQ), .MODE_FIX(MODE_FIX), .CFG_RST(CFG_RST), .PERS_K30(PERS_K30), .PERS_SCROLL(PERS_SCROLL));

	sp_dcp #(.MIF_HEX(MIF_DCP), .REFRESH_REG(1)) DECODE(.CLK(CLK), .CE(CE), .CE_N(CE_N), .RESET_N(reset_n), .RES_N(), .CT(ct[2:0]),
		.CONTINUE(acc_cont), .RAS(dc_ras), .CAS(dc_cas), .MC_END(mc_end), .MC_BEGIN(mc_begin), .MC_TYPE(mc_type),
		.MC_WRITE(mc_write), .A(acc_ao), .DI(d_bus), .DO(dc_do), .MA(dc_ma), .MCA(mca), .TURBO_HAND(ts_e),
		.CLK_Z80(clk_z80), .TURBO(turbo), .IO_N(IO_N), .RD_N(RD_N), .WR_N(WR_N), .MR_N(MR_N), .RF_N(RF_N),
		.M1_N(M1_N), .IOWR_EV(dcp_iowr_ev), .IOREL_EV(dcp_iorel_ev), .MR_FALL_EV(mr_fall), .IO_FALL_EV(io_fall),
		.WAIT_N(dc_wait_n), .IOM_N(iom_n), .IOMM_N(iomm_n), .MD(acc_do), .RA(), .PAGE(page), .TYPE(type_),
		.CS_ROM(), .CS_RAM(), .V_RAM(v_ram), .PORT(), .DOS(dos_e), .WR_DWG(wr_dwg), .WR_TM9(), .WR_AWG(wr_awg),
		.RD_KP11(), .KP11_MIX(), .REFRESH_EV(ct4_rise), .G_LINE({2'b00, acc_gline}), .GA(ga), .GRAF(),
		.SP_SCR(sp_scr), .SP_SA(sp_sa), .SCR128(scr128), .TEST_R(1'b0), .HDD_DATA(hdd_data), .HDD_FLIP(hdd_flip),
		.RAM(dc_ram), .BLK_R(blk_r), .PN4Q(pn4q), .ACC_ON(acc_on), .DCPP(dcpp), .DCAS_FALL_EV(dcas_fall),
		.BLK_MEM(blk_mem), .IOMM_N_NX(iomm_n_nx), .IOM_N_NX(iom_n_nx), .RAS_NX(ras_nx), .MC_TYPE_NX(mc_type_nx),
		.CLK_Z80_NX(clk_z80_nx), .TYPE_NX(type_nx), .HDD_DATA_NX(hdd_data_nx), .CFG_RST(CFG_RST), .PERS_K30(PERS_K30),
		.PERS_SCROLL(PERS_SCROLL));

	sp_acceler ACC(.CLK(CLK), .CE(CE), .CE_N(CE_N), .RESET_N(reset_n), .CT(ct[2:0]), .CAS(dc_cas),
		.CLK_Z80_EV(~clk_z80 & clk_z80_nx), .CONTINUE(acc_cont), .MC_END(mc_end), .MC_TYPE(mc_type), .AI(A),
		.DI(d_bus), .AO(acc_ao), .DO(acc_do), .IO_N(IO_N), .RD_N(RD_N), .WR_N(WR_N), .MR_N(MR_N), .MR_N_EV(mr_rise),
		.RF_N(RF_N), .M1_N(M1_N), .M1_N_EV(m1_rise), .IOM_N(iom_n), .DCP(dcpp), .MDI(md_bus), .MDO(acc_mdo), .MD(),
		.G_LINE(acc_gline), .GLISSER(acc_gliss), .ACC_ON(acc_on), .ACC_ENA(all_mode_e[0]), .DOUBLE_CAS(dcas),
		.HDDR(hddr), .HDD_FLIP(hdd_flip), .ACC_DIR(acc_dir), .ACC_BLK(acc_blk), .CFG_RST(CFG_RST));

	sp_ay #(.MIF_HEX(MIF_AY)) AY3(.CLK(CLK), .CE(CE), .RESET_N(reset_n), .AY_T({cth[2:0], ct}), .AY_D_WR(ayd_q),
		.AY_A_WR(aya_q), .AY_A_WR_EV(~aya_q & aya_d), .D(d_bus), .DO(ay_do), .AY_CH_A(), .AY_CH_B(), .AY_CH_C(),
		.AY_CH_L(ay_l), .AY_CH_R(ay_r), .AY_CH_VAL(), .BEEPER(border[4]), .CFG_RST(CFG_RST));

	sp_kbd #(.MIF_HEX(MIF_KBD)) KEYS(.CLK(CLK), .CE(CE), .CLK_K_EV(clk_k_ev), .KBD_CC(kbd_cc), .KBD_DD(kbd_dd),
		.RF_N(keys_rf), .IO_N(key_io), .A(A[15:8]), .ENA(kena), .INT_ENA(kint_ena), .KBO(kbo),
		.KB_RESET(kb_reset), .KB_F12(kb_f12), .KB_CTRL(kb_ctrl), .KB_ALT(kb_alt), .KB_SH(kb_sh), .INT(k_int),
		.KB_F12_NX(kb_f12_nx), .KB_CTRL_NX(kb_ctrl_nx), .KB_ALT_NX(kb_alt_nx), .KB_SH_NX(kb_sh_nx),
		.INT_Q_NX(k_int_qnx), .CFG_RST(CFG_RST));

	sp_mouse MS(.CLK(CLK), .CE(CE), .CLK_EV(clk_k_ev), .MOUSE_D(mouse_d), .OUT_X(ms_x), .OUT_Y(ms_y), .OUT_K(ms_k),
		.INT(), .CFG_RST(CFG_RST));
endmodule
