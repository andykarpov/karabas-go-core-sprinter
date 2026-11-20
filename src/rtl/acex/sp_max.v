// Sprinter MAX (EPM7064, "SINC_controller", SP2_MAX.TDF of Ivan Mak / Peters Plus, gitlab sprinter-computer/hard
// MaxPlus2/MAX): 14 MHz, line / frame syncs (also to the ACEX: SINC_1 = CTH5, SINC_2 = CTV8), reset, the strobes of
// the WD1793 / CMOS / IDE decoded from the control word on the MA bus (HDD_C / FDD_C), the 312 / 320 lines and HDD1 / 2
// latches, the ACEX configuration pins. Not yet: the FDD data separator and write precompensation (CLK_WG, FDAT,
// QDAT, WDAT; Ф2). Rules: docs/translation.md. EXP() of MAX+plus II is an inverting buffer.
//
// CLK = 2 x 42 MHz; every CLK edge is an edge of the original TG42: CE = its rising, CE_N = its falling edge
// (exactly one of them is 1 at each CLK edge). The divider of the original counts on (TG42 xor !XCT1): at a rising
// TG42 edge when XCT1 = 1, at a falling one when XCT1 = 0 — 14 MHz on XCT1.
module sp_max (
	input            CLK,
	input            CE,
	input            CE_N,
	input            EPM_RES,      // power-on reset of the board, active low
	input            PW_GOOD,
	input      [3:0] HDD_C,        // control word from the ACEX (MA bus)
	input      [2:0] FDD_C,
	input            XACS,         // the ACEX is configured and running (its first XACS low ends the load mode)
	input            WR_CNF,       // configuration load: clock and data from the CPU
	input            D0,
	output           CLK14,
	output           CLKZZ_O,      // TRI(XCT1, CNF_OFF): the CPU clock while the ACEX is not configured
	output           CLKZZ_OE,
	output           AUD,          // CT3: clock of the timers
	output           SINC_H,
	output           SINC_V,
	output           SINC,
	output           SINC_1,       // CTH5 to the ACEX
	output           SINC_2,       // CTV8 to the ACEX
	output           CONF_X_N,     // nCONFIG of the ACEX: OPNDRN(/RESET), low = driven low
	output           K_CLK,        // 10K_CLK: ACEX DCLK in the load mode, HDD_CLK after
	output           K_D0,         // 10K_D0: ACEX DATA0 in the load mode, FDD 1.44 flag after
	output           WR_PDOS,
	output           WG_WR_N,
	output           WG_RD_N,
	output           CMOS_DWR,
	output           CMOS_AS,
	output           CMOS_DRD,
	output           HD_DIR,
	output           HD_CS,
	output           XHD_RES,
	output           XHD_WR,
	output           XHD_RD,
	output     [2:1] XHD1_CS,
	output     [2:1] XHD2_CS,
	output           T320_O        // 1: 320 lines, 0: 312 (for the video output)
);
	// test only (tb_eq_max, with the matching reference variant): XHD_RES on the line sync instead of the frame sync,
	// so /RESET goes high after a line, not after 20 ms
	parameter XHD_RES_ON_HSYNC = 0;
	// ---- divider and counters (ripple chain of the original, all in this CLK edge)
	reg  [2:0] xct = 3'd0;
	wire       xinc = CE ? xct[1] : ~xct[1];
	wire [2:0] xct_n = xct + {2'b00, xinc};
	wire       x0_rise = ~xct[0] & xct_n[0];
	wire       x1_rise = ~xct[1] & xct_n[1];
	reg        clk14 = 1'b0;

	reg  [3:0] ct = 4'd0;
	wire [3:0] ct_n = ct + {3'd0, x1_rise};
	wire       ct3_fall = ct[3] & ~ct_n[3];

	reg  [5:0] cth = 6'd0;
	reg        sinc_ht = 1'b0;
	wire [5:0] cth_n = ~ct3_fall ? cth : ((cth[1:0] == 2'b11) & sinc_ht) ? 6'd0 : cth + 6'd1;
	wire       sinc_ht_n = ct3_fall ? (cth[5:2] == 4'b1101) : sinc_ht;
	wire       sht_rise = ~sinc_ht & sinc_ht_n;

	reg  [8:0] ctv = 9'd0;
	reg        sinc_vt = 1'b0;
	wire       svt_d = (ctv[8:2] == 7'b1001111) | ((ctv[8:2] == 7'b1001101) & nt320);
	wire       sinc_vt_n = sht_rise ? svt_d : sinc_vt;
	wire       svt_rise = ~sinc_vt & sinc_vt_n;

	// ---- control word decodes (active low, EXP = NOT)
	wire soft_reset  = ~((HDD_C == 4'b1011) & (FDD_C == 3'b000));
	wire soft_reset2 = ~((HDD_C == 4'b1011) & (FDD_C == 3'b001));
	wire s144  = ~((HDD_C == 4'b0001) & (FDD_C == 3'b001));
	wire s720  = ~((HDD_C == 4'b0001) & (FDD_C == 3'b000));
	wire s312  = ~((HDD_C == 4'b1001) & (FDD_C == 3'b001));
	wire s320  = ~((HDD_C == 4'b1001) & (FDD_C == 3'b000));
	wire shdd2 = ~((HDD_C == 4'b0011) & (FDD_C == 3'b001));
	wire shdd1 = ~((HDD_C == 4'b0011) & (FDD_C == 3'b000));

	// ---- /RESET = DFF(EPM_RES & XHD_RES, !CT3, SOFT_RESET)
	reg        rst_q = 1'b0;
	wire       rst = soft_reset & rst_q;
	reg        xhd_res = 1'b0;

	// ---- latches (cross-coupled EXP): 312 / 320 lines, HDD1 / HDD2 / none
	reg        t320_q = 1'b0;
	wire       t320 = (~s320 | ~rst) ? 1'b1 : ~s312 ? 1'b0 : t320_q;
	wire       nt320 = ~(t320 & s312);
	reg  [1:0] hdd_q = 2'd0;                    // 0 none, 1 HDD1 (THDD = 0), 2 HDD2 (NTHDD = 0)
	wire [1:0] hdd = (~rst | ~soft_reset2) ? 2'd0 : ~shdd1 ? 2'd1 : ~shdd2 ? 2'd2 : hdd_q;
	wire       thdd = hdd != 2'd1;
	wire       nthdd = hdd != 2'd2;

	// ---- configuration: CNF_OFF = DFF(GND, GND, XACS, /RESET) is a latch: set by /RESET, cleared by XACS
	reg        cnf_off_q = 1'b0;
	wire       cnf_off = ~XACS ? 1'b0 : ~rst ? 1'b1 : cnf_off_q;   // both active: the clear wins
	reg        k_clk = 1'b0;
	wire       k_clk_d = (WR_CNF & cnf_off) | ((HDD_C[0] | FDD_C[2]) & ~cnf_off);
	wire       k_rise = CE & ~k_clk & k_clk_d;
	reg        k_d0_q = 1'b0;
	wire       k_d0 = ~s720 ? 1'b0 : ~(s144 & rst) ? 1'b1 : k_d0_q;

	// ---- strobes on HDD_CLK = 10K_CLK; prn FDD_C2 (WG / CMOS / PDOS), HDD_C0 (IDE)
	reg wr_pdos_q = 1'b0, wg_wr_q = 1'b0, wg_rd_q = 1'b0, cmos_dwr_q = 1'b0, cmos_as_q = 1'b0, cmos_drd_q = 1'b0;
	reg xhd_wr_q = 1'b0, xhd_rd_q = 1'b0;
	reg [2:1] xhd1 = 2'b00, xhd2 = 2'b00;
	wire h0 = HDD_C == 4'b0000;
	wire hx101 = HDD_C[2:0] == 3'b101;

	always @(posedge CLK) if (CE | CE_N) begin
		xct <= xct_n;
		if (x0_rise) clk14 <= ~clk14;
		ct <= ct_n;
		cth <= cth_n;
		sinc_ht <= sinc_ht_n;
		if (ct3_fall) rst_q <= soft_reset ? EPM_RES & xhd_res : 1'b0;
		else if (~soft_reset) rst_q <= 1'b0;
		if (sht_rise) begin
			sinc_vt <= svt_d;
			if (~((ctv[1:0] == 2'b11) & sinc_vt)) ctv <= ctv + 9'd1;   // xor (CTV8M, 0) with CTV8M = FN_NUM = 0
			else ctv <= 9'd0;
		end
		if (XHD_RES_ON_HSYNC ? sht_rise : svt_rise) xhd_res <= PW_GOOD;
		t320_q <= t320;
		hdd_q <= hdd;
		cnf_off_q <= cnf_off;
		if (CE) k_clk <= k_clk_d;
		// 10K_D0: DFFE(D0, 10K_CLK, S720, S144 & /RESET, CNF_OFF)
		if (~s720) k_d0_q <= 1'b0;
		else if (~(s144 & rst)) k_d0_q <= 1'b1;
		else if (k_rise & cnf_off) k_d0_q <= D0;
		// strobes
		if (~FDD_C[2]) begin
			wr_pdos_q <= 1'b1; wg_wr_q <= 1'b1; wg_rd_q <= 1'b1; cmos_dwr_q <= 1'b1; cmos_as_q <= 1'b1; cmos_drd_q <= 1'b1;
		end else if (k_rise) begin
			wr_pdos_q  <= ~(h0 & (FDD_C[1:0] == 2'b01));
			wg_wr_q    <= ~(h0 & (FDD_C[1:0] == 2'b00));
			wg_rd_q    <= ~(h0 & (FDD_C[1:0] == 2'b10));
			cmos_dwr_q <= ~((HDD_C == 4'b1110) & (FDD_C[1:0] == 2'b01));
			cmos_as_q  <= ~((HDD_C == 4'b0110) & (FDD_C[1:0] == 2'b01));
			cmos_drd_q <= ~((HDD_C == 4'b1110) & (FDD_C[1:0] == 2'b10));
		end
		if (~HDD_C[0]) begin xhd_wr_q <= 1'b1; xhd_rd_q <= 1'b1; end
		else if (k_rise) begin
			xhd_wr_q <= ~hx101 | FDD_C[1];
			xhd_rd_q <= ~hx101 | ~FDD_C[1];
		end
		if (CE) begin
			xhd1[1] <= ~(HDD_C[3:1] == 3'b010) | thdd;
			xhd1[2] <= ~(HDD_C[3:1] == 3'b110) | thdd;
			xhd2[1] <= ~(HDD_C[3:1] == 3'b010) | nthdd;
			xhd2[2] <= ~(HDD_C[3:1] == 3'b110) | nthdd;
		end
	end

	assign CLK14    = clk14;
	assign CLKZZ_O  = xct[1];
	assign CLKZZ_OE = cnf_off;
	assign AUD      = ct[3];
	assign SINC_H   = sinc_ht;
	assign SINC_V   = sinc_vt;
	assign SINC     = sinc_vt ^ sinc_ht;
	assign SINC_1   = cth[5];
	assign SINC_2   = ctv[8];
	assign CONF_X_N = rst;
	assign K_CLK    = k_clk;
	assign K_D0     = k_d0;
	assign WR_PDOS  = ~FDD_C[2] | wr_pdos_q;
	assign WG_WR_N  = ~FDD_C[2] | wg_wr_q;
	assign WG_RD_N  = ~FDD_C[2] | wg_rd_q;
	assign CMOS_DWR = ~FDD_C[2] | cmos_dwr_q;
	assign CMOS_AS  = ~(~FDD_C[2] | cmos_as_q);
	assign CMOS_DRD = ~FDD_C[2] | cmos_drd_q;
	assign XHD_WR   = ~HDD_C[0] | xhd_wr_q;
	assign XHD_RD   = ~HDD_C[0] | xhd_rd_q;
	assign HD_DIR   = XHD_RD;
	assign HD_CS    = 1'b0;                     // CTV8M = FN_NUM = 0 (NUM = "NO")
	assign XHD_RES  = xhd_res;
	assign XHD1_CS  = xhd1;
	assign XHD2_CS  = xhd2;
	assign T320_O   = t320;
endmodule
