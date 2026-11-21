// sp_ms_tx -> sp_mouse (the ACEX MOUSE module) and the SIO B bytes, time scaled: the line clock of the ACEX
// (CLK_EV) every 16 CLK, a bit of the line 13 of them (as 1200 baud at 15.6 kHz). USB deltas in, the sums of the
// ACEX and the packets out (docs/minig.md 7).
`timescale 1ns/1ps
module tb_ms;
	reg clk = 0; always #5 clk = ~clk;
	reg [3:0] dv = 0; always @(posedge clk) dv <= dv + 4'd1;
	wire ev = dv == 4'd15;
	reg ms_wr = 0; reg [7:0] mx = 0, my = 0; reg [2:0] mb = 0;
	wire md, stb; wire [7:0] rx;
	sp_ms_tx #(.BIT_T(208)) tx(.CLK(clk), .RESET(1'b0), .MS_WR(ms_wr), .MS_X(mx), .MS_Y(my), .MS_B(mb), .MOUSE_D(md),
		.RX_D(rx), .RX_STB(stb), .RX_RDY(1'b1));
	wire [9:0] ox, oy; wire [1:0] ok; wire oint;
	sp_mouse acex_ms(.CLK(clk), .CE(1'b1), .CLK_EV(ev), .MOUSE_D(md), .OUT_X(ox), .OUT_Y(oy), .OUT_K(ok), .INT(oint),
		.CFG_RST(1'b0));
	integer errors = 0, nb = 0, sx = 0, sy = 0;
	always @(posedge clk) if (stb) begin nb = nb + 1; $display("  SIO B byte %h", rx); end
	task mv(input integer x, input integer y, input [2:0] b); begin
		@(posedge clk); mx <= x; my <= y; mb <= b; ms_wr <= 1; repeat (3) @(posedge clk); ms_wr <= 0;
		sx = sx + x; sy = sy + y;
	end endtask
	task idle; integer q; begin q = 0; while (q < 3000) begin @(posedge clk); q = (tx.st == 0 && !tx.go) ? q + 1 : 0; end end endtask
	initial begin
		repeat (100) @(posedge clk);
		mv(5, -3, 3'b001); idle;
		$display("sum X %0d Y %0d K %b (expect %0d %0d, buttons L)", $signed(ox), $signed(oy), ok, sx, sy);
		if ($signed(ox) !== sx || $signed(oy) !== sy) errors = errors + 1;
		mv(100, 100, 3'b010); mv(100, -128, 3'b010); idle;   // 200 / -28: more than one step of 127
		$display("sum X %0d Y %0d K %b (expect %0d %0d)", $signed(ox), $signed(oy), ok, sx, sy);
		if ($signed(ox) !== sx || $signed(oy) !== sy) errors = errors + 1;
		mv(0, 0, 3'b000); idle;
		$display("sum X %0d Y %0d K %b (buttons released)", $signed(ox), $signed(oy), ok);
		if (nb % 3 != 0) errors = errors + 1;
		$display("tx: ax %0d ay %0d bt %b bs %b st %0d go %b", tx.ax, tx.ay, tx.bt, tx.bs, tx.st, tx.go);
		$display("tb_ms: %0d bytes, %0d errors", nb, errors);
		$finish;
	end
endmodule
