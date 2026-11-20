// sp_mouse against the MOUSE netlist of the 3.03a AHDL: Microsoft mouse packets (buttons, signed moves), 1200-baud
// 7N1 at 13 samples per bit of the mouse clock; the mouse clock runs 32 times faster than the real line clock.
`timescale 1ns/1ps
`include "eq_cmp.vh"
module tb_eq_mouse;
	reg clk = 0; always #11.905 clk = ~clk;           // 42 MHz, our module with CE = 1
	reg mclk = 0, md = 1;
	reg cmp_on = 0;
	integer errors = 0, weak = 0, m_cnt = 0;
	// the mouse clock: a register of the top; our module gets the event of its rising edge
	always @(posedge clk) if (m_cnt == 41) begin m_cnt <= 0; mclk <= ~mclk; end else m_cnt <= m_cnt + 1;
	wire mclk_ev = (m_cnt == 41) & ~mclk;

	wire [9:0] x_r, y_r, x_o, y_o; wire [1:0] k_r, k_o; wire int_r, int_o;
	mouse ref(.MOUSE_D(md), .CLK(mclk), .OUT_X(x_r), .OUT_Y(y_r), .OUT_K(k_r), .\INT (int_r));
	sp_mouse dut(.CLK(clk), .CE(1'b1), .CLK_EV(mclk_ev), .MOUSE_D(md), .OUT_X(x_o), .OUT_Y(y_o), .OUT_K(k_o), .INT(int_o));

	`EQ_CMP(x, 10, x_o, x_r)
	`EQ_CMP(y, 10, y_o, y_r)
	`EQ_CMP(keys, 2, k_o, k_r)
	`EQ_CMP(intr, 1, int_o, int_r)

	// one 7N1 byte: 13 mouse clocks per bit; the line changes on the clk42 edge 21 clocks after a mouse clock edge
	task bit_out(input b); begin
		repeat (13 * 84) @(posedge clk);
		md <= b;
	end endtask
	task byte_out(input [6:0] v); integer i; begin
		bit_out(0);
		for (i = 0; i < 7; i = i + 1) bit_out(v[i]);
		bit_out(1);
	end endtask
	task packet(input l, input r, input [7:0] dx, input [7:0] dy); begin
		byte_out({1'b1, l, r, dy[7:6], dx[7:6]});
		byte_out({1'b0, dx[5:0]});
		byte_out({1'b0, dy[5:0]});
		repeat (40 * 84 + ($random & 255)) @(posedge clk);
	end endtask

	integer n;
	initial begin
		repeat (21) @(posedge clk);                   // the line moves away from the mouse clock edges
		repeat (3000) @(posedge clk); cmp_on = 1;
		packet(0, 0, 8'd5, 8'd3); packet(1, 0, -8'd7, 8'd120); packet(0, 1, 8'd127, -8'd128);
		for (n = 0; n < 12; n = n + 1) packet($random, $random, $random, $random);
		repeat (2000) @(posedge clk);
		$display("tb_eq_mouse (3.03a MOUSE vs sp_mouse):");
		x_report; y_report; keys_report; intr_report;
		$display("tb_eq_mouse: %0d errors%s", errors, weak ? " (some outputs never toggled)" : "");
		$finish;
	end
endmodule
