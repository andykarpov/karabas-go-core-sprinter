// Smoke test of the board glue around sp_machine (docs/minig.md 7): the ROM bytes of the MCU loader (kg_l2_load
// timing in the 28 MHz link clock: one byte per 7 clocks = 250 ns) through sp_ld_bridge into the SRAM while the
// machine is held in reset (as karabas_minig_top: until the first ROM load has ended and the bridge is empty), then
// the MAX releases /RESET, the CPU runs the ACEX loader of the BIOS 3.04 from what the bridge wrote, the stream is
// counted, the ACEX released, the BIOS starts at 0000 of ROM page 8. After the release: the video (sp_vout: 896
// WR_COL rises a SINC_H line, 896 lbuf writes a line, DE 720 clocks a doubled line, HSYNC 64), the keyboard
// (sp_kbd_tx: an AT frame decoded by the ACEX KBD module, the same byte to SIO A at the end of the frame), and in
// iverilog the sound path (sp_i2s_rx: a forced AY_CHS word must come out on both channels).
// Defines: CFG_BITS_T (default 256: a short stream, the hash is not complete), LOAD_ALL (load the whole 256 KB through
// the bridge, 65 ms of model time: Verilator; else only the loader page 0x30000..0x301FF, the rest preloaded),
// RUN_US (after the release), ROM_HEX.
`timescale 1ns/1ps
`ifndef CFG_BITS_T
`define CFG_BITS_T 256
`endif
`ifndef RUN_US
`define RUN_US 300
`endif
`ifndef ROM_HEX
`define ROM_HEX "build/rom.hex"
`endif
module tb_board;
	reg clk = 0, clk28 = 0;
	always #5.952 clk = ~clk;                         // 84 MHz
	always #17.856 clk28 = ~clk28;                    // 28 MHz = clk / 3, edges aligned
	integer errors = 0;

	// ---- the loader of the MCU (clk28): kind 0, byte address, data, ld_wr one clock
	reg ld_active = 0, ld_wr = 0;
	reg [17:0] ld_addr = 0;
	reg [7:0] ld_data = 0;
	reg [7:0] rom [0:262143];
`ifdef LOAD_ALL
	localparam integer L_BASE = 0, L_N = 262144;
`else
	localparam integer L_BASE = 18'h30000, L_N = 512;
