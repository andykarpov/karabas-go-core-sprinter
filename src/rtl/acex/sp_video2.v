// Sprinter ACEX: video controller (VIDEO2.TDF of the ACEX configuration 3.03a, MODE = "SPRINTER", MOUSE = "NO").
// Translated from the AHDL of Ivan Mak / Peters Plus, reconstruction of Tolik-Trek (github.com/Tolik-Trek/SP2000-ACEX).
// Rules: docs/translation.md; slots and counters: docs/ahdl.md 3.1 / 3.2.
//
// One clock CLK with two enables: CE = rising edge of the original CLK42, CE_N = its falling edge (on the board CLK =
// 84 MHz, CE and CE_N alternate). All inputs are synchronous to CLK:
// - COPY_SINC_H / COPY_SINC_V, ZX_PORT, DIR_PORT, VAI, MDI, DOUBLE_CAS: change after a CE (registers of the top on CLK42;
//   DIR_PORT = BORDER / RGMOD registers, any time).
// - WR: the top's DFF(.., !CLK42): changes after a CE_N.
// - VDM0..3: the video RAM data bus as seen by the FPGA (= VDO while V_WEN is low). It must hold, at a CE_N, the data
//   of the address VAO that was presented at the CE half a cycle before (D_PICx_ capture), and at the following CE
//   still that data (MODE0..2 capture on WR_MODE, which in the original is taken "slightly after" the edge through two
//   LCELLs, i.e. on the hold time of the SRAM).
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
	output            INTT_NX
);
	// ================= sync counters CT / CTH / CTV / CTF
	reg  [5:0] ct_q = 6'd0;
	reg  [5:0] cth_q = 6'd0;
	reg  [8:0] ctv_q = 9'd0;
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
	reg        wr_pic = 1'b0, wr_col = 1'b0, wr_mode = 1'b0, tsn_w3 = 1'b0;
	reg        lwr_pic = 1'b0, lwr_col = 1'b0;
	reg        bord = 1'b0, blank = 1'b0, inttx = 1'b0, wide = 1'b0, bordp = 1'b0, intt = 1'b0;
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

	reg [17:0] vla_n;
	reg        wr_pic_d, wr_col_d, wr_mode_d;
	always @* begin
		wr_pic_d = 1'b1; wr_col_d = 1'b1; wr_mode_d = 1'b1;
		case (vcm[1:0])
			2'd0: vla_n = {brva, 5'b11111, rbrva_e, 2'b00};
			2'd1: begin vla_n = sva; wr_pic_d = ~vcm[2]; wr_col_d = vcm[2]; end
			2'd2: vla_n = vxa[17:0];
			default: begin
				vla_n = {DIR_PORT[3], cth_e, ct_e[5], 2'b11, ctv_e[8:3], 2'b00};
				wr_pic_d = x_mode[5];
				wr_mode_d = ~(ct_e[5:3] == 3'b111) & ~(ct_e[4] & ct_e[3] & ~mode0[5]);
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
			if (ct5_rise)
				intt <= ~(inttx & (ctv_n[2:0] == 3'd7));
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
			sva      <= {sva_hi, rsva[8:6], mode0[3:0], rsva[5:0]};
			wr_pic   <= wr_pic_d;
			wr_col   <= wr_col_d;
			wr_mode  <= wr_mode_d;
			tsn_w3   <= vcm[1:0] != 2'd0;
			lwr_pic  <= wr_pic;
			lwr_col  <= wr_col;
			vla_d    <= vla[1:0];
			ldp_a    <= ct_e[5:3] == 3'd0;
			ldp_b    <= ct_e[4:2] == 3'd0;

			// pixels, colours
			if (!lwr_pic)
				d_pic0 <= ld_pic ? dpicx : {d_pic0[6:0], 1'b0};
			dcol  <= blank ? 8'd0 : (!lwr_col ? (bordp ? {2'b00, DIR_PORT[7:5], DIR_PORT[7:5]} : dpicx) : dcol);
			brva  <= wide ? dcol_e : (ct_e[2] ? {4'h0, dcol_e[7:4]} : {4'h0, dcol_e[3:0]});
			rbrva <= bord ? 3'b100 : (x_mode[4] ? {1'b1, ctf_e[4] & ~blank, d_pic0[7]} : {1'b0, x_mode[7:6]});

			// derived clocks
			if (wr_mode_rise) begin mode0 <= VDM3; mode1 <= VDM2; mode2 <= VDM1; end
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
	assign INTT_NX = ct5_rise ? ~(inttx & (ctv_n[2:0] == 3'd7)) : intt;
endmodule
