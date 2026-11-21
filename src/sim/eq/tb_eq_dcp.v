// sp_dcp against the DCP netlist of the 3.03a AHDL (UPDATE = 1). A Z80 bus model clocked by the reference's own
// CLK_Z80 (21 MHz turbo / 3.5 MHz): M1 fetches with refresh, memory reads / writes in all four windows, IN / OUT
// through the two-level port decoder (a descriptor byte read from DRAM page 0x40 = a table in the testbench,
// addressed by the row / column the reference puts on MA, returned on MD the way ACCELER DO does), INTA; CNF writes
// (port maps, PN5 reset, Scorpion off, Pentagon-512, TB_SW / AROM16 / SYS), 7FFD / 1FFD, page ports E9 / EA / Fx,
// HDD ports (descriptors 20..29), AY / system ports, wait states, DOS on / off, CONTINUE stretches, resets.
// CLK = 84 MHz, clk42 toggles at every CLK edge and is the reference's CLK42; CE = ~clk42 (the reference's CLK42
// rises at our CE edge), CE_N = clk42. All inputs change 1 ns after a CE edge (MD after a CE_N edge).
// -DK30 / -DSCROLL: the personality against the k30 / SCROLL DCP netlist (SCROLL: the MEM[EE] reload by CFG_RST, below).
`timescale 1ns/1ps
`include "eq_cmp.vh"
module tb_eq_dcp;
	reg clk = 0; always #5.952 clk = ~clk;
	reg clk42 = 0; always @(posedge clk) clk42 <= ~clk42;
	wire ce = ~clk42, ce_n = clk42;
	reg cmp_on = 0;
	integer errors = 0, weak = 0;
	integer seed = 1;

	// ---- inputs: applied value and the next value (set in the half cycle before the CE where it is applied)
	reg reset_n = 0, reset_nx = 0;
	reg [5:0] ct = 0;
	reg cont = 1, cont_nx = 1;
	reg [15:0] a = 16'hFFFF, a_nx = 16'hFFFF;
	reg [7:0] di = 8'hFF, di_nx = 8'hFF;
	reg th = 1, th_nx = 1;
	reg io_n = 1, rd_n = 1, wr_n = 1, mr_n = 1, rf_n = 1, m1_n = 1;
	reg io_nx = 1, rd_nx = 1, wr_nx = 1, mr_nx = 1, rf_nx = 1, m1_nx = 1;
	reg [7:0] md = 8'h00;
	reg dos = 1, dos_nx = 1;
	reg [9:0] gl = 0, gl_nx = 0;
	reg test_r = 0, tr_nx = 0, acc_on = 0, acc_nx = 0, dcas = 0, dcas_nx = 0, blk_mem = 0, bm_nx = 0;

	function [5:0] ct_next(input [5:0] c);
		case (c[2:0])
			3'd0: ct_next = {c[5:3], 3'd1}; 3'd1: ct_next = {c[5:3], 3'd2}; 3'd2: ct_next = {c[5:3], 3'd4};
			3'd4: ct_next = {c[5:3], 3'd5}; 3'd5: ct_next = {c[5:3], 3'd6}; default: ct_next = {c[5:3] + 3'd1, 3'd0};
		endcase
	endfunction
	wire [5:0] ct_nx = ct_next(ct);

	always @(posedge clk) if (ce) begin
		ct <= #1 ct_nx;
		reset_n <= #1 reset_nx; cont <= #1 cont_nx; a <= #1 a_nx; di <= #1 di_nx; th <= #1 th_nx;
		io_n <= #1 io_nx; rd_n <= #1 rd_nx; wr_n <= #1 wr_nx; mr_n <= #1 mr_nx; rf_n <= #1 rf_nx; m1_n <= #1 m1_nx;
		dos <= #1 dos_nx; gl <= #1 gl_nx; test_r <= #1 tr_nx; acc_on <= #1 acc_nx; dcas <= #1 dcas_nx; blk_mem <= #1 bm_nx;
	end
	// events of the strobes used as clocks, high at the CE where the edge happens
	wire iowr_ev = ~(io_n | wr_n | ~m1_n) & (io_nx | wr_nx | ~m1_nx);
	wire iorel_ev = ~(io_n | ~m1_n) & (io_nx | ~m1_nx);
	wire mr_fall_ev = mr_n & ~mr_nx;
	wire io_fall_ev = io_n & ~io_nx;
	wire refresh_ev = ~ct[4] & ct_nx[4];
	wire dcas_fall_ev = dcas & ~dcas_nx;

	// ---- the two sides
	wire res_r, ras_r, cas_r, mce_r, mcb_r, mct_r, mcw_r, clkz_r, turbo_r, wait_r, iom_r, iomm_r;
	wire cs_rom_r, cs_ram_r, v_ram_r, port_r, wr_dwg_r, wr_tm9_r, wr_awg_r, rd_kp11_r, kp11_r, graf_r, sp_scr_r, sp_sa_r;
	wire scr128_r, hdd_data_r, hdd_flip_r, ram_r, blk_r_r, pn4_r;
	wire [7:0] do_r, dcpp_r; wire [11:0] ma_r, page_r; wire [1:0] mca_r; wire [3:0] ra_r, type_r; wire [9:0] ga_r;
	wire res_o, ras_o, cas_o, mce_o, mcb_o, mct_o, mcw_o, clkz_o, turbo_o, wait_o, iom_o, iomm_o;
	wire cs_rom_o, cs_ram_o, v_ram_o, port_o, wr_dwg_o, wr_tm9_o, wr_awg_o, rd_kp11_o, kp11_o, graf_o, sp_scr_o, sp_sa_o;
	wire scr128_o, hdd_data_o, hdd_flip_o, ram_o, blk_r_o, pn4_o;
	wire [7:0] do_o, dcpp_o; wire [11:0] ma_o, page_o; wire [1:0] mca_o; wire [3:0] ra_o, type_o; wire [9:0] ga_o;

	// -DSCROLL: ours starts with the 3.03a MIF and a CFG_RST of 300 CLK (the reload, then MEM[EE] = 2041 by
	// PERS_SCROLL); the reference's clock is held meanwhile, so both leave power-up together
	reg cfg_rst = `PERS_SCROLL_V;
	wire clk42_r = clk42 & ~cfg_rst;
	dcp ref(.CLK42(clk42_r), .\/RESET (reset_n), .\/RES (res_r), .CT(ct[2:0]), .\CONTINUE (cont), .RAS(ras_r), .CAS(cas_r),
		.MC_END(mce_r), .MC_BEGIN(mcb_r), .MC_TYPE(mct_r), .MC_WRITE(mcw_r), .A(a), .DI(di), .\DO (do_r), .MA(ma_r),
		.MCA(mca_r), .TURBO_HAND(th), .CLK_Z80(clkz_r), .TURBO(turbo_r), .\/IO (io_n), .\/RD (rd_n), .\/WR (wr_n),
		.\/MR (mr_n), .\/RF (rf_n), .\/M1 (m1_n), .\/WAIT (wait_r), .\/IOM (iom_r), .\/IOMM (iomm_r), .MD(md),
		.RA(ra_r), .PAGE(page_r), .\TYPE (type_r), .CS_ROM(cs_rom_r), .CS_RAM(cs_ram_r), .V_RAM(v_ram_r),
		.PORT(port_r), .DOS(dos), .WR_DWG(wr_dwg_r), .WR_TM9(wr_tm9_r), .WR_AWG(wr_awg_r), .RD_KP11(rd_kp11_r),
		.KP11_MIX(kp11_r), .REFRESH(ct[4]), .G_LINE(gl), .GA(ga_r), .GRAF(graf_r), .SP_SCR(sp_scr_r), .SP_SA(sp_sa_r),
		.SCR128(scr128_r), .TEST_R(test_r), .HDD_DATA(hdd_data_r), .HDD_FLIP(hdd_flip_r), .RAM(ram_r),
		.BLK_R(blk_r_r), .PN4Q(pn4_r), .ACC_ON(acc_on), .DCPP(dcpp_r), .DOUBLE_CAS(dcas), .BLK_MEM(blk_mem));
	sp_dcp #(.MIF_HEX("../../rtl/acex/mif/dcp.hex")) dut(.CLK(clk), .CE(ce), .CE_N(ce_n), .RESET_N(reset_n),
		.RES_N(res_o), .CT(ct[2:0]), .CONTINUE(cont), .RAS(ras_o), .CAS(cas_o), .MC_END(mce_o), .MC_BEGIN(mcb_o),
		.MC_TYPE(mct_o), .MC_WRITE(mcw_o), .A(a), .DI(di), .DO(do_o), .MA(ma_o), .MCA(mca_o), .TURBO_HAND(th),
		.CLK_Z80(clkz_o), .TURBO(turbo_o), .IO_N(io_n), .RD_N(rd_n), .WR_N(wr_n), .MR_N(mr_n), .RF_N(rf_n),
		.M1_N(m1_n), .IOWR_EV(iowr_ev), .IOREL_EV(iorel_ev), .MR_FALL_EV(mr_fall_ev), .IO_FALL_EV(io_fall_ev),
		.WAIT_N(wait_o), .IOM_N(iom_o), .IOMM_N(iomm_o), .MD(md), .RA(ra_o), .PAGE(page_o), .TYPE(type_o),
		.CS_ROM(cs_rom_o), .CS_RAM(cs_ram_o), .V_RAM(v_ram_o), .PORT(port_o), .DOS(dos), .WR_DWG(wr_dwg_o),
		.WR_TM9(wr_tm9_o), .WR_AWG(wr_awg_o), .RD_KP11(rd_kp11_o), .KP11_MIX(kp11_o), .REFRESH_EV(refresh_ev),
		.G_LINE(gl), .GA(ga_o), .GRAF(graf_o), .SP_SCR(sp_scr_o), .SP_SA(sp_sa_o), .SCR128(scr128_o),
		.TEST_R(test_r), .HDD_DATA(hdd_data_o), .HDD_FLIP(hdd_flip_o), .RAM(ram_o), .BLK_R(blk_r_o), .PN4Q(pn4_o),
		.ACC_ON(acc_on), .DCPP(dcpp_o), .DCAS_FALL_EV(dcas_fall_ev), .BLK_MEM(blk_mem), .CFG_RST(cfg_rst), .PERS_K30(`PERS_K30_V),
		.PERS_SCROLL(`PERS_SCROLL_V));

	// +mut (must fail): -DK30 the k30 PN5 clear forced back to 3.03a; -DSCROLL MEM[EE] left at the 3.03a word
	wire m_pn_clr5 = dut.pn_clr_lo & dut.pn_clr_hi;   // a plain net: iverilog evaluates another force RHS once
	wire [15:0] m_ee = dut.rl_d;
`ifdef SCROLL
	initial if ($test$plusargs("mut")) #1 force dut.ee_wd = m_ee;
	initial begin repeat (300) @(posedge clk); @(negedge clk); while (clk42) @(negedge clk); cfg_rst = 0; end
`else
	initial if ($test$plusargs("mut")) #1 force dut.pn_clr5 = m_pn_clr5;
`endif
	`EQ_CMP(res, 1, res_o, res_r)
	`EQ_CMP(ras_cas, 2, ({ras_o, cas_o}), ({ras_r, cas_r}))
	`EQ_CMP(mc, 4, ({mcb_o, mce_o, mct_o, mcw_o}), ({mcb_r, mce_r, mct_r, mcw_r}))
	`EQ_CMP(ma, 12, ma_o, ma_r)
	`EQ_CMP(mca, 2, mca_o, mca_r)
	`EQ_CMP(clk_z80, 1, clkz_o, clkz_r)
	`EQ_CMP(turbo, 1, turbo_o, turbo_r)
	`EQ_CMP(wait_n, 1, wait_o, wait_r)
	`EQ_CMP(iom, 2, ({iom_o, iomm_o}), ({iom_r, iomm_r}))
	`EQ_CMP(dout, 8, do_o, do_r)
	`EQ_CMP(page, 12, page_o, page_r)
	`EQ_CMP(type, 4, type_o, type_r)
	`EQ_CMP(dcpp, 8, dcpp_o, dcpp_r)
	`EQ_CMP(ra, 4, ra_o, ra_r)
	`EQ_CMP(cs, 3, ({cs_rom_o, cs_ram_o, ram_o}), ({cs_rom_r, cs_ram_r, ram_r}))
	`EQ_CMP(port, 1, port_o, port_r)
	`EQ_CMP(pn_bits, 4, ({v_ram_o, scr128_o, pn4_o, blk_r_o}), ({v_ram_r, scr128_r, pn4_r, blk_r_r}))
	`EQ_CMP(wr_dwg, 1, wr_dwg_o, wr_dwg_r)
	`EQ_CMP(wr_tm9, 1, wr_tm9_o, wr_tm9_r)
	`EQ_CMP(wr_awg, 1, wr_awg_o, wr_awg_r)
	`EQ_CMP(rd_kp11, 1, rd_kp11_o, rd_kp11_r)
	`EQ_CMP(kp11_mix, 1, kp11_o, kp11_r)
	`EQ_CMP(ga, 10, ga_o, ga_r)
	`EQ_CMP(graf, 1, graf_o, graf_r)
	`EQ_CMP(sp_scr, 2, ({sp_scr_o, sp_sa_o}), ({sp_scr_r, sp_sa_r}))
	`EQ_CMP(hdd_data, 1, hdd_data_o, hdd_data_r)
	`EQ_CMP(hdd_flip, 1, hdd_flip_o, hdd_flip_r)
	// internal registers (named dffeas of the netlist; CNF[2..0], SC[7..5,3..2] are unused and removed there)
	wire [7:0] pn_ri = {ref.\PN[7] .q, ref.\PN[6] .q, ref.\PN[5] .q, ref.\PN[4] .q, ref.\PN[3] .q, ref.\PN[2] .q,
		ref.\PN[1] .q, ref.\PN[0] .q};
	wire [4:0] cnf_ri = {ref.\CNF[7] .q, ref.\CNF[6] .q, ref.\CNF[5] .q, ref.\CNF[4] .q, ref.\CNF[3] .q};
	wire [2:0] sc_ri = {ref.\SC[4] .q, ref.\SC[1] .q, ref.\SC[0] .q};
	wire [7:0] pgs_ri = {ref.\PGS[7] .q, ref.\PGS[6] .q, ref.\PGS[5] .q, ref.\PGS[4] .q, ref.\PGS[3] .q,
		ref.\PGS[2] .q, ref.\PGS[1] .q, ref.\PGS[0] .q};
	`EQ_CMP(i_pn, 8, dut.pn_e, pn_ri)
	`EQ_CMP(i_cnf, 5, dut.cnf_e[7:3], cnf_ri)
	`EQ_CMP(i_sc, 3, ({dut.sc_e[4], dut.sc_e[1:0]}), sc_ri)
	`EQ_CMP(i_pgs, 8, dut.pgs_q, pgs_ri)

	// coverage counters (from our side, equal to the reference where the comparison passes)
	integer cv_pn[0:3], cv_pn5 = 0, cv_cnf = 0, cv_sc = 0, cv_scoff = 0, cv_memwr = 0, cv_fx = 0, cv_flip = 0, cv_nio = 0;
	integer cv_wt[0:15], cv_inta = 0, cv_cont = 0, cv_dcas = 0, cv_sys = 0, k_cv; reg memwr_p = 0;
	initial begin for (k_cv = 0; k_cv < 4; k_cv = k_cv + 1) cv_pn[k_cv] = 0; for (k_cv = 0; k_cv < 16; k_cv = k_cv + 1) cv_wt[k_cv] = 0; end
	always @(posedge clk) if (ce & cmp_on) begin
		if (iowr_ev & dut.pn_ena_n) begin cv_pn[{dut.cnf_e[7], dut.cnf_e[5]}] = cv_pn[{dut.cnf_e[7], dut.cnf_e[5]}] + 1; if (di[5]) cv_pn5 = cv_pn5 + 1; end
		if (iowr_ev & dut.sys_ena_n) cv_cnf = cv_cnf + 1;
		if (iowr_ev & dut.sc_ena_n) begin cv_sc = cv_sc + 1; if (dut.cnf_e[6]) cv_scoff = cv_scoff + 1; end
		if (dut.memwr & ~memwr_p) cv_memwr = cv_memwr + 1;
		memwr_p = dut.memwr;
		if (dut.mced_q == 1'b0 && dut.mc_end && dut.dcp_res_q && md[7:4] == 4'hF) cv_fx = cv_fx + 1;
		if (dut.flip_ev & dut.flip_ena) cv_flip = cv_flip + 1;
		if (dut.nio_q & ~io_n) cv_nio = cv_nio + 1;
		if (io_fall_ev & ~m1_n) cv_inta = cv_inta + 1;
		if (dcas_fall_ev & hdd_flip_r) cv_dcas = cv_dcas + 1;
		if (mr_fall_ev & ~m1_n & dut.sys_e & ~a[15] & ~a[14]) cv_sys = cv_sys + 1;
		if (~cont & dut.mc_end == 1'b0 & ~mr_n) cv_cont = cv_cont + 1;
	end
	reg iom_p = 1;
	always @(posedge clk) if (ce) begin iom_p <= dut.iom_e; if (iom_p & ~dut.iom_e) cv_wt[{turbo_o, dut.q[14:12]}] = cv_wt[{turbo_o, dut.q[14:12]}] + 1; end

	// first mismatch print, for debugging
	reg [255:0] sig_o, sig_r; reg first_done = 0;
	always @(negedge clk) if (cmp_on && !first_done) begin
		sig_o = {res_o, ras_o, cas_o, mcb_o, mce_o, mct_o, mcw_o, ma_o, mca_o, clkz_o, turbo_o, wait_o, iom_o, iomm_o,
			do_o, page_o, type_o, dcpp_o, ra_o, cs_rom_o, cs_ram_o, ram_o, port_o, v_ram_o, scr128_o, pn4_o, blk_r_o,
			wr_dwg_o, wr_tm9_o, wr_awg_o, rd_kp11_o, kp11_o, ga_o, graf_o, sp_scr_o, sp_sa_o, hdd_data_o, hdd_flip_o};
		sig_r = {res_r, ras_r, cas_r, mcb_r, mce_r, mct_r, mcw_r, ma_r, mca_r, clkz_r, turbo_r, wait_r, iom_r, iomm_r,
			do_r, page_r, type_r, dcpp_r, ra_r, cs_rom_r, cs_ram_r, ram_r, port_r, v_ram_r, scr128_r, pn4_r, blk_r_r,
			wr_dwg_r, wr_tm9_r, wr_awg_r, rd_kp11_r, kp11_r, ga_r, graf_r, sp_scr_r, sp_sa_r, hdd_data_r, hdd_flip_r};
		if (sig_o !== sig_r) begin
			first_done = 1;
			$display("first mismatch at %0t ns (ce_n=%b ct=%0d): ours %h ref %h diff %h", $time, ce_n, ct[2:0], sig_o, sig_r, sig_o ^ sig_r);
		end
	end

	// ---- DRAM: row / column = the reference MA right after the fall of RAS / CAS (MA changes to the column at the
	// CAS edge; the top delays CAS by LCELLs); the byte comes on MD at the CE_N after MC_END rises
	// (ACCELER DO = DFFE(MD, DFF(MC_END, !CLK42)))
	reg [11:0] row = 0, col = 0; reg ras_p = 1, cas_p = 1;
	always @(negedge clk) begin
		if (ras_p & ~ras_r & mct_r === 1'b0) row <= ma_r;
		if (cas_p & ~cas_r & mct_r === 1'b0) col <= ma_r;
		ras_p <= ras_r; cas_p <= cas_r;
	end
	reg [7:0] dtab [0:16383];                  // page 0x40: {CNF4, CNF3, PN5, DOS, /WR, A15, A14, A6, A5, A13, A7, A2, A1, A0}
	function [7:0] dram(input [11:0] r, input [11:0] c, input [1:0] b);
		if (c[7:0] == 8'h40 && c[11:10] == 2'b00) dram = dtab[{c[9:8], r[9:0], b}];
		else dram = (r[7:0] * 8'd37) ^ (c[7:0] * 8'd11) ^ {r[11:8], c[11:8]} ^ {b, 6'd0} ^ 8'h5A;
	endfunction
	reg mce_y = 0;
	always @(posedge clk) if (ce_n) begin
		mce_y <= mce_r;
		if (mce_r === 1'b1 && mce_y === 1'b0) md <= #1 dram(row, col, mca_r);
	end
	function [13:0] didx(input [15:0] p, input w_n, input [1:0] cnf43, input pn5, input ds);
		didx = {cnf43, pn5, ds, w_n, p[15], p[14], p[6], p[5], p[13], p[7], p[2], p[1], p[0]};
	endfunction
	task dset(input [15:0] p, input w_n, input [7:0] d); integer k; begin
		for (k = 0; k < 16; k = k + 1) dtab[didx(p, w_n, k[3:2], k[1], k[0])] = d;
	end endtask

	// ---- Z80 bus model on the reference CLK_Z80: outputs change at the CE after a CLK_Z80 edge
	reg wait_s = 1;
	always @(negedge clk) wait_s <= wait_r;
	task zr; begin @(posedge clkz_r); #2; end endtask
	task zf; begin @(negedge clkz_r); #2; end endtask
	task wsamp; begin while (wait_s === 1'b0) begin zr; zf; end end endtask
	reg [6:0] r_reg = 0;
	task t1(input [15:0] ad, input m1); begin zr; a_nx = ad; m1_nx = ~m1; rf_nx = 1; end endtask
	task m1cyc(input [15:0] ad); begin
		t1(ad, 1);
		zf; mr_nx = 0; rd_nx = 0;
		// DOS of the top: DFF(DOS_, !(/M1 or /MR), , /RESET)
		dos_nx = (~(pn4_r & ad[13] & ad[12] & (ad[11:8] == 4'hD)) & dos) | ad[14] | ad[15];
		zr; zf; wsamp;
		zr; m1_nx = 1; mr_nx = 1; rd_nx = 1; rf_nx = 0; a_nx = {8'h3F, 1'b0, r_reg}; r_reg = r_reg + 1;
		zf; mr_nx = 0;
		zr; zf; mr_nx = 1;
	end endtask
	task mrd(input [15:0] ad); begin
		t1(ad, 0); zf; mr_nx = 0; rd_nx = 0; zr; zf; wsamp; zr; zf; mr_nx = 1; rd_nx = 1;
	end endtask
	task mwr(input [15:0] ad, input [7:0] d); begin
		t1(ad, 0); di_nx = d; zf; mr_nx = 0; zr; zf; wr_nx = 0; wsamp; zr; zf; mr_nx = 1; wr_nx = 1;
	end endtask
	task ior(input [15:0] p); begin
		t1(p, 0); zr; io_nx = 0; rd_nx = 0; zf; zr; zf; wsamp; zr; zf; io_nx = 1; rd_nx = 1;
	end endtask
	task iow(input [15:0] p, input [7:0] d); begin
		t1(p, 0); di_nx = d; zr; io_nx = 0; wr_nx = 0; zf; zr; zf; wsamp; zr; zf; io_nx = 1; wr_nx = 1;
	end endtask
	task inta; begin
		t1(16'h1234, 1); zf; zr; zf; zr; zf; io_nx = 0; zr; zf; wsamp;
		zr; m1_nx = 1; io_nx = 1; rf_nx = 0; a_nx = {8'h3F, 1'b0, r_reg}; r_reg = r_reg + 1;
		zf; mr_nx = 0; zr; zf; mr_nx = 1;
	end endtask
	task idle(input integer n); begin zr; rf_nx = 1; repeat (n - 1) zr; end endtask

	// ---- slow inputs of the top / ACCELER (not at the CE of a strobe edge they are data of)
	integer cont_cnt = 0;
	wire z_quiet = (io_nx == io_n) && (mr_nx == mr_n) && (wr_nx == wr_n) && (m1_nx == m1_n) && (rd_nx == rd_n);
	reg slow_on = 0;
	always @(posedge clk) if (ce_n && slow_on) begin
		#4;
		if (cont_cnt > 0) begin cont_cnt = cont_cnt - 1; if (cont_cnt == 0) cont_nx = 1; end
		else if (($random(seed) & 511) == 0) begin cont_nx = 0; cont_cnt = 6 + ($random(seed) & 31); end
		if (($random(seed) & 1023) == 0) acc_nx = ~acc_on;
		if (($random(seed) & 1023) == 1) tr_nx = ~test_r;
		if (($random(seed) & 255) == 2) gl_nx = $random(seed);
		if (z_quiet && ($random(seed) & 511) == 3) bm_nx = ~blk_mem;
		if (z_quiet && ($random(seed) & 255) == 4) dcas_nx = ~dcas;
	end

	// ---- program
	reg [7:0] pick [0:63]; integer npick;
	task rand_op; integer r, w; reg [15:0] ad; reg [7:0] d; begin
		r = $random(seed) & 255; ad = $random(seed); d = $random(seed);
		w = $random(seed) & 15;
		if (r < 100) m1cyc((w == 0) ? {4'h3, 4'hD, ad[7:0]} : ad);
		else if (r < 140) mrd(ad);
		else if (r < 175) mwr(ad, d);
		else if (r < 205) ior(ad);
		else if (r < 250) iow(ad, d);
		else if (r < 252) inta;
		else idle(1 + (w & 3));
	end endtask
	// a directed port with a chosen descriptor
	localparam [15:0] P_CNF = 16'h00C6, P_CNF_S = 16'h0086, P_PN = 16'h7FFD, P_SC = 16'h1FFD, P_W1 = 16'h4089,
		P_W2 = 16'h40A9, P_W0 = 16'h40C9, P_W3 = 16'h80F5, P_HDD = 16'h0050, P_HDR = 16'h4051, P_AY = 16'hFFFD,
		P_KBD = 16'h00FE, P_WG = 16'h001F, P_NOW = 16'h00FF, P_EE = 16'h2003;
	reg use_sys = 0;                           // CNF writes through the port with A6 = 0: SYS = 1 (BIOS / DOS ROM map)
	task cnf(input [7:0] v); iow(use_sys ? P_CNF_S : P_CNF, v); endtask

	integer i, j;
	initial begin
		npick = 0;
		for (i = 8'h10; i <= 8'h17; i = i + 1) begin pick[npick] = i; npick = npick + 1; end
		for (i = 8'h20; i <= 8'h2F; i = i + 1) begin pick[npick] = i; npick = npick + 1; end
		pick[npick] = 8'h1C; pick[npick+1] = 8'h1D; pick[npick+2] = 8'h30; pick[npick+3] = 8'h33; pick[npick+4] = 8'h40;
		pick[npick+5] = 8'h52; pick[npick+6] = 8'h58; pick[npick+7] = 8'h80; pick[npick+8] = 8'h88; pick[npick+9] = 8'h89;
		pick[npick+10] = 8'h8C; pick[npick+11] = 8'h8F; pick[npick+12] = 8'h90; pick[npick+13] = 8'h91;
		pick[npick+14] = 8'h9F; pick[npick+15] = 8'hB0; pick[npick+16] = 8'hC0; pick[npick+17] = 8'hC1;
		pick[npick+18] = 8'hC8; pick[npick+19] = 8'hC9; pick[npick+20] = 8'hC2; pick[npick+21] = 8'h00;
		pick[npick+22] = 8'hE9; pick[npick+23] = 8'hEA; pick[npick+24] = 8'hE3; pick[npick+25] = 8'hF2;
		pick[npick+26] = 8'hD7; pick[npick+27] = 8'hFC; pick[npick+28] = 8'hA0; pick[npick+29] = 8'h00;
		npick = npick + 30;
		for (i = 0; i < 16384; i = i + 1) dtab[i] = pick[($random(seed) & 32'h7FFFFFFF) % npick];
		dset(P_CNF, 0, 8'hC6); dset(P_CNF_S, 0, 8'hCE); dset(P_PN, 0, 8'hC1); dset(P_SC, 0, 8'hC0);
		dset(P_W1, 0, 8'hE9); dset(P_W2, 0, 8'hEA); dset(P_W0, 0, 8'hE0); dset(P_W3, 0, 8'hF5);
		dset(P_HDD, 0, 8'h20); dset(P_HDD, 1, 8'h20); dset(P_HDR, 0, 8'h23); dset(P_HDR, 1, 8'h27);
		dset(P_AY, 0, 8'h90); dset(P_AY, 1, 8'h90); dset(P_KBD, 1, 8'h80); dset(P_WG, 1, 8'h10); dset(P_WG, 0, 8'h14);
		dset(P_NOW, 1, 8'h2A); dset(P_W1, 1, 8'hE9); dset(P_PN, 1, 8'hC1);
		dset(P_EE, 0, 8'hEE); dset(P_EE, 1, 8'hEE);   // descriptor EE: MEM[EE] (2000 in 3.03a, 2041 in SCROLL)

		repeat (400) @(posedge clk);
		reset_nx = 1; dos_nx = 1;
		repeat (400) @(posedge clk);
		cmp_on = 1; slow_on = 1;
		// before the first IN: window 3 shows MEM[0] (page 0x40), OUTs do nothing
		m1cyc(16'h0000); mrd(16'hC000); mwr(16'hC123, 8'h55); iow(P_PN, 8'h07); m1cyc(16'hF000); idle(3);
		ior(P_KBD);                              // STARTING
		// 3.5 MHz first (TB_SW = 1 after reset, TURBO_HAND = 0)
		th_nx = 0;
		repeat (6) m1cyc(16'h0100);
		for (i = 0; i < 40; i = i + 1) rand_op;
		ior(P_HDD); ior(P_HDR); iow(P_HDR, 8'h12); ior(P_AY); iow(P_AY, 8'h07); ior(P_WG); iow(P_WG, 8'h33); ior(P_NOW);
		// turbo on
		th_nx = 1; repeat (4) m1cyc(16'h0200);
		// CNF: maps, PN5 reset / Pentagon-512 combinations, Scorpion off, TB_SW / AROM16 / SYS
		iow(P_PN, 8'hFF); iow(P_SC, 8'hFF); m1cyc(16'hC000); mrd(16'h0000);
		cnf(8'h24); iow(P_PN, 8'hFF); m1cyc(16'hC000);           // CNF5
		cnf(8'hA4); iow(P_PN, 8'hFF); m1cyc(16'hC000);           // CNF5 + CNF7
		cnf(8'h84); iow(P_PN, 8'hFF); m1cyc(16'hC000);           // CNF7
		cnf(8'h04); iow(P_PN, 8'hE5); m1cyc(16'hC000);
		cnf(8'h44); iow(P_SC, 8'h13); m1cyc(16'h0000);           // Scorpion off
		cnf(8'h04); iow(P_SC, 8'h13); m1cyc(16'h0000); mrd(16'h4000);
		cnf(8'h01); m1cyc(16'h0000); cnf(8'h00); m1cyc(16'h0000);   // AROM16
		cnf(8'h02); repeat (3) m1cyc(16'h0300); cnf(8'h03); repeat (3) m1cyc(16'h0300);   // TB_SW
		iow(P_CNF_S, 8'h00); m1cyc(16'h0000); iow(P_CNF, 8'h00); m1cyc(16'h0000);        // SYS
		for (j = 0; j < 4; j = j + 1) begin                       // the four port maps
			cnf({3'b000, j[1:0], 3'b100});
			ior(P_KBD); iow(P_PN, 8'h10 | j); ior(P_HDD); iow(P_W1, 8'h50 + j); mrd(16'h4100); mwr(16'h4200, 8'hAA);
		end
		// pages: graphics page in windows 1 / 2, Fx descriptor (DD = PG3), window 0 variants
		iow(P_W1, 8'h50); m1cyc(16'h4000); mrd(16'h5000); mwr(16'h6000, 8'h01);
		iow(P_W2, 8'h57); mrd(16'h8000); mwr(16'hA000, 8'h02); m1cyc(16'h8000);
		iow(P_W3, 8'h5C); mrd(16'hC000); mwr(16'hC000, 8'h03); iow(P_PN, 8'h05); mrd(16'hC000);
		iow(P_W0, 8'h33); m1cyc(16'h0000); mrd(16'h1000);
		ior(P_EE); iow(P_EE, 8'h2E); ior(P_EE); m1cyc(16'h0000); mrd(16'hC000);   // descriptor EE (MEM[EE])
		// HDD data register twice, a flip clear by DOUBLE_CAS
		ior(P_HDD); ior(P_HDD); iow(P_HDD, 8'h11); ior(P_HDD); ior(P_HDR); iow(P_HDR, 8'h22);
		for (j = 0; j < 3; j = j + 1) begin
			ior(P_HDD); idle(2); dcas_nx = 1; idle(2); dcas_nx = 0; idle(2); ior(P_HDD); ior(P_HDD); idle(2); dcas_nx = 1; idle(2); dcas_nx = 0; idle(2);
		end
		// SYS = 1: window 0 by SC0 / SC1 / AROM16 / PN4 / DOS / TEST_R
		use_sys = 1; cnf(8'h04);
		for (j = 0; j < 16; j = j + 1) begin
			iow(P_SC, {3'b000, j[3], 2'b00, j[1:0]}); iow(P_PN, {3'b000, j[2], 4'h0});
			if (j == 8) cnf(8'h01);
			if (j == 12) begin tr_nx = 1; idle(1); end
			m1cyc(16'h3D10); mrd(16'h0123); m1cyc(16'h0200); mwr(16'h1000, j[7:0]); m1cyc(16'h4100); mrd(16'h2000);
		end
		tr_nx = 0; cnf(8'h00);
		// DOS on / off
		iow(P_PN, 8'h10); m1cyc(16'h3D2F); mrd(16'h0000); ior(P_NOW); m1cyc(16'h4000); ior(P_NOW);
		inta; inta;
		// random, turbo
		for (i = 0; i < 800; i = i + 1) begin
			rand_op;
			if (i == 350) use_sys = 0; if (i == 650) use_sys = 1;
			if ((i % 200) == 100) cnf({$random(seed)} & 8'h1B | 8'h04);
			if ((i % 300) == 150) begin iow(P_W1, 8'h50 + (i & 7)); iow(P_W3, 8'h50 + (i & 15)); end
		end
		// 3.5 MHz with waits for NO_IO_WAIT ports
		th_nx = 0; cnf(8'h04);
		for (i = 0; i < 90; i = i + 1) begin rand_op; if ((i % 10) == 0) ior(P_NOW); end
		// mid-test reset: window 3 / OUTs before the first IN again
		idle(2); reset_nx = 0; dos_nx = 1; idle(20); reset_nx = 1; idle(4);
		m1cyc(16'h0000); mrd(16'hC000); iow(P_PN, 8'h07); ior(P_KBD); mrd(16'hC000);
		th_nx = 1; cnf(8'h03);
		for (i = 0; i < 200; i = i + 1) rand_op;
		idle(10);
		$display("tb_eq_dcp (%0s DCP vs sp_dcp%0s), %0t ns:", `PERS_NAME, $test$plusargs("mut") ? ", mutation" : "", $time);
		res_report; ras_cas_report; mc_report; ma_report; mca_report; clk_z80_report; turbo_report; wait_n_report;
		iom_report; dout_report; page_report; type_report; dcpp_report; ra_report; cs_report; port_report;
		pn_bits_report; wr_dwg_report; wr_tm9_report; wr_awg_report; rd_kp11_report; kp11_mix_report; ga_report;
		graf_report; sp_scr_report; hdd_data_report; hdd_flip_report;
		i_pn_report; i_cnf_report; i_sc_report; i_pgs_report;
		$display("  coverage: PN writes by (CNF7, CNF5) %0d %0d %0d %0d (DI5 = 1: %0d), CNF writes %0d, SC writes %0d (%0d with CNF6),",
			cv_pn[0], cv_pn[1], cv_pn[2], cv_pn[3], cv_pn5, cv_cnf, cv_sc, cv_scoff);
		$display("  MEM writes %0d, Fx descriptors %0d, HDD_FLIP clocks %0d (cleared by DOUBLE_CAS %0d), NO_IO_WAIT CEs %0d, INTA %0d,", cv_memwr,
			cv_fx, cv_flip, cv_dcas, cv_nio, cv_inta);
		$display("  CONTINUE = 0 stall CEs %0d, window-0 fetches with SYS = 1 %0d,", cv_cont, cv_sys);
		$display("  I/O cycles by (TURBO, TYPE) %0d %0d %0d %0d %0d %0d %0d %0d / %0d %0d %0d %0d %0d %0d %0d %0d", cv_wt[0], cv_wt[1], cv_wt[2],
			cv_wt[3], cv_wt[4], cv_wt[5], cv_wt[6], cv_wt[7], cv_wt[8], cv_wt[9], cv_wt[10], cv_wt[11], cv_wt[12], cv_wt[13], cv_wt[14], cv_wt[15]);
		$display("tb_eq_dcp: %0d errors%s", errors, weak ? " (some outputs never toggled)" : "");
		$finish;
	end
endmodule