`endif

	// ---- reset as in karabas_minig_top
	reg rom_loaded = 0, ld_act_p = 0, rst_bus = 1;
	always @(posedge clk28) begin
		ld_act_p <= ld_active;
		if (ld_act_p && !ld_active) rom_loaded <= 1'b1;
		rst_bus <= !rom_loaded | ld_active;
	end
	wire ldb_req, ldb_ack, ldb_busy, ldb_ovf; wire [20:0] ldb_a; wire [1:0] ldb_be; wire [15:0] ldb_d;
	sp_ld_bridge ldb(.CLK(clk), .LD_WR(ld_wr), .LD_ROM(ld_active), .LD_ADDR(ld_addr), .LD_DATA(ld_data),
		.REQ(ldb_req), .A(ldb_a), .BE(ldb_be), .D(ldb_d), .ACK(ldb_ack), .BUSY(ldb_busy), .OVF(ldb_ovf));
	reg [2:0] rst_sys = 3'b111;
	always @(posedge clk) rst_sys <= {rst_sys[1:0], rst_bus | ldb_busy};
	wire epm = !rst_sys[2];

	// ---- keyboard generator (short bits for the test; the ACEX frame logic is timed by the line clock only)
	reg ps2_wr = 0; reg [7:0] ps2_code = 0;
	wire kbd_cc, kbd_dd, rxa_stb, rxa_rdy; wire [7:0] rxa_d;
`ifdef KBD_REAL
	sp_kbd_tx ktx(                                    // the shipped timing: 80 us bits, 1 ms gaps
`else
	sp_kbd_tx #(.BIT_T(168), .GAP_T(84000)) ktx(
`endif.CLK(clk), .RESET(1'b0), .PS2_WR(ps2_wr), .PS2_CODE(ps2_code),
		.KBD_CC(kbd_cc), .KBD_DD(kbd_dd), .RX_D(rxa_d), .RX_STB(rxa_stb), .RX_RDY(rxa_rdy), .OVF());

	// ---- the machine
	wire [20:0] sr_a; wire [15:0] sr_do, sr_dt, sr_di; wire [1:0] sr_we, sr_oe;
	wire sd_clk, sd_cke, sd_cs, sd_ras, sd_cas, sd_we; wire [1:0] sd_ba, sd_dqm; wire [12:0] sd_a;
	wire [15:0] sd_dqo, sd_dqt, sd_dqi;
	wire [1:0] cfg_state, cfg_pers; wire [31:0] cfg_hash; wire [16:0] cfg_bytes; wire cfg_unknown;
	wire wr_col, sinc_h, sinc_v, dac_data, dac_ws, dac_bck; wire [31:0] pal_q;
	sp_machine #(.MIF_DCP("../../rtl/acex/mif/dcp.hex"), .MIF_AY("../../rtl/acex/mif/ay.hex"),
		.MIF_KBD("../../rtl/acex/mif/kbd_ini2.hex"), .CFG_BITS(`CFG_BITS_T), .SD_INIT(16'd16),
		.XHD_RES_ON_HSYNC(1)) m(.CLK(clk), .EPM_RES_N(epm), .PW_GOOD(1'b1),
		.SRAM_A(sr_a), .SRAM_D_O(sr_do), .SRAM_D_T(sr_dt), .SRAM_D_I(sr_di), .SRAM_WE_N(sr_we), .SRAM_OE_N(sr_oe),
		.LD_REQ(ldb_req), .LD_A(ldb_a), .LD_BE(ldb_be), .LD_D(ldb_d), .LD_ACK(ldb_ack),
		.SD_CLK(sd_clk), .SD_CKE(sd_cke), .SD_CS_N(sd_cs), .SD_RAS_N(sd_ras), .SD_CAS_N(sd_cas), .SD_WE_N(sd_we),
		.SD_BA(sd_ba), .SD_A(sd_a), .SD_DQM(sd_dqm), .SD_DQ_O(sd_dqo), .SD_DQ_T(sd_dqt), .SD_DQ_I(sd_dqi),
		.KBD_CC(kbd_cc), .KBD_DD(kbd_dd), .MOUSE_D(1'b1), .TAPE_IN(1'b1), .FDD_W(1'b1), .FDD_CH(1'b1), .TAPE_OUT(),
		.RXA_D(rxa_d), .RXA_STB(rxa_stb), .RXA_RDY(rxa_rdy), .RXB_D(8'h00), .RXB_STB(1'b0), .RXB_RDY(),
		.PA_I(8'hFF), .PA_O(), .PB_I(8'hFF), .PB_O(), .PER_D(16'hFFFF), .PER_OE(1'b0), .MD(), .HDD_C(), .FDD_C(),
		.HD_A(), .WR_PDOS(), .WG_WR_N(), .WG_RD_N(), .CMOS_DWR(), .CMOS_AS(), .CMOS_DRD(), .XHD_RES(), .XHD_WR(),
		.XHD_RD(), .XHD1_CS(), .XHD2_CS(), .FDD_1440(), .WR_COL(wr_col), .PAL_Q(pal_q), .VA(), .SINC_H(sinc_h),
		.SINC_V(sinc_v), .T320(), .DAC_DATA(dac_data), .DAC_WS(dac_ws), .DAC_BCK(dac_bck), .TURBO_LED(),
		.CFG_STATE(cfg_state), .CFG_HASH(cfg_hash), .CFG_BYTES(cfg_bytes), .CFG_PERS(cfg_pers),
		.CFG_UNKNOWN(cfg_unknown));
	wire on = cfg_state == 2'd3;

	// ---- video and sound of the board
	wire [7:0] vr, vg, vb; wire vhs, vvs, vde;
	sp_vout #(.V0(9'd2)) vout(.CLK(clk), .WR_COL(wr_col), .PAL_Q(pal_q), .SINC_H(sinc_h), .SINC_V(sinc_v), .ON(on), .CLK28(clk28),
		.R(vr), .G(vg), .B(vb), .HS(vhs), .VS(vvs), .DE(vde));
	wire [15:0] snd_l, snd_r;
	sp_i2s_rx i2s(.CLK(clk), .BCK(dac_bck), .WS(dac_ws), .DATA(dac_data), .LEFT(snd_l), .RIGHT(snd_r));

	// ---- SRAM / SDRAM: zero-delay models (as tb_machine)
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

	// ---- contents: the ROM region empty (FF) where the loader writes, the BIOS elsewhere
	integer i;
	initial begin
		for (i = 0; i < 524288; i = i + 1) begin slo[i] = 8'h00; shi[i] = 8'h00; end
		for (i = 0; i < 2097152; i = i + 1) sdm[i] = 16'h0000;
		$readmemh(`ROM_HEX, rom);
		for (i = 0; i < 262144; i = i + 2) begin
			slo[19'h40000 + i / 2] = (i >= L_BASE && i < L_BASE + L_N) ? 8'hFF : rom[i];
			shi[19'h40000 + i / 2] = (i + 1 >= L_BASE && i + 1 < L_BASE + L_N) ? 8'hFF : rom[i + 1];
		end
	end

	// ---- the load (as kg_l2_load: START ... DATA bytes ... END), from 2 us
	realtime t_ld0 = 0, t_ld1 = 0;
	initial begin
		#(2000.0);
		@(posedge clk28); ld_active <= 1'b1;
		t_ld0 = $realtime;
		for (i = 0; i < L_N; i = i + 1) begin
			repeat (6) @(posedge clk28);
			ld_addr <= L_BASE + i; ld_data <= rom[L_BASE + i]; ld_wr <= 1'b1;
			@(posedge clk28); ld_wr <= 1'b0;
		end
		repeat (8) @(posedge clk28); ld_active <= 1'b0;
		t_ld1 = $realtime;
		$display("%0.1f us: ROM load ended (%0d bytes from %h)", $realtime / 1000.0, L_N, L_BASE);
	end

	// ---- observation: the loaded bytes in the SRAM at the release of the reset, the first M1
	reg epm_p = 0; realtime t_epm = 0;
	integer n_bad = 0, first_m1 = 1;
	wire m1 = ~m.m1_n & ~m.mr_n & ~m.rd_n;
	reg m1_p = 0, on_p = 0, cfg_m1 = 0;
	always @(posedge clk) begin
		epm_p <= epm;
		if (epm && !epm_p) begin
			t_epm = $realtime;
			if (ldb_busy) begin $display("  ERROR: reset released with the bridge busy"); errors = errors + 1; end
			for (i = L_BASE; i < L_BASE + L_N; i = i + 1)
				if ((i[0] ? shi[19'h40000 + i / 2] : slo[19'h40000 + i / 2]) !== rom[i]) n_bad = n_bad + 1;
			$display("%0.1f us: machine reset released (EPM_RES_N); %0d of %0d loaded bytes wrong in the SRAM",
				$realtime / 1000.0, n_bad, L_N);
			if (n_bad != 0) errors = errors + 1;
		end
		m1_p <= m1;
		if (m1 && !m1_p && first_m1 && !on) begin
			first_m1 = 0;
			$display("%0.1f us: first M1 at %h: %h (ROM 0x30000 = %h)", $realtime / 1000.0, m.a, m.d_bus, rom[18'h30000]);
			if (m.a !== 16'h0000 || m.d_bus !== rom[18'h30000]) begin $display("  ERROR: first fetch"); errors = errors + 1; end
		end
		on_p <= on;
		if (on && !on_p) $display("%0.1f us: ACEX released: %0d bytes, hash %h", $realtime / 1000.0, cfg_bytes, cfg_hash);
		if (m1 && !m1_p && on && m.z_res_n && !cfg_m1) begin
			cfg_m1 = 1;
			$display("%0.1f us: first M1 in the configured map at %h, RA %h", $realtime / 1000.0, m.a, m.x_ra);
			if ({m.x_ra, m.a} !== 20'h80000) begin $display("  ERROR: not 0000 of ROM page 8"); errors = errors + 1; end
		end
	end

	// ---- video: WR_COL rises a SINC_H line (MAX syncs run from power-up), lbuf writes a line, DE / HS a doubled line
	reg wc_p = 0, sh_p = 0; integer n_wc = 0, n_lines = 0, n_wc_bad = 0, n_wr = 0, n_wr_bad = 0;
	always @(posedge clk) begin
		wc_p <= wr_col; sh_p <= sinc_h;
		if (wr_col && !wc_p) n_wc = n_wc + 1;
		if (vout.px && (vout.wx < 896)) n_wr = n_wr + 1;
		if (sinc_h && !sh_p) begin
			if (on && n_lines > 0) begin
				if (n_wc != 896) begin n_wc_bad = n_wc_bad + 1; if (n_wc_bad <= 3) $display("  line: %0d WR_COL rises", n_wc); end
				if (n_wr != 896) begin n_wr_bad = n_wr_bad + 1; if (n_wr_bad <= 3) $display("  line: %0d dots written", n_wr); end
			end
			if (on) n_lines = n_lines + 1;
			n_wc = 0; n_wr = 0;
		end
	end
	reg hs_p = 0; integer n_de = 0, n_hs = 0, n_ol = 0, n_de_bad = 0, n_hs_bad = 0, n_de_lines = 0, n_clk_line = 0;
	always @(posedge clk28) begin
		hs_p <= vhs;
		if (vde) n_de = n_de + 1;
		if (vhs) n_hs = n_hs + 1;
		n_clk_line = n_clk_line + 1;
		if (vhs && !hs_p) begin
			if (n_ol > 2) begin
				if (n_de != 0 && n_de != 720) begin n_de_bad = n_de_bad + 1; if (n_de_bad <= 3) $display("  output line: DE %0d", n_de); end
				if (n_de == 720) n_de_lines = n_de_lines + 1;
				if (n_hs != 64 || n_clk_line != 896) begin n_hs_bad = n_hs_bad + 1;
					if (n_hs_bad <= 3) $display("  output line: HS %0d, %0d clocks", n_hs, n_clk_line); end
			end
			n_ol = n_ol + 1; n_de = 0; n_hs = 0; n_clk_line = 0;
		end
	end

	// ---- keyboard: an AT frame 20 us after the release; the ACEX KBD shift register must hold it at the SIO strobe
	// KBD_REAL: make + break of A (1C, F0 1C) with the shipped timing; KB_OFF of the ACEX (the break flag) must be
	// set by the frame F0 and cleared by the next one, each byte handled before the next frame comes
	integer n_kbd = 0;
	reg [7:0] k_exp [0:2];
	initial begin k_exp[0] = 8'h1C; k_exp[1] = 8'hF0; k_exp[2] = 8'h1C; end
`ifdef KBD_REAL
	localparam integer N_KBD = 3;
`else
	localparam integer N_KBD = 1;
`endif
	always @(posedge clk) if (rxa_stb) begin
		$display("%0.1f us: SIO A byte %h, ACEX KB_D %b, KB_OFF %b", $realtime / 1000.0, rxa_d, m.ACEX.KEYS.d_q,
			m.ACEX.KEYS.off_q);
		if (rxa_d !== k_exp[n_kbd] || m.ACEX.KEYS.d_q !== {1'b1, ~^k_exp[n_kbd], k_exp[n_kbd], 1'b0} ||
		    m.ACEX.KEYS.off_q !== (n_kbd == 2)) begin
			$display("  ERROR: keyboard frame"); errors = errors + 1; end
		n_kbd = n_kbd + 1;
	end
	reg off_p = 0;
	always @(posedge clk) begin
		off_p <= m.ACEX.KEYS.off_q;
		if (on && off_p != m.ACEX.KEYS.off_q) $display("%0.1f us: ACEX KB_OFF -> %b", $realtime / 1000.0, m.ACEX.KEYS.off_q);
	end

	initial begin
		wait (on);
		#(20000.0);
		@(posedge clk28); ps2_code <= 8'h1C; ps2_wr <= 1'b1; @(posedge clk28); ps2_wr <= 1'b0;
`ifdef KBD_REAL
		repeat (10) @(posedge clk28); ps2_code <= 8'hF0; ps2_wr <= 1'b1; @(posedge clk28); ps2_wr <= 1'b0;
		repeat (10) @(posedge clk28); ps2_code <= 8'h1C; ps2_wr <= 1'b1; @(posedge clk28); ps2_wr <= 1'b0;
`endif
`ifndef VERILATOR
		// sound: a word in AY_CHS must come out of sp_i2s_rx on both channels (MSB first, framing as the TDA1543)
		force m.ACEX.ay_chs = 16'hA5C3;
		#(30000.0);
		$display("%0.1f us: I2S with AY_CHS = A5C3: left %h right %h", $realtime / 1000.0, snd_l, snd_r);
		if (snd_l !== 16'hA5C3 || snd_r !== 16'hA5C3) begin $display("  ERROR: I2S"); errors = errors + 1; end
		force m.ACEX.ay_chs = 16'h4F81;
		#(30000.0);
		$display("%0.1f us: I2S with AY_CHS = 4F81: left %h right %h", $realtime / 1000.0, snd_l, snd_r);
		if (snd_l !== 16'h4F81 || snd_r !== 16'h4F81) begin $display("  ERROR: I2S"); errors = errors + 1; end
		release m.ACEX.ay_chs;
`endif
	end

	initial begin
		wait (on);
		#(`RUN_US * 1000.0);
		if (ldb_ovf) begin $display("  ERROR: loader bridge overflow"); errors = errors + 1; end
		if (!cfg_m1) begin $display("  ERROR: no configured M1"); errors = errors + 1; end
		if (n_lines < 3 || n_wc_bad || n_wr_bad) begin
			$display("  ERROR: video write side: %0d lines, %0d / %0d bad", n_lines, n_wc_bad, n_wr_bad); errors = errors + 1; end
		if (n_de_bad || n_hs_bad || n_ol < 4) begin
			$display("  ERROR: video read side: %0d lines, %0d / %0d bad", n_ol, n_de_bad, n_hs_bad); errors = errors + 1; end
		if (n_kbd != N_KBD) begin $display("  ERROR: %0d keyboard bytes", n_kbd); errors = errors + 1; end
		$display("tb_board: load %0.1f us (%0.1f .. %0.1f), reset released %0.1f us; %0d lines of 896 dots, %0d output lines (%0d with DE 720)",
			(t_ld1 - t_ld0) / 1000.0, t_ld0 / 1000.0, t_ld1 / 1000.0, t_epm / 1000.0, n_lines, n_ol, n_de_lines);
		$display("tb_board: %0d errors", errors);
		$finish;
	end
	initial begin #(400000000.0); $display("tb_board: timeout"); $finish; end
endmodule
