// tb_eq_acexm: the memory of OUR module. sp_acex sees its memory only through sp_sram (+ two IS61WV20488 models)
// and sp_sdram (+ an MT48LC16M16A2 model), with pad delays; the reference keeps the ideal models of tb_eq_acex with
// the same contents. Included into the module after the ideal models.

	// ---- pad delays (ns): FPGA out = IOB clock to pad + board, FPGA in = board + pad to IOB flip-flop
	parameter real T_SO = 7.0, T_SI = 3.0;            // SRAM (TS_SRAM_OUT 8 / TS_SRAM_IN 4 of core-archie)
	parameter real T_DO = 3.0, T_SKEW = 3.0, T_BACK = 2.5;   // SDRAM out, SD_CLK to the chip, DQ back
	localparam [20:0] ROM_W = 21'h040000, FAST_W = 21'h060000, LD_W = 21'h070000;

	// ---- our buses
	wire [7:0] d_u, vd0_u, vd1_u, vd2_u, vd3_u; wire [15:0] md_u;
	reg [7:0] d_ku = 8'hFF; reg [15:0] md_ku = 16'hFFFF;
	assign (weak0, weak1) d_u = d_ku; assign (weak0, weak1) md_u = md_ku;
	always @(d_u) d_ku = keep(d_ku, d_u); always @(md_u) md_ku = keep(md_ku, md_u);

	// ---- sp_sram and the two SRAM chips
	wire [7:0] cpu_q; wire cpu_rdy, wb_ovf; wire [31:0] pal_q;
	reg cpu_flush = 0;
	reg ld_req = 0; reg [20:0] ld_a = 0; reg [1:0] ld_be = 0; reg [15:0] ld_d = 0; wire ld_ack;
	wire [20:0] sr_a; wire [15:0] sr_do, sr_dt, sr_di; wire [1:0] sr_we, sr_oe;
	sp_sram #(.SIM_X(1)) u_sram(.CLK(clk), .CE(ce), .CE_N(ce_n), .CT(ct_ph), .VA_NX(va_nx), .V_WR_NX(v_wr_nx),
		.VA_MOD(va_mod), .MODE_RQ(mode_rq), .MLO_RQ(mlo_rq), .VA_ATR(va_atr), .ATR_ZX(atr_zx), .PIX_RQ(pix_rq),
		.VD0_O(vd0_o), .VD1_O(vd1_o), .VD2_O(vd2_o), .VD3_O(vd3_o), .VA(va_o), .VD0_I(vd0_u), .VD1_I(vd1_u),
		.VD2_I(vd2_u), .VD3_I(vd3_u), .PAL_Q(pal_q), .A(a), .RA(ra_o), .SEL_ROM(sel_rom), .SEL_CASH(sel_cash),
		.RF_N(rf_n), .MR_N(mr_n), .WR_N(wr_n), .CS_CASH(cs_cash_o), .CPU_D(d_u), .CPU_FLUSH(cpu_flush),
		.CPU_Q(cpu_q), .CPU_RDY(cpu_rdy), .LD_REQ(ld_req), .LD_A(ld_a), .LD_BE(ld_be), .LD_D(ld_d),
		.LD_ACK(ld_ack), .WB_OVF(wb_ovf), .SRAM_A(sr_a), .SRAM_D_O(sr_do), .SRAM_D_T(sr_dt), .SRAM_D_I(sr_di),
		.SRAM_WE_N(sr_we), .SRAM_OE_N(sr_oe));
	wire [20:0] sr_a_p; wire [15:0] sr_do_p, sr_dt_p; wire [1:0] sr_we_p, sr_oe_p; wire [15:0] sr_dq;
	assign #(T_SO) sr_a_p = sr_a; assign #(T_SO) sr_do_p = sr_do; assign #(T_SO) sr_dt_p = sr_dt;
	assign #(T_SO) sr_we_p = sr_we; assign #(T_SO) sr_oe_p = sr_oe;
	genvar gi;
	generate for (gi = 0; gi < 16; gi = gi + 1) begin : g_sdq
		assign sr_dq[gi] = sr_dt_p[gi] ? 1'bz : sr_do_p[gi];
	end endgenerate
	assign #(T_SI) sr_di = sr_dq;
	sram_is61 #(.NAME("SRAM D[7:0]")) u_slo(.A(sr_a_p), .DQ(sr_dq[7:0]), .WE_N(sr_we_p[0]), .OE_N(sr_oe_p[0]),
		.EXT_DRV(~sr_dt_p[0]));
	sram_is61 #(.NAME("SRAM D[15:8]")) u_shi(.A(sr_a_p), .DQ(sr_dq[15:8]), .WE_N(sr_we_p[1]), .OE_N(sr_oe_p[1]),
		.EXT_DRV(~sr_dt_p[8]));
	task sram_wr(input [20:0] w, input l, input [7:0] x); begin if (l) u_shi.mem[w] = x; else u_slo.mem[w] = x; end endtask
	function [7:0] sram_rd(input [20:0] w, input l); sram_rd = l ? u_shi.mem[w] : u_slo.mem[w]; endfunction

	// ---- sp_sdram and the SDRAM
	wire [15:0] sd_mdq; wire [1:0] sd_mddrv; wire sd_rdy;
	wire sd_clk, sd_cke, sd_cs, sd_ras, sd_cas, sd_we; wire [1:0] sd_ba, sd_dqm; wire [12:0] sd_a;
	wire [15:0] sd_dqo, sd_dqt, sd_dqi;
