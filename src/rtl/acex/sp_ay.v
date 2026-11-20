// Sprinter ACEX: AY-3-8910 on a microprogram in block RAM (AY.TDF of the ACEX configuration 3.03a = 2.18 = k30;
// the 3.03a file differs only in the comment encoding). Translated from the AHDL of Ivan Mak / Peters Plus,
// reconstruction of Tolik-Trek (github.com/Tolik-Trek/SP2000-ACEX). Rules: docs/translation.md.
//
// AY_T = (CTH[2..0], CT[5..0]) of the top: the microprogram step is AY_T[7..2], AY_T[1..0] the phase.
// AY_A_WR / AY_D_WR are registers of the top (port strobes, active low); the *_EV inputs are high at the CE where
// that register rises (the end of the strobe), the AHDL clock of AY_ADR / AY_AAX.
module sp_ay (
	input            CLK,
	input            CE,
	input            RESET_N,
	input      [8:0] AY_T,
	input            AY_D_WR,
	input            AY_A_WR,
	input            AY_A_WR_EV,
	input      [7:0] D,
	output     [7:0] DO,
	output reg [3:0] AY_CH_A = 4'd0,
	output reg [3:0] AY_CH_B = 4'd0,
	output reg [3:0] AY_CH_C = 4'd0,
	output     [9:0] AY_CH_L,
	output     [9:0] AY_CH_R,
	output reg       AY_CH_VAL = 1'b0,
	input            BEEPER,
	// karabas: configuration reset (docs/machine.md): every register to its power-up value, the microprogram RAM
	// reloaded from AY.MIF (256 CLK). Use only in if (CFG_RST).
	input            CFG_RST
);
	parameter MIF_HEX = "ay.hex";

	reg  [8:0] ccc = 9'd0;                      // AY_CCC = DFF(AY_T)
	wire       ccc7_rise = ~ccc[7] & AY_T[7];

	// ---- register address / data latch
	reg  [7:0] adr = 8'd0;
	reg  [1:0] aax = 2'd0;
	reg  [7:0] bd_q = 8'd0;
	reg        bwr = 1'b0;
	wire       bd_clr75 = (adr[3:0] == 4'b0001) | (adr[3:0] == 4'b0011) | (adr[3:0] == 4'b0101) | (adr[3:0] == 4'b0110);
	wire       bd_clr4  = (adr[3:0] == 4'b0001) | (adr[3:0] == 4'b0011) | (adr[3:0] == 4'b0101);
	wire [7:0] bd = {bd_clr75 ? 3'b000 : bd_q[7:5], bd_clr4 ? 1'b0 : bd_q[4], bd_q[3:0]};

	// ---- envelope restart: AY_F_RES = DFF(DFF(VCC, AY_CCC7, AY_F_R1), AY_CCC7, AY_F_R1)
	reg        f_r1 = 1'b0, f_res1 = 1'b0, f_res = 1'b0;
	wire       f_res1_e = f_r1 & f_res1;
	wire       f_res_e  = f_r1 & f_res;

	// ---- microprogram RAM: lpm_ram_dq with inclock and outclock CLK42 (address, data, we and output registered)
	reg  [7:0] mem [0:255];
	initial $readmemh(MIF_HEX, mem);
	// karabas: reload on CFG_RST from a ROM copy of the MIF through the write port
	reg  [7:0] ini [0:255];
	initial $readmemh(MIF_HEX, ini);
	reg  [8:0] rl_a = 9'd0;
	reg  [7:0] rl_wa = 8'd0, rl_d = 8'd0;
	reg        rl_we = 1'b0;
	reg  [7:0] ram_q = 8'd0;                    // read in the CE after the address latch
	reg  [7:0] ay_do = 8'd0;                    // output register
	reg  [7:0] dat = 8'd0;
	reg        c = 1'b0;
	reg        cxx_q = 1'b0, cx_q = 1'b0;
	reg  [7:0] ax; reg ay_wr; reg [7:0] di; reg dat_wr_d;
	always @* begin
		case (ccc[1:0])
			2'b00: begin ax = {2'b10, ccc[7:2]}; ay_wr = 1'b0; di = dat; dat_wr_d = 1'b1; end
			2'b01: begin ax = {4'b0000, adr[3:0]}; ay_wr = ~bwr; di = bd; dat_wr_d = 1'b1; end
			default: begin
				ax = {3'b000, ay_do[4:0]}; dat_wr_d = ay_do[6]; di = dat;
				ay_wr = (ay_do[7:5] == 3'b010) | ((ay_do[7:5] == 3'b110) & cxx_e);
			end
		endcase
	end

	reg  [7:0] dd = 8'd0;
	reg        dat_wr = 1'b0, dat_wr2 = 1'b0;
	reg        n5 = 1'b0, d7 = 1'b0, sb = 1'b0, do0d = 1'b0;

	// AY_CX / AY_CXX
	reg        p_cx = 1'b0, e_cx = 1'b0, s010 = 1'b0, rexp = 1'b0;
	wire       cx_e  = p_cx ? 1'b1 : cx_q;
	wire       cxx_e = p_cx ? 1'b1 : cxx_q;

	// tone / noise / envelope state
	reg  [3:1] out_q = 3'd0;
	reg        outs1 = 1'b0, outs2 = 1'b0, outs3 = 1'b0, outsx = 1'b0, sh_q = 1'b0;
	reg  [3:0] amp = 4'd0, aa = 4'd0;
	reg  [3:0] dq1 = 4'd0, dq2 = 4'd0, dq3 = 4'd0, dqx_q = 4'd0;
	reg        ch_mix = 1'b0, bp = 1'b0;
	wire [3:0] dqx_e = sh_q ? 4'd0 : (dqx_q | (bp ? 4'b1101 : 4'b0000));
	reg [16:0] sh_r = 17'd0;
	wire [16:0] sh = RESET_N ? sh_r : {17{1'b1}};
	reg        va_ena = 1'b0;
	reg  [5:0] vcnt = 6'd0;                     // (AY_VX, AY_VA[3..0], AY_VAR), clrn AY_F_RES
	wire [5:0] vcnt_e = f_res_e ? vcnt : 6'd0;
	wire       vx = vcnt_e[5];
	wire [3:0] va = vcnt_e[4:1];
	reg        x_ena = 1'b0, gf_ena = 1'b0;
	reg  [5:0] x_ = 6'd0;
	reg  [3:0] gf = 4'd0;
	reg        bblk = 1'b0, ablk = 1'b0, binv = 1'b0;
	wire       ainv = gf[2];

	reg  [8:0] cs = 9'd0;
	reg        outs1x = 1'b0, outs2x = 1'b0, outs3x = 1'b0, outs1y = 1'b0, outs3y = 1'b0;
	reg        lclr = 1'b0, lena1 = 1'b0, lena2 = 1'b0, rena1 = 1'b0, rena2 = 1'b0;
	reg [10:0] lx = 11'd0, rx = 11'd0;
	wire [10:0] lx_e = lclr ? 11'd0 : lx;
	wire [10:0] rx_e = lclr ? 11'd0 : rx;

	wire       mix1 = (out_q[1] | x_[0]) & (x_[3] | sh[0]);
	wire       mix2 = (out_q[2] | x_[1]) & (x_[4] | sh[0]);
	wire       mix3 = (out_q[3] | x_[2]) & (x_[5] | sh[0]);
	wire       ccc1 = ccc[1];
	wire [8:0] dat_sub = {1'b0, ay_do} - {8'd0, sb};

	wire       mem_we = rl_we | (CE & ay_wr);
	wire [7:0] mem_wa = rl_we ? rl_wa : ax;
	wire [7:0] mem_wd = rl_we ? rl_d : di;
	always @(posedge CLK) begin
		rl_we <= 1'b0;
		if (CFG_RST) begin rl_we <= ~rl_a[8]; if (~rl_a[8]) rl_a <= rl_a + 9'd1; end
		else rl_a <= 9'd0;
		rl_wa <= rl_a[7:0];
		rl_d  <= ini[rl_a[7:0]];
		if (mem_we) mem[mem_wa] <= mem_wd;
	end

	always @(posedge CLK) begin
	if (CE) begin
		ccc <= AY_T;
		if (ccc1) begin bd_q <= D; bwr <= AY_D_WR; end
		if (bd_clr75) bd_q[7:5] <= 3'b000;
		if (bd_clr4)  bd_q[4] <= 1'b0;
		if (AY_A_WR_EV) begin
			adr <= D;
			aax <= {(D[3:0] == 4'h8) | (D[3:0] == 4'h9) | (D[3:0] == 4'hA), D[3:0] == 4'hD};
		end

		f_r1 <= ~aax[0] | bwr;
		if (~f_r1) begin f_res1 <= 1'b0; f_res <= 1'b0; end
		else if (ccc7_rise) begin f_res1 <= 1'b1; f_res <= f_res1_e; end

		// RAM: address / data / we latched now, the word read now goes to the output register at the next CE
		if (ay_wr) ram_q <= di;                 // write-first (the RAM write is above)
		else ram_q <= mem[mem_wa];   // = ax; the reload address only during CFG_RST: one address keeps BRAM
		ay_do <= ram_q;

		if (~ccc[1] & ~ccc[0]) dd <= ay_do;
		dat_wr  <= dat_wr_d;
		dat_wr2 <= dat_wr;
		n5   <= ~ay_do[5];
		d7   <= ay_do[7];
		sb   <= n5 | (c & d7);
		do0d <= ay_do[0];
		if (~dat_wr2) {c, dat} <= dat_sub;

		p_cx <= (ay_do[7:5] == 3'b000) & ccc1;
		e_cx <= ((ay_do[7:5] == 3'b010) | (ay_do[7:5] == 3'b111)) & ccc1;
		s010 <= ay_do[7:5] == 3'b010;
		rexp <= (~RESET_N & ay_do[0]) | (~f_res_e & ~ay_do[0]);
		if (p_cx) begin cx_q <= 1'b1; cxx_q <= 1'b1; end
		else if (e_cx) begin
			cx_q  <= s010 ? (dat == 8'd0) & cx_q : rexp;
			cxx_q <= s010 ? ((dat == 8'd0) & cxx_q) | (c & do0d) : rexp;
		end

		outs1 <= (ay_do[7:5] == 3'b011) & (ay_do[2:0] == 3'b001) & ccc1;
		outs2 <= (ay_do[7:5] == 3'b011) & (ay_do[2:0] == 3'b010) & ccc1;
		outs3 <= (ay_do[7:5] == 3'b011) & (ay_do[2:0] == 3'b011) & ccc1;
		outsx <= (ay_do[7:5] == 3'b011) & ((ay_do[2:1] == 2'b01) | ((ay_do[2] == 1'b0) & ay_do[0])) & ccc1;
		sh_q  <= (ay_do[7:5] == 3'b011) & (ay_do[2:0] == 3'b100) & ccc1;
		if (outs1) begin out_q[1] <= cx_e ^ out_q[1]; dq1 <= amp & {4{mix1}}; end
		if (outs2) begin out_q[2] <= cx_e ^ out_q[2]; dq2 <= amp & {4{mix2}}; end
		if (outs3) begin out_q[3] <= cx_e ^ out_q[3]; dq3 <= amp & {4{mix3}}; end
		amp <= (dat[3:0] | {4{dat[4]}}) & (aa | {4{~dat[4]}});
		case (ay_do[1:0])
			2'd2: ch_mix <= mix2;
			2'd3: ch_mix <= mix3;
			default: ch_mix <= mix1;
		endcase
		bp <= sh_q & BEEPER;
		if (sh_q) dqx_q <= 4'd0;
		else if (outsx) dqx_q <= (amp & {4{ch_mix}}) | (bp ? 4'b1101 : 4'b0000);
		else dqx_q <= dqx_e;

		if (~RESET_N) sh_r <= {17{1'b1}};
		else if (sh_q & cxx_e) sh_r <= {sh[3] ^ sh[0], sh[16:1]};

		va_ena <= (ay_do[7:5] == 3'b011) & (ay_do[2:0] == 3'b101) & ccc1 & ~bblk & cx_e;
		if (~f_res_e) vcnt <= 6'd0;
		else if (va_ena) vcnt <= vcnt + 6'd1;
		x_ena  <= (ay_do[7:5] == 3'b011) & (ay_do[2:0] == 3'b110) & ccc1;
		gf_ena <= (ay_do[7:5] == 3'b011) & (ay_do[2:0] == 3'b111) & ccc1;
		if (x_ena) x_ <= dat[5:0];
		if (gf_ena) gf <= dat[3:0];
		bblk <= vx & (gf[0] | ~gf[3]);
		ablk <= ~gf[3] & vx;
		binv <= vx & ((gf[3] & gf[1:0] == 2'b10) | (gf[3] & gf[1:0] == 2'b01));
		aa   <= (va ^ {4{binv}} ^ {4{~ainv}}) & {4{~ablk}};

		// clocked by AY_CCC7: the ripple edge comes after CLK42, so these see the new DQ1..3
		if (ccc7_rise) begin
			AY_CH_A <= outs1 ? amp & {4{mix1}} : dq1;
			AY_CH_B <= outs2 ? amp & {4{mix2}} : dq2;
			AY_CH_C <= outs3 ? amp & {4{mix3}} : dq3;
		end

		case (dqx_e)
			4'd15: cs <= 9'd360; 4'd14: cs <= 9'd255; 4'd13: cs <= 9'd180; 4'd12: cs <= 9'd127;
			4'd11: cs <= 9'd90;  4'd10: cs <= 9'd64;  4'd9:  cs <= 9'd45;  4'd8:  cs <= 9'd32;
			4'd7:  cs <= 9'd22;  4'd6:  cs <= 9'd16;  4'd5:  cs <= 9'd11;  4'd4:  cs <= 9'd8;
			4'd3:  cs <= 9'd6;   4'd2:  cs <= 9'd4;   4'd1:  cs <= 9'd2;   default: cs <= 9'd0;
		endcase
		outs1x <= outs1;
		outs2x <= outs2 | sh_q;
		outs3x <= outs3;
		outs1y <= outs1 | outs1x;
		outs3y <= outs3 | outs3x;
		lclr  <= ccc[7:2] == 6'd0;
		lena1 <= outs1 | outs1y | outs2x | outs2;
		lena2 <= lena1;
		rena1 <= outs3 | outs3y | outs2x | outs2;
		rena2 <= rena1;
		if (lclr) lx <= 11'd0; else if (lena2) lx <= lx + {2'b00, cs};
		if (lclr) rx <= 11'd0; else if (rena2) rx <= rx + {2'b00, cs};
		AY_CH_VAL <= ccc[7:2] == 6'b111100;
	end
	if (CFG_RST) begin   // the power-up values above
		AY_CH_A <= 4'd0; AY_CH_B <= 4'd0; AY_CH_C <= 4'd0; AY_CH_VAL <= 1'b0; ccc <= 9'd0; adr <= 8'd0; aax <= 2'd0;
		bd_q <= 8'd0; bwr <= 1'b0; f_r1 <= 1'b0; f_res1 <= 1'b0; f_res <= 1'b0; ram_q <= 8'd0; ay_do <= 8'd0;
		dat <= 8'd0; c <= 1'b0; cxx_q <= 1'b0; cx_q <= 1'b0; dd <= 8'd0; dat_wr <= 1'b0; dat_wr2 <= 1'b0; n5 <= 1'b0;
		d7 <= 1'b0; sb <= 1'b0; do0d <= 1'b0; p_cx <= 1'b0; e_cx <= 1'b0; s010 <= 1'b0; rexp <= 1'b0; out_q <= 3'd0;
		outs1 <= 1'b0; outs2 <= 1'b0; outs3 <= 1'b0; outsx <= 1'b0; sh_q <= 1'b0; amp <= 4'd0; aa <= 4'd0;
		dq1 <= 4'd0; dq2 <= 4'd0; dq3 <= 4'd0; dqx_q <= 4'd0; ch_mix <= 1'b0; bp <= 1'b0; sh_r <= 17'd0;
		va_ena <= 1'b0; vcnt <= 6'd0; x_ena <= 1'b0; gf_ena <= 1'b0; x_ <= 6'd0; gf <= 4'd0; bblk <= 1'b0;
		ablk <= 1'b0; binv <= 1'b0; cs <= 9'd0; outs1x <= 1'b0; outs2x <= 1'b0; outs3x <= 1'b0; outs1y <= 1'b0;
		outs3y <= 1'b0; lclr <= 1'b0; lena1 <= 1'b0; lena2 <= 1'b0; rena1 <= 1'b0; rena2 <= 1'b0; lx <= 11'd0;
		rx <= 11'd0;
	end
	end

	assign DO = dd;
	assign AY_CH_L = lx_e[10:1];
	assign AY_CH_R = rx_e[10:1];
endmodule
