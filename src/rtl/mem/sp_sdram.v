// Sprinter on the Karabas Mini G: the DRAM of the ACEX (4 MB, RAS_ / CAS_[3:0] / WE_N / MA[11:0]) on the
// MT48LC16M16A2 at 84 MHz (CL 2, BL 1, auto precharge). Contracts: docs/memtiming.md 3; edges c0..c11 as in sp_sram.
//
// One DRAM cycle of the ACEX per 7 MHz cycle, followed by the pins:
//   c5   RAS_ low: ACTIVE (bank 0, row {MA[11], MCA1, MA[10:0]}: MA = row c2..c6, MCA from c2; MA[11] = 0 for 4 MB)
//        RAS_ high and CAS_ = 0000 (CBR): AUTO REFRESH; RAS_ high and our counter ran out: AUTO REFRESH too
//   c7   CAS_ low (fell at c6) and WE_N high: READ with auto precharge, column MA[8:0]; data in the IOB at c10
//   c9   WE_N low (from c7) and CAS_ low (fell at c8): WRITE with auto precharge, DQM from CAS_ of bank MCA1,
//        data MD_O (stable c4..c14); CAS_ low at c8 with WE_N high (a blocked write: the DRAM of the original
//        reads): READ with auto precharge, data at c12
//   c11  an ACTIVE without READ / WRITE (blocked cycles): PRECHARGE
// tRCD 2, tRAS 4 (c5 -> c9), tRP 2, tRC 6: the bank is free at c11 (read) / c14 (write); the next ACTIVE is c17.
// The window c11..c17 of a cycle is free for a second channel (MCU loader, disk images): AUX_* is a stub for now.
// Read data for the ACEX: MD_Q / MD_DRV (byte lanes [1] = MD[15:8]) from the CLK after the IOB took it (c10, or
// c12 for the blocked write) to c14 (= c2 of the next cycle) inclusive, as the DRAM data the ACEX takes at c13 (DO,
// XMD) and c14 (DCPP); the top puts it on MD_I there and the peripheral data otherwise.
// SDRAM clock: SD_CLK = CLK inverted (ODDR2, as sdram2p of core-tsconf): the SDRAM takes a command half a CLK
// after it leaves the IOB, the read word is taken by the IOB on the rising edge CL + 1/2 CLK after the command's
// SDRAM edge (here: READ at n, word in the IOB at n+3).
// Power-up: INIT_WAIT CLK of NOP (100 us: 8400 at 84 MHz; the simulation shortens it), PRECHARGE all, 2 x AUTO
// REFRESH, LOAD MODE; RDY then. The top holds the ACEX in reset till RDY.
module sp_sdram #(
	parameter [15:0] INIT_WAIT = 16'd8400,
	parameter  [5:0] REF_CYC   = 6'd40       // own AUTO REFRESH after this many 7 MHz cycles without one (5.7 us)
) (
	input             CLK,
	input             CE,
	input             CE_N,
	input       [2:0] CT,           // sp_acex CT_PH
	// DRAM pins of sp_acex
	input             RAS_N,        // RAS_[0] (both are the same)
	input       [3:0] CAS_N,
	input             WE_N,
	input      [11:0] MA,
	input       [1:0] MCA,
	input      [15:0] MD_O,
	output     [15:0] MD_Q,
	output reg  [1:0] MD_DRV = 2'b00,
	output reg        RDY = 1'b0,
	// second channel (stub)
	input             AUX_REQ,
	output            AUX_ACK,
	// SDRAM pins (the top makes the tristate: SD_DQ = SD_DQ_T[i] ? Z : SD_DQ_O[i])
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
	input      [15:0] SD_DQ_I
);
	assign AUX_ACK = 1'b0;

	reg  [3:0] e;
	reg  [3:0] f;
	always @* begin
		case (CT)
			3'd5: f = 4'd0; 3'd6: f = 4'd2; 3'd0: f = 4'd4; 3'd1: f = 4'd6; 3'd2: f = 4'd8; default: f = 4'd10;
		endcase
		e = CE ? f : (f == 4'd0 ? 4'd11 : f - 4'd1);
	end

	localparam [2:0] C_NOP = 3'b111, C_ACT = 3'b011, C_RD = 3'b101, C_WR = 3'b100, C_PRE = 3'b010, C_REF = 3'b001,
	                 C_LMR = 3'b000;
	(* IOB = "TRUE" *) reg  [2:0] cmd = C_NOP;
	(* IOB = "TRUE" *) reg  [1:0] ba = 2'b00;
	(* IOB = "TRUE" *) reg [12:0] sa = 13'd0;
	(* IOB = "TRUE" *) reg  [1:0] dqm = 2'b11;
	(* IOB = "TRUE" *) reg [15:0] dq_o = 16'd0;
	(* IOB = "TRUE", equivalent_register_removal = "no" *) reg [15:0] dq_t = 16'hFFFF;
	(* IOB = "TRUE" *) reg [15:0] dq_in = 16'd0;
	assign {SD_RAS_N, SD_CAS_N, SD_WE_N} = cmd;
	assign SD_CS_N = 1'b0;
	assign SD_CKE  = 1'b1;
	assign SD_BA   = ba;
	assign SD_A    = sa;
	assign SD_DQM  = dqm;
	assign SD_DQ_O = dq_o;
	assign SD_DQ_T = dq_t;
	ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b0), .SRTYPE("SYNC")) u_ck (
		.Q(SD_CLK), .C0(CLK), .C1(~CLK), .CE(1'b1), .D0(1'b0), .D1(1'b1), .R(1'b0), .S(1'b0));

	// ================= power-up
	reg [15:0] ic = 16'd0;
	wire [15:0] it = ic - INIT_WAIT;              // steps after the wait

	// ================= the DRAM cycle
	reg        act = 1'b0, done = 1'b0;
	reg  [5:0] rcnt = 6'd0;
	reg  [2:0] rp = 3'b000;                       // a READ went out 1 / 2 / 3 CLK ago
	reg  [1:0] rl = 2'b00, rl_p = 2'b00;          // lanes of the read
	reg        byp = 1'b0;
	reg [15:0] md_q = 16'd0;
	wire [1:0] lanes = MCA[1] ? ~CAS_N[3:2] : ~CAS_N[1:0];
	assign MD_Q = byp ? dq_in : md_q;

	always @(posedge CLK) begin
		dq_in <= SD_DQ_I;
		cmd   <= C_NOP;
		dqm   <= 2'b11;
		dq_t  <= 16'hFFFF;
		rp    <= {rp[1:0], 1'b0};
		// read data: in dq_in at the edge 3 CLK after the READ
		byp <= rp[2];
		if (rp[2]) begin MD_DRV <= rl_p; end
		if (byp) md_q <= dq_in;
		if (e == 4'd2 & ~rp[2]) MD_DRV <= 2'b00;

		if (!RDY) begin
			if (ic != 16'hFFFF) ic <= ic + 16'd1;
			if (ic >= INIT_WAIT) case (it)
				16'd0:  begin cmd <= C_PRE; sa <= 13'h0400; end                  // PRECHARGE all
				16'd3:  cmd <= C_REF;
				16'd10: cmd <= C_REF;
				16'd17: begin cmd <= C_LMR; ba <= 2'b00; sa <= 13'b000_1_00_010_0_000; end   // single write, CL 2, BL 1
				16'd20: RDY <= 1'b1;
				default: ;
			endcase
		end else begin
			case (e)
				4'd5: begin
					done <= 1'b0;
					if (!RAS_N) begin
						cmd <= C_ACT; ba <= 2'b00; sa <= {MA[11], MCA[1], MA[10:0]}; act <= 1'b1;
						if (rcnt != 6'h3F) rcnt <= rcnt + 6'd1;
					end else if (CAS_N == 4'b0000 || rcnt >= REF_CYC) begin
						cmd <= C_REF; rcnt <= 6'd0;
					end else if (rcnt != 6'h3F) rcnt <= rcnt + 6'd1;
				end
				4'd7:
					if (act & ~done & WE_N & (lanes != 2'b00)) begin
						cmd <= C_RD; sa <= {4'b0010, MA[8:0]}; dqm <= 2'b00; done <= 1'b1;
						rp[0] <= 1'b1; rl <= lanes;
					end
				4'd9:
					if (act & ~done & (lanes != 2'b00)) begin
						done <= 1'b1;
						if (!WE_N) begin
							cmd <= C_WR; sa <= {4'b0010, MA[8:0]}; dqm <= ~lanes; dq_o <= MD_O; dq_t <= 16'h0000;
						end else begin
							cmd <= C_RD; sa <= {4'b0010, MA[8:0]}; dqm <= 2'b00; rp[0] <= 1'b1; rl <= lanes;
						end
					end
				4'd11: begin
					if (act & ~done) begin cmd <= C_PRE; sa <= 13'h0000; end
					act <= 1'b0;
				end
				default: ;
			endcase
		end
		if (rp[1]) rl_p <= rl;
	end
endmodule