`ifndef REF_CYC_T
`define REF_CYC_T 6'd40
`endif
	sp_sdram #(.INIT_WAIT(16'd16), .REF_CYC(`REF_CYC_T)) u_sdram(.CLK(clk), .CE(ce), .CE_N(ce_n), .CT(ct_ph), .RAS_N(ras_o[0]),
		.CAS_N(cas_o), .WE_N(we_o), .MA(ma_o[11:0]), .MCA(mca_o), .MD_O(md_o), .MD_Q(sd_mdq), .MD_DRV(sd_mddrv),
		.RDY(sd_rdy), .AUX_REQ(1'b0), .AUX_ACK(), .SD_CLK(sd_clk), .SD_CKE(sd_cke), .SD_CS_N(sd_cs),
		.SD_RAS_N(sd_ras), .SD_CAS_N(sd_cas), .SD_WE_N(sd_we), .SD_BA(sd_ba), .SD_A(sd_a), .SD_DQM(sd_dqm),
		.SD_DQ_O(sd_dqo), .SD_DQ_T(sd_dqt), .SD_DQ_I(sd_dqi));
	wire sd_clk_p, sd_cke_p, sd_cs_p, sd_ras_p, sd_cas_p, sd_we_p; wire [1:0] sd_ba_p, sd_dqm_p; wire [12:0] sd_a_p;
	wire [15:0] sd_dqo_p, sd_dqt_p, sd_dq;
	assign #(T_SKEW) sd_clk_p = sd_clk;
	assign #(T_DO) sd_cke_p = sd_cke; assign #(T_DO) sd_cs_p = sd_cs; assign #(T_DO) sd_ras_p = sd_ras;
	assign #(T_DO) sd_cas_p = sd_cas; assign #(T_DO) sd_we_p = sd_we; assign #(T_DO) sd_ba_p = sd_ba;
	assign #(T_DO) sd_dqm_p = sd_dqm; assign #(T_DO) sd_a_p = sd_a; assign #(T_DO) sd_dqo_p = sd_dqo;
	assign #(T_DO) sd_dqt_p = sd_dqt;
	generate for (gi = 0; gi < 16; gi = gi + 1) begin : g_ddq
		assign sd_dq[gi] = sd_dqt_p[gi] ? 1'bz : sd_dqo_p[gi];
	end endgenerate
	assign #(T_BACK) sd_dqi = sd_dq;
	sdram_mt48 #(.PU_CLK(10)) u_sdm(.CLK(sd_clk_p), .CKE(sd_cke_p), .CS_N(sd_cs_p), .RAS_N(sd_ras_p), .CAS_N(sd_cas_p),
		.WE_N(sd_we_p), .BA(sd_ba_p), .A(sd_a_p), .DQM(sd_dqm_p), .DQ(sd_dq));
	integer sd_cont = 0;
	always @(clk) #1 if (sd_dqt_p[0] === 1'b0 && u_sdm.dq_o !== 16'hzzzz) sd_cont = sd_cont + 1;

	always @(posedge clk) if (cmp_on && u_sdram.e == 9 && u_sdram.act && we_o === 1'b0 && cas_o !== 4'hF)
		if ($test$plusargs("sdw")) $display("  DRAM write %0d ns: cas %b mca %b ma %h md %h", $time, cas_o, mca_o, ma_o, md_o);
	// ---- drivers of our buses
	// D: the Z80, our D_O, ROM / fastram through sp_sram (X until its byte is there), ISA: the ideal model
	wire fast_o = cs_cash_o === 1'b0 && ra_o[3:2] == 2'b01;
	wire cs_mem_u = (cs_rom_o === 1'b0 || fast_o) && rd_n === 1'b0;
	assign d_u = z_drv ? z_do : 8'bz;
	assign d_u = d_oe_o ? d_o : 8'bz;
	assign d_u = cs_mem_u ? (cpu_rdy ? cpu_q : 8'hxx) : 8'bz;
	assign d_u = (cs_cash_o === 1'b0 && !fast_o && rd_n === 1'b0) ? cache_q : 8'bz;
	// MD: our MD_O, the SDRAM word (sp_sdram lanes), the peripherals as for the reference (by our pins)
	assign md_u = md_oe_o ? md_o : 16'hzzzz;
	assign md_u[7:0]  = sd_mddrv[0] ? sd_mdq[7:0] : 8'hzz;
	assign md_u[15:8] = sd_mddrv[1] ? sd_mdq[15:8] : 8'hzz;
	wire per_on_u = ~io_n & ~rd_n & ras_o[0] & (cas_o === 4'hF);
	wire per_en_u; assign #(30, 0) per_en_u = per_on_u;
	assign md_u = (per_on_u & per_en_u) ? periph : 16'hzzzz;
	// ROM pokes of the Z80 model (op): sp_sram forgets its fetched byte
	event flush_ev;
	always @(flush_ev) begin cpu_flush = 1; @(posedge clk); #1 cpu_flush = 0; end

	// ---- loader traffic: random writes into a free region (words LD_W .. +4095) in the free slots
	reg [15:0] ld_exp [0:4095]; reg ld_run = 0; integer n_ld = 0, ld_seed = 99;
	always @(posedge clk) begin
		if (ld_ack) begin
			if (ld_be[0]) ld_exp[ld_a[11:0]][7:0] <= ld_d[7:0];
			if (ld_be[1]) ld_exp[ld_a[11:0]][15:8] <= ld_d[15:8];
			n_ld <= n_ld + 1;
		end
		if (ld_run && (!ld_req || ld_ack)) begin
			ld_req <= 1; ld_a <= LD_W | ({$random(ld_seed)} & 4095); ld_d <= $random(ld_seed);
			ld_be <= ((ld_seed & 7) == 0) ? 2'b01 : ((ld_seed & 7) == 1) ? 2'b10 : 2'b11;
		end else if (!ld_run && ld_ack) ld_req <= 0;
	end

	// ---- initial contents of our memories = the ideal models' (after the mode table and the port table)
	task init_mem; integer b, w; reg [21:0] i; reg [7:0] x; begin
		for (b = 0; b < 262144; b = b + 1) begin                       // video RAM: byte {VA, lane}
			x = (vram[b] === 8'hxx) ? dflt(b, 8'd5) : vram[b]; sram_wr(b >> 1, b[0], x);
		end
		for (b = 0; b < 262144; b = b + 1) begin                       // ROM
			x = (rom[b] === 8'hxx) ? dflt(b, 8'd1) : rom[b]; sram_wr(ROM_W | (b >> 1), b[0], x);
		end
		for (b = 0; b < 65536; b = b + 1) begin                        // fastram = cache[{01, ROM_RG[1:0], A}]
			i = {6'd1, b[15:0]};
			x = (cache[i] === 8'hxx) ? dflt(i, 8'd2) : cache[i]; sram_wr(FAST_W | (b >> 1), b[0], x);
		end
		for (b = 0; b < 2048; b = b + 1) begin                         // palette shadow: VA {b[10:3], 11111, b[2:0]}
			i = {b[10:3], 5'b11111, b[2:0], 2'd0};
			u_sram.pal0[b] = (vram[i] === 8'hxx) ? dflt(i, 8'd5) : vram[i];
			u_sram.pal1[b] = (vram[i | 1] === 8'hxx) ? dflt(i | 1, 8'd5) : vram[i | 1];
			u_sram.pal2[b] = (vram[i | 2] === 8'hxx) ? dflt(i | 2, 8'd5) : vram[i | 2];
			u_sram.pal3[b] = (vram[i | 3] === 8'hxx) ? dflt(i | 3, 8'd5) : vram[i | 3];
		end
		for (w = 0; w < 4096; w = w + 1) begin
			ld_exp[w] = w * 16'h9E37; sram_wr(LD_W | w, 0, ld_exp[w][7:0]); sram_wr(LD_W | w, 1, ld_exp[w][15:8]);
		end
		for (w = 0; w < 2097152; w = w + 1) begin                      // SDRAM word {bank, row, col} = DRAM lanes
			i = {w[20], 1'b0, w[19:0]};
			u_sdm.mem[w][7:0] = (dram[i] === 8'hxx) ? ddef(i) : dram[i];
			i = {w[20], 1'b1, w[19:0]};
			u_sdm.mem[w][15:8] = (dram[i] === 8'hxx) ? ddef(i) : dram[i];
		end
	end endtask

	// ================= checks that the equivalence cannot see
	// the edge number c0..c11 at a posedge (as in sp_sram)
	function [3:0] edge_no(input c, input [2:0] t); reg [3:0] f; begin
		case (t) 3'd5: f = 0; 3'd6: f = 2; 3'd0: f = 4; 3'd1: f = 6; 3'd2: f = 8; default: f = 10; endcase
		edge_no = c ? f : (f == 0 ? 11 : f - 1);
	end endfunction
	wire [3:0] e_now = edge_no(ce, ct_ph);
	integer n_cm = 0, x_cm = 0, n_dp = 0, x_dp = 0, n_pal = 0, x_pal = 0, n_w = 0, x_w = 0, n_cpu = 0, x_cpu = 0;
	integer n_rd9 = 0, n_dps = 0, n_md = 0, x_md = 0, x_mdu = 0, n_early = 0, n_rcap = 0, x_rcap = 0;
	real slack_min = 100.0;
	reg [31:0] rdp = 0; reg [3:0] w_pred = 4'hF; reg wcol_p = 0; reg ref_drd = 0;
	realtime t_ap = 0, t_oep = 0;
	always @(sr_a_p) t_ap = $realtime;
	always @(negedge sr_oe_p[0]) t_oep = $realtime;
	always @(posedge clk) begin
		if (ce_n) rdp <= {vd3, vd2, vd1, vd0};
		if (cmp_on) begin
			// MODE0..2 take VDM3..1 at the rise of WR_MODE: what the reference bus has there
			if (ce && dut.SVIDEO.wr_mode_rise) begin
				n_cm = n_cm + 1;
				if ({dut.vd3, dut.vd2, dut.vd1} !== {vd3, vd2, vd1}) begin
					x_cm = x_cm + 1;
					if (x_cm <= 3) $display("  MODE load at %0d ns: ours %h%h%h ref %h%h%h", $time, dut.vd3, dut.vd2, dut.vd1, vd3, vd2, vd1);
				end
			end
			// D_PIC0 / DCOL take the byte DFF(VLA[1:0]) of D_PICx_ (the bus at the last CE_N)
			// (a D_PIC0 load is checked only when D_PIC0 can be seen: ZX now or in the last slot, MODE0[4] | X_MODE4, or
			// cycle 0 of 16-colour graphics (a ZX / text half-cell with MODE0[5] may follow, docs/memtiming.md 8.3);
			// otherwise sp_sram does not fetch it, by design: PIX_RQ)
			if (ce && !dut.SVIDEO.lwr_pic && dut.SVIDEO.ld_pic && !(dut.SVIDEO.mode0[4] | dut.SVIDEO.x_mode[4]) &&
			    !(!dut.SVIDEO.mode0[5] && dut.SVIDEO.ct_e[5:3] == 3'd0)) n_dps = n_dps + 1;
			else if (ce && ((!dut.SVIDEO.lwr_pic && dut.SVIDEO.ld_pic) || (!dut.SVIDEO.lwr_col && !dut.SVIDEO.blank && !dut.SVIDEO.bordp))) begin
				n_dp = n_dp + 1;
				if (dut.SVIDEO.dpicx !== rdp[8 * dut.SVIDEO.vla_d +: 8]) begin
					x_dp = x_dp + 1;
					if (x_dp <= 3) $display("  D_PIC0 / DCOL load at %0d ns (pic %b col %b): ours %h ref %h", $time,
						!dut.SVIDEO.lwr_pic, !dut.SVIDEO.lwr_col, dut.SVIDEO.dpicx, rdp[8 * dut.SVIDEO.vla_d +: 8]);
				end
			end
			// the write lanes taken at c11 are the V_WR of c0..c1
			if (e_now == 11) w_pred <= ~u_sram.wl;
			if (e_now == 1 && cmp_vwr && (v_wr_o !== 4'hF || w_pred !== 4'hF)) begin
				n_w = n_w + 1;
				if (v_wr_o !== w_pred) begin x_w = x_w + 1; if (x_w <= 3) $display("  V_WR at %0d ns: %b, taken at c11 %b", $time, v_wr_o, w_pred); end
			end
			// the SDRAM word at c13 (DO / XMD) and c14 (DCPP), in the lanes the DRAM of the reference drove
			if ((e_now == 1 || e_now == 2) && sd_mddrv != 2'b00 && ref_drd) begin
				n_md = n_md + 1;
				if ((md_u & {{8{sd_mddrv[1]}}, {8{sd_mddrv[0]}}}) !== (md & {{8{sd_mddrv[1]}}, {8{sd_mddrv[0]}}})) begin
					x_md = x_md + 1;
					if (x_md <= 3) $display("  DRAM word at c%0d %0d ns: ours %h ref %h (lanes %b)", 12 + e_now, $time, md_u, md, sd_mddrv);
				end
			end
			// READ at c9: CAS_ at c8 with WE_N high (a blocked write; the DRAM of the original reads)
			if (u_sdram.e == 9 && u_sdram.act && !u_sdram.done && we_o === 1'b1 && u_sdram.lanes != 2'b00) n_rd9 = n_rd9 + 1;
			// DRAM accesses before the SDRAM is ready
			if (e_now == 5 && !sd_rdy && ras_o[0] === 1'b0) n_early = n_early + 1;
			// SRAM capture: a read slot that ends here; slack of the data at the input flip-flop
			if (e_now[0] && u_sram.tag_cur != 0 && u_sram.oe_n == 2'b00) begin
				n_rcap = n_rcap + 1;
				if ($realtime - ((t_ap + u_slo.T_AA > t_oep + u_slo.T_DOE) ? t_ap + u_slo.T_AA : t_oep + u_slo.T_DOE) - T_SI < slack_min)
					slack_min = $realtime - ((t_ap + u_slo.T_AA > t_oep + u_slo.T_DOE) ? t_ap + u_slo.T_AA : t_oep + u_slo.T_DOE) - T_SI;
				if (^sr_di === 1'bx) begin x_rcap = x_rcap + 1; if (x_rcap <= 3) $display("  SRAM read X at the capture, %0d ns", $time); end
			end
		end
		if (e_now == 5) ref_drd <= 0;
	end
	always @(negedge clk) if (dr_rd) ref_drd <= 1;
	// the palette DAC latch at the rise of WR_COL: our shadow against the reference bus
	always @(negedge clk) begin
		if (cmp_on && wr_col_o && !wcol_p) begin
			n_pal = n_pal + 1;
			if (pal_q !== {vd3, vd2, vd1, vd0}) begin
				x_pal = x_pal + 1;
				if (x_pal <= 3) $display("  palette at %0d ns (VA %h): shadow %h ref %h", $time, va_o, pal_q, {vd3, vd2, vd1, vd0});
			end
		end
		wcol_p <= wr_col_o;
		if (cmp_on && ^md_u === 1'bx) begin x_mdu = x_mdu + 1; if (x_mdu <= 3) $display("  X on our MD at %0d ns: %h", $time, md_u); end
	end
	// CPU read data: from the T80 latch (end of T2: edge c_f+5 for the cache, c_f+13 for the ROM, c_f = the CE
	// after which CS is low) to the rise of CS our D_I must be the reference's D; ISA cycles excluded. cpu_k = k
	// after the edge c_f+k: the negedge sample with cpu_k = 4 is the value the edge c_f+5 takes.
	// (TB_MEM_CPU_WAIT: a testbench with the real CPU on the /WAIT of sp_sram, CPU_WAIT_N; a cycle where the T80
	// sampled it low, at a CE_N where CLKZ1 falls, is left to that testbench's own check at the T80 latch, cpu_wt)
	integer cpu_k = 0; reg cpu_on = 0, cpu_rom = 0, cpu_wt = 0;
	always @(posedge clk) begin
		if (!cpu_on && (cs_rom_o === 1'b0 || fast_o)) begin cpu_on = 1; cpu_rom = cs_rom_o === 1'b0; cpu_k = 0; cpu_wt = 0; end
		else if (cpu_on && !(cs_rom_o === 1'b0 || fast_o)) cpu_on = 0;
		cpu_k = cpu_k + 1;
`ifdef TB_MEM_CPU_WAIT
		if (cpu_on && ce_n && clkz_o && !clkz_nx_o && u_sram.CPU_WAIT_N === 1'b0) cpu_wt = 1;   // T80 samples it
`endif
	end
	always @(negedge clk) if (cmp_on && cpu_on && !cpu_wt && rd_n === 1'b0 && cpu_k >= (cpu_rom ? 12 : 4)) begin
		n_cpu = n_cpu + 1;
		if (d_u !== d) begin
			x_cpu = x_cpu + 1;
			if (x_cpu <= 5) $display("  CPU %0s byte at c_f+%0d, %0d ns (A %h RA %h): ours %h ref %h", cpu_rom ? "ROM" : "cache",
				cpu_k + 1, $time, a, ra_o, d_u, d);
		end
	end

	// ---- end of the run: our memories against the ideal ones
	integer m_v, m_r, m_f, m_p, m_d, m_l;
	task mem_report; integer b, w; reg [21:0] i; reg [7:0] x, y; begin
		m_v = 0; m_r = 0; m_f = 0; m_p = 0; m_d = 0; m_l = 0;
		for (b = 0; b < 262144; b = b + 1) begin
			x = (vram[b] === 8'hxx) ? dflt(b, 8'd5) : vram[b];
			if (sram_rd(b >> 1, b[0]) !== x) m_v = m_v + 1;
			x = (rom[b] === 8'hxx) ? dflt(b, 8'd1) : rom[b];
			if (sram_rd(ROM_W | (b >> 1), b[0]) !== x) m_r = m_r + 1;
		end
		for (b = 0; b < 65536; b = b + 1) begin
			i = {6'd1, b[15:0]}; x = (cache[i] === 8'hxx) ? dflt(i, 8'd2) : cache[i];
			if (sram_rd(FAST_W | (b >> 1), b[0]) !== x) m_f = m_f + 1;
		end
		for (b = 0; b < 2048; b = b + 1) begin
			i = {b[10:3], 5'b11111, b[2:0], 2'd0};
			if (u_sram.pal0[b] !== sram_rd(i >> 1, 0) || u_sram.pal1[b] !== sram_rd(i >> 1, 1) ||
			    u_sram.pal2[b] !== sram_rd((i >> 1) | 1, 0) || u_sram.pal3[b] !== sram_rd((i >> 1) | 1, 1)) m_p = m_p + 1;
		end
		for (w = 0; w < 4096; w = w + 1) if ({sram_rd(LD_W | w, 1), sram_rd(LD_W | w, 0)} !== ld_exp[w]) m_l = m_l + 1;
		for (w = 0; w < 2097152; w = w + 1) begin
			i = {w[20], 1'b0, w[19:0]}; x = (dram[i] === 8'hxx) ? ddef(i) : dram[i];
			i = {w[20], 1'b1, w[19:0]}; y = (dram[i] === 8'hxx) ? ddef(i) : dram[i];
			if (u_sdm.mem[w] !== {y, x}) begin
				m_d = m_d + 1;
				if (m_d <= 4) $display("    SDRAM word %h (bank %0d row %h col %h): ours %h ref %h", w, w[20], w[19:9], w[8:0], u_sdm.mem[w], {y, x});
			end
		end
		u_sdm.final_check;
		$display("  memory checks: MODE loads %0d (bad %0d), D_PIC0 / DCOL loads %0d (bad %0d; D_PIC0 not visible, not fetched %0d), palette latches %0d (bad %0d),",
			n_cm, x_cm, n_dp, x_dp, n_dps, n_pal, x_pal);
		$display("    video writes %0d (lanes bad %0d), CPU bytes %0d (bad %0d), DRAM words at c13 / c14 %0d (bad %0d), X on our MD %0d,",
			n_w, x_w, n_cpu, x_cpu, n_md, x_md, x_mdu);
		$display("    SRAM reads %0d (X %0d, slack min %0.2f ns), loader writes %0d, cache write buffer overflow %0d, DRAM cycles before SDRAM ready %0d",
			n_rcap, x_rcap, slack_min, n_ld, wb_ovf, n_early);
		$display("    SDRAM READ at c9 (blocked writes) %0d", n_rd9);
		$display("    SRAM: writes %0d + %0d, violations %0d + %0d (contention %0d + %0d); SDRAM: ACT %0d RD %0d WR %0d PRE %0d REF %0d, violations %0d, max refresh gap %0.2f us, DQ contention %0d",
			u_slo.n_wr, u_shi.n_wr, u_slo.viol, u_shi.viol, u_slo.n_cont, u_shi.n_cont, u_sdm.n_act, u_sdm.n_rd,
			u_sdm.n_wr, u_sdm.n_pre, u_sdm.n_ref, u_sdm.viol, u_sdm.ref_gap / 1000.0, sd_cont);
		$display("    end of run: video RAM %0d, ROM %0d, fastram %0d, palette shadow %0d, loader region %0d, SDRAM %0d differing",
			m_v, m_r, m_f, m_p, m_l, m_d);
		errors = errors + x_cm + x_dp + x_pal + x_w + x_cpu + x_md + x_mdu + x_rcap + wb_ovf + n_early + u_slo.viol +
			u_shi.viol + u_sdm.viol + sd_cont + m_v + m_r + m_f + m_p + m_l + m_d;
	end endtask
