`timescale 1ns / 1ps
/*
 tb_fdd_phys: the physical floppy drives of the Karabas Go (docs/storage.md 8): sp_fdd PHYS 1 (wd1793 for the
 images, sp_fdd_phys with the VG93 model for the physical drives) on clk_bus 28.03 MHz, with two drive models at the
 pins (fdd_model.v of core-msx2 / core-pcxt: high = active, an IBM track, jitter, STEP / DIR timing checked, the
 written data decoded back into the image). The CPU side is the strobes of the MAX as sp_storage gives them
 (WG_RD_N / WG_WR_N / WR_PDOS, the register on a, the byte on din), the writes as fast as FDRIVER2 at 21 MHz gives
 them: the sector / data register and the command 2 us apart (the write queue of sp_fdd_phys).
 - the mapping: slot 0 (drive A) -> DS0, slot 1 (drive B) -> DS1 by IMG_PHYS; the pins all 0 before;
 - drive A (DS0, 2 heads, 250 kbit/s, FDD_1440 = 0, the disk SPEED of +speed): Restore from cylinder 5, Seek 2,
   Read Sector of side 1, Write Sector of side 0 and its read back;
 - drive B (DS1, 1 head, 500 kbit/s, FDD_1440 = 1, write protected): Restore from cylinder 2, Read Sector, Write
   Sector refused (status WP, nothing written);
 - a mount of an image on slot 0 puts drive A back on wd1793: no image (not ready), the pins all 0.
 Runs in verilator (--timing, run_fdd_phys.sh), seconds. Ends with "tb_fdd_phys: N errors".
*/
module tb_fdd_phys;

real speed = 1.0;
initial begin
	if ($value$plusargs("speed=%f", speed)) ;
	#1 drv_a.cell_ns = 100 * 20.0 * speed;
	$display("tb_fdd_phys: drive A speed %0.3f", speed);
end

reg clk = 1'b0;
always #17.837 clk = ~clk;           // 28.03 MHz

reg reset = 1'b1;
reg wg_rd_n = 1'b1, wg_wr_n = 1'b1, wr_pdos_n = 1'b1, hd = 1'b0;
reg [1:0] a = 2'd0;
reg [7:0] din = 8'h00;
wire [7:0] dout, sys_q;
reg [1:0] img_mounted = 2'b00;
reg img_phys_wr = 1'b0;
reg [15:0] img_phys = 16'd0;
wire [3:0] fdd_in, in_a, in_b;
wire [7:0] fdd_out;
assign fdd_in = in_a | in_b;

sp_fdd #(.PHYS(1)) dut (
	.clk(clk), .reset(reset), .wg_rd_n(wg_rd_n), .wg_wr_n(wg_wr_n), .wr_pdos_n(wr_pdos_n), .a(a), .din(din),
	.fdd_1440(hd), .dout(dout), .sys_q(sys_q), .wp(2'b00),
	.img_mounted(img_mounted), .img_size(64'd0), .sdc_rd(), .sdc_wr(), .sdc_sector(), .sdc_busy(1'b0),
	.sdc_done(1'b0), .sdc_byte_addr(9'd0), .sdc_byte_in_strobe(1'b0), .sdc_byte_in_data(8'd0),
	.sdc_byte_out_data(), .active(),
	.img_phys_wr(img_phys_wr), .img_phys(img_phys), .fdd_in(fdd_in), .fdd_out(fdd_out)
);

localparam integer SPT = 3, GAP3 = 40, TRK = 2100;   // a short track: 67 ms a revolution at 250 kbit/s
fdd_model #(.DS(0), .CELL(100), .SPT(SPT), .HEADS(2), .CYLS(80), .GAP3(GAP3), .TRK_BYTES(TRK),
	.SPEED(1.0), .CYL0(5)) drv_a (.fdd_out(fdd_out), .fdd_in(in_a));
fdd_model #(.DS(1), .CELL(50), .SPT(SPT), .HEADS(1), .CYLS(80), .GAP3(GAP3), .TRK_BYTES(TRK),
	.SPEED(0.99), .CYL0(2), .STEP_MIN_NS(1000.0)) drv_b (.fdd_out(fdd_out), .fdd_in(in_b));   // 2 MHz: 2 us steps

integer errors = 0;
task check;
	input ok;
	input [8*64-1:0] what;
	begin
		if (!ok) begin
			errors = errors + 1;
			$display("%t ERROR: %0s", $realtime, what);
		end
	end
endtask

// ---- the strobes of the MAX as tb_storage measured them (docs/storage.md 2): WG_RD_N / WG_WR_N 417 ns, the ACEX
// takes a read byte ~310 ns after the strobe falls (here: the byte at 300 ns) ----
task wr;
	input [1:0] r;
	input [7:0] v;
	begin
		a = r; din = v; wg_wr_n = 1'b0;
		#417 wg_wr_n = 1'b1;
		#100;
	end
endtask
task wr_sys;
	input [7:0] v;
	begin
		din = v; wr_pdos_n = 1'b0;
		#417 wr_pdos_n = 1'b1;
		#100;
	end
endtask
reg [7:0] q;
task rd;
	input [1:0] r;
	begin
		a = r; wg_rd_n = 1'b0;
		#300 q = dout;
		#117 wg_rd_n = 1'b1;
		#100;
	end
endtask
task gap;                         // less than the code of FDRIVER2 between two writes at 21 MHz (~40 T, ~2 us)
	#300;
endtask

// wait for INTRQ (#FF bit 7), then the status
reg [7:0] st;
integer n;
task wait_int;
	input integer ms;
	begin
		n = 0;
		while (!sys_q[7] && n < ms * 1000) begin
			#1000;
			n = n + 1;
		end
		check(sys_q[7], "INTRQ timeout");
		rd(2'd0);
		st = q;
	end
endtask
task cmd;
	input [7:0] c;
	begin
		wr(2'd0, c);
	end
endtask

// Type II data: DRQ (#FF bit 6) moves a byte, INTRQ ends
reg [7:0] dbuf [0:1023];
integer cnt;
task xfer;
	input wr_dir;          // 1: the CPU writes
	input integer ms;
	begin
		cnt = 0;
		n = 0;
		while (!sys_q[7] && n < ms * 5000) begin
			if (sys_q[6]) begin
				if (wr_dir) wr(2'd3, dbuf[cnt]);
				else begin rd(2'd3); dbuf[cnt] = q; end
				cnt = cnt + 1;
			end
			else #200;
			n = n + 1;
		end
		check(sys_q[7], "INTRQ timeout in a transfer");
		rd(2'd0);
		st = q;
	end
endtask

function [7:0] pat;               // the data of the drive model
	input integer c, h, r, i;
	pat = (c * 7 + h * 13 + r * 3 + i) & 255;
endfunction

integer i, bad, wr0;
initial begin
	#200000 reset = 1'b0;
	#2000;
	check(fdd_out == 8'd0, "the pins before the mapping");

	// ---------------- the mapping: slot 0 = DS0, slot 1 = DS1 (CMD_IMG_PHYS) ----------------
	@(posedge clk) begin img_phys_wr <= 1'b1; img_phys <= {8'd0, 8'd1}; end
	@(posedge clk) begin img_phys <= {8'd1, 8'd2}; end
	@(posedge clk) img_phys_wr <= 1'b0;

	// ---------------- drive A on DS0, 250 kbit/s ----------------
	wr_sys(8'h3C);                     // drive A, side 0, HLT, /MR high (FDRIVER2 S_FDD)
	#10000;
	check(fdd_out == 8'h01, "A: the pins after the select: DS0 only (no head load)");
	// the end of /MR: the chip makes a Restore (03, no head load, 30 ms a step): wait for it
	n = 0;
	rd(2'd0);
	while (q[0] && n < 2000) begin #100000; rd(2'd0); n = n + 1; end
	$display("A: the Restore of /MR: %0.1f ms, status %h, cylinder %0d", n * 0.1, q, drv_a.cyl);
	check(!q[0] && drv_a.cyl == 0, "A: the Restore of /MR");
	drv_a.cyl = 5;                     // the head away again
	cmd(8'h08);                        // Restore, head load, 6 ms
	#100000;
	check(fdd_out[0] && !fdd_out[1] && fdd_out[2], "A: DS0 and the motor with the head load");
	wait_int(400);
	check(drv_a.cyl == 0, "A: Restore, the head not on cylinder 0");
	check(st[2], "A: Restore, no TR00 in the status");
	check(drv_a.short_steps == 0, "A: Restore, steps lost (STEP / DIR timing)");
	rd(2'd1);
	check(q == 8'd0, "A: Restore, track register");

	wr(2'd3, 8'd2); gap;               // Seek 2 (FDRIVER2: OUT (R_DAT) then EXECOM)
	cmd(8'h18);
	wait_int(200);
	check(drv_a.cyl == 2, "A: Seek, the head not on cylinder 2");
	rd(2'd1);
	check(q == 8'd2, "A: Seek, track register");

	// the density probe of the BIOS (FDRIVER2 DISK_ID): Read Address at the wrong rate (2 MHz on a 250 kbit/s disk)
	// gives neither DRQ nor INTRQ for ~140 ms; then the other rate (TURNSPD) and Read Address again (the chip is
	// still busy with the first one and ignores it): the ID of cylinder 2 within a revolution
	hd = 1'b1;
	cmd(8'hC0);
	n = 0;
	while (!sys_q[7] && !sys_q[6] && n < 140) begin #1000000; n = n + 1; end
	check(n == 140, "A: Read Address at the wrong rate: DRQ / INTRQ");
	hd = 1'b0;
	cmd(8'hC0);
	xfer(1'b0, 300);
	$display("A: Read Address after the rate change: status %h, %0d bytes: %h %h %h %h", st, cnt, dbuf[0], dbuf[1],
		dbuf[2], dbuf[3]);
	check(st == 8'h00 && cnt == 6 && dbuf[0] == 8'd2 && dbuf[1] == 8'd0 && dbuf[3] == 8'd2, "A: Read Address");

	wr_sys(8'h2C);                     // side 1
	wr(2'd2, 8'd3); gap;               // sector 3, Read Sector
	cmd(8'h80);
	xfer(1'b0, 400);
	$display("A: Read Sector C 2 H 1 R 3: status %h, %0d bytes", st, cnt);
	check(st == 8'h00, "A: Read Sector, status");
	check(cnt == 512, "A: Read Sector, not 512 bytes");
	bad = 0;
	for (i = 0; i < 512; i = i + 1) if (dbuf[i] != pat(2, 1, 3, i)) bad = bad + 1;
	check(bad == 0, "A: Read Sector, data");

	wr_sys(8'h3C);                     // side 0, sector 1: Write Sector
	for (i = 0; i < 512; i = i + 1) dbuf[i] = (i * 5 + 17) & 255;
	wr0 = drv_a.data_writes;
	wr(2'd2, 8'd1); gap;
	cmd(8'hA0);
	xfer(1'b1, 400);
	$display("A: Write Sector C 2 H 0 R 1: status %h, %0d bytes", st, cnt);
	check(st == 8'h00, "A: Write Sector, status");
	check(cnt == 512, "A: Write Sector, not 512 bytes");
	check(drv_a.data_writes == wr0 + 1, "A: Write Sector, no data field written");
	check(drv_a.crc_errs == 0, "A: Write Sector, CRC of the written field");
	bad = 0;
	for (i = 0; i < 512; i = i + 1) if (drv_a.img[((2 * 2 + 0) * SPT + 0) * 512 + i] != ((i * 5 + 17) & 255)) bad = bad + 1;
	check(bad == 0, "A: Write Sector, the data in the image");
	for (i = 0; i < 512; i = i + 1) dbuf[i] = 8'h00;
	wr(2'd2, 8'd1); gap;
	cmd(8'h80);
	xfer(1'b0, 400);
	bad = 0;
	for (i = 0; i < 512; i = i + 1) if (dbuf[i] != ((i * 5 + 17) & 255)) bad = bad + 1;
	$display("A: read back: status %h, %0d bytes, %0d differ", st, cnt, bad);
	check(st == 8'h00 && cnt == 512 && bad == 0, "A: read back");

	// ---------------- drive B on DS1, 500 kbit/s (1.44 MB), write protected ----------------
	drv_b.wprot = 1'b1;
	hd = 1'b1;
	wr_sys(8'h3D);                     // drive B, side 0
	#2000;
	check(fdd_out[1:0] == 2'b10, "B: DS1 after the select");
	cmd(8'h08);
	#100000;
	check(!fdd_out[0] && fdd_out[1] && fdd_out[2], "B: DS1 and the motor");
	wait_int(400);
	check(drv_b.cyl == 0, "B: Restore, the head not on cylinder 0");
	check(drv_b.short_steps == 0, "B: Restore, steps lost");
	wr(2'd2, 8'd2); gap;
	cmd(8'h80);
	xfer(1'b0, 400);
	bad = 0;
	for (i = 0; i < 512; i = i + 1) if (dbuf[i] != pat(0, 0, 2, i)) bad = bad + 1;
	$display("B: Read Sector C 0 H 0 R 2 at 500 kbit/s: status %h, %0d bytes, %0d differ", st, cnt, bad);
	check(st == 8'h00 && cnt == 512 && bad == 0, "B: Read Sector");
	wr0 = drv_b.data_writes;
	wr(2'd2, 8'd1); gap;
	cmd(8'hA0);
	xfer(1'b1, 400);
	$display("B: Write Sector (protected): status %h, %0d bytes", st, cnt);
	check(st[6] && cnt == 0 && drv_b.data_writes == wr0, "B: Write Sector not refused");

	// ---------------- drive A back on the image (a mount of slot 0): wd1793, no image, the pins 0 ----------------
	hd = 1'b0;
	@(posedge clk) img_mounted <= 2'b01;
	@(posedge clk) img_mounted <= 2'b00;
	wr_sys(8'h3C);
	#2000;
	check(fdd_out == 8'd0, "A on the image: the pins");
	cmd(8'h80);                        // wd1793 without an image: not ready
	#200000;
	rd(2'd0);
	$display("A on the image: status %h", q);
	check(q[7], "A on the image: not ready");
	check(fdd_out == 8'd0, "A on the image: the pins after a command");

	$display("tb_fdd_phys: %0d errors (%0.1f ms)", errors, $realtime / 1.0e6);
	$finish;
end

initial begin
	#3000000000;
	$display("tb_fdd_phys: time out");
	$display("tb_fdd_phys: %0d errors", errors + 1);
	$finish;
end

endmodule
