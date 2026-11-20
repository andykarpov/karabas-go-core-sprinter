// Sprinter on the Karabas Mini G: controller of the shared 16-bit SRAM (2 x IS61WV20488BLL-10, MA[20:0], one
// /WE and one /OE per byte chip) at 84 MHz for the translated ACEX (sp_acex): video RAM, ROM, fastram (the cache,
// CS_CASH), a write port for the loader (the MCU writes the ROM image), and the palette shadow in BRAM.
// Contracts and slot plan: docs/memtiming.md (sections 1, 2, 4, 6).
//
// Time axis: CLK = 84 MHz, CE / CE_N alternate (CLK42 rising / falling). The 7 MHz memory cycle is 12 edges
// c0..c11, c0 = the CE before which CT[2:0] = 5 (after it CT = 6). Every access takes 2 CLK: a slot [s, s+2] starts
// at an odd edge s (c11, c1, c3, c5, c7, c9): the address leaves an IOB register at s, the data is in the IOB input
// register md_in at s+2 (TS_SRAM_OUT 8 ns + tAA 10 ns + TS_SRAM_IN 4 ns = 22 ns < 23.8 ns). A write: address and
// data from s, the data drive (T) from s+1/2 to s+2, /WE low from s+1/2 to s+3/2 (ODDR2: /WE is the write flag of
// [s, s+1) half a CLK later), /OE high for the whole slot (the SRAM stops driving within tHZOE <= 4 ns, before
// the data drive). The slot is decided at its start edge from what is visible then:
//   W  [11,1]       video write (VA_NX = VXA and VDO at c11, V_WR_NX taken at c10), also into the palette shadow
//   P  [3,5]        pixels, VA_NX at c3 (only when PIX_RQ)
//   A  [1,3] [3,5]  ZX attribute by VA_ATR (ATR_ZX) or [5,7] by VA_NX at c5 (the only one for graphics); at c5
//                   a ZX attribute fetched by VA_ATR is fetched again when VA_NX turned out different
//   MH / ML         mode table halves (bytes 3,2 / 1,0) by VA_MOD in [1,3]..[9,11] (MODE_RQ; ML also MLO_RQ, from
//                   c3); they take a slot before the CPU only when the rest of the cycle would not hold them
//   C               ROM / fastram read for the CPU, speculative: on a change of A (not in refresh), or of RA / SEL_*
//   B               the cache write buffer (1 byte, captured at the fall of /WR), L the loader: free slots only
//                   (a loader write to the word fetched for the CPU makes it fetch again: the ROM loaded under
//                   a fetch made during the reset)
// Priority: W, P, A at its deadline (c5), urgent M, C, A early, M, B, L.
// The data for the ACEX (VDx_I) is assembled per period: the consumers take the data of a VA presented at CE n at
// CE n+2 (MODE0..2, VDM3..1) and CE_N n+3 (D_PICx_): P on the bus before c7, A before c9, the mode word before c12
// (= c0) and c13 (= c1). A register is shown as md_in itself in the CLK where md_in holds its data (bypass).
// SIM_X = 1 (simulation): data not fetched for a period is X, so a missed slot shows up in the equivalence test.
//
// Layout (16-bit words): video RAM 0x000000..0x03FFFF (512 KB, sp_video2 uses 256 KB), ROM 0x040000..0x05FFFF
// (256 KB), fastram 0x060000..0x067FFF (64 KB), the rest free. A video byte lane i of the 32-bit word (VDi) is the
// half i[1], byte i[0] (0 = SRAM D[7:0]); ROM / fastram byte address b: word b >> 1, byte b[0].
module sp_sram #(
	parameter [20:0] ROM_BASE  = 21'h040000,
	parameter [20:0] FAST_BASE = 21'h060000,
	parameter        SIM_X     = 0
) (
	input             CLK,
	input             CE,
	input             CE_N,
	input       [2:0] CT,           // sp_acex CT_PH
	// video (sp_acex)
	input      [17:1] VA_NX,
	input       [3:0] V_WR_NX,
	input      [15:0] VA_MOD,
	input             MODE_RQ,
	input             MLO_RQ,
	input      [17:1] VA_ATR,
	input             ATR_ZX,
	input             PIX_RQ,
	input       [7:0] VD0_O,
	input       [7:0] VD1_O,
	input       [7:0] VD2_O,
	input       [7:0] VD3_O,
	input      [15:0] VA,           // the palette read address (sp_acex VA in the periods c2-3 / c8-9)
	output      [7:0] VD0_I,
	output      [7:0] VD1_I,
	output      [7:0] VD2_I,
	output      [7:0] VD3_I,
	output reg [31:0] PAL_Q = 32'd0, // palette entry of VA, registered every CLK: stable over the WR_COL rise
	// CPU (Z80 pins and sp_acex outputs)
	input      [15:0] A,
	input     [17:14] RA,
	input             SEL_ROM,
	input             SEL_CASH,
	input             RF_N,
	input             MR_N,
	input             WR_N,
	input             CS_CASH,
	input       [7:0] CPU_D,        // CPU write data (valid at the fall of /WR)
	input             CPU_FLUSH,    // forget the fetched CPU byte (ROM changed under it)
	output      [7:0] CPU_Q,        // ROM / fastram byte of the current A (valid when CPU_RDY)
	output            CPU_RDY,
	output            CPU_WAIT_N,   // /WAIT for the CPU (the top ANDs it with the ACEX /WAIT): the byte would be late
	// loader: a write is taken (in a free slot) at the CLK where LD_ACK is high; hold LD_A / LD_BE / LD_D till then
	input             LD_REQ,
	input      [20:0] LD_A,         // word address
	input       [1:0] LD_BE,        // [1] = D[15:8]
	input      [15:0] LD_D,
	output reg        LD_ACK = 1'b0,
	output reg        WB_OVF = 1'b0, // a cache write came while the buffer was full (sticky; should never happen)
	// SRAM pins (the top makes the tristate: SRAM_D = SRAM_D_T[i] ? Z : SRAM_D_O[i])
	output     [20:0] SRAM_A,
	output     [15:0] SRAM_D_O,
	output     [15:0] SRAM_D_T,
	input      [15:0] SRAM_D_I,
	output      [1:0] SRAM_WE_N,
	output      [1:0] SRAM_OE_N
);
	// ================= edge number
	reg  [3:0] e;                        // the edge at this posedge (CE: even, CE_N: odd)
	reg  [3:0] f;
	always @* begin
		case (CT)
			3'd5: f = 4'd0; 3'd6: f = 4'd2; 3'd0: f = 4'd4; 3'd1: f = 4'd6; 3'd2: f = 4'd8; default: f = 4'd10;
		endcase
		e = CE ? f : (f == 4'd0 ? 4'd11 : f - 4'd1);
	end
	reg  [3:0] ph = 4'd0;                // the last edge
	wire       slot = e[0];

	// ================= targets
	localparam [3:0] G_NONE = 4'd0, G_W = 4'd1, G_P = 4'd2, G_A = 4'd3, G_MH = 4'd4, G_ML = 4'd5, G_C = 4'd6,
	                 G_B = 4'd7, G_L = 4'd8;

	// W: the lanes of the write registered at c10 (V_WR_NX is stable c10..c11; a path of one CLK less)
	reg  [3:0] wl = 4'd0;
	wire       w_half = wl[3] | wl[2];
	wire       w_req  = (e == 4'd11) & (|wl);

	// A, M flags of the cycle (cleared at c11, the slot before the first one of the cycle)
	reg        a_done = 1'b0, a_atr = 1'b0, mh_done = 1'b0, ml_done = 1'b0;
	reg [17:1] a_addr = 17'd0;
	wire       a_fix  = (e == 4'd5) & (~a_done | (a_atr & (VA_NX != a_addr)));
	wire       a_early = ATR_ZX & ~a_done & ((e == 4'd1) | (e == 4'd3));
	wire       mh_ok  = MODE_RQ & ~mh_done & (e >= 4'd1) & (e <= 4'd9);
	wire       ml_ok  = ((MODE_RQ & (e >= 4'd1)) | (MLO_RQ & (e >= 4'd3))) & ~ml_done & (e <= 4'd9);
	// M is urgent when the slots left up to c9 (minus P at c3 and A by c5 still to come) are no more than the halves
	// pending: at c1 4 - P - A >= 2, at c3 3 - A >= 2, at c5 2: never; at c7 1 (both pending), at c9 0 (any)
	wire       m_urg  = ((e == 4'd7) & mh_ok & ml_ok) | ((e == 4'd9) & (mh_ok | ml_ok));

	// C: the CPU byte. A fetch starts when A changes (not in refresh: A = {I, R}), in any window (one per M-cycle,
	// as the slot plan assumes; a fetch in a DRAM window is wasted), or one edge after RA / the select changed alone
	// (port writes): the fast trigger is the A pins against the fetched A, RA and SEL_* (deeper) only feed the address.
	wire [18:0] key_now = SEL_CASH ? {1'b1, 2'b00, RA[15:14], A[13:0]} : {1'b0, RA[17:14], A[13:0]};
	reg  [18:0] c_key = 19'd0;
	reg  [15:0] c_a = 16'd0;
	reg         c_have = 1'b0, c_pend = 1'b0, c_valid = 1'b0, c_oth = 1'b0;
	reg  [15:0] c_word = 16'd0;
	wire        key_new = RF_N & (~c_have | (A != c_a) | c_oth);
	wire        c_req   = key_new | c_pend;
	wire [18:0] c_k     = key_new ? key_now : c_key;
	wire [20:0] c_wa    = c_k[18] ? (FAST_BASE | {6'd0, c_k[15:1]}) : (ROM_BASE | {4'd0, c_k[17:1]});
	wire [20:0] c_kwa   = c_key[18] ? (FAST_BASE | {6'd0, c_key[15:1]}) : (ROM_BASE | {4'd0, c_key[17:1]});

	// B: the cache write buffer
	reg  [15:0] wb_a = 16'd0;
	reg   [7:0] wb_d = 8'd0;
	reg         wb_pend = 1'b0, wb_cap = 1'b0;
	wire        wb_now = ~CS_CASH & ~MR_N & ~WR_N & (RA[17:16] == 2'b01) & ~wb_cap;

	// ================= the decision at a slot edge
	reg  [3:0] g;
	reg [20:0] g_a;
	reg [15:0] g_d;
	reg  [1:0] g_be;                     // write lanes, 0 = read
	always @* begin
		g = G_NONE; g_a = 21'd0; g_d = 16'd0; g_be = 2'b00;
		if (e == 4'd11) begin
			if (w_req) g = G_W;
			else if (c_req) g = G_C;
			else if (wb_pend) g = G_B;
			else if (LD_REQ) g = G_L;
		end else begin
			if ((e == 4'd3) & PIX_RQ) g = G_P;
			else if (a_fix) g = G_A;
			else if (m_urg) g = mh_ok ? G_MH : G_ML;
			else if (c_req) g = G_C;
			else if (a_early) g = G_A;
			else if (mh_ok) g = G_MH;
			else if (ml_ok) g = G_ML;
			else if (wb_pend) g = G_B;
			else if (LD_REQ) g = G_L;
		end
		case (g)
			G_W:  begin g_a = {4'd0, VA_NX[17:2], w_half}; g_be = w_half ? wl[3:2] : wl[1:0];
			            g_d = w_half ? {VD3_O, VD2_O} : {VD1_O, VD0_O}; end
			G_P:  g_a = {4'd0, VA_NX};
			G_A:  g_a = {4'd0, (e == 4'd5) ? VA_NX : VA_ATR};
			G_MH: g_a = {4'd0, VA_MOD, 1'b1};
			G_ML: g_a = {4'd0, VA_MOD, 1'b0};
			G_C:  g_a = c_wa;
			G_B:  begin g_a = FAST_BASE | {6'd0, wb_a[15:1]}; g_d = {wb_d, wb_d}; g_be = {wb_a[0], ~wb_a[0]}; end
			G_L:  begin g_a = LD_A; g_d = LD_D; g_be = LD_BE; end
			default: ;
		endcase
	end

	// ================= pins
	(* IOB = "TRUE" *) reg [20:0] sa = 21'd0;
	// the write data: an ODDR2 like the data drive (T) of the same pins (an OLOGIC takes OFF and TFF both SDR or both
	// DDR): D0 = the value the register takes at this rising edge, D1 = the register, i.e. the pin as an IOB register
	reg [15:0] sd_o = 16'd0;
	wire [15:0] sd_n;
	(* IOB = "TRUE" *) reg  [1:0] oe_n = 2'b00;
	// the read data: an IDDR2 (Q0 = the pin at the rising edge, i.e. an IOB register): the same pins have DDR
	// outputs (ODDR2 data and T), and an IOB does not take SDR and DDR together
	wire [15:0] md_in;
	reg        w1 = 1'b0, w2 = 1'b0;         // write slot: first / second CLK
	reg  [1:0] wlan = 2'b00;
	assign SRAM_A    = sa;
	assign SRAM_OE_N = oe_n;
	// /WE: low from s+1/2 to s+3/2; data drive (T = 0) from s+1/2 to s+2 (D0 at the rising edge, D1 at the falling)
	genvar i;
	generate
		for (i = 0; i < 2; i = i + 1) begin : g_we
			ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b1), .SRTYPE("SYNC")) u_we (.Q(SRAM_WE_N[i]), .C0(CLK), .C1(~CLK),
				.CE(1'b1), .D0(~(w1 & wlan[i])), .D1(~(w1 & wlan[i])), .R(1'b0), .S(1'b0));
		end
		for (i = 0; i < 16; i = i + 1) begin : g_do
			ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b0), .SRTYPE("SYNC")) u_d (.Q(SRAM_D_O[i]), .C0(CLK), .C1(~CLK),
				.CE(1'b1), .D0(sd_n[i]), .D1(sd_o[i]), .R(1'b0), .S(1'b0));
		end
		for (i = 0; i < 16; i = i + 1) begin : g_di
			IDDR2 #(.DDR_ALIGNMENT("NONE"), .INIT_Q0(1'b0), .INIT_Q1(1'b0), .SRTYPE("SYNC")) u_di (.Q0(md_in[i]), .Q1(),
				.C0(CLK), .C1(~CLK), .CE(1'b1), .D(SRAM_D_I[i]), .R(1'b0), .S(1'b0));
		end
		for (i = 0; i < 16; i = i + 1) begin : g_t
			ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b1), .SRTYPE("SYNC")) u_t (.Q(SRAM_D_T[i]), .C0(CLK), .C1(~CLK),
				.CE(1'b1), .D0(~w1), .D1(~(w1 | w2)), .R(1'b0), .S(1'b0));
		end
	endgenerate

	// the write data the register takes (at a slot edge; else it holds)
	assign sd_n = ~slot ? sd_o : w_req ? (w_half ? {VD3_O, VD2_O} : {VD1_O, VD0_O}) : wb_pend ? {wb_d, wb_d} : LD_D;

	// ================= read data: tags, registers, views
	reg  [3:0] tag_cur = G_NONE, tag_land = G_NONE;
	reg        p_half = 1'b0, a_half = 1'b0, c_bfwd = 1'b0;
	reg [18:0] c_tkey = 19'd0;
	reg [15:0] p_q = 16'd0, a_q = 16'd0, mh_q = 16'd0, ml_q = 16'd0;
	wire       land_odd = ph[0];
	wire [15:0] p_v  = (land_odd & (tag_land == G_P))  ? md_in : p_q;
	wire [15:0] a_v  = (land_odd & (tag_land == G_A))  ? md_in : a_q;
	wire [15:0] mh_v = (land_odd & (tag_land == G_MH)) ? md_in : mh_q;
	wire [15:0] ml_v = (land_odd & (tag_land == G_ML)) ? md_in : ml_q;
	// the CPU word as it lands: merged with the buffered cache write to the same word
	wire        c_land = land_odd & (tag_land == G_C) & (c_tkey == c_key);
	wire        c_fwd  = (wb_pend | c_bfwd) & c_tkey[18] & (wb_a[15:1] == c_tkey[15:1]);
	wire [15:0] c_lw   = ~c_fwd ? md_in : wb_a[0] ? {wb_d, md_in[7:0]} : {md_in[15:8], wb_d};
	wire [15:0] c_v    = c_land ? c_lw : c_word;
	assign CPU_Q   = c_key[0] ? c_v[15:8] : c_v[7:0];
	assign CPU_RDY = c_have & (c_valid | c_land);
	// /WAIT: a ROM / fastram cycle (not refresh, no /WR yet) whose byte is neither here nor in flight in a slot that
	// lands in time. T80pa samples /WAIT at the fall of T2 / TW (the CE_N c_f+3, ...) and takes the opcode at c_f+5,
	// the read data at c_f+7: a C slot granted at c_f+1 or earlier lands by c_f+3, one granted at the sampling edge
	// itself lands at c_f+5, too late for an opcode. The only case (docs/memtiming.md 4, 7): the first graphics
	// cycle after ZX with PIX_RQ, a cache M1 with c_f = 4 (P at c3, A at its deadline c5, C at c7) -> one TW.
	assign CPU_WAIT_N = ~(~MR_N & RF_N & WR_N & (SEL_ROM | SEL_CASH) & ~CPU_RDY & ~((tag_cur == G_C) & (c_tkey == c_key)));

	localparam [15:0] XX = SIM_X ? 16'hxxxx : 16'h0000;
	reg [31:0] vd;
	always @* begin
		case (ph)
			4'd6:  vd = p_half ? {p_v, XX} : {XX, p_v};
			4'd8:  vd = a_half ? {a_v, XX} : {XX, a_v};
			4'd11, 4'd0: vd = {mh_v, ml_v};
			default: vd = SIM_X ? 32'hxxxxxxxx : {mh_v, ml_v};
		endcase
	end
	assign {VD3_I, VD2_I, VD1_I, VD0_I} = vd;

	// ================= palette shadow: 2048 x 32 (index = {VA[15:8], VA[2:0]}: bytes 0x3E0-0x3FF of each line)
	reg [7:0] pal0 [0:2047], pal1 [0:2047], pal2 [0:2047], pal3 [0:2047];
	wire        pal_we = w_req & (VA_NX[9:5] == 5'b11111);
	wire [10:0] pal_wa = {VA_NX[17:10], VA_NX[4:2]};
	wire [10:0] pal_ra = {VA[15:8], VA[2:0]};
	always @(posedge CLK) begin
		if (pal_we & wl[0]) pal0[pal_wa] <= VD0_O;
		if (pal_we & wl[1]) pal1[pal_wa] <= VD1_O;
		if (pal_we & wl[2]) pal2[pal_wa] <= VD2_O;
		if (pal_we & wl[3]) pal3[pal_wa] <= VD3_O;
		PAL_Q <= {pal3[pal_ra], pal2[pal_ra], pal1[pal_ra], pal0[pal_ra]};
	end

	// ================= registers
	always @(posedge CLK) begin
		ph     <= e;
		if (e == 4'd10) wl <= ~V_WR_NX;
		LD_ACK <= 1'b0;
		w2     <= w1;
		w1     <= 1'b0;

		// CPU key
		if (key_new) begin c_key <= key_now; c_a <= A; c_have <= 1'b1; c_valid <= 1'b0; c_pend <= 1'b1; end
		c_oth <= RF_N & c_have & ~key_new & (key_now[18:14] != c_key[18:14]);
		// cache write buffer
		if (WR_N | MR_N) wb_cap <= 1'b0;
		if (wb_now) begin
			wb_cap <= 1'b1;
			if (wb_pend & ~(slot & (g == G_B))) WB_OVF <= 1'b1;
			wb_a <= {RA[15:14], A[13:0]}; wb_d <= CPU_D; wb_pend <= 1'b1;
			// the fetched byte of that address
			if (c_have & c_key[18] & (c_key[15:0] == {RA[15:14], A[13:0]})) begin
				if (A[0]) c_word[15:8] <= CPU_D; else c_word[7:0] <= CPU_D;
			end
		end

		if (slot) begin
			tag_land <= tag_cur;
			tag_cur  <= g;
			if (g != G_NONE) sa <= g_a;
			oe_n <= (g_be != 2'b00) ? 2'b11 : 2'b00;
			if (g_be != 2'b00) w1 <= 1'b1;
			// data and lanes of the write this slot would make (not on the grant: a write slot is W at c11, else B,
			// else L; the data is not driven in a read slot)
			sd_o <= sd_n;
			if (w_req) wlan <= w_half ? wl[3:2] : wl[1:0];
			else if (wb_pend) wlan <= {wb_a[0], ~wb_a[0]};
			else wlan <= LD_BE;
			case (g)
				G_P: p_half <= VA_NX[1];
				G_A: begin a_done <= 1'b1; a_half <= g_a[0]; a_atr <= (e != 4'd5); a_addr <= (e == 4'd5) ? VA_NX : VA_ATR; end
				G_MH: mh_done <= 1'b1;
				G_ML: ml_done <= 1'b1;
				G_C: begin c_pend <= 1'b0; c_tkey <= c_k; c_bfwd <= 1'b0; end
				G_B: begin wb_pend <= wb_now; if (tag_cur == G_C) c_bfwd <= 1'b1; end   // a read in flight saw the old byte
				G_L: begin LD_ACK <= 1'b1; if (LD_A == c_kwa) begin c_have <= 1'b0; c_valid <= 1'b0; end end   // the loader wrote the fetched word
				default: ;
			endcase
			if (e == 4'd11) begin a_done <= 1'b0; a_atr <= 1'b0; mh_done <= 1'b0; ml_done <= 1'b0; end
		end else begin
			// the data of the slot that landed at the last (odd) edge
			case (tag_land)
				G_P:  p_q  <= md_in;
				G_A:  a_q  <= md_in;
				G_MH: mh_q <= md_in;
				G_ML: ml_q <= md_in;
				G_C:  if (c_land & ~key_new) begin c_word <= c_lw; c_valid <= 1'b1; end
				default: ;
			endcase
			if (SIM_X) begin
				if (e == 4'd0) p_q <= 16'hxxxx;
				if (e == 4'd10) a_q <= 16'hxxxx;
				if (e == 4'd2) begin mh_q <= 16'hxxxx; ml_q <= 16'hxxxx; end
			end
		end
		if (key_new & ~(slot & (g == G_C))) c_pend <= 1'b1;
		if (CPU_FLUSH) begin c_have <= 1'b0; c_valid <= 1'b0; end
	end
endmodule
