// Unit test of sp_z84c15 (T80pa + SIO / CTC / PIO / SCRP): the CPU runs z84c15_test.asm from a 64 KB RAM model.
// Clock as in the core: CLK 84 MHz, CE / CE_N; the Z80 clock CLKZ1 made here as the DCP does (changes at CE_N,
// 21 MHz = every CE_N, 3.5 MHz = every 6th, switched by the program), CLKZ1_NX its next value.
// Models: RAM (reads while /MR /RD, written at the rise of /WR), 2 wait states on memory at 4000-7FFF and 1 (after the automatic one) on the
// log port 80, external ports read as port xor A5, data bus 00 in INTA; INT on request until INTA; SIO byte feeds;
// CTC TRG0 = 875 kHz (CLK / 96, as the MAX CT3); PIO inputs A = 3C, B = 15; SIO A CTS / DCD = 0, B CTS = 1.
// Checks: the log of the program (OUT 80 / 84, CS0 / CS1 at reads of xEEE) against the list below, the ZC/TO0
// periods, the CTC3 interrupt period (CTC2 -> CTC3 cascade, IM 2 vector 06, RETI), PIO outputs, and the bus shape (z80_bus_chk.vh: every cycle as the bus model of tb_eq_acex).
`timescale 1ns/1ps
module tb_z84c15;
	reg clk = 0; always #5.952 clk = ~clk;
	reg clk42 = 0; always @(posedge clk) clk42 <= ~clk42;
	wire ce = ~clk42, ce_n = clk42;
	integer errors = 0;

	// ---- Z80 clock (DCP model): toggles at CE_N
	reg turbo = 1; reg zclk = 0; integer zdiv = 0;
	wire zclk_nx = turbo ? ~zclk : (zdiv == 5 ? ~zclk : zclk);
	always @(posedge clk) if (ce_n) begin zclk <= zclk_nx; zdiv <= (turbo || zdiv == 5) ? 0 : zdiv + 1; end

	// ---- DUT
	reg rst_n = 0, int_n = 1; reg wait_n = 1;
	wire m1_n, rf_n, io_n, wr_n, rd_n, mr_n, halt_n, d_oe, cs0, cs1, int_rd;
	wire m1_nx, rf_nx, io_nx, wr_nx, rd_nx, mr_nx;
	wire [15:0] a, a_nx; wire [7:0] d_o, csbr, mcr, wr5a, wr5b, pa_o, pa_oe, pb_o, pb_oe;
	reg  [7:0] rxa_d = 0, rxb_d = 0; reg rxa_stb = 0, rxb_stb = 0; wire rxa_rdy, rxb_rdy, zc0;
	reg  trg0 = 0; integer tdiv = 0;
	always @(posedge clk) begin tdiv <= (tdiv == 47) ? 0 : tdiv + 1; if (tdiv == 47) trg0 <= ~trg0; end
	reg [7:0] mem [0:65535];
	wire [7:0] mem_q = mem[a];
	wire [7:0] d_i = (~mr_n & ~rd_n) ? mem_q : (~io_n & ~rd_n & m1_n) ? a[7:0] ^ 8'hA5 : 8'h00;
	sp_z84c15 dut (.CLK(clk), .CE(ce), .CE_N(ce_n), .CLKZ1(zclk), .CLKZ1_NX(zclk_nx), .RESET_N(rst_n), .WAIT_N(wait_n),
		.INT_N(int_n), .NMI_N(1'b1), .M1_N(m1_n), .RF_N(rf_n), .IO_N(io_n), .WR_N(wr_n), .RD_N(rd_n), .MR_N(mr_n),
		.HALT_N(halt_n), .A(a), .D_O(d_o), .D_OE(d_oe), .M1_N_NX(m1_nx), .RF_N_NX(rf_nx), .IO_N_NX(io_nx),
		.WR_N_NX(wr_nx), .RD_N_NX(rd_nx), .MR_N_NX(mr_nx), .A_NX(a_nx), .D_I(d_i), .INT_RD(int_rd), .CS0(cs0), .CS1(cs1),
		.CSBR(csbr), .MCR(mcr), .RXA_D(rxa_d), .RXA_STB(rxa_stb), .RXA_RDY(rxa_rdy), .RXB_D(rxb_d), .RXB_STB(rxb_stb),
		.RXB_RDY(rxb_rdy), .CTSA(1'b0), .DCDA(1'b0), .CTSB(1'b1), .DCDB(1'b0), .WR5A(wr5a), .WR5B(wr5b), .TRG0(trg0),
		.ZC0(zc0), .PA_I(8'h3C), .PA_O(pa_o), .PA_OE(pa_oe), .PB_I(8'h15), .PB_O(pb_o), .PB_OE(pb_oe));

	// ---- bus shape
	reg chk_on = 0;
	wire c_m1 = m1_n, c_mr = mr_n, c_io = io_n, c_rd = rd_n, c_wr = wr_n, c_rf = rf_n, c_wait = wait_n;
	wire [15:0] c_a = a;
	`include "z80_bus_chk.vh"
	// *_NX change only at a CE_N; the pins after a CE = the *_NX before it
	reg [22:0] nx_s = 0;
	wire [22:0] nx_v = {m1_nx, rf_nx, io_nx, wr_nx, rd_nx, mr_nx, a_nx};
	always @(negedge clk) if (ce) nx_s <= nx_v;                    // just after a CE_N edge
	always @(posedge clk) if (chk_on && ce && nx_v !== nx_s) begin
		if (errors < 10) $display("  *_NX changed outside a CE_N at %0d ns", $time); errors = errors + 1;
	end
	always @(negedge clk) if (chk_on && ce_n && {m1_n, rf_n, io_n, wr_n, rd_n, mr_n, a} !== nx_s) begin
		if (errors < 10) $display("  pins differ from the *_NX of the CE before at %0d ns", $time); errors = errors + 1;
	end

	// ---- memory write, /WAIT (set at a CE, as the ACEX drives it)
	integer wcnt = 0;
	always @(posedge clk) if (ce) begin
		if (~mr_n & ~wr_n & wr_nx) mem[a] <= d_o;
		if (~mr_n & ~wr_n & wr_nx & ~d_oe) begin $display("  memory write without D_OE at %0d ns", $time); errors = errors + 1; end
		if (~io_n & ~wr_n & wr_nx & ~d_oe) begin $display("  I/O write without D_OE at %0d ns", $time); errors = errors + 1; end
		if (d_oe & ~rd_n) begin $display("  D_OE in a read at %0d ns", $time); errors = errors + 1; end
	end
	// waits: count Z80 clock falls of the cycle; /WAIT low for the first 2 (memory 4000-7FFF) / 1 (port 80) samples
	reg [1:0] wneed = 0; reg cyc_q = 0;
	wire mem_w = ~mr_n & rf_n & (a[15:14] == 2'b01) & (~rd_n | ~wr_n | 1'b1);
	wire io_w  = ~io_n & m1_n & (a[7:0] == 8'h80);
	always @(posedge clk) if (ce) begin
		if ((mem_w | io_w) & ~cyc_q) begin cyc_q <= 1; wneed <= 2'd2; wait_n <= 1'b0; end
		else if (~(mem_w | io_w)) begin cyc_q <= 0; wait_n <= 1'b1; end
	end
	always @(posedge clk) if (ce_n && zclk && !zclk_nx && !wait_n && wneed != 0) begin
		wneed = wneed - 1; if (wneed == 0) #1 wait_n = 1'b1;
	end

	// ---- I/O to the testbench, log
	reg [15:0] lg [0:255]; integer nlg = 0, done = 0;
	reg [3:0] zc_mode = 0;
	always @(posedge clk) if (ce && ~io_n && m1_n && ~wr_n && wr_nx) begin
		case (a[7:0])
			8'h80: begin lg[nlg] = {8'h80, d_o}; nlg = nlg + 1; end
			8'h84: begin lg[nlg] = {8'h84, d_o}; nlg = nlg + 1;
				if (d_o < 1 || d_o > 45) begin $display("  CTC0 read %h out of 1..45", d_o); errors = errors + 1; end end
			8'h81: done = 1;
			8'h82: case (d_o)
				1: fork feed_a(8'h11, 1); join_none
				2: fork feed_a(8'h55, 0); join_none
				3: fork feed_b; join_none
				4: fork do_int; join_none
				5: turbo <= 0;
				6: turbo <= 1;
				7: fork feed_a(8'h99, 2); join_none
				8, 9, 10, 11: zc_mode <= d_o - 8;
			endcase
		endcase
	end
	// CS0 / CS1 at memory reads of xEEE (not M1)
	always @(posedge clk) if (ce && ~mr_n && ~rd_n && rd_nx && m1_n && a[11:0] == 12'hEEE) begin
		lg[nlg] = {6'b110000, cs1, cs0, 4'h0, a[15:12]}; nlg = nlg + 1;
	end
	// SIO feeds (a byte per 30 CLK; mode 1 waits for RDY, 0 does not, 2 = one byte)
	task feed_a(input [7:0] first, input integer mode); integer i; begin
		for (i = 0; i < (mode == 2 ? 1 : 4); i = i + 1) begin
			repeat (30) @(posedge clk);
			if (mode == 1) while (!rxa_rdy) @(posedge clk);
			rxa_d <= (mode == 2) ? first : first + 8'h11 * i; rxa_stb <= 1; @(posedge clk); rxa_stb <= 0;
		end
	end endtask
	task feed_b; begin
		repeat (30) @(posedge clk); rxb_d <= 8'h0F; rxb_stb <= 1; @(posedge clk); rxb_stb <= 0;
		repeat (30) @(posedge clk); rxb_d <= 8'h8F; rxb_stb <= 1; @(posedge clk); rxb_stb <= 0;
	end endtask
	integer n_inta = 0;
	task do_int; begin
		repeat (200) @(posedge clk); @(posedge clk); while (!ce) @(posedge clk); #1 int_n = 0;
		while (!(~m1_n & ~io_n)) @(posedge clk);
		#1 int_n = 1; n_inta = n_inta + 1;
	end endtask
	// ZC/TO0 periods: counter 45 x 96 CLK, timer 16 x 16 Z80 clocks x 4 CLK; the first interval of a phase skipped
	integer zc_t = -1, zc_n1 = 0, zc_n2 = 0, zc_cnt = 0; reg [3:0] zc_pm = 0;
	always @(posedge clk) begin
		if (zc_mode != zc_pm) begin zc_pm = zc_mode; zc_t = -1; end
		if (zc0) begin
			zc_cnt = zc_cnt + 1;
			if (zc_t >= 0 && zc_mode == 1) begin
				if (zc_t + 1 != 45 * 96) begin $display("  CTC0 counter period %0d CLK, not %0d", zc_t + 1, 45 * 96); errors = errors + 1; end
				zc_n1 = zc_n1 + 1;
			end
			if (zc_t >= 0 && zc_mode == 2) begin
				if (zc_t + 1 != 256 * 4) begin $display("  CTC0 timer period %0d CLK, not %0d", zc_t + 1, 256 * 4); errors = errors + 1; end
				zc_n2 = zc_n2 + 1;
			end
			zc_t = 0;
		end else if (zc_t >= 0) zc_t = zc_t + 1;
	end

	// CTC interrupt period (zc_mode 3): INTA cycles 2 x 5 x 96 CLK apart (one HALT NOP of jitter: 16 CLK); none with 0
	integer ia_t = -1, ia_n = 0, ia_all = 0; reg ia_q = 0;
	always @(posedge clk) begin
		ia_q <= ~m1_n & ~io_n;
		if (zc_mode != 3) ia_t = -1;
		else if (~m1_n & ~io_n & ~ia_q) begin
			if (ia_t >= 0) begin
				if (ia_t < 960 - 20 || ia_t > 960 + 20) begin $display("  CTC interrupt period %0d CLK, not 960", ia_t); errors = errors + 1; end
				ia_n = ia_n + 1;
			end
			ia_t = 0;
		end else if (ia_t >= 0) ia_t = ia_t + 1;
		if (~m1_n & ~io_n & ~ia_q) ia_all = ia_all + 1;
	end

	// ---- expected log
	reg [15:0] ex [0:255]; integer nex = 0;
	task e(input [15:0] v); begin ex[nex] = v; nex = nex + 1; end endtask
	task eb(input [7:0] v); e({8'h80, v}); endtask
	integer i, t0;
	initial begin
		$readmemh("build/z84c15_test.hex", mem);
		mem[16'h5555] = 8'h3C;
		// 1 external ports; 2 SCDP 0..4, SCRP, CS
		eb(8'hF0); eb(8'hF0);
		eb(8'h00); eb(8'hF0); eb(8'hFF); eb(8'h01); eb(8'hFF); eb(8'h04);
		e(16'hC10F);                                   // FEEE at reset: CS0
		eb(8'h03); eb(8'hFE);
		e(16'hC100); e(16'hC10E); e(16'hC20F);          // CSBR FE MCR 03: 0 CS0, E CS0, F CS1
		e(16'hC100); e(16'hC201); e(16'hC20F);          // CSBR F0: 0 CS0, 1 CS1, F CS1
		e(16'hC001);                                   // MCR 01: 1 none
		// 3 SIO A
		eb(8'h44); eb(8'h45); eb(8'h11); eb(8'h22); eb(8'h33); eb(8'h44); eb(8'h44); eb(8'h01);
		eb(8'h21); eb(8'h55); eb(8'h66); eb(8'h88); eb(8'h44); eb(8'h01); eb(8'h44);
		// SIO B
		eb(8'h64); eb(8'h65); eb(8'h8F); eb(8'h8F); eb(8'h5A);
		// 4 PIO, 5 WDT
		eb(8'h3A); eb(8'h5A); eb(8'hFF); eb(8'hD5); eb(8'hFF); eb(8'hFF);
		// 6 CTC (range checked), 7 interrupts, 9 CTC interrupts (vector 06, 3 of them, then INT -> FF), 8 3.5 MHz / memory
		e(16'h84xx);
		eb(8'h38); eb(8'h01); eb(8'h22); eb(8'h02);
		eb(8'h33); eb(8'h33); eb(8'h33); eb(8'h22); eb(8'h03);
		eb(8'hF0); eb(8'd120); eb(8'h3C); eb(8'h44);

		repeat (380) @(posedge clk); chk_on = 1;               // the pins are idle in reset
		repeat (20) @(posedge clk); #1 rst_n = 1;
		t0 = $time;
		while (!done && $time < 5000000) @(posedge clk);
		repeat (50) @(posedge clk);
		$display("tb_z84c15: %0d us simulated, %0d log entries", ($time - t0) / 1000, nlg);
		if (!done) begin $display("  program did not end (pc area %h)", a); errors = errors + 1; end
		for (i = 0; i < nlg || i < nex; i = i + 1)
			if (i >= nlg || i >= nex || (lg[i] !== ex[i] && !(ex[i][15:8] == 8'h84 && lg[i][15:8] == 8'h84))) begin
				$display("  log %0d: %h, expected %h", i, (i < nlg) ? lg[i] : 16'hxxxx, (i < nex) ? ex[i] : 16'hxxxx);
				errors = errors + 1;
			end
		if (ia_n < 2) begin $display("  CTC interrupt periods checked: %0d (want >= 2)", ia_n); errors = errors + 1; end
		if (ia_all != 6) begin $display("  %0d INTA cycles, not 6 (2 + 3 CTC + 1: none after CTC3 is off)", ia_all); errors = errors + 1; end
		if (zc_n1 < 2 || zc_n2 < 2) begin $display("  CTC0 periods checked: counter %0d, timer %0d (want >= 2 each)", zc_n1, zc_n2); errors = errors + 1; end
		if (pa_o !== 8'h5A || pa_oe !== 8'hFF || pb_o !== 8'hC0 || pb_oe !== 8'hC0) begin
			$display("  PIO outputs A %h / %h, B %h / %h", pa_o, pa_oe, pb_o, pb_oe); errors = errors + 1; end
		if (csbr !== 8'hFF || mcr !== 8'h01 || wr5a !== 8'h62 || wr5b !== 8'hE0) begin
			$display("  CSBR %h MCR %h WR5A %h WR5B %h", csbr, mcr, wr5a, wr5b); errors = errors + 1; end
		$display("  CTC0 ZC/TO pulses %0d, periods checked counter %0d / timer %0d, INTA %0d, CTC interrupt periods %0d", zc_cnt, zc_n1, zc_n2, n_inta, ia_n);
		bc_report;
		errors = errors + bc_err;
		$display("tb_z84c15: %0d errors", errors);
		$finish;
	end
endmodule
