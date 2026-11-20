// Smoke test of the reference netlist of SP2_MAX (Quartus 13 functional .vo): 42 MHz in,
// measure CLK14 and the H / V sync periods. Proves the reference flow; not a test of our code.
`timescale 1ns/1ps
module tb_max_smoke;
	reg tg42 = 0; always #11.905 tg42 = ~tg42;
	wire clk14, sinc_h, sinc_v, sinc, clkzz, s1, s2, confx;
	pullup(clkzz); pullup(s1); pullup(s2); pullup(confx);
	SP2_MAX u(.TG42_IN(tg42), .CLK14(clk14), .CLKZZ(clkzz), .SINC_H(sinc_h), .SINC_V(sinc_v), .SINC(sinc),
		.SINC_1(s1), .SINC_2(s2), .\/CONF_X (confx),
		.WD(1'b0), .WSTB(1'b0), .SR(1'b0), .SL(1'b0), .RSTB(1'b0), .TR43(1'b0), .RDAT(1'b1), .STE(1'b0),
		.XA(3'b0), .XACS(1'b1), .HDD_C(4'b0), .FDD_C(3'b0), .WR_CNF(1'b0), .D0(1'b0), .VGA_IN(1'b0),
		.SINC_IN(1'b0), .XHR_RDY(1'b1), .EPM_RES(1'b1), .PW_GOOD(1'b1), .GND65(1'b0), .GND33(1'b0));
	integer n14 = 0, nh = 0, nv = 0; realtime th0 = 0, th1 = 0, tv0 = 0, tv1 = 0;
	always @(posedge clk14) n14 = n14 + 1;
	always @(negedge sinc_h) begin nh = nh + 1; th0 = th1; th1 = $realtime; end
	always @(negedge sinc_v) begin nv = nv + 1; tv0 = tv1; tv1 = $realtime; end
	// default 0.5 ms: CLK14 and the line (seconds); +frame: two frames for the V period (~4 min in iverilog)
	reg [63:0] t_end;
	initial begin
		t_end = $test$plusargs("frame") ? 64'd45_000_000 : 64'd500_000;
		#(t_end);
		$display("CLK14 %0.3f MHz, H period %0.3f us (%0d), V period %0.3f ms (%0d)",
			n14 / (t_end / 1000.0), (th1 - th0) / 1000.0, nh, (tv1 - tv0) / 1e6, nv);
		if (n14 < t_end / 1000 * 13 || (th1 - th0) < 63_900 || (th1 - th0) > 64_100 ||
		    ($test$plusargs("frame") && (tv1 - tv0) < 19_000_000)) begin $display("tb_max_smoke: FAIL"); $finish; end
		$display("tb_max_smoke: 0 errors"); $finish;
	end
endmodule
