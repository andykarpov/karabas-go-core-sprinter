// sp_max against the SP2_MAX netlist (2.18 of Peters Plus, MaxPlus2/MAX): the divider, line counter and syncs over
// ~30 lines (+frame: two frames, minutes), control words on HDD_C / FDD_C with the 10K_CLK strobe (WD1793, CMOS, IDE,
// 312 / 320 lines, HDD1 / HDD2, soft reset, 720 / 1.44), the configuration load (WR_CNF, D0, XACS).
// Test variant on both sides: XHD_RES latched on SINC_H, not SINC_V, so /RESET ends after a line (run_eq.sh max).
`timescale 1ns/1ps
`include "eq_cmp.vh"
module tb_eq_max;
	reg clk = 0; always #5.952 clk = ~clk;            // 84 MHz
	reg clk42 = 0; always @(posedge clk) clk42 <= ~clk42;
	wire ce = ~clk42, ce_n = clk42;                   // our enables for the edge at which clk42 rises / falls
	reg cmp_on = 0, epm_res = 0, pw_good = 1, xacs = 1, wr_cnf = 0, d0 = 0;
	reg [3:0] hdd_c = 0; reg [2:0] fdd_c = 0;
	integer errors = 0, weak = 0;

	wire clkzz, s1, s2, confx;
	pullup(clkzz); pullup(confx);
	wire clk14_r, aud_r, sh_r, sv_r, s_r, kclk_r, kd0_r, pdos_r, wgwr_r, wgrd_r, cdwr_r, cas_r, cdrd_r, hddir_r, hdcs_r,
		xres_r, xwr_r, xrd_r; wire [2:1] x1_r, x2_r;
	SP2_MAX ref(.TG42_IN(clk42), .CLKZZ(clkzz), .CLK14(clk14_r), .AUD(aud_r), .CMOS_DRD(cdrd_r), .CMOS_AS(cas_r),
		.CMOS_DWR(cdwr_r), .WR_PDOS(pdos_r), .WD(1'b0), .WSTB(1'b0), .SR(1'b0), .SL(1'b0), .RSTB(1'b0), .TR43(1'b0),
		.RDAT(1'b1), .\/WG_WR (wgwr_r), .\/WG_RD (wgrd_r), .STE(1'b0), .XA(3'b111), .XACS(xacs), .SINC_1(s1),
		.SINC_2(s2), .HDD_C(hdd_c), .FDD_C(fdd_c), .HD_DIR(hddir_r), .HD_CS(hdcs_r), .\/CONF_X (confx),
		.\10K_CLK (kclk_r), .WR_CNF(wr_cnf), .\10K_D0 (kd0_r), .D0(d0), .VGA_IN(1'b0), .SINC_V(sv_r), .SINC_H(sh_r),
		.SINC(s_r), .SINC_IN(1'b0), .XHD_RES(xres_r), .XHD_WR(xwr_r), .XHD_RD(xrd_r), .XHD1_CS(x1_r), .XHD2_CS(x2_r),
		.XHR_RDY(1'b1), .EPM_RES(epm_res), .PW_GOOD(pw_good), .GND65(1'b0), .GND33(1'b0));
	wire clk14_o, zz_o, zz_oe, aud_o, sh_o, sv_o, s_o, s1_o, s2_o, confx_o, kclk_o, kd0_o, pdos_o, wgwr_o, wgrd_o,
		cdwr_o, cas_o, cdrd_o, hddir_o, hdcs_o, xres_o, xwr_o, xrd_o, t320_o; wire [2:1] x1_o, x2_o;
	sp_max #(.XHD_RES_ON_HSYNC(1)) dut(.CLK(clk), .CE(ce), .CE_N(ce_n), .EPM_RES(epm_res), .PW_GOOD(pw_good), .HDD_C(hdd_c), .FDD_C(fdd_c),
		.XACS(xacs), .WR_CNF(wr_cnf), .D0(d0), .CLK14(clk14_o), .CLKZZ_O(zz_o), .CLKZZ_OE(zz_oe), .AUD(aud_o),
		.SINC_H(sh_o), .SINC_V(sv_o), .SINC(s_o), .SINC_1(s1_o), .SINC_2(s2_o), .CONF_X_N(confx_o), .K_CLK(kclk_o),
		.K_D0(kd0_o), .WR_PDOS(pdos_o), .WG_WR_N(wgwr_o), .WG_RD_N(wgrd_o), .CMOS_DWR(cdwr_o), .CMOS_AS(cas_o),
		.CMOS_DRD(cdrd_o), .HD_DIR(hddir_o), .HD_CS(hdcs_o), .XHD_RES(xres_o), .XHD_WR(xwr_o), .XHD_RD(xrd_o),
		.XHD1_CS(x1_o), .XHD2_CS(x2_o), .T320_O(t320_o));
	wire zz_ours = zz_oe ? zz_o : 1'b1;
	wire confx_ours = confx_o ? 1'b1 : 1'b0;

	`EQ_CMP(clk14, 1, clk14_o, clk14_r)
	`EQ_CMP(clkzz, 1, zz_ours, clkzz)
	`EQ_CMP(aud, 1, aud_o, aud_r)
	`EQ_CMP(syncs, 3, ({sh_o, sv_o, s_o}), ({sh_r, sv_r, s_r}))
	`EQ_CMP(sinc12, 2, ({s1_o, s2_o}), ({s1, s2}))
	`EQ_CMP(conf_x, 1, confx_ours, confx)
	`EQ_CMP(k10, 2, ({kclk_o, kd0_o}), ({kclk_r, kd0_r}))
	`EQ_CMP(wg, 3, ({pdos_o, wgwr_o, wgrd_o}), ({pdos_r, wgwr_r, wgrd_r}))
	`EQ_CMP(cmos, 3, ({cdwr_o, cas_o, cdrd_o}), ({cdwr_r, cas_r, cdrd_r}))
	`EQ_CMP(ide, 3, ({hddir_o, xwr_o, xrd_o}), ({hddir_r, xwr_r, xrd_r}))
	`EQ_CMP(hd_cs, 4, ({x1_o, x2_o}), ({x1_r, x2_r}))
	`EQ_CMP(xhd_res, 1, xres_o, xres_r)

	// Control words change on the rising edge of clk42, one bit per 42 MHz clock: in the zero-delay netlist a word
	// that changes several bits at once passes through intermediate codes in delta time, and the decodes of the RS
	// latches (S720, S312, SHDD1 ...) catch them (0011/000 -> 0000/000 via 0001/000 clears 10K_D0). Our module has no
	// such glitches; held for a whole clock, an intermediate word is a real command for both sides.
	task word(input [3:0] h, input [2:0] f, input integer len); integer b; reg [6:0] cur, nxt; begin
		nxt = {h, f};
		for (b = 0; b < 7; b = b + 1) begin
			cur = {hdd_c, fdd_c};
			if (cur[b] !== nxt[b]) begin
				@(posedge clk); while (clk42) @(posedge clk);
				if (b < 3) fdd_c[b] <= f[b]; else hdd_c[b - 3] <= h[b - 3];
				repeat (2) @(posedge clk);
			end
		end
		repeat (2 * len) @(posedge clk);
	end endtask
	// the code first, then the strobe bit: HDD_C0 for the IDE codes (X101), FDD_C2 for the others
	task strobe(input [3:0] h, input [1:0] f); begin
		word({h[3:1], 1'b0}, {1'b0, f}, 4);
		if (h[2:0] == 3'b101) word(h, {1'b0, f}, 6); else word(h, {1'b1, f}, 6);
		word({h[3:1], 1'b0}, {1'b0, f}, 4); word(4'b0000, 3'b000, 6);
	end endtask

	integer i;
	initial begin
		repeat (400) @(posedge clk); epm_res = 1;
		// the ACEX can load only after /RESET (its nCONFIG) is high: the load comes after the first line here.
		// (While /RESET is low 10K_D0 is preset; the Quartus netlist emulates a register with both async inputs by a
		// latch that returns to the clocked value when the preset ends — the chip keeps 1. Not exercised.)
		wait (confx === 1'b1); repeat (100) @(posedge clk);
		// configuration load: 64 bits on WR_CNF / D0, then the ACEX starts (XACS low)
		for (i = 0; i < 64; i = i + 1) begin
			@(posedge clk); while (clk42) @(posedge clk);
			d0 <= $random; repeat (6) @(posedge clk); wr_cnf <= 1; repeat (8) @(posedge clk); wr_cnf <= 0;
		end
		repeat (20) @(posedge clk); cmp_on = 1;
		@(posedge clk); while (clk42) @(posedge clk); xacs <= 0; repeat (8) @(posedge clk); xacs <= 1;
		for (i = 0; i < 3; i = i + 1) begin
			strobe(4'b0000, 2'b01); strobe(4'b0000, 2'b00); strobe(4'b0000, 2'b10);        // PDOS, WG write / read
			strobe(4'b0110, 2'b01); strobe(4'b1110, 2'b01); strobe(4'b1110, 2'b10);        // CMOS address / write / read
			strobe(4'b0011, 2'b00); strobe(4'b0101, 2'b00); strobe(4'b1101, 2'b10);        // HDD1, IDE write / read
			strobe(4'b0011, 2'b01); strobe(4'b0100, 2'b10); strobe(4'b1100, 2'b00);        // HDD2, CS1 / CS3
			strobe(4'b1001, 2'b01); strobe(4'b1001, 2'b00);                                 // 312 / 320 lines
			strobe(4'b0001, 2'b01); strobe(4'b0001, 2'b00);                                 // 1.44 / 720
			strobe(4'b1011, 2'b01);                                                         // soft reset 2 (HDD none)
			repeat (20000) @(posedge clk);
		end
		for (i = 0; i < 200; i = i + 1) word($random, $random, 2 + ($random & 15));
		pw_good = 0; repeat (6000) @(posedge clk); pw_good = 1;                             // XHD_RES follows
		strobe(4'b1011, 2'b00);                                                             // soft reset
		repeat ($test$plusargs("frame") ? 3500000 : 300000) @(posedge clk);
		$display("tb_eq_max (2.18 SP2_MAX vs sp_max):");
		clk14_report; clkzz_report; aud_report; syncs_report; sinc12_report; conf_x_report; k10_report; wg_report;
		cmos_report; ide_report; hd_cs_report; xhd_res_report;
		$display("tb_eq_max: %0d errors%s", errors, weak ? " (some outputs never toggled)" : "");
		$finish;
	end
endmodule
