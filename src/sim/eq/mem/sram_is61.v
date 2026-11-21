// One IS61WV20488BLL-10 (2M x 8, asynchronous, /CE tied low) for the memory tests: read data valid tAA after the
// last address change and tDOE after /OE fell, the old data held tOHA after an address change, X in between; the
// output drives from /OE low (+tLZOE) / /WE high (+tLZWE) and lets go tHZOE / tHZWE after (worst case for
// contention: on early, off late). A write is taken at the rise of /WE. Violations are counted (viol) and the
// first ones printed: tWP, tDS, tAW (address valid to the end of the write), the address changing while /WE is
// low, X / Z data at the rise of /WE, the bus driven by both sides (EXT_DRV = the FPGA drives) for more than 0 ns.
// The memory holds WORDS bytes (backdoor: mem[]); addresses above read X and are a violation when written.
`timescale 1ns/1ps
module sram_is61 #(
	parameter NAME = "sram",
	parameter integer WORDS = 524288,
	parameter real T_AA = 10.0, T_OHA = 2.5, T_DOE = 4.5, T_LZOE = 0.0, T_HZOE = 4.0, T_LZWE = 2.0, T_HZWE = 5.0,
	parameter real T_WP = 8.0, T_DS = 6.0, T_AW = 8.0
) (
	input      [20:0] A,
	inout       [7:0] DQ,
	input             WE_N,
	input             OE_N,
	input             EXT_DRV
);
	reg [7:0] mem [0:WORDS-1];
	integer viol = 0, n_wr = 0, n_cont = 0;
	task v(input [8*48-1:0] what); begin
		viol = viol + 1;
		if (viol <= 5) $display("  %0s: %0s at %0t (A %h)", NAME, what, $realtime, A);
	end endtask

	// address timing: a_aa / a_oha follow A after tAA / tOHA (inertial)
	wire [20:0] a_aa, a_oha;
	assign #(T_AA) a_aa = A;
	assign #(T_OHA) a_oha = A;
	wire oe_ok;  assign #(T_DOE, 0) oe_ok = ~OE_N & WE_N;          // data valid tDOE after /OE fell
	wire on_oe;  assign #(T_LZOE, T_HZOE) on_oe = ~OE_N;
	wire on_we;  assign #(T_LZWE, T_HZWE) on_we = WE_N;
	wire drv = on_oe & on_we;
	reg  [7:0] q;
	reg        wr_ev = 0;
	function [7:0] rd(input [20:0] a); rd = (a < WORDS) ? mem[a] : 8'hxx; endfunction
	always @(A or a_aa or a_oha or oe_ok or wr_ev)
		q = !oe_ok ? 8'hxx : (a_aa === A) ? rd(A) : (a_oha === a_aa) ? rd(a_aa) : 8'hxx;
	assign DQ = drv ? q : 8'hzz;

	// write
	realtime t_a = 0, t_we = 0, t_dq = 0, t_c = 0;
	always @(A) begin
		if (WE_N === 1'b0) v("address changed while /WE low");
		t_a = $realtime;
	end
	always @(DQ) t_dq = $realtime;
	reg we_p = 1'b1;
	always @(WE_N) begin if (WE_N === 1'b0) t_we = $realtime; we_p <= WE_N; end
	always @(posedge WE_N) if (we_p === 1'b0) begin
		if ($realtime - t_we < T_WP - 0.001) v("tWP");
		if ($realtime - t_dq < T_DS - 0.001) v("tDS");
		if ($realtime - t_a < T_AW - 0.001) v("tAW");
		if (^DQ === 1'bx) v("X / Z data at the end of a write");
		if (A < WORDS) mem[A] = DQ; else v("write above the model");
		n_wr = n_wr + 1;
		wr_ev = ~wr_ev;
	end
	// both sides on the bus
	reg both = 0;
	always @(drv or EXT_DRV) begin
		if (drv === 1'b1 && EXT_DRV === 1'b1) begin if (!both) begin both = 1; t_c = $realtime; end end
		else if (both) begin
			both = 0;
			if ($realtime - t_c > 0.001) begin n_cont = n_cont + 1; v("bus driven by both"); end
		end
	end
endmodule
