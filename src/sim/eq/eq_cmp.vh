// Comparison of one output group of our module against the reference netlist: ours(t) must equal ref(t) on every
// cycle (errors = mismatches at latency 0). Mismatches at latencies 1..3 are printed for diagnosis: a translation
// that is one CE late shows 0 there. Sampled on the falling edge (both sides settled). Instantiate inside the testbench: `EQ_CMP(name, width, ours, ref)
`define EQ_CMP(NAME, W, OURS, REF) \
	reg [W-1:0] NAME``_h0, NAME``_h1, NAME``_h2, NAME``_h3; \
	integer NAME``_m0 = 0, NAME``_m1 = 0, NAME``_m2 = 0, NAME``_m3 = 0, NAME``_tg = 0; \
	reg [W-1:0] NAME``_last; \
	always @(negedge clk) if (cmp_on) begin \
		if ((OURS) !== NAME``_h0) NAME``_m0 = NAME``_m0 + 1; \
		if ((OURS) !== NAME``_h1) NAME``_m1 = NAME``_m1 + 1; \
		if ((OURS) !== NAME``_h2) NAME``_m2 = NAME``_m2 + 1; \
		if ((OURS) !== NAME``_h3) NAME``_m3 = NAME``_m3 + 1; \
		if ((REF) !== NAME``_last) NAME``_tg = NAME``_tg + 1; \
	end \
	always @(negedge clk) begin NAME``_last <= REF; NAME``_h3 <= NAME``_h2; NAME``_h2 <= NAME``_h1; NAME``_h1 <= NAME``_h0; end \
	always @* NAME``_h0 = REF; \
	task NAME``_report; integer best, l; begin \
		best = NAME``_m0; l = 0; \
		if (NAME``_m1 < best) begin best = NAME``_m1; l = 1; end \
		if (NAME``_m2 < best) begin best = NAME``_m2; l = 2; end \
		if (NAME``_m3 < best) begin best = NAME``_m3; l = 3; end \
		$display("  %-10s %0d mismatches (at latency 1..3: %0d %0d %0d; best %0d), ref toggles %0d", `"NAME`", NAME``_m0, \
			NAME``_m1, NAME``_m2, NAME``_m3, l, NAME``_tg); \
		errors = errors + NAME``_m0; \
		if (NAME``_tg == 0) begin $display("  %-10s never toggles: test too weak", `"NAME`"); weak = weak + 1; end \
	end endtask
// karabas: the personality inputs of sp_acex / sp_dcp / sp_video2: PERS_K30 = 1 with -DK30 (the k30 benches),
// PERS_SCROLL = 1 with -DSCROLL (the SCROLL benches), else 3.03a
`ifdef K30
`define PERS_K30_V 1'b1
`define PERS_SCROLL_V 1'b0
`define PERS_NAME "k30"
`elsif SCROLL
`define PERS_K30_V 1'b0
`define PERS_SCROLL_V 1'b1
`define PERS_NAME "SCROLL"
`else
`define PERS_K30_V 1'b0
`define PERS_SCROLL_V 1'b0
`define PERS_NAME "3.03a"
`endif
