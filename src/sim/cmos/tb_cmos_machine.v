// sp_cmos on the real bus: sp_machine (CPU + ACEX + MAX as in tb_machine) with sp_cmos on PER_D / PER_OE / MD /
// CMOS_*, and a model of the core side of kg_l2_rtc in the 28 MHz clock (RTC_A -> RTC_DO a clock later, a write
// with RTC_WR_N low). The BIOS 3.04 loads the ACEX (short stream, CFG_BITS_T); at 0000 of ROM page 8 (ROM 0x20000)
// the testbench puts a program instead of the BIOS (first a dummy IN A,(#FFBD): it ends STARTING; and answers the port table reads of the DCP from DRAM with the
// codes of the CMOS ports, the table the BIOS would have written):
//   OUT (#DFBD),#3F; OUT (#BFBD),#5A; IN A,(#FFBD); CPL; OUT (#BFBD),A      the CMOS_TEST of the BIOS on #3F
//   OUT (#DFBD),#0C; IN A,(#FFBD); LD E,A                                   C: the override #50
//   OUT (#DFBD),#0A; IN A,(#FFBD); LD D,A                                   A: UIP cleared (the model has #A6)
//   OUT (#DFBD),#40; OUT (#BFBD),E; OUT (#DFBD),#41; OUT (#BFBD),D          the read values into #40 / #41
//   OUT (#DFBD),#85; OUT (#BFBD),#77                                        A7 not decoded: #05
// Checks: the writes the model receives (address, data, in this order), the bytes the CPU reads (on its data bus at
// the end of each IN), the model RAM at the end. +storage: the read through the stage of sp_storage. +trace: every edge of the CMOS strobes with MD and the drivers.
`timescale 1ns/1ps
`ifndef CFG_BITS_T
`define CFG_BITS_T 256
`endif
`ifndef ROM_HEX
`define ROM_HEX "build/rom.hex"
`endif
module tb_cmos_machine;
	reg clk = 0, clk28 = 0;
	always #5.952 clk = ~clk;                         // 84 MHz
	always #17.856 clk28 = ~clk28;                    // 28 MHz = clk / 3, edges aligned
	integer errors = 0;

	// ---- the machine
	wire [20:0] sr_a; wire [15:0] sr_do, sr_dt, sr_di; wire [1:0] sr_we, sr_oe;
	wire sd_clk, sd_cke, sd_cs, sd_ras, sd_cas, sd_we; wire [1:0] sd_ba, sd_dqm; wire [12:0] sd_a;
	wire [15:0] sd_dqo, sd_dqt, sd_dqi;
	wire [1:0] cfg_state; wire [15:0] md; wire cmos_as, cmos_dwr, cmos_drd;
	wire [7:0] c_q; wire c_oe;
	// PER_D / PER_OE: +storage = the read stage of sp_storage in the board top (PER_D <= {Q, Q} a clock after the
	// strobe, PER_OE held until /IORQ rises), else sp_cmos directly ({Q, FF}, OE)
	wire [15:0] per_d; wire per_oe;
	reg  [15:0] st_d = 16'h0000; reg st_oe = 1'b0;
	always @(posedge clk) begin
		if (~cmos_drd) st_d <= {c_q, c_q};
		if (~cmos_drd) st_oe <= 1'b1; else if (m.io_n) st_oe <= 1'b0;
	end
	wire storage = $test$plusargs("storage");
	assign per_d  = storage ? st_d : {c_q, 8'hFF};
	assign per_oe = storage ? st_oe : c_oe;
	sp_machine #(.MIF_DCP("../../rtl/acex/mif/dcp.hex"), .MIF_AY("../../rtl/acex/mif/ay.hex"),
		.MIF_KBD("../../rtl/acex/mif/kbd_ini2.hex"), .CFG_BITS(`CFG_BITS_T), .SD_INIT(16'd16),
		.XHD_RES_ON_HSYNC(1)) m(.CLK(clk), .EPM_RES_N(1'b1), .PW_GOOD(1'b1),
		.SRAM_A(sr_a), .SRAM_D_O(sr_do), .SRAM_D_T(sr_dt), .SRAM_D_I(sr_di), .SRAM_WE_N(sr_we), .SRAM_OE_N(sr_oe),
		.LD_REQ(1'b0), .LD_A(21'd0), .LD_BE(2'b00), .LD_D(16'd0), .LD_ACK(),
		.SD_CLK(sd_clk), .SD_CKE(sd_cke), .SD_CS_N(sd_cs), .SD_RAS_N(sd_ras), .SD_CAS_N(sd_cas), .SD_WE_N(sd_we),
		.SD_BA(sd_ba), .SD_A(sd_a), .SD_DQM(sd_dqm), .SD_DQ_O(sd_dqo), .SD_DQ_T(sd_dqt), .SD_DQ_I(sd_dqi),
		.KBD_CC(1'b1), .KBD_DD(1'b1), .MOUSE_D(1'b1), .TAPE_IN(1'b1), .FDD_W(1'b1), .FDD_CH(1'b1), .TAPE_OUT(),
		.RXA_D(8'h00), .RXA_STB(1'b0), .RXA_RDY(), .RXB_D(8'h00), .RXB_STB(1'b0), .RXB_RDY(),
		.PA_I(8'hFF), .PA_O(), .PB_I(8'hFF), .PB_O(), .PER_D(per_d), .PER_OE(per_oe), .MD(md), .HDD_C(),
		.FDD_C(), .HD_A(), .WR_PDOS(), .WG_WR_N(), .WG_RD_N(), .CMOS_DWR(cmos_dwr), .CMOS_AS(cmos_as),
		.CMOS_DRD(cmos_drd), .XHD_RES(), .XHD_WR(), .XHD_RD(), .XHD1_CS(), .XHD2_CS(), .FDD_1440(), .WR_COL(),
		.PAL_Q(), .VA(), .SINC_H(), .SINC_V(), .T320(), .DAC_DATA(), .DAC_WS(), .DAC_BCK(), .TURBO_LED(),
		.CFG_STATE(cfg_state), .CFG_HASH(), .CFG_BYTES(), .CFG_PERS(), .CFG_UNKNOWN());

	// ---- sp_cmos and the kg_l2_rtc model
	wire [7:0] rtc_a, rtc_di, rtc_do; wire rtc_wr_n;
	sp_cmos u_cmos(.CLK(clk), .MD(md), .CMOS_AS(cmos_as), .CMOS_DWR(cmos_dwr), .CMOS_DRD(cmos_drd), .Q(c_q), .OE(c_oe),
		.CLK_BUS(clk28), .RTC_A(rtc_a), .RTC_DI(rtc_di), .RTC_WR_N(rtc_wr_n), .RTC_DO(rtc_do));
	reg [7:0] rtc [0:255];
	reg [7:0] rtc_q = 8'h00;
	assign rtc_do = rtc_q;
	integer nw = 0;
	reg [15:0] wr_log [0:15];
	always @(posedge clk28) begin
		rtc_q <= rtc[rtc_a];
		if (!rtc_wr_n) begin
			rtc[rtc_a] <= rtc_di;
			if (nw < 16) wr_log[nw] = {rtc_a, rtc_di};
			nw = nw + 1;
			$display("%0.1f us: RTC write %h = %h", $realtime / 1000.0, rtc_a, rtc_di);
		end
	end

	// ---- SRAM / SDRAM models (as tb_machine)
	reg [7:0] slo [0:524287], shi [0:524287];
	wire [18:0] sw = sr_a[18:0];
	assign sr_di[7:0]  = ~sr_dt[0] ? sr_do[7:0]  : ~sr_oe[0] ? slo[sw] : 8'hFF;
	assign sr_di[15:8] = ~sr_dt[8] ? sr_do[15:8] : ~sr_oe[1] ? shi[sw] : 8'hFF;
	always @(posedge sr_we[0]) slo[sw] <= sr_do[7:0];
	always @(posedge sr_we[1]) shi[sw] <= sr_do[15:8];
	reg [15:0] sdm [0:2097151];
	function [7:0] port_code(input [15:0] a);
		port_code = a == 16'hFFBD ? 8'h1C : a == 16'hDFBD ? 8'h1D : a == 16'hBFBD ? 8'h1E : 8'h00;
	endfunction
	reg [11:0] row = 0;
	reg [16:0] p0 = 0, p1 = 0, pq = 0;
	wire [20:0] sdi = {row, sd_a[8:0]};
	always @(posedge sd_clk) begin
		pq <= p1; p1 <= p0; p0 <= 17'd0;
		if (!sd_cs) case ({sd_ras, sd_cas, sd_we})
			3'b011: row <= sd_a[11:0];
			// READ; with A = a CMOS port it is the port table of the DCP (DRAM page #40, written by the BIOS at its
			// start, which this program skips; the program has no other DRAM access): the codes 1C / 1D / 1E
			3'b101: p0 <= port_code(m.a) != 8'h00 ? {1'b1, {2{port_code(m.a)}}} : {1'b1, sdm[sdi]};
			3'b100: begin
				if (!sd_dqm[0]) sdm[sdi][7:0]  <= sd_dqo[7:0];
				if (!sd_dqm[1]) sdm[sdi][15:8] <= sd_dqo[15:8];
			end
			default: ;
		endcase
	end
	assign sd_dqi = ~sd_dqt[0] ? sd_dqo : pq[16] ? pq[15:0] : 16'hFFFF;

	// ---- the BIOS (its ACEX loader) and the program at ROM 0x20000
	reg [7:0] rom [0:262143];
	reg [7:0] prog [0:127];
	integer i, np;
	task p(input [7:0] b); begin prog[np] = b; np = np + 1; end endtask
	task p_out(input [15:0] port, input [7:0] v); begin   // LD BC,port; LD A,v; OUT (C),A
		p(8'h01); p(port[7:0]); p(port[15:8]); p(8'h3E); p(v); p(8'hED); p(8'h79); end endtask
	task p_bc(input [15:0] port); begin p(8'h01); p(port[7:0]); p(port[15:8]); end endtask
	initial begin
		np = 0;
		p(8'hF3);                                       // DI
		p_bc(16'hFFBD); p(8'hED); p(8'h78);             // IN: ends STARTING of the DCP (port writes before the first
		                                                // port read do not reach the devices, as MAME m_starting)
		p_out(16'hDFBD, 8'h3F); p_out(16'hBFBD, 8'h5A);
		p_bc(16'hFFBD); p(8'hED); p(8'h78);             // IN A,(C)
		p(8'h2F);                                       // CPL
		p_bc(16'hBFBD); p(8'hED); p(8'h79);             // OUT (C),A
		p_out(16'hDFBD, 8'h0C); p_bc(16'hFFBD); p(8'hED); p(8'h78); p(8'h5F);   // LD E,A
		p_out(16'hDFBD, 8'h0A); p_bc(16'hFFBD); p(8'hED); p(8'h78); p(8'h57);   // LD D,A
		p_out(16'hDFBD, 8'h40); p_bc(16'hBFBD); p(8'hED); p(8'h59);             // OUT (C),E
		p_out(16'hDFBD, 8'h41); p_bc(16'hBFBD); p(8'hED); p(8'h51);             // OUT (C),D
		p_out(16'hDFBD, 8'h85); p_out(16'hBFBD, 8'h77);
		p(8'h18); p(8'hFE);                             // JR $
		for (i = 0; i < 524288; i = i + 1) begin slo[i] = 8'h00; shi[i] = 8'h00; end
		for (i = 0; i < 2097152; i = i + 1) sdm[i] = 16'h0000;
		for (i = 0; i < 256; i = i + 1) rtc[i] = 8'h00;
		rtc[8'h0A] = 8'hA6;                             // UIP set in the mirror: the read must clear it
		rtc[8'h0C] = 8'h00;                             // as the firmware sends C
		$readmemh(`ROM_HEX, rom);
		for (i = 0; i < np; i = i + 1) rom[18'h20000 + i] = prog[i];
		for (i = 0; i < 262144; i = i + 2) begin slo[19'h40000 + i / 2] = rom[i]; shi[19'h40000 + i / 2] = rom[i + 1]; end
	end

	// ---- observation
	wire on = cfg_state == 2'd3;
	integer nin = 0;
	reg [7:0] in_log [0:7];
	reg rd_p = 1, io_p = 1, wr_p = 1, as_p = 0, dwr_p = 1, drd_p = 1, m1_p = 0;
	integer n_m1 = 0;
	wire m1 = ~m.m1_n & ~m.mr_n & ~m.rd_n;
	always @(posedge clk) begin
		rd_p <= m.rd_n; io_p <= m.io_n; wr_p <= m.wr_n; as_p <= cmos_as; dwr_p <= cmos_dwr; drd_p <= cmos_drd; m1_p <= m1;
		if (on && m.z_res_n && m1 && !m1_p) begin
			n_m1 = n_m1 + 1;
			if (n_m1 <= 60 && $test$plusargs("trace")) $display("  M1 %h: %h (RA %h)", m.a, m.d_bus, m.x_ra);
		end
		if (on && m.z_res_n && wr_p && !m.wr_n && !m.io_n && $test$plusargs("trace"))
			$display("%0.3f us: OUT (%h), %h  HDD_C/FDD_C %b/%b", $realtime / 1000.0, m.a, m.d_bus, m.HDD_C, m.FDD_C);
		if (on && m.z_res_n && !rd_p && m.rd_n && !io_p && m.m1_n) begin   // the end of an I/O read
			if (nin < 8) in_log[nin] = m.d_bus;
			nin = nin + 1;
			$display("%0.1f us: IN (%h) = %h", $realtime / 1000.0, m.a, m.d_bus);
		end
		if ($test$plusargs("trace") && on && (as_p != cmos_as || dwr_p != cmos_dwr || drd_p != cmos_drd))
			$display("%0.3f us: AS %b DWR %b DRD %b  MD %h  ACEX MD_OE %b SDRAM drv %b  /RD %b /WR %b /IORQ %b A %h",
				$realtime / 1000.0, cmos_as, cmos_dwr, cmos_drd, md, m.x_mdoe, m.sd_drv, m.rd_n, m.wr_n, m.io_n, m.a);
	end

	task want_w(input integer k, input [15:0] v); begin
		if (wr_log[k] !== v) begin $display("  ERROR: RTC write %0d = %h, want %h", k, wr_log[k], v); errors = errors + 1; end
	end endtask
	task want_in(input integer k, input [7:0] v); begin
		if (in_log[k] !== v) begin $display("  ERROR: IN %0d = %h, want %h", k, in_log[k], v); errors = errors + 1; end
	end endtask
	task want_r(input [7:0] a, input [7:0] v); begin
		if (rtc[a] !== v) begin $display("  ERROR: RTC register %h = %h, want %h", a, rtc[a], v); errors = errors + 1; end
	end endtask

	initial begin
		wait (on);
		$display("%0.1f us: ACEX released", $realtime / 1000.0);
		#(60000.0);
		if (nw != 5) begin $display("  ERROR: %0d RTC writes, want 5", nw); errors = errors + 1; end
		want_w(0, 16'h3F5A); want_w(1, 16'h3FA5); want_w(2, 16'h4050); want_w(3, 16'h4126); want_w(4, 16'h0577);
		if (nin != 4) begin $display("  ERROR: %0d INs, want 4", nin); errors = errors + 1; end
		want_in(1, 8'h5A); want_in(2, 8'h50); want_in(3, 8'h26);
		want_r(8'h3F, 8'hA5); want_r(8'h40, 8'h50); want_r(8'h41, 8'h26); want_r(8'h05, 8'h77);
		$display("tb_cmos_machine: %0d errors", errors);
		$finish;
	end
	initial begin
		#(3000000.0);
		$display("  ERROR: no release in 3 ms");
		$display("tb_cmos_machine: %0d errors", errors + 1);
		$finish;
	end
endmodule
