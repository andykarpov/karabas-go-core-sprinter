// Behavioural MT48LC16M16A2 for the memory tests: commands on the rising CLK, CL 2 / BL 1 (the mode register is
// checked), banks with open rows, AUTO PRECHARGE, refresh. Timing in clocks of the 84 MHz SDRAM clock (11.9 ns):
// tRCD 2, tRP 2, tRC 6, tRAS 4, tRFC 6, tMRD 2, tWR 2, tRRD 2; refresh at least every T_REFI ns after the
// initialisation; power-up NOPs >= PU_CLK, then PRECHARGE all, >= 2 AUTO REFRESH, LOAD MODE before the first
// ACTIVE. Inputs are checked against tIS / tIH around the clock edge. Read data: X from tLZ after the edge before
// the CL edge, the word tAC after it, held tOH after the CL edge, then Z; a read with a violation gives X.
// Violations are counted (viol), the first ones printed. Memory: 2M words = row[11:0], col[8:0] of bank 0 (4 MB);
// other banks / rows are a violation. Backdoor: mem[].
`timescale 1ns/1ps
module sdram_mt48 #(
	parameter integer PU_CLK = 16,
	parameter real T_AC = 6.0, T_OH = 3.0, T_LZ = 1.0, T_IS = 1.5, T_IH = 0.8, T_REFI = 7800.0
) (
	input             CLK,
	input             CKE,
	input             CS_N,
	input             RAS_N,
	input             CAS_N,
	input             WE_N,
	input       [1:0] BA,
	input      [12:0] A,
	input       [1:0] DQM,
	inout      [15:0] DQ
);
	localparam integer tRCD = 2, tRP = 2, tRC = 6, tRAS = 4, tRFC = 6, tMRD = 2, tWR = 2, tRRD = 2;
	reg [15:0] mem [0:2097151];
	integer viol = 0, n_act = 0, n_rd = 0, n_wr = 0, n_ref = 0, n_pre = 0;
	realtime ref_gap = 0, t_ref = 0;
	task v(input [8*40-1:0] what); begin
		viol = viol + 1;
		if (viol <= 8) $display("  sdram: %0s at %0t (cmd %b%b%b ba %0d a %h)", what, $realtime, RAS_N, CAS_N, WE_N, BA, A);
	end endtask

	// input timing
	realtime t_in = 0, t_clk = -100;
	always @(CS_N or RAS_N or CAS_N or WE_N or BA or A or DQM) begin
		if ($realtime - t_clk < T_IH - 0.001 && $realtime > 1) v("tIH");
		t_in = $realtime;
	end
	realtime t_dq = 0;
	always @(DQ) t_dq = $realtime;

	integer cyc = 0;
	reg        open [0:3];
	reg [12:0] row [0:3];
	integer t_act [0:3], t_idle [0:3], t_wr [0:3];
	integer t_act_any = -100, t_ref_busy = 0, t_mrd = 0;
	integer pu = 0, n_iref = 0; reg pre_all = 0, mode_ok = 0;
	reg [15:0] dq_o = 16'hzzzz;
	assign DQ = dq_o;
	integer k;
	initial for (k = 0; k < 4; k = k + 1) begin open[k] = 0; row[k] = 0; t_act[k] = -100; t_idle[k] = 0; t_wr[k] = -100; end

	// read pipeline (CL 2): word and its "bad" flag
	reg [15:0] rq1 = 0; reg rv1 = 0, rb1 = 0;
	function [20:0] idx(input [1:0] b, input [12:0] r, input [8:0] c); idx = {r[11:0], c}; endfunction
	function inrange(input [1:0] b, input [12:0] r); inrange = (b == 2'b00) && (r[12] == 1'b0); endfunction

	wire [2:0] cmd = {RAS_N, CAS_N, WE_N};
	reg bad;
	always @(posedge CLK) begin
		t_clk = $realtime;
		cyc = cyc + 1;
		// the read word of the READ one clock ago
		if (rv1) begin
			dq_o <= #(T_LZ) 16'hxxxx;
			dq_o <= #(T_AC) (rb1 ? 16'hxxxx : rq1);
			dq_o <= #(11.905 + T_OH) 16'hzzzz;
		end
		rv1 = 0;
		if (CKE !== 1'b1) v("CKE not high");
		if (!CS_N && cmd != 3'b111) begin
			bad = 0;
			if ($realtime - t_in < T_IS - 0.001) begin v("tIS"); bad = 1; end
			if (^{cmd, BA, A, DQM} === 1'bx) begin v("X on the command pins"); bad = 1; end
			if (cyc < PU_CLK) begin v("command before the power-up time"); bad = 1; end
			if (cyc < t_ref_busy) begin v("command in tRFC"); bad = 1; end
			if (cyc < t_mrd) begin v("command in tMRD"); bad = 1; end
			case (cmd)
				3'b011: begin // ACTIVE
					n_act = n_act + 1;
					if (!mode_ok) begin v("ACTIVE before LOAD MODE"); bad = 1; end
					if (open[BA]) begin v("ACTIVE on an open bank"); bad = 1; end
					if (cyc < t_idle[BA]) begin v("tRP"); bad = 1; end
					if (cyc - t_act[BA] < tRC) begin v("tRC"); bad = 1; end
					if (cyc - t_act_any < tRRD) begin v("tRRD"); bad = 1; end
					if (!inrange(BA, A)) begin v("row / bank outside the model"); bad = 1; end
					open[BA] = !bad; row[BA] = A; t_act[BA] = cyc; t_act_any = cyc;
				end
				3'b101, 3'b100: begin // READ / WRITE
					if (!open[BA]) begin v("READ / WRITE on a closed bank"); bad = 1; end
					if (cyc - t_act[BA] < tRCD) begin v("tRCD"); bad = 1; end
					if (A[9] !== 1'b0 || A[12:11] !== 2'b00) begin v("column bits"); bad = 1; end
					if (cmd == 3'b101) begin
						n_rd = n_rd + 1;
						if (DQM !== 2'b00) v("read DQM (not modelled)");
						rq1 = mem[idx(BA, row[BA], A[8:0])]; rb1 = bad; rv1 = 1;
					end else begin
						n_wr = n_wr + 1;
						if ($realtime - t_dq < T_IS - 0.001) begin v("tDS"); bad = 1; end
						if (!DQM[0]) mem[idx(BA, row[BA], A[8:0])][7:0] = bad ? 8'hxx : DQ[7:0];
						if (!DQM[1]) mem[idx(BA, row[BA], A[8:0])][15:8] = bad ? 8'hxx : DQ[15:8];
						if (^(DQ | {{8{DQM[1]}}, {8{DQM[0]}}}) === 1'bx) v("X on DQ in a write");
						t_wr[BA] = cyc;
						if ($test$plusargs("sdw")) $display("  sdram WRITE %0t: ba %0d row %h col %h dqm %b dq %h", $realtime, BA, row[BA], A[8:0], DQM, DQ);
					end
					if (A[10]) begin   // auto precharge
						open[BA] = 0;
						t_idle[BA] = ((cmd == 3'b100) ? cyc + tWR : cyc + 1);
						if (t_idle[BA] < t_act[BA] + tRAS) t_idle[BA] = t_act[BA] + tRAS;
						t_idle[BA] = t_idle[BA] + tRP;
					end
				end
				3'b010: begin // PRECHARGE
					n_pre = n_pre + 1;
					for (k = 0; k < 4; k = k + 1) if (A[10] || BA == k) begin
						if (open[k]) begin
							if (cyc - t_act[k] < tRAS) v("tRAS");
							if (cyc - t_wr[k] < tWR) v("tWR");
						end
						open[k] = 0;
						if (t_idle[k] < cyc + tRP) t_idle[k] = cyc + tRP;
					end
					if (A[10]) pre_all = 1;
				end
				3'b001: begin // AUTO REFRESH
					n_ref = n_ref + 1;
					for (k = 0; k < 4; k = k + 1) if (open[k] || cyc < t_idle[k]) begin v("AUTO REFRESH with a bank not idle"); k = 4; end
					if (!pre_all) v("AUTO REFRESH before PRECHARGE all");
					t_ref_busy = cyc + tRFC;
					if (mode_ok) begin
						if ($realtime - t_ref > ref_gap) ref_gap = $realtime - t_ref;
						if ($realtime - t_ref > T_REFI) v("refresh interval");
					end
					t_ref = $realtime;
					n_iref = n_iref + 1;
				end
				3'b000: begin // LOAD MODE
					for (k = 0; k < 4; k = k + 1) if (open[k] || cyc < t_idle[k]) begin v("LOAD MODE with a bank not idle"); k = 4; end
					if (n_iref < 2) v("LOAD MODE before 2 AUTO REFRESH");
					if (A[6:4] != 3'b010 || A[2:0] != 3'b000 || A[3] != 1'b0) v("mode: not CL 2 / BL 1");
					mode_ok = 1; t_mrd = cyc + tMRD; t_ref = $realtime;
				end
				default: v("unsupported command");
			endcase
		end
	end
	// refresh interval at the end of a test
	task final_check; begin
		if (mode_ok && $realtime - t_ref > ref_gap) ref_gap = $realtime - t_ref;
		if (mode_ok && $realtime - t_ref > T_REFI) v("refresh interval (at the end)");
	end endtask
endmodule
