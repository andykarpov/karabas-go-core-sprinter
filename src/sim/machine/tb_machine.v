// sp_machine from power-up: the MAX reset, the ACEX loader of the BIOS ROM (page 0x0C) on the 14 MHz clock of the
// MAX, the configuration stream (bits, MAME hash), the release of the ACEX, its start-up reset, and the CPU in the
// configured map. Memories: zero-delay models (the timing of sp_sram / sp_sdram is checked by tb_eq_acexm), so the
// same testbench runs in iverilog and Verilator (--timing).
// Defines: CFG_BITS_T (configuration clocks counted as the whole stream; the full EP1K30 stream is 473 720, the
// default here is the shortest with the whole MAME hash: 4096 = 512 bytes), RUN_US (simulated microseconds after the
// release), ROM_HEX (the BIOS image, one byte per line). +trace: every M1 of the CPU.
`timescale 1ns/1ps
`ifndef CFG_BITS_T
`define CFG_BITS_T 4096
`endif
`ifndef RUN_US
`define RUN_US 100
`endif
`ifndef ROM_HEX
`define ROM_HEX "build/rom.hex"
`endif
module tb_machine;
	reg clk = 0;
	reg epm = 1;                                      // the reset button
	integer errors = 0;
	always #5.952 clk = ~clk;                         // 84 MHz

	// ---- the machine
	wire [20:0] sr_a; wire [15:0] sr_do, sr_dt, sr_di; wire [1:0] sr_we, sr_oe;
	wire sd_clk, sd_cke, sd_cs, sd_ras, sd_cas, sd_we; wire [1:0] sd_ba, sd_dqm; wire [12:0] sd_a;
	wire [15:0] sd_dqo, sd_dqt, sd_dqi;
	wire [1:0] cfg_state, cfg_pers; wire [31:0] cfg_hash; wire [16:0] cfg_bytes; wire cfg_unknown;
	sp_machine #(.MIF_DCP("../../rtl/acex/mif/dcp.hex"), .MIF_AY("../../rtl/acex/mif/ay.hex"),
		.MIF_KBD("../../rtl/acex/mif/kbd_ini2.hex"), .CFG_BITS(`CFG_BITS_T), .SD_INIT(16'd16),
		.XHD_RES_ON_HSYNC(1)) m(.CLK(clk), .EPM_RES_N(epm), .PW_GOOD(1'b1),
		.SRAM_A(sr_a), .SRAM_D_O(sr_do), .SRAM_D_T(sr_dt), .SRAM_D_I(sr_di), .SRAM_WE_N(sr_we), .SRAM_OE_N(sr_oe),
		.LD_REQ(1'b0), .LD_A(21'd0), .LD_BE(2'b00), .LD_D(16'd0), .LD_ACK(),
		.SD_CLK(sd_clk), .SD_CKE(sd_cke), .SD_CS_N(sd_cs), .SD_RAS_N(sd_ras), .SD_CAS_N(sd_cas), .SD_WE_N(sd_we),
		.SD_BA(sd_ba), .SD_A(sd_a), .SD_DQM(sd_dqm), .SD_DQ_O(sd_dqo), .SD_DQ_T(sd_dqt), .SD_DQ_I(sd_dqi),
		.KBD_CC(1'b1), .KBD_DD(1'b1), .MOUSE_D(1'b1), .TAPE_IN(1'b1), .FDD_W(1'b1), .FDD_CH(1'b1), .TAPE_OUT(),
		.RXA_D(8'h00), .RXA_STB(1'b0), .RXA_RDY(), .RXB_D(8'h00), .RXB_STB(1'b0), .RXB_RDY(),
		.PA_I(8'hFF), .PA_O(), .PB_I(8'hFF), .PB_O(), .PER_D(16'hFFFF), .PER_OE(1'b0), .MD(), .HDD_C(), .FDD_C(),
		.HD_A(), .WR_PDOS(), .WG_WR_N(), .WG_RD_N(), .CMOS_DWR(), .CMOS_AS(), .CMOS_DRD(), .XHD_RES(), .XHD_WR(),
		.XHD_RD(), .XHD1_CS(), .XHD2_CS(), .FDD_1440(), .WR_COL(), .PAL_Q(), .VA(), .SINC_H(), .SINC_V(), .T320(),
		.DAC_DATA(), .DAC_WS(), .DAC_BCK(), .TURBO_LED(), .CFG_STATE(cfg_state), .CFG_HASH(cfg_hash),
		.CFG_BYTES(cfg_bytes), .CFG_PERS(cfg_pers), .CFG_UNKNOWN(cfg_unknown));

	// ---- SRAM: two byte chips, 512 K words each modelled (video RAM, ROM at 0x040000, fastram at 0x060000)
	reg [7:0] slo [0:524287], shi [0:524287];
	wire [18:0] sw = sr_a[18:0];
	assign sr_di[7:0]  = ~sr_dt[0] ? sr_do[7:0]  : ~sr_oe[0] ? slo[sw] : 8'hFF;
	assign sr_di[15:8] = ~sr_dt[8] ? sr_do[15:8] : ~sr_oe[1] ? shi[sw] : 8'hFF;
	always @(posedge sr_we[0]) slo[sw] <= sr_do[7:0];
	always @(posedge sr_we[1]) shi[sw] <= sr_do[15:8];

	// ---- SDRAM: CL 2, BL 1, bank 0 (4 MB): commands at the rise of SD_CLK, read data valid from the edge CL after
	reg [15:0] sdm [0:2097151];
	reg [11:0] row = 0;
	reg [16:0] p0 = 0, p1 = 0, pq = 0;                 // {valid, word}
	wire [20:0] sdi = {row, sd_a[8:0]};
	always @(posedge sd_clk) begin
		pq <= p1; p1 <= p0; p0 <= 17'd0;
		if (!sd_cs) case ({sd_ras, sd_cas, sd_we})
			3'b011: row <= sd_a[11:0];                    // ACTIVE
			3'b101: p0 <= {1'b1, sdm[sdi]};               // READ
			3'b100: begin                                 // WRITE
				if (!sd_dqm[0]) sdm[sdi][7:0]  <= sd_dqo[7:0];
				if (!sd_dqm[1]) sdm[sdi][15:8] <= sd_dqo[15:8];
			end
			default: ;
		endcase
	end
	assign sd_dqi = ~sd_dqt[0] ? sd_dqo : pq[16] ? pq[15:0] : 16'hFFFF;

	// ---- contents: the BIOS image in the ROM region, the rest 0
	reg [7:0] rom [0:262143];
	integer i;
	initial begin
		for (i = 0; i < 524288; i = i + 1) begin slo[i] = 8'h00; shi[i] = 8'h00; end
		for (i = 0; i < 2097152; i = i + 1) sdm[i] = 16'h0000;
		$readmemh(`ROM_HEX, rom);
		for (i = 0; i < 262144; i = i + 2) begin slo[19'h40000 + i / 2] = rom[i]; shi[19'h40000 + i / 2] = rom[i + 1]; end
		// +scroll: the configuration of the game in fastram, as its installer leaves it: the loader signature at FEF0
		// (the 16 bytes the loader compares, ROM 0x3009E) and SCROLL.ACX at 1000; the loader then takes the stream
		// from fastram (CSBR = F0)
		if ($test$plusargs("scroll")) begin
			for (i = 0; i < 59215; i = i + 1) acx[i] = 8'hxx;
			$readmemh("build/scroll.hex", acx);
			for (i = 0; i < 59215; i = i + 1) fast_wr(16'h1000 + i, acx[i]);
			for (i = 0; i < 16; i = i + 1) fast_wr(16'hFEF0 + i, rom[18'h3009E + i]);
		end
	end
	reg [7:0] acx [0:59214];
	task fast_wr(input [15:0] b, input [7:0] x); begin
		if (b[0]) shi[19'h60000 + b[15:1]] = x; else slo[19'h60000 + b[15:1]] = x;
	end endtask

	// ---- observation
	wire on = cfg_state == 2'd3;
	// per boot (release of the ACEX): hash, personality, first configured M1 {RA, A}, first OUTs
	integer nb = 0;
	reg [31:0] b_hash [0:3]; reg [1:0] b_pers [0:3]; reg b_unk [0:3]; reg [19:0] b_m1 [0:3]; integer b_nout [0:3];
	reg [23:0] b_out [0:31];                          // [boot * 8 + n]
	event rel_ev;
	// the MAX must leave the load mode at the release (the XACS pulse)
	always @(rel_ev) begin
		#(20000.0);
		if (m.max_clkzz_oe !== 1'b0) begin $display("  ERROR: the MAX is still in the load mode 20 us after the release"); errors = errors + 1; end
	end
	wire m1 = ~m.m1_n & ~m.mr_n & ~m.rd_n;
	reg  m1_p = 0; reg on_p = 0; reg res_p = 0;
	integer n_m1_u = 0, n_m1_c = 0, n_wr_cnf = 0, shown = 0, kb_next = 1024;
	realtime t_res = 0, t_first = 0, t_load = 0, t_on = 0, t_cfg_m1 = 0, t_z0 = 0, t_z1 = 0;
	integer n_z = 0;
	reg zp = 0;
	always @(posedge clk) begin
		m1_p <= m1;
		if (m1 && !m1_p) begin
			if (on) n_m1_c = n_m1_c + 1; else n_m1_u = n_m1_u + 1;
			if (n_m1_u == 1 && !on && t_first == 0) begin
				t_first = $realtime;
				$display("%0.1f us: first M1 at %h (unconfigured)", $realtime / 1000.0, m.a);
			end
			if (on && m.z_res_n && b_m1[nb - 1] == 20'hFFFFF) begin
				b_m1[nb - 1] = {m.x_ra, m.a};
				t_cfg_m1 = $realtime;
				$display("%0.1f us: first M1 in the configured map at %h, ROM page RA %h, CS_ROM %b", $realtime / 1000.0,
					m.a, m.x_ra, m.x_cs_rom);
			end
			if ((on && shown < 40) || $test$plusargs("trace")) begin
				shown = shown + (on ? 1 : 0);
				$display("  M1 %h: %h (%0s, RA %h)", m.a, m.d_bus, on ? "conf" : "unconf", on ? m.x_ra : 4'hx);
			end
		end
		// the 14 MHz clock while unconfigured: count edges of the CPU clock
		zp <= m.zclk;
		if (!on && m.zclk && !zp && m.z_res_n) begin
			if (n_z == 0) t_z0 = $realtime;
			n_z = n_z + 1; t_z1 = $realtime;
		end
		res_p <= m.max_res_n;
		if (m.max_res_n && !res_p) begin t_res = $realtime; $display("%0.1f us: MAX /RESET released", $realtime / 1000.0); end
		if (m.k_rise && m.max_clkzz_oe && cfg_state == 2'd1) begin
			n_wr_cnf = n_wr_cnf + 1;
			if (n_wr_cnf == 1) begin t_load = $realtime; $display("%0.1f us: first configuration clock", $realtime / 1000.0); end
		end
		if (cfg_bytes == kb_next) begin
			$display("%0.1f us: %0d bytes of the stream", $realtime / 1000.0, cfg_bytes);
			kb_next = kb_next * 2;
		end
		on_p <= on;
		if (!on && on_p) $display("%0.1f us: ACEX erased (state %0d)", $realtime / 1000.0, cfg_state);
		if (on && !on_p) begin
			t_on = $realtime;
			b_hash[nb] = cfg_hash; b_pers[nb] = cfg_pers; b_unk[nb] = cfg_unknown; b_m1[nb] = 20'hFFFFF; b_nout[nb] = 0;
			nb = nb + 1;
			->rel_ev;
			$display("%0.1f us: ACEX released: %0d clocks, %0d bytes, hash %h, personality %0d, unknown %b, CSBR %h MCR %h",
				$realtime / 1000.0, m.bits, cfg_bytes, cfg_hash, cfg_pers, cfg_unknown, m.csbr, m.mcr);
		end
	end
	// CPU writes in the configured map (BIOS activity): count, first few
	integer n_mw = 0, n_iow = 0;
	reg wr_p = 1;
	always @(posedge clk) begin
		wr_p <= m.wr_n;
		if (on && m.z_res_n && wr_p && !m.wr_n) begin
			if (!m.mr_n) n_mw = n_mw + 1; else if (!m.io_n) begin
				n_iow = n_iow + 1;
				if (b_nout[nb - 1] < 8) begin b_out[(nb - 1) * 8 + b_nout[nb - 1]] = {m.a, m.d_bus}; b_nout[nb - 1] = b_nout[nb - 1] + 1; end
				if (n_iow <= 24) $display("  OUT (%h), %h at %0.1f us", m.a, m.d_bus, $realtime / 1000.0);
			end
		end
	end

	// +reset: the button pressed 1 ms after the first release; +p2e: the control word of port 2E (1011/000) in the MA
	// latch at that moment (as an OUT to port 2E leaves it); either must give a second, identical boot
	integer k, j, again;
	initial begin
		again = $test$plusargs("reset") || $test$plusargs("p2e");
		wait (on);
		if (again) begin
			#(1000000.0);
			if ($test$plusargs("reset")) begin
				$display("%0.1f us: reset button", $realtime / 1000.0);
				epm = 0; #(3000.0); epm = 1;
			end else begin
				$display("%0.1f us: control word 2E in the MA latch", $realtime / 1000.0);
				m.ma_l[8:2] = 7'b1011000;
			end
			wait (!on); wait (on);
		end
		#(`RUN_US * 1000.0);
		for (k = 0; k < nb; k = k + 1) begin
			$display("  boot %0d: hash %h personality %0d unknown %b, first configured M1 RA %h A %h, %0d OUTs: %h %h %h %h %h %h %h %h",
				k, b_hash[k], b_pers[k], b_unk[k], b_m1[k][19:16], b_m1[k][15:0], b_nout[k], b_out[k * 8], b_out[k * 8 + 1],
				b_out[k * 8 + 2], b_out[k * 8 + 3], b_out[k * 8 + 4], b_out[k * 8 + 5], b_out[k * 8 + 6], b_out[k * 8 + 7]);
			if (b_m1[k] !== 20'h80000) begin $display("  ERROR: boot %0d does not start at 0000 of ROM page 8", k); errors = errors + 1; end
			if (`CFG_BITS_T >= 4096) begin
				if ($test$plusargs("scroll") ? (b_hash[k] !== 32'h3861cfa4 || b_pers[k] !== 2'd2) :
				    (b_hash[k] !== 32'h78eddfc6 || b_pers[k] !== 2'd0 || b_unk[k] !== 1'b0)) begin
					$display("  ERROR: boot %0d: wrong hash / personality", k); errors = errors + 1;
				end
			end
			if (k > 0) begin
				if (b_hash[k] !== b_hash[0] || b_nout[k] !== b_nout[0]) begin $display("  ERROR: boot %0d differs from boot 0", k); errors = errors + 1; end
				for (j = 0; j < 8; j = j + 1) if (j < b_nout[0] && b_out[k * 8 + j] !== b_out[j]) begin
					$display("  ERROR: boot %0d OUT %0d differs", k, j); errors = errors + 1; end
			end
		end
		if (nb != (again ? 2 : 1)) begin $display("  ERROR: %0d boots", nb); errors = errors + 1; end
		if (m.SRAM.WB_OVF !== 1'b0) begin $display("  ERROR: fastram write buffer overflow"); errors = errors + 1; end
		$display("tb_machine: CFG_BITS %0d, %0.1f us simulated", `CFG_BITS_T, $realtime / 1000.0);
		$display("  MAX /RESET released at %0.1f us; first M1 %0.1f us; first configuration clock %0.1f us; ACEX released %0.1f us",
			t_res / 1000.0, t_first / 1000.0, t_load / 1000.0, t_on / 1000.0);
		$display("  load: %0d clocks in %0.1f us = %0.3f us per byte -> the full stream (59 215 bytes): %0.1f ms",
			n_wr_cnf, (t_on - t_load) / 1000.0, (t_on - t_load) / 1000.0 / (n_wr_cnf / 8.0),
			(t_on - t_load) / 1e6 / (n_wr_cnf / 8.0) * 59215.0);
		$display("  CPU clock while unconfigured: %0d rises in %0.1f us = %0.3f MHz", n_z, (t_z1 - t_z0) / 1000.0,
			(n_z - 1) / ((t_z1 - t_z0) / 1000.0));
		$display("  M1 cycles: unconfigured %0d, configured %0d (first at %0.1f us); configured memory writes %0d, OUTs %0d",
			n_m1_u, n_m1_c, t_cfg_m1 / 1000.0, n_mw, n_iow);
		$display("tb_machine: %0d errors", errors);
		$finish;
	end
`ifndef STOP_US
`define STOP_US 4000000
`endif
	initial begin
		#(`STOP_US * 1000.0);
		$display("tb_machine: stopped at %0.1f us (STOP_US): state %0d, %0d clocks, %0d bytes, M1 %0d / %0d",
			$realtime / 1000.0, cfg_state, m.bits, cfg_bytes, n_m1_u, n_m1_c);
		$finish;
	end
	// progress every 200 us of simulated time
	integer n_vw = 0; reg [15:0] last_pc = 0; reg [3:0] last_ra = 0;
	`ifndef PROG_US
	`define PROG_US 200
	`endif
	initial forever begin
		#(`PROG_US * 1000.0);
		$display("  ... %0.1f us: state %0d, %0d bytes; last M1 %h (RA %h); video RAM writes %0d, memory writes %0d, OUTs %0d",
			$realtime / 1000.0, cfg_state, cfg_bytes, last_pc, last_ra, n_vw, n_mw, n_iow);
		$fflush;
	end
	// video RAM writes in the configured map
	reg vw_p = 1;
	always @(posedge clk) begin
		vw_p <= m.x_vwr == 4'hF;
		if (on && vw_p && m.x_vwr != 4'hF) begin   // a /WE pulse (low between a CE and the next CE_N)
			if (n_vw == 0) $display("%0.1f us: first video RAM write (VA %h)", $realtime / 1000.0, m.x_va);
			n_vw = n_vw + 1;
		end
		if (m1 && !m1_p) begin last_pc <= m.a; last_ra <= m.x_ra; end
	end
endmodule
