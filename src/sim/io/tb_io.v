// tb_io: the board I/O of sp_machine through the CPU and the ACEX (docs/PLAN.md Ф4): the BIOS image (its loader pours
// a short configuration stream, CFG_BITS_T) with io.asm in ROM page 8, as tb_storage:
// - tape in: TAPE_IN (the XA multiplexer, SXA = 0) read on port #FE bit 6, 0 and then 1;
// - tape out: OUT (#FE) bit 3 -> XA2 latched by WR_AWG -> TAPE_OUT, 1 and then 0;
// - MIDI: MIDI_TX = bit 2 of AY register 14 (#FFFD / #BFFD, codes 90 / 91): idle 1, R14 = FB -> 0, a write of R7
//   leaves it, R14 = 04 -> 1, a write of R13 with bit 2 = 0 leaves it.
// The program logs through OUT (#01) (bytes) and OUT (#02) (markers). Runs in Verilator (--timing) or iverilog.
`timescale 1ns/1ps
`ifndef CFG_BITS_T
`define CFG_BITS_T 256
`endif
`ifndef STOP_MS
`define STOP_MS 20
`endif
module tb_io;
	reg clk = 0;
	always #5.952 clk = ~clk;                         // 84 MHz
	integer errors = 0;
	reg tape_in = 1'b0;

	// ---- the machine
	wire [20:0] sr_a; wire [15:0] sr_do, sr_dt, sr_di; wire [1:0] sr_we, sr_oe;
	wire sd_clk, sd_cke, sd_cs, sd_ras, sd_cas, sd_we; wire [1:0] sd_ba, sd_dqm; wire [12:0] sd_a;
	wire [15:0] sd_dqo, sd_dqt, sd_dqi;
	wire [1:0] cfg_state;
	wire tape_out, midi_tx;
	sp_machine #(.MIF_DCP("../../rtl/acex/mif/dcp.hex"), .MIF_AY("../../rtl/acex/mif/ay.hex"),
		.MIF_KBD("../../rtl/acex/mif/kbd_ini2.hex"), .CFG_BITS(`CFG_BITS_T), .SD_INIT(16'd16),
		.XHD_RES_ON_HSYNC(1)) m(.CLK(clk), .EPM_RES_N(1'b1), .PW_GOOD(1'b1),
		.SRAM_A(sr_a), .SRAM_D_O(sr_do), .SRAM_D_T(sr_dt), .SRAM_D_I(sr_di), .SRAM_WE_N(sr_we), .SRAM_OE_N(sr_oe),
		.LD_REQ(1'b0), .LD_A(21'd0), .LD_BE(2'b00), .LD_D(16'd0), .LD_ACK(),
		.SD_CLK(sd_clk), .SD_CKE(sd_cke), .SD_CS_N(sd_cs), .SD_RAS_N(sd_ras), .SD_CAS_N(sd_cas), .SD_WE_N(sd_we),
		.SD_BA(sd_ba), .SD_A(sd_a), .SD_DQM(sd_dqm), .SD_DQ_O(sd_dqo), .SD_DQ_T(sd_dqt), .SD_DQ_I(sd_dqi),
		.KBD_CC(1'b1), .KBD_DD(1'b1), .MOUSE_D(1'b1), .TAPE_IN(tape_in), .FDD_W(1'b1), .FDD_CH(1'b1),
		.TAPE_OUT(tape_out), .MIDI_TX(midi_tx),
		.RXA_D(8'h00), .RXA_STB(1'b0), .RXA_RDY(), .RXB_D(8'h00), .RXB_STB(1'b0), .RXB_RDY(),
		.PA_I(8'hFF), .PA_O(), .PB_I(8'hFF), .PB_O(), .PER_D(16'hFFFF), .PER_OE(1'b0), .MD(), .HDD_C(),
		.FDD_C(), .HD_A(), .WG_A(), .RD_KMPS(), .IORQ_N(), .CPU_RES_N(),
		.WR_PDOS(), .WG_WR_N(), .WG_RD_N(), .CMOS_DWR(), .CMOS_AS(),
		.CMOS_DRD(), .XHD_RES(), .XHD_WR(), .XHD_RD(), .XHD1_CS(),
		.XHD2_CS(), .FDD_1440(), .WR_COL(), .PAL_Q(), .VA(), .SINC_H(), .SINC_V(), .T320(),
		.DAC_DATA(), .DAC_WS(), .DAC_BCK(), .TURBO_LED(), .CFG_STATE(cfg_state), .CFG_HASH(),
		.CFG_BYTES(), .CFG_PERS(), .CFG_UNKNOWN());

	// ---- SRAM, SDRAM: as tb_storage
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
		$readmemh("build/io.hex", prg);
		for (i = 0; i < 16384; i = i + 1) rom[18'h20000 + i] = prg[i];
		for (i = 0; i < 262144; i = i + 2) begin slo[19'h40000 + i / 2] = rom[i]; shi[19'h40000 + i / 2] = rom[i + 1]; end
	end

	// ---- the log of the program, the checks at the markers
	reg [7:0] lg [0:255]; integer nl = 0;
	reg [7:0] last_mk = 8'h00; integer nm = 0;
	reg wr_p = 1;
	wire on = cfg_state == 2'd3;
	task check(input ok, input [8*48-1:0] what);
		if (!ok) begin $display("ERROR: %0s", what); errors = errors + 1; end
	endtask
	always @(posedge clk) begin
		wr_p <= m.wr_n;
		if (on && wr_p && !m.wr_n && !m.io_n) begin
			if (m.a[7:0] == 8'h01) begin if (nl < 256) lg[nl] = m.d_bus; nl = nl + 1; end
			if (m.a[7:0] == 8'h02) begin
				last_mk = m.d_bus; nm = nm + 1;
				$display("%0.1f us: marker %h (%0d bytes logged), TAPE_OUT %b, MIDI_TX %b", $realtime / 1000.0, m.d_bus, nl, tape_out,
					midi_tx);
				case (m.d_bus)
					8'h20: tape_in <= 1'b1;
					8'h21: begin
						$display("  port #FE: %h with TAPE_IN 0, %h with TAPE_IN 1", lg[0], lg[1]);
						check(nl == 2 && lg[0][6] == 1'b0 && lg[1][6] == 1'b1, "TAPE_IN on #FE bit 6");
					end
					8'h22: check(tape_out === 1'b1, "TAPE_OUT after OUT (#FE),#08");
					8'h23: begin
						check(tape_out === 1'b0, "TAPE_OUT after OUT (#FE),#00");
						check(midi_tx === 1'b1, "MIDI_TX idle");
					end
					8'h30: check(midi_tx === 1'b0, "MIDI_TX after R14 = FB");
					8'h31: check(midi_tx === 1'b0, "MIDI_TX after a write of R7");
					8'h32: check(midi_tx === 1'b1, "MIDI_TX after R14 = 04");
					8'h33: check(midi_tx === 1'b1, "MIDI_TX after a write of R13");
					default: ;
				endcase
			end
		end
	end
	reg fin = 0;
	always @(posedge clk) if (last_mk == 8'hff) fin <= 1;
	initial begin #(`STOP_MS * 1.0e6); fin = 1; end
	initial begin
		wait (fin);
		#(100.0);
		if (last_mk != 8'hff) begin $display("ERROR: the program did not end (%0d markers)", nm); errors = errors + 1; end
		$display("tb_io: %0d errors (%0.2f ms)", errors, $realtime / 1.0e6);
		$finish;
	end
endmodule
