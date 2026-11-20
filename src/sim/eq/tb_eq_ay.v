// sp_ay against the AY netlist of the 3.03a AHDL: the AY_T counter of the top (CT 0,1,2,4,5,6; CTH 0..55), AY register
// writes through the address / data strobes (tones, noise, mixer, volumes, envelopes), the beeper, a reset.
// Both sides use the test variant of AY.MIF (ay_test_mif.py: counters start at 0, not FFFF).
`timescale 1ns/1ps
`include "eq_cmp.vh"
module tb_eq_ay;
	reg clk = 0; always #11.905 clk = ~clk;           // 42 MHz, our module with CE = 1
	reg cmp_on = 0, reset_n = 0, beeper = 0;
	reg a_wr = 1, d_wr = 1;
	reg [7:0] d = 8'h00;
	integer errors = 0, weak = 0;

	// CT[2..0]: 0 1 2 4 5 6; CT[5..3] +1 after phase 6; CTH 0..55 +1 every 48 clocks
	reg [5:0] ct = 0; reg [5:0] cth = 0;
	always @(posedge clk) begin
		case (ct[2:0]) 3'd0: ct[2:0] <= 1; 3'd1: ct[2:0] <= 2; 3'd2: ct[2:0] <= 4; 3'd4: ct[2:0] <= 5; 3'd5: ct[2:0] <= 6; default: ct[2:0] <= 0; endcase
		if (ct[2:0] == 3'd6) begin
			ct[5:3] <= ct[5:3] + 1;
			if (ct[5:3] == 3'd7) cth <= (cth == 55) ? 0 : cth + 1;
		end
	end
	wire [8:0] ay_t = {cth[2:0], ct};
	// the strobes are registers of the top: our module gets the rising-edge event, known before the edge
	reg a_wr_n = 1, d_wr_n = 1;                        // next values
	always @(posedge clk) begin a_wr <= a_wr_n; d_wr <= d_wr_n; end
	wire a_wr_ev = ~a_wr & a_wr_n;

	wire [7:0] do_r, do_o; wire [3:0] a_r, b_r, c_r, a_o, b_o, c_o; wire [9:0] l_r, r_r, l_o, r_o; wire v_r, v_o;
	ay ref(.\/RESET (reset_n), .CLK42(clk), .AY_T(ay_t), .AY_D_WR(d_wr), .AY_A_WR(a_wr), .D(d), .\DO (do_r),
		.AY_CH_A(a_r), .AY_CH_B(b_r), .AY_CH_C(c_r), .AY_CH_L(l_r), .AY_CH_R(r_r), .AY_CH_VAL(v_r), .BEEPER(beeper));
	sp_ay #(.MIF_HEX("build/ay_t/ay_t.hex")) dut(.CLK(clk), .CE(1'b1), .RESET_N(reset_n), .AY_T(ay_t),
		.AY_D_WR(d_wr), .AY_A_WR(a_wr), .AY_A_WR_EV(a_wr_ev), .D(d), .DO(do_o), .AY_CH_A(a_o), .AY_CH_B(b_o),
		.AY_CH_C(c_o), .AY_CH_L(l_o), .AY_CH_R(r_o), .AY_CH_VAL(v_o), .BEEPER(beeper));

	`EQ_CMP(dout, 8, do_o, do_r)
	`EQ_CMP(cha, 4, a_o, a_r)
	`EQ_CMP(chb, 4, b_o, b_r)
	`EQ_CMP(chc, 4, c_o, c_r)
	`EQ_CMP(left, 10, l_o, l_r)
	`EQ_CMP(right, 10, r_o, r_r)
	`EQ_CMP(val, 1, v_o, v_r)

	task strobe(input addr, input [7:0] v); begin
		@(posedge clk); d <= v;
		repeat (2) @(posedge clk);
		if (addr) a_wr_n <= 0; else d_wr_n <= 0;
		repeat (8) @(posedge clk);
		if (addr) a_wr_n <= 1; else d_wr_n <= 1;
		repeat (6) @(posedge clk);
	end endtask
	task wreg(input [3:0] r, input [7:0] v); begin strobe(1, {4'h0, r}); strobe(0, v); end endtask

	integer i;
	initial begin
		repeat (200) @(posedge clk); reset_n = 1;
		repeat (2000) @(posedge clk); cmp_on = 1;
		wreg(0, 8'h10); wreg(1, 8'h00); wreg(2, 8'h18); wreg(3, 8'h00); wreg(4, 8'h0C); wreg(5, 8'h01);
		wreg(6, 8'h05); wreg(7, 8'b00110000); wreg(8, 8'h0F); wreg(9, 8'h0A); wreg(10, 8'h10);
		wreg(11, 8'h01); wreg(12, 8'h00); wreg(13, 8'h0E);
		repeat (20000) @(posedge clk);
		beeper = 1; wreg(13, 8'h0A); wreg(7, 8'b00000111); wreg(8, 8'h10); wreg(9, 8'h10);
		repeat (12000) @(posedge clk);
		beeper = 0;
		for (i = 0; i < 16; i = i + 1) begin wreg($random, $random); repeat (1000 + ($random & 2047)) @(posedge clk); end
		strobe(1, 8'h0D); strobe(0, 8'h09);
		repeat (10000) @(posedge clk);
		reset_n = 0; repeat (100) @(posedge clk); reset_n = 1;
		repeat (3000) @(posedge clk);
		$display("tb_eq_ay (3.03a AY vs sp_ay):");
		dout_report; cha_report; chb_report; chc_report; left_report; right_report; val_report;
		$display("tb_eq_ay: %0d errors%s", errors, weak ? " (some outputs never toggled)" : "");
		$finish;
	end
endmodule
