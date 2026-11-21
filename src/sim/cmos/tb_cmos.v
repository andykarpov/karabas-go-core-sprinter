// sp_cmos + kg_mcu2 (RTC_COALESCE 1, RTC_SEND_LIMIT 128) + a model of the firmware (lib/rtc rtc_mode 0 and
// link_api.c v2_rtc_event) on the SPI link, the bus driven as the BIOS drives it (docs/rtc.md):
// 1. start: rtc_send_all from the .eep (src/roms/cmos_default.bin), INIT done; CMOS_TEST on #3F (3.04); the read
//    overrides: A with UIP set in the mirror -> UIP 0, C -> #50, D -> #80;
// 2. SETUP READING #0E..#3F (each read after a CMOS_TEST of #7F, as BIOS 3.06): the checksum of the image is valid;
// 3. SETUP WRITING: new values, new checksum, #0E..#3F with CMOS_TEST of #7F before each: 150 writes back to back
//    (~10 us a call: faster than the BIOS) while the firmware reads one GET every 200 us (slow on purpose: more than
//    8 registers wait) and sends the time (SET 00..09) every 150 us;
// 4. CMSERR as BIOS 3.06: B = #82, the time 00..09, B = #02;
// 5. at the end: the firmware copy (EEPROM, its clock), the mirror read through sp_cmos and the values written agree;
//    then a power cycle (rtc_send_all from the EEPROM of the firmware) and READING again: the checksum is valid.
// Prints "tb_cmos: 0 errors".
// -DCOALESCE=0: the fifo of 8 alone (the check that the test sees the lost writes).
`timescale 1ns/1ps
`ifndef COALESCE
`define COALESCE 1
`define COALESCE_ON
`endif
module tb_cmos;
	reg clk = 0, clk28 = 0;
	always #5.952 clk = ~clk;                         // 84 MHz
	always #17.856 clk28 = ~clk28;                    // 28 MHz = clk / 3, edges aligned
	integer errors = 0;
	task check(input [255:0] what, input [7:0] got, input [7:0] want); begin
		if (got !== want) begin $display("ERROR %0s: got %h, want %h", what, got, want); errors = errors + 1; end
	end endtask

	// ---- the core: the bus of the MAX, sp_cmos, kg_mcu2
	reg [15:0] md = 16'hFFFF;
	reg as = 0, dwr = 1, drd = 1;
	wire [7:0] q; wire oe;
	wire [7:0] rtc_a, rtc_di, rtc_do; wire rtc_wr_n;
	sp_cmos dut(.CLK(clk), .MD(md), .CMOS_AS(as), .CMOS_DWR(dwr), .CMOS_DRD(drd), .Q(q), .OE(oe),
		.CLK_BUS(clk28), .RTC_A(rtc_a), .RTC_DI(rtc_di), .RTC_WR_N(rtc_wr_n), .RTC_DO(rtc_do));

	reg sck = 1'b0, mosi = 1'b0, ss = 1'b1;
	wire miso, int_line;
	kg_mcu2 #(.ENABLE_OSD(0), .ENABLE_RTC(1), .RTC_SEND_LIMIT(128), .RTC_COALESCE(`COALESCE), .ENABLE_FT(0), .ENABLE_SD2(0)) mcu(
		.CLK(clk28), .N_RESET(1'b1),
		.MCU_SCK(sck), .MCU_MOSI(mosi), .MCU_MISO(miso), .MCU_SS(ss), .MCU_INT(int_line),
		.MCU_SPI_FT_SS(1'b1), .MCU_SPI_SD2_SS(1'b1),
		.SW(), .SW_WR(), .SW_INDEX(), .SW_VALUE(), .HW_ID(), .DVI_ONLY(), .CORE_BUILD(), .FW_BUILD(),
		.BUSY(), .BTNS(), .RELOAD_REQ(1'b0), .RELOAD_CORE(8'd0),
		.KBD(), .KBD_WR(), .PS2_CODE(), .PS2_KIND(), .PS2_WR(), .MS_X(), .MS_Y(), .MS_Z(), .MS_B(),
		.MS_WR(), .JOY_L(), .JOY_R(), .JOY_WR(), .PS2_CMD(16'd0), .PS2_CMD_WR(1'b0),
		.LD_KIND(), .LD_SLOT(), .LD_SIZE(), .LD_START(), .LD_ACTIVE(), .LD_END(), .LD_ADDR(),
		.LD_DATA(), .LD_WR(), .LD_READY(1'b1),
		.OSD_WR(), .OSD_WADDR(), .OSD_WDATA(), .OSD_EN(), .OSD_FG(), .OSD_BG(), .OSD_ALPHA(),
		.OSD_PX(), .OSD_PY(), .OSD_PW(), .OSD_PH(), .OSD_PLACE(), .OSD_ZOOM(),
		.SDC_IMG_MOUNTED(), .SDC_IMG_SIZE(), .SDC_RD(8'd0), .SDC_WR(8'd0), .SDC_SECTOR(32'd0),
		.SDC_BUSY(), .SDC_DONE(), .SDC_ERROR(), .SDC_SLOT(), .SDC_BYTE_IN_STROBE(), .SDC_BYTE_ADDR(),
		.SDC_BYTE_IN_DATA(), .SDC_BYTE_OUT_DATA(8'd0), .IMG_WP(), .IMG_PHYS_WR(), .IMG_PHYS(),
		.IMG_FLUSH(), .FDD_CHNG_WR(), .FDD_CHNG(), .FDD_CHNG_REQ(1'b0), .FDD_CHNG_DS(2'd0), .IMG_ACTIVE(),
		.BK_MOUNT(), .BK_FLUSHED(), .BK_SLOT(), .BK_SIZE(), .BK_KIND(), .BK_RESULT(),
		.PORT_OUT_DATA(), .PORT_OUT_WR(), .PORT_OUT_READY(4'd0), .PORT_IN_DATA(32'd0), .PORT_IN_WR(4'd0),
		.PORT_IN_FULL(), .PORT_CFG(128'd0), .PORT_STAT(), .PORT_STAT_WR(),
		.RTC_A(rtc_a), .RTC_DI(rtc_di), .RTC_DO(rtc_do), .RTC_CS(1'b1), .RTC_WR_N(rtc_wr_n),
		.MATRIX_CMD(24'd0), .MATRIX_CMD_WR(1'b0), .DEBUG_ADDR(16'd0), .DEBUG_DATA(16'd0),
		.FT_SPI_ON(), .FT_VGA_ON(), .FT_RESET(), .FT_SCK(), .FT_MOSI(), .FT_MISO(1'b1), .FT_CS_N(),
		.SD2_SCK(), .SD2_MOSI(), .SD2_MISO(1'b1), .SD2_CS_N()
	);

	// ---- the bus of the MAX (sp_max: the strobes registered at 10K_CLK, ~10 CLK21 of /WAIT): MD set before the
	// strobe, held through it and after (the ACEX drives it for an OUT, md_keep keeps it), then other traffic
	integer seed = 5;
	task bus_gap; begin repeat (8) @(posedge clk); md <= $random(seed); repeat (40) @(posedge clk); end endtask
	task io_adr(input [7:0] a); begin                 // OUT (#DFBD),a
		@(posedge clk); md <= {a, 8'hFF}; repeat (4) @(posedge clk);
		as <= 1'b1; repeat (40) @(posedge clk); as <= 1'b0; repeat (4) @(posedge clk);
		bus_gap;
	end endtask
	task io_wr(input [7:0] v); begin                  // OUT (#BFBD),v
		@(posedge clk); md <= {v, 8'hFF}; repeat (4) @(posedge clk);
		dwr <= 1'b0; repeat (40) @(posedge clk); dwr <= 1'b1; repeat (4) @(posedge clk);
		bus_gap;
	end endtask
	task io_rd(output [7:0] v); begin                 // IN A,(#FFBD): the ACEX takes MD[15:8] at the end
		@(posedge clk); drd <= 1'b0; repeat (40) @(posedge clk);
		if (oe !== 1'b1) begin $display("ERROR OE not driven while CMOS_DRD is low"); errors = errors + 1; end
		v = q; drd <= 1'b1;
		bus_gap;
	end endtask
	// the BIOS functions #F5 / #F6 / #F7 (3.06: the test cell #7F; 3.04: #3F)
	reg [7:0] test_cell = 8'h3F;
	task cmos_test(output ok); reg [7:0] x, y; begin
		io_adr(test_cell); io_rd(x); io_adr(test_cell); io_wr(~x); io_adr(test_cell); io_rd(y);
		io_adr(test_cell); io_wr(x);
		ok = (y == ~x);
	end endtask
	task cmos_rd(input [7:0] r, output [7:0] v); reg ok; begin
		cmos_test(ok);
		if (!ok) begin $display("ERROR CMOS_TEST failed (CMOS: None)"); errors = errors + 1; end
		io_adr(r); io_rd(v);
	end endtask
	task cmos_wr(input [7:0] r, input [7:0] v); reg ok; begin
		cmos_test(ok);
		if (!ok) begin $display("ERROR CMOS_TEST failed (CMOS: None)"); errors = errors + 1; end
		io_adr(r); io_wr(v);
	end endtask
	function [7:0] cksum(input integer count); integer i; reg [7:0] h, a; begin
		h = 8'hDE;
		for (i = 0; i < count; i = i + 1) begin
			a = h - area[8'h0E + i]; a = {a[6:0], a[7]}; h = a - area[8'h0E + i];
		end
		cksum = h;
	end endfunction
	reg [7:0] area [0:255];                            // CMOSARE of SETUP
	task reading; integer r; reg [7:0] v; begin
		for (r = 8'h0E; r <= 8'h3F; r = r + 1) begin cmos_rd(r, v); area[r] = v; end
	end endtask
	task writing; integer r; begin
		area[8'h3F] = cksum(18);
		for (r = 8'h0E; r <= 8'h3F; r = r + 1) cmos_wr(r, area[r]);
	end endtask

	// ---- the firmware: SPI packets one at a time (lock), lib/rtc rtc_mode 0
	reg [7:0] tx [0:300];
	reg [7:0] rx [0:300];
	reg lock = 0;
	task xbyte(input [7:0] b, output [7:0] r); integer i; begin
		for (i = 7; i >= 0; i = i - 1) begin mosi = b[i]; #16; sck = 1'b1; r[i] = miso; #16; sck = 1'b0; end
	end endtask
	task packet(input integer len); integer i; reg [7:0] r; begin
		wait (!lock); lock = 1;
		ss = 1'b0; #16;
		for (i = 0; i < len; i = i + 1) begin xbyte(tx[i], r); rx[i] = r; end
		#16; ss = 1'b1; #1000;
		lock = 0;
	end endtask
	reg [7:0] eep [0:255];                             // the .eep of the core
	reg [7:0] fw_time [0:9];                           // its clock (BCD), the alarms
	integer n_get = 0, n_pairs = 0, max_pend = 0;
	task fw_send_all; integer r; begin                 // rtc_send_all (time first, then 0..255)
		wait (!lock); lock = 1;
		tx[0] = 8'h06; tx[1] = 8'h01; tx[2] = 8'h00;
		for (r = 0; r < 256; r = r + 1)
			case (r)
				1, 3, 5: tx[3 + r] = 8'h00;
				8'h0A: tx[3 + r] = eep[r] & 8'h7F;
				8'h0B: tx[3 + r] = (eep[r] | 8'h02) & 8'h7B;   // 24 h, BCD, never SET
				8'h0C: tx[3 + r] = 8'h00;
				8'h0D: tx[3 + r] = 8'h80;
				default: tx[3 + r] = eep[r];
			endcase
		lock = 0;
		packet(259);
	end endtask
	task fw_time_packet; integer r; begin             // every 500 ms on the board: SET 00..09
		wait (!lock); lock = 1;
		tx[0] = 8'h06; tx[1] = 8'h01; tx[2] = 8'h00;
		for (r = 0; r < 10; r = r + 1) tx[3 + r] = fw_time[r];
		lock = 0;
		packet(13);
	end endtask
	task fw_set_data(input [7:0] a, input [7:0] v); begin   // rtc_set_data, rtc_mode 0
		if (a <= 8'h09) fw_time[a] = v;                 // the fields + adjust() of the DS3231
		else if (a == 8'h0A) eep[a] = v & 8'h7F;
		else if (a == 8'h0B) eep[a] = v & 8'h7F;          // SET not kept
		else if (a == 8'h0C || a == 8'h0D) ;
		else eep[a] = v;
	end endtask
	task fw_get; integer k; begin                      // v2_rtc_event
		wait (!lock); lock = 1;
		tx[0] = 8'h06; tx[1] = 8'h02;
		for (k = 2; k < 20; k = k + 1) tx[k] = 8'h00;
		lock = 0;
		packet(20);
		n_get = n_get + 1;
		for (k = 0; k < rx[3] && k < 8; k = k + 1) begin
			fw_set_data(rx[4 + 2 * k], rx[5 + 2 * k]);
			n_pairs = n_pairs + 1;
		end
	end endtask
	task fw_irq(output [7:0] bits); begin
		wait (!lock); lock = 1;
		tx[0] = 8'h00; tx[1] = 8'h01; tx[2] = 8'h00; tx[3] = 8'h00; tx[4] = 8'h00;
		lock = 0;
		packet(5);
		bits = rx[4];
	end endtask
	reg fw_run = 0;
	reg [7:0] ib;
	integer pend, pk;
	// the main loop, slow on purpose (SD / USB / OSD work between): one GET every 200 us while the burst runs, so
	// that more than 8 registers wait (the fifo of 8 alone would lose writes); GET until the irq ends after it
	reg fw_fast = 0;
	initial forever begin
		#(200000.0);
		if (fw_run) begin
			pend = 0;
`ifdef COALESCE_ON
			for (pk = 0; pk < 128; pk = pk + 1)
				pend = pend + (mcu.kg_mcu2_rtc_on.u_rtc.rtc_coalesce.dirty[pk] | mcu.kg_mcu2_rtc_on.u_rtc.rtc_coalesce.queued[pk]);
`endif
			if (pend > max_pend) max_pend = pend;
			fw_irq(ib);
			if (ib[6]) fw_get;
			if (fw_fast) begin fw_irq(ib); while (ib[6]) begin fw_get; fw_irq(ib); end end
		end
	end
	initial forever begin
		#(150000.0);
		if (fw_run) fw_time_packet;
	end

	// ---- the run
	integer i, r;
	reg [7:0] v;
	reg ok;
	reg [7:0] newv [0:255];
	initial begin
		$readmemh("build/cmos_default.hex", eep);
		for (i = 0; i < 10; i = i + 1) fw_time[i] = 8'h00;
		fw_time[0] = 8'h30; fw_time[2] = 8'h15; fw_time[4] = 8'h12; fw_time[6] = 8'h06; fw_time[7] = 8'h21;
		fw_time[8] = 8'h11; fw_time[9] = 8'h26;
		#2000;
		fw_send_all;
		tx[0] = 8'h00; tx[1] = 8'h05; tx[2] = 8'h00; packet(3);   // INIT done (the core runs)
		fw_run = 1;

		// 1. start
		cmos_test(ok); check("CMOS_TEST #3F", ok, 1'b1);
		// the firmware sends the .eep over 00..09 after the time (rtc_send_all): the time comes with the next packet
		#(200000.0);
		io_adr(8'h00); io_rd(v); check("seconds", v, 8'h30);
		io_adr(8'h32); io_rd(v); check("century", v, 8'h20);
		io_adr(8'h0C); io_rd(v); check("C override", v, 8'h50);
		io_adr(8'h0D); io_rd(v); check("D override", v, 8'h80);
		io_adr(8'h0A); io_rd(v); check("A", v, 8'h26);
		tx[0] = 8'h06; tx[1] = 8'h01; tx[2] = 8'h0A; tx[3] = 8'hA6; packet(4);   // UIP in the mirror
		io_adr(8'h0A); io_rd(v); check("A UIP cleared", v, 8'h26);
		io_adr(8'h8B); io_rd(v); check("A7 not decoded (#8B = B)", v, 8'h02);
		tx[0] = 8'h06; tx[1] = 8'h01; tx[2] = 8'h0A; tx[3] = 8'h26; packet(4);

		// 2. READING with the 3.06 test cell
		test_cell = 8'h7F;
		reading;
		check("checksum of the image (3.04, 0E..1F)", area[8'h3F], cksum(18));
		check("image #0E", area[8'h0E], 8'h68);

		// 3. WRITING new values: 150 writes
		for (r = 8'h0E; r <= 8'h3E; r = r + 1) area[r] = r ^ 8'hA5;
		area[8'h32] = 8'h20;
		writing;
		for (r = 0; r < 256; r = r + 1) newv[r] = area[r];
		$display("%0.1f us: WRITING done", $realtime / 1000.0);

		// 4. CMSERR (3.06): set the clock
		cmos_wr(8'h0B, 8'h82);
		cmos_wr(8'h00, 8'h00); cmos_wr(8'h02, 8'h00); cmos_wr(8'h04, 8'h00);
		cmos_wr(8'h07, 8'h25); cmos_wr(8'h08, 8'h06); cmos_wr(8'h09, 8'h25); cmos_wr(8'h32, 8'h20);
		cmos_wr(8'h0B, 8'h02);
		newv[8'h32] = 8'h20;

		// 5. drain, compare
		fw_fast = 1;
		#(600000.0);
		fw_run = 0;
		#(200000.0);
		for (r = 8'h0E; r <= 8'h3F; r = r + 1) begin
			check("firmware EEPROM", eep[r], newv[r]);
			io_adr(r); io_rd(v); check("mirror", v, newv[r]);
		end
		check("EEPROM B", eep[8'h0B], 8'h02);
		check("EEPROM test cell #7F", eep[8'h7F], 8'h00);
		check("clock day", fw_time[7], 8'h25); check("clock month", fw_time[8], 8'h06);
		check("clock year", fw_time[9], 8'h25); check("clock hours", fw_time[4], 8'h00);
		io_adr(8'h09); io_rd(v); check("mirror year", v, 8'h25);
		$display("%0d GETs, %0d pairs, at most %0d registers pending at a sample", n_get, n_pairs, max_pend);

		// power cycle: the EEPROM of the firmware back into the mirror, READING: valid checksum
		for (r = 0; r < 128; r = r + 1) if (r != 8'h0C && r != 8'h0D) begin
			tx[0] = 8'h06; tx[1] = 8'h01; tx[2] = r; tx[3] = 8'h00; packet(4);   // clear the mirror first
		end
		fw_send_all;
		reading;
		check("checksum after the power cycle", area[8'h3F], cksum(18));
		check("#0E after the power cycle", area[8'h0E], newv[8'h0E]);
		$display("tb_cmos: %0d errors", errors);
		$finish;
	end
	initial begin #(20000000.0); $display("ERROR timeout"); $display("tb_cmos: %0d errors", errors + 1); $finish; end
endmodule
