// XST gate only (acexm_xst.sh): sp_acex with its memory controllers sp_sram and sp_sdram, the way the Mini G top
// will connect them: CE / CE_N from a toggle on CLK (84 MHz), VDx_I and D_I (ROM / fastram) from sp_sram, MD_I from
// sp_sdram while it drives, else the peripheral bus. Pins split into _O / _T / _I (the script runs with -iobuf NO).
module sp_acexm_gate (
	input             CLK,
	// Z80
	input             M1_N, RF_N, IO_N, WR_N, RD_N, MR_N,
	input             M1_N_NX, RF_N_NX, IO_N_NX, WR_N_NX, RD_N_NX, MR_N_NX,
	input      [15:0] A,
	input       [7:0] CPU_DO,       // T80 data out
	input             CPU_DOE,
	output      [7:0] CPU_DI,       // data for the T80
	output            CLKZ1, WAIT_N_OE, RESET_N_OE,
	input             RESET_N_I,
	// peripherals on MD
	input      [15:0] PER_MD,
	output     [15:0] MD_O,
	output            MD_OE,
	// palette, sound, MAX
	output     [31:0] PAL_Q,
	output            WR_COL, DAC_DATA, DAC_WS, DAC_BCK, XACS, SXA, RDXA, WR_AWG, RD_KMPS, WR_DWG,
	input       [2:0] XA_I,
	input             XA3,
	output      [2:0] XA_O,
	output            XA_OE,
	// loader
	input             LD_REQ,
	input      [20:0] LD_A,
	input       [1:0] LD_BE,
	input      [15:0] LD_D,
	output            LD_ACK, SD_RDY,
	// SRAM
	output     [20:0] SRAM_A,
	output     [15:0] SRAM_D_O, SRAM_D_T,
	input      [15:0] SRAM_D_I,
	output      [1:0] SRAM_WE_N, SRAM_OE_N,
	// SDRAM
	output            SD_CLK, SD_CKE, SD_CS_N, SD_RAS_N, SD_CAS_N, SD_WE_N,
	output      [1:0] SD_BA, SD_DQM,
	output     [12:0] SD_A,
	output     [15:0] SD_DQ_O, SD_DQ_T,
	input      [15:0] SD_DQ_I
);
	reg t = 1'b0;
	always @(posedge CLK) t <= ~t;
	wire ce = t, ce_n = ~t;

	wire [7:0] d_o, vd0_o, vd1_o, vd2_o, vd3_o, vd0_i, vd1_i, vd2_i, vd3_i, cpu_q;
	wire d_oe, cs_rom, cs_cash, cpu_rdy;
	wire [17:14] ra; wire [3:0] v_wr, vd_oe, cas; wire [1:0] ras, mca; wire [15:0] va, md_q; wire [14:0] ma; wire [1:0] md_drv;
	wire we, mode_rq, mlo_rq, atr_zx, pix_rq, sel_rom, sel_cash; wire [2:0] ct_ph;
	wire [17:1] va_nx, va_atr; wire [3:0] v_wr_nx; wire [15:0] va_mod;
	wire cs_mem = ~cs_rom | (~cs_cash & (ra[17:16] == 2'b01));
	wire [7:0] d_i = CPU_DOE ? CPU_DO : cs_mem ? cpu_q : 8'hFF;
	assign CPU_DI = d_oe ? d_o : d_i;
	wire [15:0] md_i = {md_drv[1] ? md_q[15:8] : PER_MD[15:8], md_drv[0] ? md_q[7:0] : PER_MD[7:0]};

	sp_acex acex(.CLK(CLK), .CE(ce), .CE_N(ce_n), .M1_N(M1_N), .RF_N(RF_N), .IO_N(IO_N), .WR_N(WR_N), .RD_N(RD_N),
		.MR_N(MR_N), .M1_N_NX(M1_N_NX), .RF_N_NX(RF_N_NX), .IO_N_NX(IO_N_NX), .WR_N_NX(WR_N_NX), .RD_N_NX(RD_N_NX),
		.MR_N_NX(MR_N_NX), .A(A), .D_I(d_i), .D_O(d_o), .D_OE(d_oe), .CLKZ1(CLKZ1), .WAIT_N_OE(WAIT_N_OE),
		.RESET_N_I(RESET_N_I), .RESET_N_OE(RESET_N_OE), .CS_ROM(cs_rom), .CS_CASH(cs_cash), .RA(ra),
		.V_CS(), .VA(va), .V_WR(v_wr), .VD0_I(vd0_i), .VD1_I(vd1_i), .VD2_I(vd2_i), .VD3_I(vd3_i), .VD0_O(vd0_o),
		.VD1_O(vd1_o), .VD2_O(vd2_o), .VD3_O(vd3_o), .VD_OE(vd_oe), .WR_COL(WR_COL), .DAC_DATA(DAC_DATA),
		.DAC_WS(DAC_WS), .DAC_BCK(DAC_BCK), .MD_I(md_i), .MD_O(MD_O), .MD_OE(MD_OE), .MA(ma), .RAS_(ras),
		.CAS_(cas), .WE_N(we), .XACS(XACS), .XA_I(XA_I), .XA_O(XA_O), .XA_OE(XA_OE), .XA3(XA3), .SXA(SXA),
		.RDXA(RDXA), .WR_AWG(WR_AWG), .RD_KMPS(RD_KMPS), .WR_DWG(WR_DWG), .CT_PH(ct_ph), .VA_NX(va_nx),
		.V_WR_NX(v_wr_nx), .VA_MOD(va_mod), .MODE_RQ(mode_rq), .MLO_RQ(mlo_rq), .VA_ATR(va_atr), .ATR_ZX(atr_zx),
		.PIX_RQ(pix_rq), .MCA(mca), .SEL_ROM(sel_rom), .SEL_CASH(sel_cash), .CFG_RST(1'b0), .PERS_K30(1'b0));

	sp_sram sram(.CLK(CLK), .CE(ce), .CE_N(ce_n), .CT(ct_ph), .VA_NX(va_nx), .V_WR_NX(v_wr_nx), .VA_MOD(va_mod),
		.MODE_RQ(mode_rq), .MLO_RQ(mlo_rq), .VA_ATR(va_atr), .ATR_ZX(atr_zx), .PIX_RQ(pix_rq), .VD0_O(vd0_o),
		.VD1_O(vd1_o), .VD2_O(vd2_o), .VD3_O(vd3_o), .VA(va), .VD0_I(vd0_i), .VD1_I(vd1_i), .VD2_I(vd2_i),
		.VD3_I(vd3_i), .PAL_Q(PAL_Q), .A(A), .RA(ra), .SEL_ROM(sel_rom), .SEL_CASH(sel_cash), .RF_N(RF_N),
		.MR_N(MR_N), .WR_N(WR_N), .CS_CASH(cs_cash), .CPU_D(d_i), .CPU_FLUSH(1'b0), .CPU_Q(cpu_q),
		.CPU_RDY(cpu_rdy), .LD_REQ(LD_REQ), .LD_A(LD_A), .LD_BE(LD_BE), .LD_D(LD_D), .LD_ACK(LD_ACK), .WB_OVF(),
		.SRAM_A(SRAM_A), .SRAM_D_O(SRAM_D_O), .SRAM_D_T(SRAM_D_T), .SRAM_D_I(SRAM_D_I), .SRAM_WE_N(SRAM_WE_N),
		.SRAM_OE_N(SRAM_OE_N));

	sp_sdram sdram(.CLK(CLK), .CE(ce), .CE_N(ce_n), .CT(ct_ph), .RAS_N(ras[0]), .CAS_N(cas), .WE_N(we), .MA(ma[11:0]),
		.MCA(mca), .MD_O(MD_O), .MD_Q(md_q), .MD_DRV(md_drv), .RDY(SD_RDY), .AUX_REQ(1'b0), .AUX_ACK(),
		.SD_CLK(SD_CLK), .SD_CKE(SD_CKE), .SD_CS_N(SD_CS_N), .SD_RAS_N(SD_RAS_N), .SD_CAS_N(SD_CAS_N),
		.SD_WE_N(SD_WE_N), .SD_BA(SD_BA), .SD_A(SD_A), .SD_DQM(SD_DQM), .SD_DQ_O(SD_DQ_O), .SD_DQ_T(SD_DQ_T),
		.SD_DQ_I(SD_DQ_I));
endmodule
