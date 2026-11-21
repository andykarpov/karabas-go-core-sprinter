// sp_kbd against the KBD netlist of the 3.03a AHDL: PS/2 frames (make / break / E0, Ctrl+Alt+Del, shifts, F12),
// refresh cycles and port reads of the ZX matrix with random A[15:8].
`timescale 1ns/1ps
`include "eq_cmp.vh"
module tb_eq_kbd;
	reg clk = 0; always #11.905 clk = ~clk;           // 42 MHz, our module with CE = 1
	reg clk_k = 0, kbd_cc = 1, kbd_dd = 1, rf_n = 1, io_n = 1, ena = 1, int_ena = 1;
	reg [7:0] a = 8'hFF;
	reg cmp_on = 0;
	// CLK_K is a register of the top (DFF(CTH5)); our module gets the event of its rising edge, known before the edge
	integer k_cnt = 0;
	wire clk_k_ev = (k_cnt == 83) & ~clk_k;
	integer errors = 0, weak = 0;

	wire [7:0] kbo_r, kbo_o;
	wire rst_r, f12_r, ctrl_r, alt_r, sh_r, int_r, rst_o, f12_o, ctrl_o, alt_o, sh_o, int_o;
	kbd ref(.CLK42(clk), .CLK_K(clk_k), .KBD_CC(kbd_cc), .KBD_DD(kbd_dd), .\/RF (rf_n), .\/IO (io_n), .\/IOM (1'b1),
		.\/M1 (1'b1), .A(a), .KBO(kbo_r), .KB_RESET(rst_r), .KB_F12(f12_r), .KB_CTRL(ctrl_r), .KB_ALT(alt_r),
		.KB_SH(sh_r), .ENA(ena), .INT_ENA(int_ena), .\INT (int_r));
	sp_kbd #(.MIF_HEX("../../rtl/acex/mif/kbd_ini2.hex")) dut(.CLK(clk), .CE(1'b1), .CLK_K_EV(clk_k_ev), .KBD_CC(kbd_cc),
		.KBD_DD(kbd_dd), .RF_N(rf_n), .IO_N(io_n), .A(a), .ENA(ena), .INT_ENA(int_ena), .KBO(kbo_o),
		.KB_RESET(rst_o), .KB_F12(f12_o), .KB_CTRL(ctrl_o), .KB_ALT(alt_o), .KB_SH(sh_o), .INT(int_o));

	`EQ_CMP(kbo, 8, kbo_o, kbo_r)
	`EQ_CMP(reset, 1, rst_o, rst_r)
	`EQ_CMP(f12, 1, f12_o, f12_r)
	`EQ_CMP(mods, 3, ({ctrl_o, alt_o, sh_o}), ({ctrl_r, alt_r, sh_r}))
	`EQ_CMP(intr, 1, int_o, int_r)

	// line clock, 16 times faster than the real 15.625 kHz (only its ratio to the PS/2 timing matters)
	always @(posedge clk) if (k_cnt == 83) begin k_cnt <= 0; clk_k <= ~clk_k; end else k_cnt <= k_cnt + 1;
	// refresh: /RF low 4 of every 20 clocks (an M1 cycle at 21 MHz)
	always begin repeat (16) @(posedge clk); rf_n <= 0; repeat (4) @(posedge clk); rf_n <= 1; end
	// port reads: /IO low 12 clocks, random high address, every ~1.5 us
	always begin
		repeat (40 + ($random & 31)) @(posedge clk);
		a <= $random; io_n <= 0;
		repeat (12) @(posedge clk); io_n <= 1;
	end
	always begin repeat (20000) @(posedge clk); int_ena <= ~int_ena; end

	// PS/2 device, 16 times faster than a real one (bit 5 us), as the line clock
	task ps2_bit(input b); begin
		repeat (26) @(posedge clk); kbd_dd <= b;
		repeat (26) @(posedge clk); kbd_cc <= 0;
		repeat (105) @(posedge clk); kbd_cc <= 1;
		repeat (52) @(posedge clk);
	end endtask
	task ps2_byte(input [7:0] v); integer i; begin
		ps2_bit(0);
		for (i = 0; i < 8; i = i + 1) ps2_bit(v[i]);
		ps2_bit(~^v);
		ps2_bit(1);
		repeat (1500) @(posedge clk);        // 36 us = 9 line clocks between bytes: the frame timeout runs out
	end endtask
	task key(input [7:0] c, input ext, input brk); begin
		if (ext) ps2_byte(8'hE0);
		if (brk) ps2_byte(8'hF0);
		ps2_byte(c);
	end endtask

	initial begin
		repeat (4000) @(posedge clk); cmp_on = 1;
		key(8'h1C, 0, 0); key(8'h1C, 0, 1);            // A
		key(8'h12, 0, 0); key(8'h16, 0, 0); key(8'h16, 0, 1); key(8'h12, 0, 1);   // Shift + 1
		key(8'h14, 0, 0); key(8'h11, 0, 0); key(8'h71, 1, 0);                      // Ctrl + Alt + Del (E0 71)
		key(8'h71, 1, 1); key(8'h11, 0, 1); key(8'h14, 0, 1);
		key(8'h07, 0, 0); key(8'h07, 0, 1);            // F12
		key(8'h59, 0, 0); key(8'h29, 0, 0); key(8'h29, 0, 1); key(8'h59, 0, 1);   // right Shift + Space
		key(8'h75, 1, 0); key(8'h75, 1, 1);            // E0 75 (up)
		key(8'h5A, 0, 0); key(8'h5A, 0, 1);            // Enter
		repeat (20000) @(posedge clk);
		$display("tb_eq_kbd (3.03a KBD vs sp_kbd):");
		kbo_report; reset_report; f12_report; mods_report; intr_report;
		$display("tb_eq_kbd: %0d errors%s", errors, weak ? " (some outputs never toggled)" : "");
		$finish;
	end
endmodule
