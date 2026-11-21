// Sprinter ACEX: video controller (VIDEO2.TDF of the ACEX configuration 3.03a, MODE = "SPRINTER", MOUSE = "NO").
// Translated from the AHDL of Ivan Mak / Peters Plus, reconstruction of Tolik-Trek (github.com/Tolik-Trek/SP2000-ACEX).
// Rules: docs/translation.md; slots and counters: docs/ahdl.md 3.1 / 3.2.
//
// One clock CLK with two enables: CE = rising edge of the original CLK42, CE_N = its falling edge (on the board CLK =
// 84 MHz, CE and CE_N alternate). All inputs are synchronous to CLK:
// - COPY_SINC_H / COPY_SINC_V, ZX_PORT, DIR_PORT, VAI, MDI, DOUBLE_CAS: change after a CE (registers of the top on CLK42;
//   DIR_PORT = BORDER / RGMOD registers, any time).
// - WR: the top's DFF(.., !CLK42): changes after a CE_N.
// - VDM0..3: the video RAM data bus as seen by the FPGA (= VDO while V_WEN is low). The data of the address VAO
//   presented at CE n is taken at CE n+2 (MODE0..2 on WR_MODE) and at CE_N n+3 (D_PICx_): one CE later than the
//   address alone suggests (measured over all loads, docs/memtiming.md); the controller may start from VAO's next value.
// Video RAM outputs: VAO (word address, 32-bit words), VDO0..3 (write data; the top drives VD only where V_WEN = 0),
// V_WR[3..0] (/WE per byte, low from a CE to the next CE_N), V_WEN[3..0] (= V_WR in the functional netlist, see below),
// V_CS[1..0].
//
// Deviations from a literal translation (all checked against the 3.03a netlist, src/sim/eq/tb_eq_video2.v):
// - LCELL / EXP delays removed. The original relies on them in:
//   * V_WR / V_WEN: V_WEMMM..V_WEMM are four LCELL delays of V_WE; V_WR = V_WEMMM & V_WEMMN (two), V_WEN =
//     V_WEMMM & V_WEMMO (three): /WE and the data-out window are the half-cycle V_WE pulse, the data window one LCELL
//     longer (data hold after /WE). Without delays both are V_WE | V_EN, which is what the netlist does; an SRAM
//     controller of our core has to give the data a hold time after /WE itself.
//   * V_WE pulse width: V_WE.prn = DFF(GND, !CLK42, , !V_WE): V_WE falls at a CE and is preset back at the next CE_N
//     (a pulse of half a CLK42 period plus the preset loop delay). Here: register set at CE, back to 1 at CE_N.
//   * LWR_MODE = LCELL(LCELL(WR_MODE)): MODE0..2 take VDM at the CE where WR_MODE rises (see VDM above).
//   * V_CS0 = DFF(!VCM0 & VCM1, CLK42, V_CSX1) with V_CSX1 = LCELL(LCELL(!CLK42)): the register is cleared while
//     CLK42 is high, i.e. from the same edge that would set it. On the chip it is a glitch of about two LCELL delays at
//     the start of the write slot; with zero delays (the netlist) it is constant 0. Here: constant 0 (suspicious in the
//     original, see the report of Ф1.1). V_CS1 = VCC.
// - Power-up: with all registers 0 the asynchronous loops settle at once: V_WE_R = 0 presets V_WE (-> 1), which
//   clocks F_WR = DFF(VCC, V_WE) (-> 1) and releases V_WE_R (-> 1); V_WE = 0 presets MXWE (-> 1). So V_WE, MXWE start
//   at 1 here, and F_WR (V_EN.clrn) is 1 for good: left out, as Quartus folds it. (Not compared: the netlist's MXWE
//   latch emulation is X until the first E_WR.)
// - Dead logic not translated: MS_X / MS_Y / MS_DAT (MOUSE = "NO"), V_CST, V_WET, V_WEX, SCR_ENA, ZX_COL / ZX_COLOR
//   (not a port), CLK84, X_MODE_BOND = GND (so TSN_W3 = 0 in palette slots). Ports START_UP, D, MOUSE_X / MOUSE_Y
//   unused in the AHDL: left out.
// - Registers on derived clocks are events at the CE where the source rises: CTF (CTV8), INTT (CT5), MODE0..2
//   (WR_MODE), BORD / BLANK / INTTX / X_MODE7..4 / the point width (LWR_COL), the border flag of DCOL (WR_PIC). Their
//   data: registers on CLK42 with the new values, other derived registers (same wave) with the old ones, inputs as
//   they are. No *_EV inputs are needed: no input of the module is a clock in the AHDL.
// - Outputs CT / CTH / CTV / CTF / INTT are used as clocks in the top (INT_X by INTT, CTH2 / CTH3 / CT4 / CTV8 ...):
//   the top has to derive its events from them (their next values are ct_n / cth_n / ctv_n here).
// - Asynchronous clrn / prn: effective values (*_e); CT5 / CTH / CTV forced by COPY_SINC_H / _V, DCOL by BLANK, RBRVA
//   by BORD, MXWE by E_WR (clear) and V_WE (preset, after the edge). CTF counts the rise of the effective CTV8: COPY_SINC_V (preset of CTV8) makes it rise while the input is high, so CTF = register + that
//   pending rise (combinational, as the ripple counter in the original).
// - karabas: personality SCROLL (PERS_SCROLL = 1; VIDEO2.TDF of upstream/tt-scroll-cnf/src, the Game Config of Ivan Mak
//   2002, docs/versions.md): the screen is a grid of 8 x 8 cells shifted by SHIFT_X / SHIFT_Y (0..15, MODE3 = byte 0
//   of the mode word, taken at the end of a cell when MODE02); each cell's word gives the source byte X =
//   (MODE0[1..0], MODE1) and line Y = MODE2 in a 1024 x 256 picture. Lines marked "SCROLL:": GRID_X / GRID_Y, SHIFT,
//   MODE3, SVA (no ZX branch), the mode slot address and WR_MODE by GRID_X, LD_PIC by GRID_X, INTT = the fall of
//   INTTX at CT5 (INTTX_N_DELAY), DCOL border by BORD; the early outputs VA_MOD / MODE_RQ / MLO_RQ / PIX_RQ follow
//   GRID_X, ATR_ZX = 0. PERS_SCROLL = 0 is 3.03a bit for bit; it changes only while CFG_RST is high.
module sp_video2 (
	input             CLK,
	input             CE,          // CLK42 rising edge
	input             CE_N,        // CLK42 falling edge
	output      [5:0] CT,
	output      [5:0] CTH,
	output      [8:0] CTV,
	output      [6:0] CTF,
	output            BLANK,
	input             COPY_SINC_H, // forces CT5 = 0, CTH = 50 while high
	input             COPY_SINC_V, // forces CTV = 290 while high
	input             COPY_SINC_H_NX, // karabas: COPY_SINC_H / _V after this CE (the top's next values; they change only
	input             COPY_SINC_V_NX, // at a CE): only for the registered early outputs below
	input             WR,          // video RAM write strobe (active low): copy of a DRAM write
	input      [19:0] VAI,         // write address: [19] = graphics, else ZX screen
	input      [15:0] MDI,         // write data
	input             DOUBLE_CAS,
	output     [15:0] VAO,
	output      [7:0] VDO0,
	output      [7:0] VDO1,
	output      [7:0] VDO2,
	output      [7:0] VDO3,
	input       [7:0] VDM0,
	input       [7:0] VDM1,
	input       [7:0] VDM2,
	input       [7:0] VDM3,
	output      [3:0] V_WR,
	output      [3:0] V_WEN,
	output      [1:0] V_CS,
	output            WR_PIX,
	input       [7:0] ZX_PORT,     // [5..0] ZX screen pages, [6] ZX screen write enable, [7] ZX A15'
	input       [7:0] DIR_PORT,    // [0] SCR128, [3] mode table page, [4] blank, [7..5] border
	output            INTT,
	// karabas: next values for the top, which clocks registers by CT4 / CTH5 / INTT ...: the counter registers
	// after this CE (CT_NX[5] / CTH_NX already forced by the current COPY_SINC_H; the top applies the next one),
	// INTT after this CE. Valid at CE.
	output      [5:0] CT_NX,
	output      [5:0] CTH_NX,
	output            INTT_NX,
	// karabas: early signals for the SRAM controller (docs/memtiming.md 5; slot [s, s+2] = address out at edge s,
	// data in at s+2; edges c0..c11 of the 7 MHz cycle, c0 = the CE after which CT[2:0] = 6)
	output     [17:1] VA_NX,       // the next VA (byte address, bit 1 = 16-bit half): stable at the CE_N before the CE that loads it
	output      [3:0] V_WR_NX,     // V_WR of the next write slot (c0..c1) when it comes: stable c10..c11 (low = byte written)
	output     [15:0] VA_MOD,      // word address of the mode table of this cycle (stable from c1 in cycles CT[5:3] = 3 / 7, from c3 in 0)
	output            MODE_RQ,     // MODE0..2 load at the c12 of this cycle (from c1)
	output            MLO_RQ,      // byte 0 of the mode word may go to D_PIC0 at c14 (cycle CT[5:3] = 0 with MODE0[5]; from c1)
	output     [17:1] VA_ATR,      // the ZX attribute address of this cycle (valid when ATR_ZX, from c1)
	output            ATR_ZX,      // MODE0[4]: ZX screen (the attribute address does not depend on CT)
	output            PIX_RQ,      // D_PIC0 takes the pixel byte at c8 of this cycle and it can be seen (from c1)
	output            MODE_FIX,    // SCROLL: COPY_SINC_H / _V moves the grid of this cycle's mode slot (c3..c8): the mode
	                               // table halves fetched before must be fetched again (VA_MOD is the moved address now)
	input             CFG_RST,     // karabas: configuration reset: registers to power-up (docs/machine.md); only in if ()
	input             PERS_K30,    // karabas: personality k30 (docs/versions.md): WR_PIC.d = MODE0[5] in the mode slot
	                               // (k30 VIDEO2.TDF:467, "fix bug with first column"), 0 = 3.03a X_MODE5
	input             PERS_SCROLL  // karabas: personality SCROLL (Game Config of Thunder in the Deep, docs/versions.md):
	                               // the character grid with X / Y offsets ("SCROLL:" below), 0 = 3.03a. Not with PERS_K30
);
	// ================= sync counters CT / CTH / CTV / CTF
	reg  [5:0] ct_q = 6'd0;
	reg  [5:0] cth_q = 6'd50;   // power-up as the netlist: preset bits high
	reg  [8:0] ctv_q = 9'd290;
	reg  [6:0] ctf_q = 7'd0;
	reg        ct53_en = 1'b0, cth_en = 1'b0, ctv_en = 1'b0;   // DFF enables
	wire [5:0] ct_e  = {COPY_SINC_H ? 1'b0 : ct_q[5], ct_q[4:0]};   // CT5.clrn = !COPY_SINC_H
	wire [5:0] cth_e = COPY_SINC_H ? 6'd50 : cth_q;                   // set CTH to 50 (32h)
	wire [8:0] ctv_e = COPY_SINC_V ? 9'h122 : ctv_q;                  // set CTV to 122h

	reg  [2:0] ct210_n;
	always @* case (ct_e[2:0])                  // 0 1 2 4 5 6
		3'd0: ct210_n = 3'd1; 3'd1: ct210_n = 3'd2; 3'd2: ct210_n = 3'd4; 3'd3: ct210_n = 3'd4;
		3'd4: ct210_n = 3'd5; 3'd5: ct210_n = 3'd6; default: ct210_n = 3'd0;
	endcase
	wire [2:0] ct53_n = ct53_en ? ct_e[5:3] + 3'd1 : ct_e[5:3];
	wire [5:0] ct_n   = {COPY_SINC_H ? 1'b0 : ct53_n[2], ct53_n[1:0], ct210_n};   // register after this CE
	wire [5:0] cth_n  = COPY_SINC_H ? 6'd50 : (cth_en ? (cth_q == 6'd55 ? 6'd0 : cth_q + 6'd1) : cth_q);
	wire [8:0] ctv_n  = COPY_SINC_V ? 9'h122 : (ctv_en ? (ctv_q == 9'd319 ? 9'd0 : ctv_q + 9'd1) : ctv_q);
	// CTF[].clk = CTV8 (effective): a pending rise while COPY_SINC_V presets CTV8, a rise at the edge from the counter
	wire       ctf_pend = COPY_SINC_V & ~ctv_q[8];
	wire       ctf_edge = ~(COPY_SINC_V | ctv_q[8]) & ctv_n[8];
	wire [6:0] ctf_e    = ctf_q + {6'd0, ctf_pend};
	wire       ct5_rise = ~ct_e[5] & ct_n[5];       // INTT clock

	// ================= slot sequencer
	reg  [2:0] vcm = 3'd0;
	reg  [2:0] vcm_n;
	always @* case (ct_e[2:0])
		3'b110: vcm_n = 3'd5; 3'b000: vcm_n = 3'd1; 3'b001: vcm_n = 3'd4;
		3'b010: vcm_n = 3'd3; 3'b100: vcm_n = 3'd2; 3'b101: vcm_n = 3'd0;
		default: vcm_n = 3'd0;
	endcase

	// ================= CPU write path
	reg        wr_q = 1'b0;                          // DFF(WR)
	reg        e_wrd = 1'b0;                         // DFF(E_WR)
	reg [19:0] vxa = 20'd0;
	reg        dbl = 1'b0;                           // DOUBLE
	reg  [7:0] vxd0 = 8'd0, vxd1 = 8'd0, vxd2 = 8'd0, vxd3 = 8'd0;
	reg        mxwe = 1'b1;                          // MXWE = DFF(MXWE, CLK42, E_WR, V_WE); power-up: preset by V_WE
	reg        v_we = 1'b1;                          // power-up: preset by V_WE_R
	reg  [3:0] v_en = 4'd0;
	wire       e_wr = WR | ~(VAI[19] | ZX_PORT[6]) | ~wr_q;
	wire [19:0] vxa_d = VAI[19] ? VAI : {2'b00, VAI[7:0], ZX_PORT[4:1], ZX_PORT[0] ^ ZX_PORT[7] ^ VAI[13], VAI[12:8]};
	wire       mxwe_b = e_wr & mxwe;                 // effective before the edge (V_WE is 1 at a CE)
	wire       v_we_d = (vcm[1:0] == 2'd2) ? mxwe_b : 1'b1;
	wire [3:0] v_en_d = {~(~vxa[1] & (~vxa[0] | dbl)), ~(~vxa[1] & (vxa[0] | dbl)),
	                     ~(vxa[1] & (~vxa[0] | dbl)),  ~(vxa[1] & (vxa[0] | dbl))};

	// ================= mode table, pixels, colours
	reg  [7:0] mode0 = 8'd0, mode1 = 8'd0, mode2 = 8'd0;
	reg  [7:0] mode3 = 8'd0;                         // SCROLL: MODE3 = VDM0 (byte 0 of the mode word): SHIFT_Y, SHIFT_X
	reg        wr_pic = 1'b0, wr_col = 1'b0, wr_mode = 1'b0, tsn_w3 = 1'b0;
	reg        lwr_pic = 1'b0, lwr_col = 1'b0;
	reg        bord = 1'b0, blank = 1'b0, inttx = 1'b0, wide = 1'b0, bordp = 1'b0, intt = 1'b0;
	reg        inttx_nd = 1'b0;                      // SCROLL: INTTX_N_DELAY = DFF(!INTTX, CT5)
	reg  [7:4] x_mode = 4'd0;
	reg [17:0] vla = 18'd0, sva = 18'd0;
	reg  [1:0] vla_d = 2'd0;                         // DFF(VLA1), DFF(VLA0)
	reg        ldp_a = 1'b0, ldp_b = 1'b0;           // DFF(CT[5..3] == 0), DFF(CT[4..2] == 0)
	reg  [7:0] dp0_ = 8'd0, dp1_ = 8'd0, dp2_ = 8'd0, dp3_ = 8'd0;   // D_PICx_ (falling edge)
	reg  [7:0] d_pic0 = 8'd0, dcol = 8'd0, brva = 8'd0;
	reg [10:8] rbrva = 3'd0;

	wire [7:0] dcol_e  = blank ? 8'd0 : dcol;        // DCOL.clrn = !BLANK
	wire [10:8] rbrva_e = bord ? 3'b100 : rbrva;     // RBRVA[9..8].clrn = RBRVA[10].prn = !BORD
	wire       ld_pic  = mode0[5] ? ldp_a : ldp_b;
	reg  [7:0] dpicx;
	always @* case (vla_d)
		2'd0: dpicx = dp0_; 2'd1: dpicx = dp1_; 2'd2: dpicx = dp2_; default: dpicx = dp3_;
	endcase

	// ================= SCROLL (VIDEO2.TDF of upstream/tt-scroll-cnf/src): the character grid shifted by SHIFT_X / Y
	// GRID_X = (CTH, CT[5..3]) + SHIFT_X on CLK42, the low 3 bits only with the CT[5..3] enable (PIX_ENA = ct53_en);
	// GRID_Y = CTV + SHIFT_Y on CLK42. SHIFT_X / Y = MODE3 at the rise of SHIFT_CLK = DFF(DFF(!(VCM = 3 & CT[5..3] = 7)))
	// when MODE02 (both derived registers of the same wave: the old MODE0 / MODE3).
	reg  [8:0] grid_x = 9'd0, grid_y = 9'd0;
	reg  [3:0] shift_x = 4'd0, shift_y = 4'd0;
	reg        shift_clk0 = 1'b0, shift_clk = 1'b0;
	wire       shift_ev = ~shift_clk & shift_clk0 & mode0[2];       // SCROLL: SHIFT_X / Y clock and enable
	wire [8:0] gx_s = {cth_e, ct_e[5:3]} + {5'd0, shift_x};
	wire [8:0] gy_s = ctv_e + {5'd0, shift_y};
	// the source byte of the cell: X = (MODE0[1..0], MODE1) + GRID_X[2..0], Y = MODE2 + GRID_Y[2..0]
	wire [9:0] src_x = {mode0[1:0], mode1} + {7'd0, grid_x[2:0]};
	wire [7:0] src_y = mode2 + {5'd0, grid_y[2:0]};
	wire       scr_wr_mode = ~(grid_x[2:0] == 3'b111) & ~(grid_x[1] & grid_x[0] & ~mode0[5]);   // SCROLL: WR_MODE.d
	wire [17:0] va_mode = PERS_SCROLL ? {DIR_PORT[3], grid_x[8:2], 2'b11, grid_y[8:3], 2'b00}    // SCROLL: mode slot
	                                  : {DIR_PORT[3], cth_e, ct_e[5], 2'b11, ctv_e[8:3], 2'b00};
	wire       ldp_a_d = PERS_SCROLL ? grid_x[2:0] == 3'd0 : ct_e[5:3] == 3'd0;            // SCROLL: LD_PIC terms
	wire       ldp_b_d = PERS_SCROLL ? (grid_x[1:0] == 2'd0) & ~ct_e[2] : ct_e[4:2] == 3'd0;
	wire       bord_col = PERS_SCROLL ? bord : bordp;    // SCROLL: the DCOL border mux by BORD (3.03a: DFF(.., WR_PIC))
	wire       intt_d = PERS_SCROLL ? inttx_nd | inttx : ~(inttx & (ctv_n[2:0] == 3'd7));   // SCROLL: INTT

	reg [17:0] vla_n;
	reg        wr_pic_d, wr_col_d, wr_mode_d;
	wire       wr_pic_x = PERS_K30 ? mode0[5] : x_mode[5];   // WR_PIC.d of the mode slot (K30: MODE0[5])
	always @* begin
		wr_pic_d = 1'b1; wr_col_d = 1'b1; wr_mode_d = 1'b1;
		case (vcm[1:0])
			2'd0: vla_n = {brva, 5'b11111, rbrva_e, 2'b00};
			2'd1: begin vla_n = sva; wr_pic_d = ~vcm[2]; wr_col_d = vcm[2]; end
			2'd2: vla_n = vxa[17:0];
			default: begin
				vla_n = va_mode;
				wr_pic_d = wr_pic_x;
				wr_mode_d = PERS_SCROLL ? scr_wr_mode : ~(ct_e[5:3] == 3'b111) & ~(ct_e[4] & ct_e[3] & ~mode0[5]);
			end
		endcase
	end

	// screen address SVA
	wire [2:0] m_ctv = mode2[2] ? {mode2[1], ctv_e[2:1]} : ctv_e[2:0];
	wire [2:0] m_ct  = mode2[2] ? {mode2[0], ~ct_e[5], ~ct_e[4]} : {ct_e[5], ~ct_e[4], ~ct_e[3]};
	reg  [8:0] rsva;
	reg  [4:0] sva_hi;
	always @* begin
		if (!mode0[4]) begin             // graphics
			rsva = {m_ctv, mode1[2:0], m_ct};                                      sva_hi = mode1[7:3];
		end else if (vcm[2]) begin       // ZX attributes
			rsva = {mode2[2:0], DIR_PORT[0], 3'b110, ~mode0[7:6]};                  sva_hi = mode2[7:3];
		end else begin                   // ZX pixels
			rsva = {mode1[2:0], DIR_PORT[0], mode0[7:6], ctv_e[2], ~ctv_e[1:0]};    sva_hi = mode1[7:3];
		end
	end

	// SCROLL: SVA = (SOURCE_Y, SOURCE_X[9..2], !SOURCE_X[1..0]) (no ZX branch)
	wire [17:0] sva_d = PERS_SCROLL ? {src_y, src_x[9:2], ~src_x[1:0]} : {sva_hi, rsva[8:6], mode0[3:0], rsva[5:0]};

	wire wr_mode_rise = ~wr_mode & wr_mode_d;       // MODE0..2 clock (LWR_MODE)
	wire lwr_col_rise = ~lwr_col & wr_col;          // BORD, BLANK, INTTX, X_MODE, width clock
	wire wr_pic_rise  = ~wr_pic & wr_pic_d;         // clock of the DCOL border flag

	always @(posedge CLK) begin
		if (CE) begin
			// counters
			ct_q    <= ct_n;
			cth_q   <= cth_n;
			ctv_q   <= ctv_n;
			ct53_en <= ct_e[0] & ct_e[2];
			cth_en  <= (ct_e[5:2] == 4'hF) & ct_e[0];
			ctv_en  <= (ct_e[5:2] == 4'hF) & ct_e[0] & (cth_e == 6'd48);
			ctf_q   <= ctf_q + {6'd0, ctf_pend} + {6'd0, ctf_edge};
			if (ct5_rise) begin
				intt <= intt_d;
				inttx_nd <= ~inttx;
			end
			vcm <= vcm_n;

			// write path
			wr_q  <= WR;
			e_wrd <= e_wr;
			if (!e_wr) begin vxa <= vxa_d; dbl <= DOUBLE_CAS; end
			if (!e_wrd) begin vxd0 <= MDI[15:8]; vxd1 <= MDI[7:0]; vxd2 <= MDI[15:8]; vxd3 <= MDI[7:0]; end
			v_we <= v_we_d;
			mxwe <= v_we_d ? mxwe_b : 1'b1;             // V_WE low after the edge presets MXWE
			v_en <= v_en_d;

			// slots
			vla      <= vla_n;
			sva      <= sva_d;
			wr_pic   <= wr_pic_d;
			wr_col   <= wr_col_d;
			wr_mode  <= wr_mode_d;
			tsn_w3   <= vcm[1:0] != 2'd0;
			lwr_pic  <= wr_pic;
			lwr_col  <= wr_col;
			vla_d    <= vla[1:0];
			ldp_a    <= ldp_a_d;
			ldp_b    <= ldp_b_d;
			// SCROLL grid
			grid_x[8:3] <= gx_s[8:3];
			if (ct53_en) grid_x[2:0] <= gx_s[2:0];
			grid_y      <= gy_s;
			shift_clk0  <= ~((vcm[1:0] == 2'd3) & (ct_e[5:3] == 3'd7));
			shift_clk   <= shift_clk0;
			if (shift_ev) begin shift_y <= mode3[7:4]; shift_x <= mode3[3:0]; end

			// pixels, colours
			if (!lwr_pic)
				d_pic0 <= ld_pic ? dpicx : {d_pic0[6:0], 1'b0};
			dcol  <= blank ? 8'd0 : (!lwr_col ? (bord_col ? {2'b00, DIR_PORT[7:5], DIR_PORT[7:5]} : dpicx) : dcol);
			brva  <= wide ? dcol_e : (ct_e[2] ? {4'h0, dcol_e[7:4]} : {4'h0, dcol_e[3:0]});
			rbrva <= bord ? 3'b100 : (x_mode[4] ? {1'b1, ctf_e[4] & ~blank, d_pic0[7]} : {1'b0, x_mode[7:6]});

			// derived clocks
			if (wr_mode_rise) begin mode0 <= VDM3; mode1 <= VDM2; mode2 <= VDM1; mode3 <= VDM0; end
			if (lwr_col_rise) begin
				bord   <= mode0[7:4] == 4'hF;
				blank  <= (bord & mode0[3] & mode0[2]) | DIR_PORT[4];
				inttx  <= bord & mode0[3] & mode0[2] & mode0[0];
				x_mode <= mode0[7:4];
				wide   <= mode0[4] | mode0[5];
			end
			if (wr_pic_rise)
				bordp <= mode0[7:4] == 4'hF;
		end
		if (CE_N) begin
			dp0_ <= VDM0; dp1_ <= VDM1; dp2_ <= VDM2; dp3_ <= VDM3;
			v_we <= 1'b1;                               // V_WE.prn = V_WE_R = DFF(GND, !CLK42, , !V_WE)
		end
		if (CFG_RST) begin   // the power-up values above
			ct_q <= 6'd0; cth_q <= 6'd50; ctv_q <= 9'd290; ctf_q <= 7'd0; ct53_en <= 1'b0; cth_en <= 1'b0; ctv_en <= 1'b0;
			vcm <= 3'd0; wr_q <= 1'b0; e_wrd <= 1'b0; vxa <= 20'd0; dbl <= 1'b0; vxd0 <= 8'd0; vxd1 <= 8'd0;
			vxd2 <= 8'd0; vxd3 <= 8'd0; mxwe <= 1'b1; v_we <= 1'b1; v_en <= 4'd0; mode0 <= 8'd0; mode1 <= 8'd0;
			mode2 <= 8'd0; wr_pic <= 1'b0; wr_col <= 1'b0; wr_mode <= 1'b0; tsn_w3 <= 1'b0; lwr_pic <= 1'b0;
			lwr_col <= 1'b0; bord <= 1'b0; blank <= 1'b0; inttx <= 1'b0; wide <= 1'b0; bordp <= 1'b0; intt <= 1'b0;
			x_mode <= 4'd0; vla <= 18'd0; sva <= 18'd0; vla_d <= 2'd0; ldp_a <= 1'b0; ldp_b <= 1'b0; dp0_ <= 8'd0;
			dp1_ <= 8'd0; dp2_ <= 8'd0; dp3_ <= 8'd0; d_pic0 <= 8'd0; dcol <= 8'd0; brva <= 8'd0; rbrva <= 3'd0;
			mode3 <= 8'd0; inttx_nd <= 1'b0; grid_x <= 9'd0; grid_y <= 9'd0; shift_x <= 4'd0; shift_y <= 4'd0;
			shift_clk0 <= 1'b0; shift_clk <= 1'b0;
		end
	end

	assign CT     = ct_e;
	assign CTH    = cth_e;
	assign CTV    = ctv_e;
	assign CTF    = ctf_e;
	assign BLANK  = blank;
	assign INTT   = intt;
	assign VAO    = vla[17:2];
	assign VDO0   = vxd0;
	assign VDO1   = vxd1;
	assign VDO2   = vxd2;
	assign VDO3   = vxd3;
	assign V_WR   = {4{v_we}} | v_en;
	assign V_WEN  = {4{v_we}} | v_en;
	assign V_CS   = 2'b10;
	assign WR_PIX = tsn_w3;
	assign CT_NX   = ct_n;
	assign CTH_NX  = cth_n;
	assign INTT_NX = ct5_rise ? intt_d : intt;
	// early signals (outputs only: nothing above uses them)
	assign VA_NX   = vla_n[17:1];
	assign V_WR_NX = {4{mxwe_b}} | v_en_d;      // = {4{v_we_d}} | v_en_d in the write slot (vcm = 2, c11)
	// ================= early outputs for sp_sram, registered (no counter / adder logic before the SRAM arbiter: PAR).
	// sp_sram decides its slots at the CE_N edges only, so each output is a register loaded at the CE before with the
	// value the combinational form would have at that CE_N: from the next counter values (ct_n, cth_n, ctv_n), the
	// next CT[5..3] enable (ct_e[0] & ct_e[2]) and the next COPY_SINC_H / _V (*_NX). At the CE edges they are stale
	// (not used there).
	// 3.03a / k30: the cell column CT_NX[5:3] and VA_MOD = (DIR_PORT3, CTH, CT5, 11, CTV[8..3]) as seen at that CE_N.
	// SCROLL: the grid as the mode slot (c10) and the pixel / colour slots of this cycle will see it. GRID_X[2..0] is
	// loaded at c2 (with CT[5..3]) and then held: the column is, from c1, the value it has after c2 (at c0: the next
	// CT[5..3] + SHIFT_X; else the next GRID_X[2..0]). GRID_X[8..3] / GRID_Y follow CTH / CT / CTV / SHIFT one CE later,
	// and those change at c2: VA_MOD = the grid after the next CE, final from c3, so MODE_RQ waits for c3 (no mode half
	// in [1,3]; the slot plan still fits, docs/versions.md). A sync jump in the middle of a cycle (COPY_SINC_H forces
	// CTH = 50, CT5 = 0; COPY_SINC_V CTV = 290 at c3..c8) moves GRID_X[8..3] / GRID_Y too late for that: VA_MOD is then
	// the grid after the jump and MODE_FIX makes sp_sram fetch both halves again.
	wire [2:0] gxl_n = ct53_en ? gx_s[2:0] : grid_x[2:0];
	wire [3:0] shx_n = shift_ev ? mode3[3:0] : shift_x;
	wire [3:0] shy_n = shift_ev ? mode3[7:4] : shift_y;
	wire [8:0] gx_n  = {cth_n, ct_n[5:3]} + {5'd0, shx_n};
	wire [8:0] gy_n  = ctv_n + {5'd0, shy_n};
	wire [8:0] vj_xs = {6'd50, 1'b0, ct_n[4:3]} + {5'd0, shx_n};
	wire [8:0] vj_ys = 9'd290 + {5'd0, shy_n};
	// the counters as seen at the next CE_N (after this CE)
	wire       en_1   = ct_e[0] & ct_e[2];                            // ct53_en after this CE
	wire [2:0] ce53_1 = {COPY_SINC_H_NX ? 1'b0 : ct_n[5], ct_n[4:3]};  // ct_e[5:3] then
	wire [2:0] cn53_1 = en_1 ? ce53_1 + 3'd1 : ce53_1;
	wire [2:0] cx_303 = {COPY_SINC_H_NX ? 1'b0 : cn53_1[2], cn53_1[1:0]};   // ct_n[5:3] then
	wire [2:0] cx_scr = (ct_e[0] & ct_e[2]) ? ct_n[5:3] + shx_n[2:0] : gxl_n;
	wire       jm_1   = (ct_n[2:0] == 3'd0) | (ct_n[2:0] == 3'd1) | (ct_n[2:0] == 3'd2);   // c3..c8 then
	wire       jh_1   = PERS_SCROLL & jm_1 & COPY_SINC_H_NX, jv_1 = PERS_SCROLL & jm_1 & COPY_SINC_V_NX;
	wire [5:0] cth_1  = COPY_SINC_H_NX ? 6'd50 : cth_n;
	wire [8:0] ctv_1  = COPY_SINC_V_NX ? 9'h122 : ctv_n;
	wire [14:0] vam_1 = PERS_SCROLL ? {jh_1 ? vj_xs[8:3] : gx_n[8:3], gxl_n[2], 2'b11, jv_1 ? vj_ys[8:3] : gy_n[8:3]}
	                                : {cth_1, ce53_1[2], 2'b11, ctv_1[8:3]};
	reg  [2:0] cx_q = 3'd0;                                           // the cell column of this cycle
	reg [14:0] vam_q = 15'd0;                                         // VA_MOD[14:0]
	reg        mfix_q = 1'b0;
	always @(posedge CLK) begin
		if (CE) begin
			cx_q   <= PERS_SCROLL ? cx_scr : cx_303;
			vam_q  <= vam_1;
			mfix_q <= jh_1 | jv_1;
		end
		if (CFG_RST) begin cx_q <= 3'd0; vam_q <= 15'd0; mfix_q <= 1'b0; end
	end
	wire       m_c1  = PERS_SCROLL & (ct_e[2:0] == 3'd6);             // SCROLL: c1 (VA_MOD not final yet)
	assign VA_MOD  = {DIR_PORT[3], vam_q};
	assign MODE_FIX = mfix_q;
	assign MODE_RQ = ((cx_q == 3'd7) | ((cx_q == 3'd3) & ~mode0[5])) & ~m_c1;
	assign MLO_RQ  = mode0[5] & (cx_q == 3'd0);
	assign VA_ATR  = {mode2[7:3], mode2[2:0], mode0[3:0], DIR_PORT[0], 3'b110, ~mode0[7]};   // [0] = ~mode0[6] dropped
	assign ATR_ZX  = mode0[4] & ~PERS_SCROLL;                         // SCROLL: no ZX address, the colour by VA_NX
	// the byte is also seen when a 16-colour graphics cell (no load at its cycle 4 for a next cell with MODE0[5] = 1)
	// is followed by a ZX / text half-cell: D_PIC0 is not reloaded there and shifts the byte of cycle 0 out
	assign PIX_RQ  = (mode0[5] ? (cx_q == 3'd0) : (cx_q[1:0] == 2'd0)) &
	                 (mode0[4] | x_mode[4] | (~mode0[5] & (cx_q == 3'd0)));
endmodule
