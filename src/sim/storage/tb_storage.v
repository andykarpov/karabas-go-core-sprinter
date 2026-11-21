// tb_storage: the storage path end to end (docs/storage.md 5). sp_machine (BIOS 3.04 image, its loader pours a short
// configuration stream, CFG_BITS_T) with storage.asm in ROM page 8, sp_storage (hdf_ata + sp_fdd / wd1793) on the
// MAX strobes and MD, and a model of the sdc side of kg_l2_img with images made of a pattern:
//   slot 0 (drive A): a 1.44 MB PC image; slot 1 (drive B): 720 KB PC (+trd: a TRD of 640 KB); slot 4 (IDE master):
//   2 GiB + 512 bytes (the ZXMAK2 VHD: a raw disk and its footer), sector 0 = an MBR-like pattern ending 55 AA.
// The program logs through OUT (#01) (bytes) and OUT (#02) (markers); the testbench checks the IDE sector 0, the
// absent slave / secondary channel, the two floppy sectors (track 79, side 1, the last sector of the track: past
// 1 MB of the 1.44 MB image), the wrong-rate timeout and Read Address. +timing prints the first strobes of each kind
// with the events of the ACEX around them (the bus measurements of docs/storage.md).
// Runs in Verilator (--timing) or iverilog; memories are zero-delay models as tb_machine.
`timescale 1ns/1ps
`ifndef CFG_BITS_T
`define CFG_BITS_T 256
`endif
`ifndef STOP_MS
`define STOP_MS 120
`endif
module tb_storage;
	reg clk = 0, clk_bus = 0;
	always #5.952 clk = ~clk;                         // 84 MHz
	always #17.856 clk_bus = ~clk_bus;                // 28 MHz = 84 / 3, the edges on every third clk edge
	integer errors = 0;
	reg trd = 0, bios = 0;
	reg pwr = 1;
	initial begin trd = $test$plusargs("trd"); bios = $test$plusargs("bios"); #(200.0); pwr = 0; end
	// +bios: the BIOS runs as it is (no test program); +img0=<file> / +img4=<file>: drive A / the IDE master from a
	// file (a raw image: .img, .vhd with its footer) instead of the pattern
	reg [1023:0] fn0, fn4; integer fd0 = 0, fd4 = 0, fsz0 = 0, fsz4 = 0, r;
	initial begin
		if ($value$plusargs("img0=%s", fn0)) begin fd0 = $fopen(fn0, "rb"); r = $fseek(fd0, 0, 2); fsz0 = $ftell(fd0); end
		if ($value$plusargs("img4=%s", fn4)) begin fd4 = $fopen(fn4, "rb"); r = $fseek(fd4, 0, 2); fsz4 = $ftell(fd4); end
		if (fd0 != 0) $display("drive A: %0s, %0d bytes", fn0, fsz0);
		if (fd4 != 0) $display("IDE master: %0s, %0d bytes", fn4, {32'd0, fsz4[31:0]});
	end
	reg [7:0] fbuf [0:511];
	task fsec(input integer fd, input [31:0] sec); integer j; begin
		r = $fseek(fd, sec * 512, 0);
		for (j = 0; j < 512; j = j + 1) fbuf[j] = $fgetc(fd);
	end endtask

	// ---- the machine
	wire [20:0] sr_a; wire [15:0] sr_do, sr_dt, sr_di; wire [1:0] sr_we, sr_oe;
	wire sd_clk, sd_cke, sd_cs, sd_ras, sd_cas, sd_we; wire [1:0] sd_ba, sd_dqm; wire [12:0] sd_a;
	wire [15:0] sd_dqo, sd_dqt, sd_dqi;
	wire [1:0] cfg_state;
	wire [15:0] per_d, md; wire per_oe;
	wire [3:0] hdd_c; wire [2:0] fdd_c, hd_a; wire [1:0] wg_a; wire rd_kmps, iorq_n, cpu_res_n;
	wire wr_pdos, wg_wr_n, wg_rd_n, cmos_dwr, cmos_as, cmos_drd, xhd_res, xhd_wr, xhd_rd, fdd_1440;
	wire [2:1] xhd1_cs, xhd2_cs;
	sp_machine #(.MIF_DCP("../../rtl/acex/mif/dcp.hex"), .MIF_AY("../../rtl/acex/mif/ay.hex"),
		.MIF_KBD("../../rtl/acex/mif/kbd_ini2.hex"), .CFG_BITS(`CFG_BITS_T), .SD_INIT(16'd16),
		.XHD_RES_ON_HSYNC(1)) m(.CLK(clk), .EPM_RES_N(1'b1), .PW_GOOD(1'b1),
		.SRAM_A(sr_a), .SRAM_D_O(sr_do), .SRAM_D_T(sr_dt), .SRAM_D_I(sr_di), .SRAM_WE_N(sr_we), .SRAM_OE_N(sr_oe),
		.LD_REQ(1'b0), .LD_A(21'd0), .LD_BE(2'b00), .LD_D(16'd0), .LD_ACK(),
		.SD_CLK(sd_clk), .SD_CKE(sd_cke), .SD_CS_N(sd_cs), .SD_RAS_N(sd_ras), .SD_CAS_N(sd_cas), .SD_WE_N(sd_we),
		.SD_BA(sd_ba), .SD_A(sd_a), .SD_DQM(sd_dqm), .SD_DQ_O(sd_dqo), .SD_DQ_T(sd_dqt), .SD_DQ_I(sd_dqi),
		.KBD_CC(1'b1), .KBD_DD(1'b1), .MOUSE_D(1'b1), .TAPE_IN(1'b1), .FDD_W(1'b1), .FDD_CH(1'b1), .TAPE_OUT(),
		.RXA_D(8'h00), .RXA_STB(1'b0), .RXA_RDY(), .RXB_D(8'h00), .RXB_STB(1'b0), .RXB_RDY(),
		.PA_I(8'hFF), .PA_O(), .PB_I(8'hFF), .PB_O(), .PER_D(per_d), .PER_OE(per_oe), .MD(md), .HDD_C(hdd_c),
		.FDD_C(fdd_c), .HD_A(hd_a), .WG_A(wg_a), .RD_KMPS(rd_kmps), .IORQ_N(iorq_n), .CPU_RES_N(cpu_res_n),
		.WR_PDOS(wr_pdos), .WG_WR_N(wg_wr_n), .WG_RD_N(wg_rd_n), .CMOS_DWR(cmos_dwr), .CMOS_AS(cmos_as),
		.CMOS_DRD(cmos_drd), .XHD_RES(xhd_res), .XHD_WR(xhd_wr), .XHD_RD(xhd_rd), .XHD1_CS(xhd1_cs),
		.XHD2_CS(xhd2_cs), .FDD_1440(fdd_1440), .WR_COL(), .PAL_Q(), .VA(), .SINC_H(), .SINC_V(), .T320(),
		.DAC_DATA(), .DAC_WS(), .DAC_BCK(), .TURBO_LED(), .CFG_STATE(cfg_state), .CFG_HASH(),
		.CFG_BYTES(), .CFG_PERS(), .CFG_UNKNOWN());

	// ---- +cmos: a DS12887 model (the CMOS of BIOS 3.04: src/roms/cmos_default.bin, docs/rtc.md 8.3): the address
	// MD[14:8] while CMOS_AS is 1, written at the rise of CMOS_DWR, read while CMOS_DRD is low; C = 50, D = 80, A
	// without UIP (the overrides of sp_cmos). Without +cmos a CMOS read gives 00 (the top until sp_cmos is wired).
	reg [7:0] cmos_m [0:255]; reg [6:0] cm_a = 0; reg cm_w = 1; reg [7:0] cm_d = 0; integer n_cr = 0, n_cw = 0;
	reg cmos_on = 0;
	initial begin cmos_on = $test$plusargs("cmos"); $readmemh("build/cmos.hex", cmos_m); end
	always @(posedge clk) begin
		cm_w <= cmos_dwr;
		if (cmos_as) cm_a <= md[14:8];
		if (!cmos_dwr) cm_d <= md[15:8];
		if (cmos_dwr && !cm_w && cmos_on) begin cmos_m[cm_a] = cm_d; n_cw = n_cw + 1; end
	end
	wire [7:0] cmos_q = !cmos_on ? 8'h00 : cm_a == 7'h0C ? 8'h50 : cm_a == 7'h0D ? 8'h80 :
		cm_a == 7'h0A ? {1'b0, cmos_m[cm_a][6:0]} : cmos_m[cm_a];
	reg cm_r = 1;
	always @(posedge clk) begin
		cm_r <= cmos_drd;
		if (!cmos_drd && cm_r && cmos_on && n_cr < 40) $display("%0.3f ms: CMOS read %h = %h", $realtime / 1.0e6, cm_a, cmos_q);
		if (!cmos_drd && cm_r) n_cr = n_cr + 1;
	end

	// ---- storage
	reg  [7:0] mnt = 8'd0; reg [63:0] mnt_size = 64'd0;
	wire [7:0] sdc_rd, sdc_wr; wire [31:0] sdc_sector; wire [7:0] sdc_out;
	reg sdc_busy = 0, sdc_done = 0, sdc_stb = 0; reg [2:0] sdc_slot = 0; reg [8:0] sdc_addr = 0; reg [7:0] sdc_in = 0;
	sp_storage st(.CLK(clk), .CLK_BUS(clk_bus), .RESET(pwr), .CPU_RES_N(cpu_res_n), .IORQ_N(iorq_n), .MD(md),
		.HDD_C(hdd_c), .FDD_C(fdd_c), .HD_A(hd_a), .WG_A(wg_a), .XHD_RES(xhd_res), .XHD_RD(xhd_rd), .XHD_WR(xhd_wr),
		.XHD1_CS(xhd1_cs), .XHD2_CS(xhd2_cs), .WG_RD_N(wg_rd_n), .WG_WR_N(wg_wr_n), .WR_PDOS(wr_pdos),
		.RD_KMPS(rd_kmps), .FDD_1440(fdd_1440), .CMOS_DRD(cmos_drd), .CMOS_Q(cmos_q), .PER_D(per_d), .PER_OE(per_oe),
		.SDC_IMG_MOUNTED(mnt), .SDC_IMG_SIZE(mnt_size), .SDC_RD(sdc_rd), .SDC_WR(sdc_wr), .SDC_SECTOR(sdc_sector),
		.SDC_BUSY(sdc_busy), .SDC_DONE(sdc_done), .SDC_ERROR(1'b0), .SDC_SLOT(sdc_slot),
		.SDC_BYTE_IN_STROBE(sdc_stb), .SDC_BYTE_ADDR(sdc_addr), .SDC_BYTE_IN_DATA(sdc_in),
		.SDC_BYTE_OUT_DATA(sdc_out), .IMG_WP(8'h00), .HDD_LED(), .FDD_ACTIVE());

	// ---- the images: a byte of slot s at byte offset o
	function [7:0] img(input [2:0] s, input [40:0] o);
		begin
			if (s == 3'd4 && o < 512) img = (o == 510) ? 8'h55 : (o == 511) ? 8'hAA : o[7:0] * 8'd3 + 8'd1;
			else img = o[7:0] ^ o[16:9] ^ {o[20:17], 1'b0, s} ^ 8'h5A;
		end
	endfunction
	// the sdc model (kg_l2_img: one request at a time, the lowest slot first; busy up when taken, down with done)
	integer k, q; reg q_wr; reg [31:0] q_sec, w_sec = 32'hFFFFFFFF; reg [7:0] wbuf [0:511];
	initial begin
		wait (!pwr);
		repeat (10) @(posedge clk_bus);
		mnt_size = fd0 != 0 ? {32'd0, fsz0[31:0]} : 64'd1474560; mnt = 8'h01; @(posedge clk_bus); mnt = 8'h00;
		mnt_size = trd ? 64'd655360 : 64'd737280; mnt = 8'h02; @(posedge clk_bus); mnt = 8'h00;
		mnt_size = fd4 != 0 ? {32'd0, fsz4[31:0]} : 64'd2147484160; mnt = 8'h10; @(posedge clk_bus); mnt = 8'h00;
		forever begin
			@(posedge clk_bus);
			if (sdc_rd != 0 || sdc_wr != 0) begin
				q = 0; while (!sdc_rd[q] && !sdc_wr[q]) q = q + 1;
				sdc_slot <= q; sdc_busy <= 1; q_sec = sdc_sector; q_wr = sdc_wr[q];   // kg_l2_img takes the sector with the request
				repeat (200) @(posedge clk_bus);          // ~7 us: the mcu is slower (ms)
				if (q_wr) begin                       // the requester gives a byte OUT_LATENCY (3) after the address
					for (k = 0; k < 512; k = k + 1) begin
						sdc_addr <= k; repeat (4) @(posedge clk_bus); wbuf[k] = sdc_out;
					end
					w_sec = q == 4 ? q_sec : 32'hFFFFFFFF;
					$display("%0.1f us: sdc slot %0d sector %0d written", $realtime / 1000.0, q, q_sec);
				end else begin
					if (q == 0 && fd0 != 0) fsec(fd0, q_sec);
					if (q == 4 && fd4 != 0) fsec(fd4, q_sec);
					for (k = 0; k < 512; k = k + 1) begin
						sdc_addr <= k;
						sdc_in <= (q == 4 && q_sec == w_sec) ? wbuf[k] : ((q == 0 && fd0 != 0) || (q == 4 && fd4 != 0)) ?
							fbuf[k] : img(q, {q_sec, 9'd0} + k);
						sdc_stb <= 1; @(posedge clk_bus);
						sdc_stb <= 0; @(posedge clk_bus);
					end
				end
				sdc_busy <= 0; sdc_done <= 1; @(posedge clk_bus); sdc_done <= 0;
				if (q != 4 || bios) $display("%0.1f us: sdc slot %0d sector %0d", $realtime / 1000.0, q, q_sec);
			end
		end
	end

	// ---- SRAM, SDRAM: as tb_machine
	reg [7:0] slo [0:524287], shi [0:524287];
	wire [18:0] sw = sr_a[18:0];
	assign sr_di[7:0]  = ~sr_dt[0] ? sr_do[7:0]  : ~sr_oe[0] ? slo[sw] : 8'hFF;
	assign sr_di[15:8] = ~sr_dt[8] ? sr_do[15:8] : ~sr_oe[1] ? shi[sw] : 8'hFF;
	always @(posedge sr_we[0]) slo[sw] <= sr_do[7:0];
	always @(posedge sr_we[1]) shi[sw] <= sr_do[15:8];
	reg [15:0] sdm [0:2097151];
	reg [11:0] row = 0;
	reg [16:0] p0 = 0, p1 = 0, pq = 0;
	wire [20:0] sdi = {row, sd_a[8:0]};
	always @(posedge sd_clk) begin
		pq <= p1; p1 <= p0; p0 <= 17'd0;
		if (!sd_cs) case ({sd_ras, sd_cas, sd_we})
			3'b011: row <= sd_a[11:0];
			3'b101: p0 <= {1'b1, sdm[sdi]};
			3'b100: begin
				if (!sd_dqm[0]) sdm[sdi][7:0]  <= sd_dqo[7:0];
				if (!sd_dqm[1]) sdm[sdi][15:8] <= sd_dqo[15:8];
			end
			default: ;
		endcase
	end
	assign sd_dqi = ~sd_dqt[0] ? sd_dqo : pq[16] ? pq[15:0] : 16'hFFFF;
	reg [7:0] rom [0:262143], prg [0:16383];
	integer i;
	initial begin
		for (i = 0; i < 524288; i = i + 1) begin slo[i] = 8'h00; shi[i] = 8'h00; end
		for (i = 0; i < 2097152; i = i + 1) sdm[i] = 16'h0000;
		for (i = 0; i < 16384; i = i + 1) prg[i] = 8'hFF;
		$readmemh("build/rom.hex", rom);
		$readmemh("build/storage.hex", prg);
		if (!$test$plusargs("bios")) for (i = 0; i < 16384; i = i + 1) rom[18'h20000 + i] = prg[i];
		for (i = 0; i < 262144; i = i + 2) begin slo[19'h40000 + i / 2] = rom[i]; shi[19'h40000 + i / 2] = rom[i + 1]; end
	end

	// ---- the log of the program
	reg [7:0] lg [0:4095]; integer nl = 0;
	reg [7:0] mk [0:63]; integer mpos [0:63]; integer nm = 0;
	reg wr_p = 1;
	wire on = cfg_state == 2'd3;
	always @(posedge clk) begin
		wr_p <= m.wr_n;
		if (on && wr_p && !m.wr_n && !m.io_n) begin
			if (m.a[7:0] == 8'h01) begin if (nl < 4096) lg[nl] = m.d_bus; nl = nl + 1; end
			if (m.a[7:0] == 8'h02) begin
				mk[nm] = m.d_bus; mpos[nm] = nl; nm = nm + 1;
				$display("%0.1f us: marker %h (%0d bytes logged)", $realtime / 1000.0, m.d_bus, nl);
			end
		end
	end
	function integer at(input [7:0] marker);         // log position of a marker, -1 if none
		integer j; begin at = -1; for (j = 0; j < nm; j = j + 1) if (mk[j] == marker && at < 0) at = mpos[j]; end
	endfunction

	// ---- +timing: the first strobes of each kind and the ACEX events around them
	integer nt [0:3]; reg [3:0] sp = 4'hF; realtime t0 [0:3];
	initial begin nt[0] = 0; nt[1] = 0; nt[2] = 0; nt[3] = 0; end
	wire [3:0] sv = {rd_kmps | ~fdd_c[0], wg_rd_n & wg_wr_n, xhd_wr, xhd_rd};
	reg iorq_p = 1, mdp_p = 0, hddr_p = 0;
	always @(posedge clk) if ($test$plusargs("timing") && on) begin : tm
		integer s;
		sp <= sv;
		for (s = 0; s < 4; s = s + 1) begin
			if (!sv[s] && sp[s] && nt[s] < 3) begin
				t0[s] = $realtime;
				$display("T %0d: %0s fall at %0.1f ns: A %h HD_A %h CS1 %b CS2 %b WG_A %h MD %h", nt[s],
					s == 0 ? "XHD_RD" : s == 1 ? "XHD_WR" : s == 2 ? "WG" : "KMPS", $realtime, m.a, hd_a, xhd1_cs, xhd2_cs, wg_a, md);
			end
			if (sv[s] && !sp[s] && nt[s] < 3) begin
				$display("T %0d: rise after %0.1f ns, MD %h PER_OE %b, x_mdoe %b sd_drv %b", nt[s], $realtime - t0[s], md,
					per_oe, m.x_mdoe, m.sd_drv);
				nt[s] = nt[s] + 1;
			end
		end
		if (m.ACEX.mdp_ev && nt[0] + nt[1] + nt[2] + nt[3] < 8)
			$display("   mdp_ev at %0.1f ns: MD %h PER_OE %b sd_drv %b", $realtime, md, per_oe, m.sd_drv);
		if (m.ACEX.hddr_ev && nt[0] < 3)
			$display("   hddr_ev at %0.1f ns: MD %h D %h PER_OE %b sd_drv %b", $realtime, md, m.d_bus, per_oe, m.sd_drv);
		iorq_p <= m.io_n;
		if (m.io_n && !iorq_p && per_oe && nt[0] + nt[1] + nt[2] + nt[3] < 8) $display("   /IORQ rise at %0.1f ns", $realtime);
	end

	// ---- +io: the I/O cycles (port, data at the end of /RD or /WR) after the marker given by +io=<hex>
	reg [7:0] io_from = 8'hFF; integer n_io = 0; reg io_q = 1, io_rd = 0; reg [7:0] io_d = 0; reg [15:0] io_a = 0;
	initial if (!$value$plusargs("io=%h", io_from)) io_from = 8'hFF;
	real iot_ms = 0; initial if (!$value$plusargs("iot=%f", iot_ms)) iot_ms = 0;   // +iot=<ms>: from that time
	// +pc: the address of an M1 every 2 ms
	real pc_next = 2.0e6; reg m1q = 1;
	always @(posedge clk) if ($test$plusargs("pc")) begin
		m1q <= m.m1_n | m.mr_n;
		if (!(m.m1_n | m.mr_n) && m1q && $realtime >= pc_next) begin
			$display("   PC %h (RA %h) at %0.1f ms", m.a, m.x_ra, $realtime / 1.0e6); pc_next = pc_next + 2.0e6;
		end
	end
	always @(posedge clk) begin
		io_q <= m.io_n;
		if (!m.io_n && m.m1_n) begin io_a <= m.a; io_d <= m.d_bus; io_rd <= !m.rd_n; end
		if (on && n_io < 600 && m.io_n && !io_q && ((nm > 0 && mk[nm - 1] >= io_from && io_from != 8'hFF) ||
		    (iot_ms > 0 && $realtime >= iot_ms * 1.0e6))) begin
			$display("   io %0s %h = %h at %0.1f us", io_rd ? "IN " : "OUT", io_a, io_d, $realtime / 1000.0);
			n_io = n_io + 1;
		end
	end

	// ---- +bios: the IDE / FDD commands and the channel select of the BIOS
	reg xw_q = 1, wgw_q = 1, xr_q = 1; integer n_st = 0;
	always @(posedge clk) if (bios) begin
		xw_q <= xhd_wr; wgw_q <= wg_wr_n; xr_q <= xhd_rd;
		if (xhd_wr && !xw_q && hd_a == 7 && st.ide_cs_n == 2'b10)
			$display("%0.3f ms: IDE command %h (%0s channel; count %h sector %h cyl %h%h dev/head %h)", $realtime / 1.0e6,
				st.ide_d[7:0], st.ide_on ? "primary" : "secondary", st.hdf.r_count, st.hdf.r_sector, st.hdf.r_cyl_hi,
				st.hdf.r_cyl_lo, st.hdf.r_head);
		if (xhd_rd && !xr_q) n_st = n_st + 1;
		if (wg_wr_n && !wgw_q && st.wg_a == 0) $display("%0.3f ms: WD1793 command %h, system register %h", $realtime / 1.0e6,
			st.wg_d, st.fdd.sys);
	end
	reg [1:0] hsel_p = 0;
	always @(posedge clk) if (bios) begin
		hsel_p <= m.MAX.hdd_q;
		if (m.MAX.hdd_q != hsel_p) $display("%0.3f ms: IDE channel %0s", $realtime / 1.0e6,
			m.MAX.hdd_q == 2 ? "HDD2 (primary)" : m.MAX.hdd_q == 1 ? "HDD1 (secondary)" : "none");
	end
	// ---- +wtrace: the first IDE data writes
	integer nw = 0; reg xw_p = 1;
	always @(posedge clk) if ($test$plusargs("wtrace")) begin
		xw_p <= xhd_wr;
		if (xhd_wr && !xw_p && hd_a == 0 && nw < 6) begin
			nw = nw + 1;
			$display("   IDE data write end at %0.1f ns: A %h MD %h ide_d %h cs %b hddr %h", $realtime, m.a, md, st.ide_d,
				st.ide_cs_n, m.ACEX.hddr);
		end
	end
	// ---- +dbg=<ns>: every CLK for 1 us from there
	real dbg_t = 0;
	initial if (!$value$plusargs("dbg=%f", dbg_t)) dbg_t = 0;
	always @(posedge clk) if (dbg_t > 0 && $realtime >= dbg_t && $realtime < dbg_t + 1000.0)
		$display("   %0.1f ce %b zclk %b io %b rd %b wait %b D %h doe %b MD %h per %b WG %b KMPS %b mdp %h tclk %b",
			$realtime, m.ce, m.zclk, m.io_n, m.rd_n, m.z_wait_n, m.d_bus, m.x_doe, md, per_oe, wg_rd_n, rd_kmps,
			m.ACEX.mdp, m.CPU.CLKZ1);

	// ---- checks
	integer p, n, e0, c0, nb;
	reg [40:0] off;
	task chk_fdd(input [7:0] marker, input [2:0] slot, input integer spt, input integer ssz, input integer sec,
		input [7:0] rmark);
		begin
			p = at(marker);
			if (p < 0) begin $display("ERROR: no marker %h", marker); errors = errors + 1; end
			else begin
				nb = lg[p + 3] * 256 + lg[p + 4];
				$display("  drive %0d: seek status %h, track %0d, end status %h, %0d bytes", slot, lg[p], lg[p + 1],
					lg[p + 2], nb);
				if (lg[p + 1] != 79 || nb != ssz || (lg[p + 2] & 8'h1C) != 0) begin
					$display("ERROR: drive %0d: track / status / count", slot); errors = errors + 1;
				end
				off = ((79 * 2 + 1) * spt + sec - 1) * ssz;
				e0 = 0;
				for (k = 0; k < ssz; k = k + 1) if (lg[p + 5 + k] !== img(slot, off + k)) begin
					if (e0 < 4) $display("  byte %0d: %h, image %h", k, lg[p + 5 + k], img(slot, off + k));
					e0 = e0 + 1;
				end
				if (e0 != 0) begin $display("ERROR: drive %0d: %0d bytes differ", slot, e0); errors = errors + 1; end
				else $display("  drive %0d: %0d bytes of track 79 side 1 sector %0d = the image (offset %0d)", slot, ssz,
					sec, off);
			end
		end
	endtask
	reg fin = 0;
	always @(posedge clk) if (nm > 0) if (mk[nm - 1] == 8'hff) fin <= 1;
	initial begin #(`STOP_MS * 1.0e6); fin = 1; end
	initial begin
		wait (fin);
		#(100.0);
		if (bios) begin
			$display("tb_storage +bios: %0d IDE read strobes, %0d CMOS reads, %0d CMOS writes, end at %0.2f ms", n_st,
				n_cr, n_cw, $realtime / 1.0e6);
			$finish;
		end else begin
		if (nm == 0 || mk[nm - 1] != 8'hff) begin $display("ERROR: the program did not end (%0d markers)", nm); errors = errors + 1; end
		// IDE: status, count read back, status at DRQ, status after; 512 bytes; slave status, count; secondary
		p = at(8'h11);
		if (p < 0) begin $display("ERROR: IDE: no sector"); errors = errors + 1; end
		else begin
			$display("  IDE: master status %h, count read back %h, status at DRQ %h, after the block %h", lg[0], lg[1],
				lg[2], lg[3]);
			if (lg[0] != 8'h50 || lg[1] != 8'h01 || lg[2] != 8'h58 || lg[3] != 8'h50) begin
				$display("ERROR: IDE status"); errors = errors + 1;
			end
			e0 = 0;
			for (k = 0; k < 512; k = k + 1) if (lg[p + k] !== img(3'd4, k)) begin
				if (e0 < 4) $display("  byte %0d: %h, image %h", k, lg[p + k], img(3'd4, k));
				e0 = e0 + 1;
			end
			if (e0 != 0) begin $display("ERROR: IDE: %0d of 512 bytes differ", e0); errors = errors + 1; end
			else $display("  IDE: sector 0 = the image (bytes 510 / 511 %h %h)", lg[p + 510], lg[p + 511]);
			// the written sector: in the image (wbuf) and read back
			p = at(8'h13);
			e0 = 0; c0 = 0;
			for (k = 0; k < 512; k = k + 1) begin
				n = ((k ^ (k >> 8) ^ 8'hA5) + (k >> 8)) & 255;
				if (wbuf[k] !== n) begin
					if (c0 < 6) $display("  written byte %0d: %h, expected %h, read back %h", k, wbuf[k], n[7:0], lg[p + k]);
					c0 = c0 + 1;
				end
				if (lg[p + k] !== n) e0 = e0 + 1;
			end
			$display("  IDE: WRITE SECTORS LBA 1: status at DRQ %h, after %h, at the read DRQ %h; %0d bytes differ in the image, %0d read back",
				lg[at(8'h12)], lg[at(8'h12) + 1], lg[at(8'h12) + 2], c0, e0);
			if (w_sec !== 32'd1 || c0 != 0 || e0 != 0 || lg[at(8'h12) + 1] != 8'h50) begin
				$display("ERROR: IDE write"); errors = errors + 1;
			end
			p = at(8'h14);
			$display("  IDE: slave status %h count %h, secondary channel status %h", lg[p], lg[p + 1], lg[p + 2]);
			if (lg[p] != 0 || lg[p + 1] != 0 || lg[p + 2] != 0) begin $display("ERROR: IDE absent devices"); errors = errors + 1; end
		end
		chk_fdd(8'h20, 3'd0, 18, 512, 18, 8'h21);
		if (trd) chk_fdd(8'h21, 3'd1, 16, 256, 9, 8'h22); else chk_fdd(8'h21, 3'd1, 9, 512, 9, 8'h22);
		if (at(8'h23) < 0) begin $display("ERROR: no timeout at the wrong rate"); errors = errors + 1; end
		else $display("  drive 0 at the 720 KB rate: no INTRQ / DRQ (timeout)");
		p = at(8'h24);
		if (p < 0) begin $display("ERROR: Read Address"); errors = errors + 1; end
		else begin
			$display("  Read Address: C %0d H %0d R %0d N %0d", lg[p], lg[p + 1], lg[p + 2], lg[p + 3]);
			if (lg[p] != 79 || lg[p + 3] != 2) begin $display("ERROR: Read Address ID"); errors = errors + 1; end
		end
		// the undriven bus read (FF: pull-ups D0..D7) and the accelerator vertical fill after the ALL_MODE restore
		p = at(8'h30);
		if (p < 0) begin $display("ERROR: no accelerator part"); errors = errors + 1; end
		else begin
			$display("  IN of #204E (code 00, nobody drives D): %h; vertical fill lines 20..27: %h %h %h %h %h %h %h %h",
				lg[p], lg[p + 1], lg[p + 2], lg[p + 3], lg[p + 4], lg[p + 5], lg[p + 6], lg[p + 7], lg[p + 8]);
			if (lg[p] !== 8'hFF) begin $display("ERROR: undriven data bus not FF"); errors = errors + 1; end
			for (k = 1; k <= 8; k = k + 1) if (lg[p + k] !== 8'h5A) begin
				$display("ERROR: vertical fill line %h: %h", 8'h1F + k, lg[p + k]); errors = errors + 1;
			end
		end
		$display("tb_storage: %0d errors (%0.2f ms)", errors, $realtime / 1.0e6);
		$finish;
		end
	end
endmodule
