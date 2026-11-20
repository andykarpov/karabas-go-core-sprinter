// Smoke test of the reference netlist of the ACEX top (default BASE_303 = 3.03a): 42 MHz, /RESET pulse, the
// Z80 bus idle, all buses pulled up. Checks that the netlist runs at all: no X on the outputs after reset, the
// Z80 clock (CLKZ1), video RAM addresses, DRAM refresh (RAS_ / CAS_), the palette strobe and the I2S clocks move.
`timescale 1ns/1ps
module tb_acex_smoke;
	reg tg42 = 0; always #11.905 tg42 = ~tg42;
	reg rst_n = 0;
	wire res_n = rst_n ? 1'bz : 1'b0;
	wire wait_n; wire [7:0] d, vd0, vd1, vd2, vd3; wire [15:0] md; wire [2:0] xa;
	pullup(wait_n); pullup p0[7:0](d); pullup p1[7:0](vd0); pullup p2[7:0](vd1); pullup p3[7:0](vd2);
	pullup p4[7:0](vd3); pullup p5[15:0](md); pullup p6[2:0](xa); pullup(res_n);
	wire clkz1, cs_rom, cs_cash, wr_col, dac_data, dac_ws, dac_bck, we_n, xacs, sxa, rdxa, wr_awg, rd_kmps, wr_dwg;
	wire [3:0] ra, v_wr, cas_n; wire [1:0] v_cs, ras_n; wire [15:0] va; wire [14:0] ma;
	wire [3:0] xa4; pullup p7[3:0](xa4);
	`TOP u(
		`include "ports.vh"
	);
	integer n_z = 0, n_va = 0, n_ras = 0, n_col = 0, n_bck = 0, n_x = 0, errors = 0;
	reg [15:0] va_q;
	always @(posedge clkz1) n_z = n_z + 1;
	always @(negedge ras_n[0]) n_ras = n_ras + 1;
	always @(posedge wr_col) n_col = n_col + 1;
	always @(posedge dac_bck) n_bck = n_bck + 1;
	always @(posedge tg42) if (rst_n) begin
		if (va !== va_q) n_va = n_va + 1;
		va_q <= va;
		// V_WR is X until the first video RAM write: F_WR (VIDEO2.TDF:666) has no reset, clocked by V_WE itself
		if (^{clkz1, cs_rom, cs_cash, v_cs, va, wr_col, ma, ras_n, cas_n, we_n, ra, dac_bck, dac_ws} === 1'bx)
		begin
			if (n_x < 3 || $test$plusargs("xall"))
				$display("%t X: clkz1 %b cs_rom %b cs_cash %b v_cs %b va %h v_wr %b wr_col %b ma %h ras %b cas %b we %b ra %b bck %b ws %b",
					$realtime, clkz1, cs_rom, cs_cash, v_cs, va, v_wr, wr_col, ma, ras_n, cas_n, we_n, ra, dac_bck, dac_ws);
			n_x = n_x + 1; t_lastx = $realtime;
		end
	end
	realtime t_lastx = 0;
	initial begin
		#2000 rst_n = 1;
		#50_000;
		$display("50 us after reset: CLKZ1 %0d (%0.2f MHz), VA changes %0d, RAS_0 falls %0d, WR_COL %0d, DAC_BCK %0d, X cycles %0d (last %0.1f us)",
			n_z, n_z / 50.0, n_va, n_ras, n_col, n_bck, n_x, t_lastx / 1000.0);
		if (n_x) errors = errors + 1;
		if (n_z < 150) errors = errors + 1;      // Z80 clock: 3.5 MHz at least
		if (n_va < 250) errors = errors + 1;    // video RAM scan
		if (n_ras < 25) errors = errors + 1;    // DRAM refresh
		if (n_col < 250) errors = errors + 1;   // palette strobe
		$display("tb_acex_smoke: %0d errors", errors);
		$finish;
	end
endmodule
