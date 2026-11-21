// tb_cpu_acexm: the three blocks together. The real CPU (sp_z84c15, T80pa) runs cpu_acex.asm and drives both our
// sp_acex and the BASE_303 netlist (3.03a), as tb_cpu_acex; our sp_acex sees its memory only through sp_sram (+ two
// IS61WV20488 models) and sp_sdram (+ an MT48LC16M16A2 model) with pad delays, as tb_eq_acexm (mem/tb_mem.vh); the
// reference keeps the ideal models (those of tb_eq_acexm: the DRAM writes a lane from the sample after its CAS_ fall).
// The CPU takes its data from OUR bus (d_u: ROM / fastram through sp_sram, DRAM bytes from sp_sdram through our D_O,
// our port data); +cpuref feeds it the reference bus instead (debug). The CPU loop is closed on ours: CLKZ1 /
// CLKZ1_NX, /WAIT = our WAIT_N_OE AND the CPU_WAIT_N of sp_sram (a fastram / ROM byte that would be late), /INT /
// /NMI = MA[13] / MA[12] latched at the rise of our WR_AWG and cleared by /RESET (the board: DD16 74ALS174 + DD17
// open-collector inverters, docs/z84c15.md 8.7), /RESET = the MAX model.
// Checks: the equivalence of every output (EQ_CMP at latency 0; D / MD where the ACEX drives them, as tb_eq_acexm),
// the program log, the bus shape of the CPU, X on the reference buses, the memory checks of tb_mem.vh (MODE /
// D_PIC0 / DCOL loads, palette shadow at WR_COL, CPU bytes from the T80s latch to the CS rise, SDRAM words at c13 /
// c14, write lanes, model protocol checks, all memories at the end) and, here: every byte the T80pa really takes
// (the CE_N where it raises /RD: opcode at the rise of T3, read data at the fall of T3) on our bus against the
// reference bus, by kind (ROM / cache / DRAM M1 / RD, I/O); the byte the cache write buffer of sp_sram takes against
// the byte at the rise of /WR; the waits of sp_sram the T80 sampled (by c_f and the video requests; a stuck wait is
// an error); a histogram of the cache M1 cycles by c_f and the video requests of that cycle; MA[14..12] across the
// WR_AWG rise. The first X the T80 takes prints the last 32 CLK of the sp_sram arbiter and ends the run (+nolstop).
// The ideal DRAM of the reference also drives MD in a CPU write the ACEX blocked (see dr_rd).
// +scen=N as tb_cpu_acex (0 ports / pages, 1 interrupts, 2 accelerator / 3.5 MHz, 3 video RAM + fastram, 4 vertical
// accelerator modes from DRAM as Flex Navigator). +logt: the time of every log entry, +m1t: every M1 address.
// Debug: vvp -n build/tb_cpu_acexm.vvp +scen=N [+stop] [+dbg=<ns>] [+cpuref] [+nolstop]
`timescale 1ns/1ps
`include "eq_cmp.vh"
module tb_cpu_acexm;
	reg clk = 0; always #5.952 clk = ~clk;            // 84 MHz
	reg clk42 = 0; always @(posedge clk) clk42 <= ~clk42;
	wire ce = ~clk42, ce_n = clk42;
	reg cmp_on = 0, cmp_vwr = 0;
	integer errors = 0, weak = 0;
	integer seed = 7;
	integer scen = 0;                                 // +scen=0 bus, 1 sync / CBL / soft reset, 2 keyboard
	reg kb_done = 0;

	// ---- the CPU: pins and their values after the next CE
	wire m1_n, rf_n, io_n, wr_n, rd_n, mr_n, halt_n, m1_nx, rf_nx, io_nx, wr_nx, rd_nx, mr_nx;
	wire [15:0] a, a_nx; wire [7:0] cpu_do; wire cpu_doe;
	reg res_drv = 0;                                  // the MAX on /RESET: 0 = pull low
	reg int_l = 0, nmi_l = 0;                         // the external latch of MA[13..12]

	// ---- pins of the reference
	wire clkz_r, cs_rom_r, cs_cash_r, wr_col_r, dac_data_r, dac_ws_r, dac_bck_r, we_r, xacs_r, sxa_r, rdxa_r;
	wire wr_awg_r, rd_kmps_r, wr_dwg_r;
	wire [3:0] ra_r, v_wr_r, cas_r; wire [1:0] v_cs_r, ras_r; wire [15:0] va_r; wire [14:0] ma_r;
	wire wait_w, res_w; pullup(wait_w); pullup(res_w);
	assign res_w = res_drv ? 1'bz : 1'b0;
	wire [7:0] d, vd0, vd1, vd2, vd3; wire [15:0] md; wire [2:0] xa; wire xa3;
	// keepers
	reg [7:0] d_k = 8'hFF, vd0_k = 8'hFF, vd1_k = 8'hFF, vd2_k = 8'hFF, vd3_k = 8'hFF; reg [15:0] md_k = 16'hFFFF;
	reg [2:0] xa_k = 3'b111;
	assign (weak0, weak1) d = d_k; assign (weak0, weak1) md = md_k; assign (weak0, weak1) xa = xa_k;
	assign (weak0, weak1) vd0 = vd0_k; assign (weak0, weak1) vd1 = vd1_k;
	assign (weak0, weak1) vd2 = vd2_k; assign (weak0, weak1) vd3 = vd3_k;
	// a keeper takes only driven 0 / 1 (an X of a conflict or of the power-up is not kept)
	function [15:0] keep(input [15:0] k, input [15:0] v); integer i; begin
		for (i = 0; i < 16; i = i + 1) keep[i] = (v[i] === 1'b0 || v[i] === 1'b1) ? v[i] : k[i];
	end endfunction
	always @(d) d_k = keep(d_k, d); always @(md) md_k = keep(md_k, md); always @(xa) xa_k = keep(xa_k, xa);
	always @(vd0) vd0_k = keep(vd0_k, vd0); always @(vd1) vd1_k = keep(vd1_k, vd1);
	always @(vd2) vd2_k = keep(vd2_k, vd2); always @(vd3) vd3_k = keep(vd3_k, vd3);

	BASE_303 ref(.TG42(clk42), .CLKZ1(clkz_r), .\/WAIT (wait_w), .\/RESET (res_w), .\/M1 (m1_n), .\/RF (rf_n),
		.\/IO (io_n), .\/WR (wr_n), .\/RD (rd_n), .\/MR (mr_n), .\/HALT (1'b1), .A(a), .D(d), .CS_ROM(cs_rom_r),
		.CS_CASH(cs_cash_r), .RA(ra_r), .V_CS(v_cs_r), .VA(va_r), .V_WR(v_wr_r), .VD3(vd3), .VD2(vd2), .VD1(vd1),
		.VD0(vd0), .WR_COL(wr_col_r), .DAC_DATA(dac_data_r), .DAC_WS(dac_ws_r), .DAC_BCK(dac_bck_r), .MD(md),
		.MA(ma_r), .RAS_(ras_r), .CAS_(cas_r), .\/WE (we_r), .XACS(xacs_r), .XA(xa), .XA3(xa3), .SXA(sxa_r),
		.RDXA(rdxa_r), .WR_AWG(wr_awg_r), .RD_KMPS(rd_kmps_r), .WR_DWG(wr_dwg_r));
	// output enables of the bidirectional pins (netlist I/O buffers)
	wire d_oe_r = ref.\D[0]~output .oe;
	wire md_oe_r = ref.\MD[0]~output .oe;
	wire [3:0] vd_oe_r = {ref.\VD3[0]~output .oe, ref.\VD2[0]~output .oe, ref.\VD1[0]~output .oe, ref.\VD0[0]~output .oe};
	wire xa_oe_r = ref.\XA[2]~output .oe;
	wire res_oe_r = ~ref.\/RESET~output .i;          // open drain
	wire wait_oe_r = ref.\/WAIT~output .oe;

	// ---- ours
	wire clkz_o, clkz_nx_o, wait_oe_o, res_oe_o, cs_rom_o, cs_cash_o, wr_col_o, dac_data_o, dac_ws_o, dac_bck_o, we_o, xacs_o;
	wire sxa_o, rdxa_o, wr_awg_o, rd_kmps_o, wr_dwg_o, d_oe_o, md_oe_o, xa_oe_o;
	wire [3:0] ra_o, v_wr_o, cas_o, vd_oe_o; wire [1:0] v_cs_o, ras_o; wire [15:0] va_o, md_o; wire [14:0] ma_o;
	wire [7:0] d_o, vd0_o, vd1_o, vd2_o, vd3_o; wire [2:0] xa_o;
	wire [2:0] ct_ph; wire [17:1] va_nx, va_atr; wire [3:0] v_wr_nx; wire [15:0] va_mod; wire [1:0] mca_o;
	wire mode_rq, mlo_rq, atr_zx, pix_rq, sel_rom, sel_cash;
	sp_acex #(.MIF_DCP("../../rtl/acex/mif/dcp.hex"), .MIF_AY("../../rtl/acex/mif/ay.hex"),
		.MIF_KBD("../../rtl/acex/mif/kbd_ini2.hex")) dut(.CLK(clk), .CE(ce), .CE_N(ce_n),
		.M1_N(m1_n), .RF_N(rf_n), .IO_N(io_n), .WR_N(wr_n), .RD_N(rd_n), .MR_N(mr_n),
		.M1_N_NX(m1_nx), .RF_N_NX(rf_nx), .IO_N_NX(io_nx), .WR_N_NX(wr_nx), .RD_N_NX(rd_nx), .MR_N_NX(mr_nx),
		.A(a), .D_I(d_u), .D_O(d_o), .D_OE(d_oe_o), .CLKZ1(clkz_o), .CLKZ1_NX(clkz_nx_o), .WAIT_N_OE(wait_oe_o), .RESET_N_I(res_drv),
		.RESET_N_OE(res_oe_o), .CS_ROM(cs_rom_o), .CS_CASH(cs_cash_o), .RA(ra_o), .V_CS(v_cs_o), .VA(va_o),
		.V_WR(v_wr_o), .VD0_I(vd0_u), .VD1_I(vd1_u), .VD2_I(vd2_u), .VD3_I(vd3_u), .VD0_O(vd0_o), .VD1_O(vd1_o),
		.VD2_O(vd2_o), .VD3_O(vd3_o), .VD_OE(vd_oe_o), .WR_COL(wr_col_o), .DAC_DATA(dac_data_o), .DAC_WS(dac_ws_o),
		.DAC_BCK(dac_bck_o), .MD_I(md_u), .MD_O(md_o), .MD_OE(md_oe_o), .MA(ma_o), .RAS_(ras_o), .CAS_(cas_o),
		.WE_N(we_o), .XACS(xacs_o), .XA_I(xa), .XA_O(xa_o), .XA_OE(xa_oe_o), .XA3(xa3), .SXA(sxa_o),
		.RDXA(rdxa_o), .WR_AWG(wr_awg_o), .RD_KMPS(rd_kmps_o), .WR_DWG(wr_dwg_o),
		.CT_PH(ct_ph), .VA_NX(va_nx), .V_WR_NX(v_wr_nx), .VA_MOD(va_mod), .MODE_RQ(mode_rq), .MLO_RQ(mlo_rq),
		.VA_ATR(va_atr), .ATR_ZX(atr_zx), .PIX_RQ(pix_rq), .MCA(mca_o), .SEL_ROM(sel_rom), .SEL_CASH(sel_cash), .CFG_RST(1'b0));
	// power-up: the modules start their preset registers high, as the netlist (CTH = 50, CTV = 290, KB_CT = 7 ...)
	// our pins as the reference's pins would be
	// D / MD compared where the ACEX drives them (the memories answer at other times than the ideal models)
	wire [7:0] d_pin_o = d_oe_o ? d_o : 8'h00, d_pin_r = d_oe_r ? d : 8'h00;
	wire [15:0] md_pin_o = md_oe_o ? md_o : 16'h0000, md_pin_r = md_oe_r ? md : 16'h0000;
	// the Z80 drive under the names of tb_mem.vh
	wire z_drv = cpu_doe; wire [7:0] z_do = cpu_do;

	// ================= models
	// ---- Z80 Z drive, ROM, cache
	// memories start unwritten (X): a read of an unwritten byte returns a fixed pseudo-random value (no init loops)
	function [7:0] dflt(input [23:0] i, input [7:0] salt); reg [31:0] x; begin
		x = ({8'd0, i} ^ {salt, 24'd0}) * 32'h9E3779B1; dflt = x[31:24] ^ x[18:11];
	end endfunction
	reg [7:0] rom [0:262143], cache [0:262143];
	assign d = cpu_doe ? cpu_do : 8'bz;
	wire [17:0] rom_a = {ra_r, a[13:0]};
	wire [7:0] rom_q, cache_q;
	assign #2 rom_q = (rom[rom_a] === 8'hxx) ? dflt(rom_a, 8'd1) : rom[rom_a];
	assign #2 cache_q = (cache[rom_a] === 8'hxx) ? dflt(rom_a, 8'd2) : cache[rom_a];
	assign d = (cs_rom_r === 1'b0 && rd_n === 1'b0) ? rom_q : 8'bz;
	assign d = (cs_cash_r === 1'b0 && rd_n === 1'b0) ? cache_q : 8'bz;
	integer n_cwr = 0;
	always @(negedge clk) if (cs_cash_r === 1'b0 && wr_n === 1'b0 && cpu_doe) begin cache[rom_a] <= d; n_cwr = n_cwr + 1; end

	// ---- DRAM: index {bank, lane, row[10:0], col[8:0]} (row[11] = col[11..10] = 0, col[9] = row[10] always)
	reg [7:0] dram [0:4194303];
	function [21:0] didx(input b, input l, input [11:0] r, input [11:0] c);
		didx = {b, l, r[10:0], c[8:0]};
	endfunction
	reg [11:0] row = 0, col = 0; reg ras_p = 1; reg [3:0] cas_p = 4'hF; reg ras_cyc = 0;
	always @(negedge clk) begin
		if (ras_p & ~ras_r[0]) begin row <= ma_r[11:0]; ras_cyc <= cas_r === 4'hF; end
		else if (ras_r[0] !== 1'b0) ras_cyc <= 1'b0;
		if (cas_p == 4'hF && cas_r !== 4'hF && ras_r[0] === 1'b0) col <= ma_r[11:0];
		ras_p <= ras_r[0]; cas_p <= cas_r;
	end
	// (tb_cpu_acexm: the DRAM drives MD in every read cycle the ACEX does not drive MD itself, also in a CPU write
	// the ACEX blocked (WE_N high: page 54, ROM ...) as the original DRAM and sp_sdram do; tb_eq_acex gates by the
	// CPU write instead, which left the reference MD at its keeper there and DO loaded different bytes)
	wire dr_rd = ras_cyc & ~ras_r[0] & we_r & ~md_oe_r;
	// an unwritten byte: random, in page 0x40 (column 0x40, the port table) a random descriptor of the pick list
	reg [7:0] pick [0:31];
	function [7:0] ddef(input [21:0] i); begin
		ddef = (i[7:0] == 8'h40) ? pick[dflt({2'b00, i}, 8'd4) & 31] : dflt({2'b00, i}, 8'd3);
	end endfunction
	wire [21:0] di0 = didx(1'b0, 1'b0, row, col), di1 = didx(1'b0, 1'b1, row, col);
	wire [21:0] di2 = didx(1'b1, 1'b0, row, col), di3 = didx(1'b1, 1'b1, row, col);
	wire [7:0] dq0 = (dram[di0] === 8'hxx) ? ddef(di0) : dram[di0], dq1 = (dram[di1] === 8'hxx) ? ddef(di1) : dram[di1];
	wire [7:0] dq2 = (dram[di2] === 8'hxx) ? ddef(di2) : dram[di2], dq3 = (dram[di3] === 8'hxx) ? ddef(di3) : dram[di3];
	assign #3 md[7:0]  = (dr_rd & ~cas_r[0]) ? dq0 : (dr_rd & ~cas_r[2]) ? dq2 : 8'bz;
	assign #3 md[15:8] = (dr_rd & ~cas_r[1]) ? dq1 : (dr_rd & ~cas_r[3]) ? dq3 : 8'bz;
	integer n_dwr = 0, n_drd = 0, n_rf = 0;
	// (as tb_eq_acexm: a lane is written only from the sample after its CAS_ fall, when col holds the column)
	always @(negedge clk) if (ras_cyc && ras_r[0] === 1'b0 && we_r === 1'b0) begin
		if (cas_r[0] === 1'b0 && cas_p[0] === 1'b0) dram[didx(1'b0, 1'b0, row, col)] <= md[7:0];
		if (cas_r[1] === 1'b0 && cas_p[1] === 1'b0) dram[didx(1'b0, 1'b1, row, col)] <= md[15:8];
		if (cas_r[2] === 1'b0 && cas_p[2] === 1'b0) dram[didx(1'b1, 1'b0, row, col)] <= md[7:0];
		if (cas_r[3] === 1'b0 && cas_p[3] === 1'b0) dram[didx(1'b1, 1'b1, row, col)] <= md[15:8];
	end
	reg we_p = 1;
	always @(negedge clk) begin
		if (we_p & ~we_r) n_dwr = n_dwr + 1;
		we_p <= we_r;
		if (ras_p & ~ras_r[0]) begin if (cas_r === 4'hF) n_drd = n_drd + 1; else n_rf = n_rf + 1; end
	end
	// peripherals on MD in I/O reads, from 30 ns after the DRAM cycle (the bus keeps the DRAM byte till then: DO
	// takes it at the CE_N after the CAS_ rise)
	reg [15:0] periph = 16'h1234;
	wire per_on = ~io_n & ~rd_n & ras_r[0] & (cas_r === 4'hF);
	wire per_en; assign #(30, 0) per_en = per_on;
	assign md = (per_on & per_en) ? periph : 16'hzzzz;

	// ---- port table in DRAM page 0x40: entry of port p (/WR = w_n) for all CNF4 / CNF3 / PN5 / DOS
	reg [7:0] tset [0:16383]; reg [15:0] tport [0:16383];
	task dset(input [15:0] p, input w_n, input [7:0] dsc); integer k; reg [11:0] r, c; reg [13:0] t; begin
		t = {w_n, p[15], p[14], p[6], p[5], p[13], p[7], p[2], p[1], p[0], 4'd0};
		if (tset[t] !== 8'hxx && tset[t] !== dsc) $display("dset: port %h (w_n %b) collides with %h", p, w_n, tport[t]);
		tset[t] = dsc; tport[t] = p;
		for (k = 0; k < 16; k = k + 1) begin
			r = {1'b0, k[3], k[1], k[0], w_n, p[15], p[14], p[6], p[5], p[13], p[7], p[2]};
			c = {2'b00, k[3], k[2], 8'h40};
			dram[didx(p[1], p[0], r, c)] = dsc;
		end
	end endtask

	// ---- video RAM
	reg [7:0] vram [0:262143];
	wire [7:0] vq0, vq1, vq2, vq3;
	// the data of the VA presented at CE n is used at CE n+2 (MODE) and CE_N n+3 (D_PICx_), docs/memtiming.md: the
	// model answers the VA of the previous CLK (with the VA of the same CLK only 44 of 1174 pixel loads got their byte)
	reg [15:0] va_lag = 0; always @(posedge clk) va_lag <= va_r;
	wire [17:0] vi0 = {va_lag, 2'd0}, vi1 = {va_lag, 2'd1}, vi2 = {va_lag, 2'd2}, vi3 = {va_lag, 2'd3};
	assign #3 vq0 = (vram[vi0] === 8'hxx) ? dflt(vi0, 8'd5) : vram[vi0];
	assign #3 vq1 = (vram[vi1] === 8'hxx) ? dflt(vi1, 8'd5) : vram[vi1];
	assign #3 vq2 = (vram[vi2] === 8'hxx) ? dflt(vi2, 8'd5) : vram[vi2];
	assign #3 vq3 = (vram[vi3] === 8'hxx) ? dflt(vi3, 8'd5) : vram[vi3];
	wire [3:0] v_wr_d; assign #3 v_wr_d = v_wr_r;
	// the SRAM drives while /WE is high, from 3 ns after its rise (the bus keeps the written byte meanwhile)
	assign vd0 = (v_wr_r[0] !== 1'b0 && v_wr_d[0] !== 1'b0) ? vq0 : 8'bz;
	assign vd1 = (v_wr_r[1] !== 1'b0 && v_wr_d[1] !== 1'b0) ? vq1 : 8'bz;
	assign vd2 = (v_wr_r[2] !== 1'b0 && v_wr_d[2] !== 1'b0) ? vq2 : 8'bz;
	assign vd3 = (v_wr_r[3] !== 1'b0 && v_wr_d[3] !== 1'b0) ? vq3 : 8'bz;
	reg [3:0] vwr_p = 4'hF; integer n_vwr = 0;
	always @(v_wr_r) begin
		if (vwr_p[0] === 1'b0 && v_wr_r[0] === 1'b1) vram[{va_r, 2'd0}] = vd0;
		if (vwr_p[1] === 1'b0 && v_wr_r[1] === 1'b1) vram[{va_r, 2'd1}] = vd1;
		if (vwr_p[2] === 1'b0 && v_wr_r[2] === 1'b1) vram[{va_r, 2'd2}] = vd2;
		if (vwr_p[3] === 1'b0 && v_wr_r[3] === 1'b1) vram[{va_r, 2'd3}] = vd3;
		if (vwr_p !== 4'hF && v_wr_r === 4'hF) n_vwr = n_vwr + 1;
		if (^v_wr_r !== 1'bx && v_wr_r !== 4'hF) cmp_vwr = cmp_on;
		vwr_p = v_wr_r;
	end
	function [7:0] pick_mode0(input integer r, input [7:0] x);
		case (r % 8)
			0:       pick_mode0 = {4'hF, 2'b11, x[1], 1'b1};          // border + blank + frame INT
			1:       pick_mode0 = {4'hF, x[3:0]};                     // border
			2, 3:    pick_mode0 = {x[7:6], x[5], 1'b1, x[3:0]};        // ZX
			4:       pick_mode0 = {x[7:6], 2'b10, x[3:0]};             // graphics 256 colours
			5:       pick_mode0 = {x[7:6], 2'b00, x[3:0]};             // graphics 16 colours
			default: pick_mode0 = x;
		endcase
	endfunction

	// ---- XA multiplexer (drives XA while RDXA = 0, 2 ns hold), its inputs
	reg kb_c = 1, kb_d = 1, tape_s = 1, mouse_s = 1, fdd_w_s = 1, fdd_ch_s = 1, sinc1_s = 1, sinc2_s = 1;
	wire [3:0] mux_v; assign #2 mux_v = sxa_r ? {sinc2_s, sinc1_s, fdd_ch_s, fdd_w_s} : {mouse_s, tape_s, kb_d, kb_c};
	wire rdxa_late; assign #2 rdxa_late = rdxa_r;
	assign xa = (rdxa_r === 1'b1 && rdxa_late === 1'b1) ? 3'bzzz : mux_v[2:0];
	assign xa3 = mux_v[3];

`define TB_MEM_CPU_WAIT
	`include "mem/tb_mem.vh"

	// ================= comparison
	`EQ_CMP(clkz, 1, clkz_o, clkz_r)
	`EQ_CMP(wait_oe, 1, wait_oe_o, wait_oe_r)
	`EQ_CMP(res_oe, 1, res_oe_o, res_oe_r)
	`EQ_CMP(cs, 2, ({cs_rom_o, cs_cash_o}), ({cs_rom_r, cs_cash_r}))
	`EQ_CMP(ra, 4, ra_o, ra_r)
	`EQ_CMP(d_oe, 1, d_oe_o, d_oe_r)
	`EQ_CMP(d_pin, 8, d_pin_o, d_pin_r)
	`EQ_CMP(ma, 15, ma_o, ma_r)
	`EQ_CMP(ras_cas, 7, ({ras_o, cas_o, we_o}), ({ras_r, cas_r, we_r}))
	`EQ_CMP(md_oe, 1, md_oe_o, md_oe_r)
	`EQ_CMP(md_pin, 16, md_pin_o, md_pin_r)
	`EQ_CMP(va, 16, va_o, va_r)
	`EQ_CMP(v_wr, 4, (cmp_vwr ? v_wr_o : 4'h0), (cmp_vwr ? v_wr_r : 4'h0))
	`EQ_CMP(vd_oe, 4, (cmp_vwr ? vd_oe_o : 4'h0), (cmp_vwr ? vd_oe_r : 4'h0))
	`EQ_CMP(vd_out, 32, (cmp_vwr ? {vd3_o, vd2_o, vd1_o, vd0_o} & {{8{vd_oe_o[3]}}, {8{vd_oe_o[2]}}, {8{vd_oe_o[1]}}, {8{vd_oe_o[0]}}} : 32'd0),
		(cmp_vwr ? {vd3, vd2, vd1, vd0} & {{8{vd_oe_r[3]}}, {8{vd_oe_r[2]}}, {8{vd_oe_r[1]}}, {8{vd_oe_r[0]}}} : 32'd0))
	`EQ_CMP(v_cs, 2, v_cs_o, v_cs_r)
	`EQ_CMP(wr_col, 1, wr_col_o, wr_col_r)
	`EQ_CMP(dac, 3, ({dac_data_o, dac_ws_o, dac_bck_o}), ({dac_data_r, dac_ws_r, dac_bck_r}))
	`EQ_CMP(xacs, 1, xacs_o, xacs_r)
	`EQ_CMP(xa_oe, 1, xa_oe_o, xa_oe_r)
	`EQ_CMP(xa_pin, 3, (xa_oe_o ? xa_o : xa), xa)
	`EQ_CMP(strobes, 5, ({sxa_o, rdxa_o, wr_awg_o, rd_kmps_o, wr_dwg_o}), ({sxa_r, rdxa_r, wr_awg_r, rd_kmps_r, wr_dwg_r}))
	`EQ_CMP(dac_data, 1, dac_data_o, dac_data_r)

	// X on reference outputs
	integer xref = 0;
	always @(negedge clk) if (cmp_on && ^{clkz_r, cs_rom_r, cs_cash_r, ra_r, va_r, ma_r, ras_r, cas_r, we_r, xacs_r,
		sxa_r, rdxa_r, wr_awg_r, rd_kmps_r, wr_dwg_r, wr_col_r, dac_data_r, dac_ws_r, dac_bck_r, d_oe_r, md_oe_r,
		wait_oe_r, res_oe_r, (cmp_vwr ? v_wr_r : 4'h0)} === 1'bx) begin
		if (xref < 3) $display("  X on a reference output at %0d ns: %b", $time, {clkz_r, cs_rom_r, cs_cash_r, ra_r, va_r, ma_r, ras_r, cas_r, we_r, xacs_r,
		sxa_r, rdxa_r, wr_awg_r, rd_kmps_r, wr_dwg_r, wr_col_r, dac_data_r, dac_ws_r, dac_bck_r, d_oe_r, md_oe_r,
		wait_oe_r, res_oe_r});
		xref = xref + 1;
	end
	// debug trace: +dbg=<from ns> for 600 ns
	integer dbg_t = -1;
	initial if (!$value$plusargs("dbg=%d", dbg_t)) dbg_t = -1;
	always @(negedge clk) if (dbg_t >= 0 && $time >= dbg_t && $time < dbg_t + 600)
		$display("%0d ce_n=%b ct=%0d io%b rd%b mr%b m1%b wr%b d %h | ras %b cas %b md %h | o: cas %b cwh %b mcw %b mct %b mdo %h mce %b ado %h dcpp %h | r: cas %b cwh %b mdo %h dcpp %h",
			$time, ce_n, dut.ct[2:0], io_n, rd_n, mr_n, m1_n, wr_n, d, ras_r[0], cas_r, md, dut.dc_cas, dut.cwh_q, dut.mc_write, dut.mc_type, dut.acc_mdo, dut.mc_end, dut.acc_do, dut.dcpp,
			ref.\DECODE|CAS .q, ref.CAS_WRITE_HOLD.q,
			ref.\ACC|MDO ,
			{ref.\DECODE|DCPP[7] .q, ref.\DECODE|DCPP[6] .q, ref.\DECODE|DCPP[5] .q, ref.\DECODE|DCPP[4] .q,
			 ref.\DECODE|DCPP[3] .q, ref.\DECODE|DCPP[2] .q, ref.\DECODE|DCPP[1] .q, ref.\DECODE|DCPP[0] .q});
	// bus conflicts (X on a bus line)
	integer xbus = 0;
	always @(negedge clk) if (cmp_on && (^d === 1'bx || ^md === 1'bx || ^xa === 1'bx || (cmp_vwr && ^{vd0, vd1, vd2, vd3} === 1'bx))) begin
		if (xbus < 5) $display("  X on a bus at %0d ns: d %h md %h xa %b vd %h%h%h%h (z_drv %b cs_rom %b cs_cash %b rd %b d_oe %b)",
			$time, d, md, xa, vd3, vd2, vd1, vd0, cpu_doe, cs_rom_r, cs_cash_r, rd_n, d_oe_r);
		xbus = xbus + 1;
	end
	// DCP cycle trace (+cdbg=<ns>)
	integer cdbg_t = -1;
	initial if (!$value$plusargs("cdbg=%d", cdbg_t)) cdbg_t = -1;
	always @(negedge clk) if (cdbg_t >= 0 && $time >= cdbg_t && $time < cdbg_t + 500)
		$display("%0d ce_n=%b ct=%0d ct4 %b io%b rd%b mr%b wr%b | o: rq %b rfc %b rft %b mcb %b mrw %b s2 %b | r: rq %b rfc %b rft %b mcb %b mrw %b",
			$time, ce_n, dut.ct[2:0], dut.ct[4], io_n, rd_n, mr_n, wr_n, dut.DECODE.mc_rq_q, dut.DECODE.rfc_q,
			dut.DECODE.rft_q, dut.DECODE.mc_begin, dut.DECODE.mem_rw, dut.DECODE.s2_e, ref.\DECODE|MC_RQ .q,
			ref.\DECODE|RFC .q, ref.\DECODE|RFT .q, ref.\DECODE|MC_BEGIN .q, ref.\DECODE|MEM_RW .q);
	// turbo trace (+tdbg)
	reg [3:0] tr_p = 0;
	always @(negedge clk) if ($test$plusargs("tdbg") && {ref.\TEST_SWITCH~q , ref.\DECODE|TURBO~q , dut.ts_e, dut.turbo} !== tr_p) begin
		tr_p = {ref.\TEST_SWITCH~q , ref.\DECODE|TURBO~q , dut.ts_e, dut.turbo};
		$display("%0d turbo: ref ts %b turbo %b f12 %b ct %b%b%b | ours ts %b turbo %b f12 %b ct %0d", $time, ref.\TEST_SWITCH~q ,
			ref.\DECODE|TURBO~q , ref.\KEYS|KB_F12~q , ref.\KEYS|KB_CT[2] .q, ref.\KEYS|KB_CT[1] .q, ref.\KEYS|KB_CT[0] .q,
			dut.ts_e, dut.turbo, dut.kb_f12, dut.KEYS.ct_e);
	end
	// first mismatch
	reg first = 1;
	wire [127:0] sig_o = {clkz_o, wait_oe_o, res_oe_o, cs_rom_o, cs_cash_o, ra_o, d_oe_o, d_pin_o, ma_o, ras_o, cas_o, we_o,
		md_oe_o, md_pin_o, va_o, xacs_o, xa_oe_o, sxa_o, rdxa_o, wr_awg_o, rd_kmps_o, wr_dwg_o, wr_col_o, dac_data_o,
		dac_ws_o, dac_bck_o};
	wire [127:0] sig_r = {clkz_r, wait_oe_r, res_oe_r, cs_rom_r, cs_cash_r, ra_r, d_oe_r, d_pin_r, ma_r, ras_r, cas_r, we_r,
		md_oe_r, md_pin_r, va_r, xacs_r, xa_oe_r, sxa_r, rdxa_r, wr_awg_r, rd_kmps_r, wr_dwg_r, wr_col_r, dac_data_r,
		dac_ws_r, dac_bck_r};
	always @(negedge clk) if (cmp_on && first && sig_o !== sig_r) begin
		first = 0;
		$display("first mismatch at %0d ns (ce_n=%b): diff %h", $time, ce_n, sig_o ^ sig_r);
		$display("  clkz %b/%b wait %b/%b res %b/%b cs %b%b/%b%b ra %h/%h d_oe %b/%b d %h/%h ma %h/%h ras %b/%b cas %b/%b we %b/%b",
			clkz_o, clkz_r, wait_oe_o, wait_oe_r, res_oe_o, res_oe_r, cs_rom_o, cs_cash_o, cs_rom_r, cs_cash_r, ra_o, ra_r,
			d_oe_o, d_oe_r, d_pin_o, d_pin_r, ma_o, ma_r, ras_o, ras_r, cas_o, cas_r, we_o, we_r);
		$display("  md_oe %b/%b md %h/%h va %h/%h xacs %b/%b strobes %b/%b wr_col %b/%b dac %b%b%b/%b%b%b",
			md_oe_o, md_oe_r, md_pin_o, md_pin_r, va_o, va_r, xacs_o, xacs_r, {sxa_o, rdxa_o, wr_awg_o, rd_kmps_o, wr_dwg_o},
			{sxa_r, rdxa_r, wr_awg_r, rd_kmps_r, wr_dwg_r}, wr_col_o, wr_col_r, dac_data_o, dac_ws_o, dac_bck_o,
			dac_data_r, dac_ws_r, dac_bck_r);
		$display("  z80 m1 %b rf %b io %b wr %b rd %b mr %b a %h | ours iord %b dcpp %h rd_ram %b blk_mem %b type %h",
			m1_n, rf_n, io_n, wr_n, rd_n, mr_n, a, dut.iord_e, dut.dcpp, dut.rd_ram, dut.blk_mem, dut.type_);
		$display("  ref /IORD %b DCPP %b%b%b%b%b%b%b%b", ref.\/IORD .q, ref.\DECODE|DCPP[7] .q, ref.\DECODE|DCPP[6] .q,
			ref.\DECODE|DCPP[5] .q, ref.\DECODE|DCPP[4] .q, ref.\DECODE|DCPP[3] .q, ref.\DECODE|DCPP[2] .q,
			ref.\DECODE|DCPP[1] .q, ref.\DECODE|DCPP[0] .q);
		if ($test$plusargs("stop")) #200 $finish;
	end

	// ---- ports (A: the table index bits A15 A14 A13 A7 A6 A5 A2 A1 A0) and their descriptors
	localparam [15:0] P_FE = 16'h00FE, P_PN = 16'h7FFD, P_SC = 16'h1FFD, P_AYA = 16'hFFFD, P_AYD = 16'hBFFD,
		P_CNF = 16'h00C6, P_CNFS = 16'h0086, P_ALLM = 16'h00C3, P_RGM = 16'h00C5, P_HOLD = 16'h20CB, P_AGR = 16'h00C4,
		P_XCNT = 16'h00C7, P_CBL = 16'h0088, P_CBLM = 16'h0089, P_ROMRG = 16'h008F, P_5C = 16'h005C,
		P_SYS0 = 16'h007C, P_SYS1 = 16'h003C, P_CASH1 = 16'h00FB, P_CASH0 = 16'h007B, P_A20 = 16'h001B,
		P_ISA = 16'h00F7, P_IDE = 16'h0050, P_IDE1 = 16'h2051, P_WG = 16'h001F, P_KMS = 16'hFADF,
		P_W1 = 16'h4089, P_W2 = 16'h40A9, P_W3 = 16'h80F5, P_W0 = 16'h40C9;
	// ---- SINC_1 pulses: COPY_SINC_H, which also speeds up CTH5 (the line clock of the keyboard and mouse)
	// SINC_HOLD[3..0] counts CT4 rises (one per 96 CLK) from HOLD[3..0] to 15 while SINC_1 = 0
	reg sinc_run = 0; integer n_sinc = 0, sinc_lo = 9 * 96, sinc_hi = 2 * 96;
	initial forever begin
		@(posedge clk);
		if (sinc_run) begin
			repeat (sinc_hi + ($random(seed) & 63)) @(posedge clk);
			@(posedge clk); while (!ce_n) @(posedge clk); #1 sinc1_s = 0;
			repeat (sinc_lo + 300) @(posedge clk);
			@(posedge clk); while (!ce_n) @(posedge clk); #1 sinc1_s = 1;
			n_sinc = n_sinc + 1;
		end
	end
	// ---- PS/2 device (bit ~1.7 us)
	task ps2_bit(input b); begin
		repeat (24) @(posedge clk); kb_d = b;
		repeat (24) @(posedge clk); kb_c = 0;
		repeat (72) @(posedge clk); kb_c = 1;
		repeat (24) @(posedge clk);
	end endtask
	task ps2_byte(input [7:0] v); integer i; begin
		ps2_bit(0); for (i = 0; i < 8; i = i + 1) ps2_bit(v[i]); ps2_bit(~^v); ps2_bit(1);
	end endtask
	// ---- mouse line: a few Microsoft-serial bits at the (sped-up) line clock rate, just to move MOUSE_D
	initial forever begin
		repeat (6000 + ($random(seed) & 4095)) @(posedge clk);
		if (sinc_run) begin mouse_s = 0; repeat (3000) @(posedge clk); mouse_s = 1; end
		tape_s = $random(seed);
	end

	// ================= the CPU
	wire c_m1, c_rf, c_io, c_wr, c_rd, c_mr, c_halt, c_m1x, c_rfx, c_iox, c_wrx, c_rdx, c_mrx, c_doe;
	wire [15:0] c_a, c_ax; wire [7:0] c_do;
	wire zclk = clkz_o, zclk_nx = clkz_nx_o;
	// /WAIT of the CPU: the ACEX (open drain) and sp_sram (a fastram / ROM byte that would be late), ANDed as the
	// top must do; the reference does not read its /WAIT pin
	wire c_wait = ~wait_oe_o & u_sram.CPU_WAIT_N;
	reg cpu_ref = 0; initial cpu_ref = $test$plusargs("cpuref");
	wire [7:0] cpu_di = cpu_ref ? d : d_u;
	wire cpu_int_rd;
	sp_z84c15 cpu (.CLK(clk), .CE(ce), .CE_N(ce_n), .CLKZ1(zclk), .CLKZ1_NX(zclk_nx), .RESET_N(res_w),
		.WAIT_N(c_wait), .INT_N(~int_l), .NMI_N(~nmi_l), .M1_N(c_m1), .RF_N(c_rf), .IO_N(c_io), .WR_N(c_wr),
		.RD_N(c_rd), .MR_N(c_mr), .HALT_N(c_halt), .A(c_a), .D_O(c_do), .D_OE(c_doe), .M1_N_NX(c_m1x),
		.RF_N_NX(c_rfx), .IO_N_NX(c_iox), .WR_N_NX(c_wrx), .RD_N_NX(c_rdx), .MR_N_NX(c_mrx), .A_NX(c_ax), .D_I(cpu_di),
		.INT_RD(cpu_int_rd), .CS0(), .CS1(), .CSBR(), .MCR(), .RXA_D(8'h00), .RXA_STB(1'b0), .RXA_RDY(), .RXB_D(8'h00),
		.RXB_STB(1'b0), .RXB_RDY(), .CTSA(1'b0), .DCDA(1'b0), .CTSB(1'b1), .DCDB(1'b0), .WR5A(), .WR5B(),
		.TRG0(1'b0), .ZC0(), .PA_I(8'hFF), .PA_O(), .PA_OE(), .PB_I(8'hFF), .PB_O(), .PB_OE());
	// the pins to both ACEXes 1 ns after the CE (as the bus model: no race with the TG42 edge of the netlist)
	assign #1 {m1_n, rf_n, io_n, wr_n, rd_n, mr_n, halt_n, a, cpu_do, cpu_doe} = {c_m1, c_rf, c_io, c_wr, c_rd, c_mr, c_halt, c_a, c_do, c_doe};
	assign #1 {m1_nx, rf_nx, io_nx, wr_nx, rd_nx, mr_nx, a_nx} = {c_m1x, c_rfx, c_iox, c_wrx, c_rdx, c_mrx, c_ax};
	// the latch of MA[14..12] on the board (schematic 2016s: DD16 = 74ALS174 (КР1533ТМ9), clock = WR_AWG rising, /CLR =
	// /RESET; Q0 = MA12 -> DD17.1, Q1 = MA13 -> DD17.2: open-collector NANDs as inverters (К155ЛА8) -> NMI/, INT/):
	// taken at the rise of WR_AWG (MA as it was before that edge), cleared while /RESET is low
	// n_awg / x_awg: WR_AWG rises / of them with MA[14..12] changing at the same edge (a race on the board)
	reg awg_p = 1'b1; reg [14:12] ma_p = 3'b111; integer n_awg = 0, x_awg = 0, n_intl = 0;
	always @(negedge clk) begin
		if (res_w === 1'b0) begin int_l <= 1'b0; nmi_l <= 1'b0; end
		else if (~awg_p & wr_awg_o) begin
			int_l <= ma_p[13]; nmi_l <= ma_p[12];
			if (cmp_on) begin n_awg = n_awg + 1; if (ma_p !== ma_o[14:12]) x_awg = x_awg + 1; if (ma_p[13] & ~int_l) n_intl = n_intl + 1; end
		end
		awg_p <= wr_awg_o; ma_p <= ma_o[14:12];
	end
	reg chk_on = 0;
	`include "../cpu/z80_bus_chk.vh"

	// ================= the CPU on our memory
	// what the T80pa takes: at the CE_N where it raises /RD (M1: the rise of T3, DInst; read: the fall of T3,
	// DI_Reg); one CLK later the pin RD_N is still 0 and RD_N_NX is 1. Our bus at that edge against the reference
	// bus; INTA and internal port reads excluded. Kinds: 0 ROM M1, 1 ROM RD, 2 cache M1, 3 cache RD, 4 DRAM M1,
	// 5 DRAM RD, 6 I/O
	reg [7:0] lat_u = 0, lat_r = 0; reg lat_rom = 0, lat_cash = 0, lat_int = 0;
	integer n_lat [0:6]; integer x_lat = 0, lk, t_end = 0;
	initial for (lk = 0; lk < 7; lk = lk + 1) n_lat[lk] = 0;
	always @(posedge clk) begin
		if (ce_n) begin lat_u <= d_u; lat_r <= d; lat_rom <= cs_rom_o === 1'b0; lat_cash <= fast_o; lat_int <= cpu_int_rd; end
		if (ce && cmp_on && ~c_rd && c_rdx && (c_m1 | c_io) && ~lat_int) begin
			lk = ~c_io ? 6 : lat_rom ? (c_m1 ? 1 : 0) : lat_cash ? (c_m1 ? 3 : 2) : (c_m1 ? 5 : 4);
			n_lat[lk] = n_lat[lk] + 1;
			if (lat_u !== lat_r) begin
				x_lat = x_lat + 1;
				if (x_lat <= 5) $display("  T80 took %h at %0d ns (kind %0d, A %h), reference bus %h", lat_u, $time, lk, a, lat_r);
				if (x_lat == 1) begin sr_dump; if (^lat_u === 1'bx && !$test$plusargs("nolstop")) t_end = 0; end
			end
		end
	end
	// the last 32 CLKs of the sp_sram arbiter, printed at the first bad byte the T80 takes (an X taken ends the run unless +nolstop)
	reg [23:0] sr_t [0:31]; reg [3:0] sr_e [0:31], sr_g [0:31], sr_tc [0:31], sr_tl [0:31]; reg [17:0] sr_f [0:31];
	integer sr_i = 0, sr_k, sr_j;
	always @(posedge clk) begin
		sr_j = sr_i % 32;
		sr_t[sr_j] = $time; sr_e[sr_j] = e_now; sr_g[sr_j] = u_sram.g; sr_tc[sr_j] = u_sram.tag_cur; sr_tl[sr_j] = u_sram.tag_land;
		sr_f[sr_j] = {u_sram.c_req, u_sram.c_pend, u_sram.key_new, u_sram.CPU_RDY, pix_rq, mode_rq, atr_zx, u_sram.a_fix,
			u_sram.m_urg, u_sram.mh_ok, u_sram.ml_ok, u_sram.wb_pend, fast_o, rd_n, m1_n, mr_n, wr_n, u_sram.c_land};
		sr_i = sr_i + 1;
	end
	task sr_dump; begin
		$display("    sp_sram, last 32 CLK (g / tags: 1 W 2 P 3 A 4 MH 5 ML 6 C 7 B 8 L): ns c g cur land | c_req c_pend key_new RDY | PIX MODE ATR a_fix m_urg mh ml wb | fast rd m1 mr wr | c_land");
		for (sr_k = sr_i; sr_k < sr_i + 32; sr_k = sr_k + 1) begin
			sr_j = sr_k % 32;
			$display("    %0d c%0d g %0d cur %0d land %0d | %b | %b | %b | %b", sr_t[sr_j], sr_e[sr_j], sr_g[sr_j], sr_tc[sr_j], sr_tl[sr_j],
				sr_f[sr_j][17:14], sr_f[sr_j][13:6], sr_f[sr_j][5:1], sr_f[sr_j][0]);
		end
	end endtask
	// the cache write buffer: the byte sp_sram takes (wb_now) against the byte on D at the rise of /WR
	integer n_wbd = 0, x_wbd = 0; reg [7:0] wbd = 0; reg wbd_on = 0;
	always @(posedge clk) begin
		if (u_sram.wb_now) begin wbd <= d_u; wbd_on <= 1'b1; end
		if (ce && cmp_on && wbd_on && ~c_wr && c_wrx) begin
			n_wbd = n_wbd + 1; wbd_on <= 1'b0;
			if (wbd !== d || ^wbd === 1'bx) begin
				x_wbd = x_wbd + 1;
				if (x_wbd <= 5) $display("  cache write at %0d ns (A %h): buffer took %h, /WR rise %h", $time, a, wbd, d);
			end
		end
	end
	// the waits of sp_sram the T80 sampled (CE_N where CLKZ1 falls, the ACEX not waiting), by the c_f of the cycle
	// and {PIX_RQ, ATR_ZX, MODE_RQ} seen at its CS fall; a run of more than 8 = a wait that never ends
	integer wh [0:31]; integer n_ow = 0, x_ow = 0, ow_run = 0, wk; reg [4:0] cyc_k = 0; reg cs_p = 1'b0;
	initial for (wk = 0; wk < 32; wk = wk + 1) wh[wk] = 0;
	always @(posedge clk) begin
		if ((fast_o || cs_rom_o === 1'b0) && !cs_p)
			cyc_k = {((e_now == 1) ? 2'd0 : (e_now == 5) ? 2'd1 : (e_now == 9) ? 2'd2 : 2'd3), pix_rq, atr_zx, mode_rq};
		cs_p = fast_o || cs_rom_o === 1'b0;
		if (cmp_on && ce_n && clkz_o && !clkz_nx_o) begin
			if (u_sram.CPU_WAIT_N === 1'b0 && !wait_oe_o) begin
				n_ow = n_ow + 1; wh[cyc_k] = wh[cyc_k] + 1; ow_run = ow_run + 1;
				if (n_ow <= 5) $display("  sp_sram /WAIT at %0d ns: A %h, c_f code %0d, PIX ATR MODE %b, %0s", $time, a,
					cyc_k[4:3], cyc_k[2:0], cs_rom_o === 1'b0 ? "ROM" : m1_n === 1'b0 ? "cache M1" : "cache");
				if (ow_run == 9) begin x_ow = x_ow + 1; $display("  sp_sram /WAIT does not end at %0d ns", $time); end
			end else ow_run = 0;
		end
	end
	// cache M1 cycles by c_f (0 / 4 / 8) and the video requests seen there ({PIX_RQ, MODE_RQ}); cache RD / WR
	integer hist [0:11]; integer n_cm1 = 0, n_crd = 0, n_cwrc = 0, hk; reg fast_p = 1'b0;
	initial for (hk = 0; hk < 12; hk = hk + 1) hist[hk] = 0;
	always @(posedge clk) begin
		if (cmp_on && fast_o && !fast_p) begin
			if (m1_n === 1'b0) begin
				n_cm1 = n_cm1 + 1;
				hk = (e_now == 1) ? 0 : (e_now == 5) ? 1 : (e_now == 9) ? 2 : 3;
				if (hk < 3) hist[hk * 4 + {pix_rq, mode_rq}] = hist[hk * 4 + {pix_rq, mode_rq}] + 1;
				else $display("  cache M1 at %0d ns: CS low first seen at edge c%0d", $time, e_now);
			end else if (wr_n === 1'b0 || cpu_doe) n_cwrc = n_cwrc + 1;
			else n_crd = n_crd + 1;
		end
		fast_p = fast_o;
	end

	// M1 trace (+m1t): every opcode fetch address
	always @(negedge c_m1) if ($test$plusargs("m1t") && c_rf) $display("  M1 %h at %0d ns", c_a, $time);
	// ================= log port 2001, end 2002, PS/2 bytes on the markers A0 / A1
	reg [7:0] lg [0:63]; integer nlg = 0, done = 0, n_inta = 0;
	reg [7:0] ps2_val = 0; event ps2_ev;
	always begin @(ps2_ev); ps2_byte(ps2_val); end
	always @(posedge clk) if (ce && ~c_io && c_m1 && ~c_wr && c_wrx) begin
		if (c_a == 16'h2001) begin
			lg[nlg] = c_do; nlg = nlg + 1;
			if ($test$plusargs("logt")) $display("  log %h at %0d ns", c_do, $time);
			if (c_do == 8'hA0) begin ps2_val = 8'h1C; -> ps2_ev; end
			if (c_do == 8'hA1) begin ps2_val = 8'h32; -> ps2_ev; end
		end
		if (c_a == 16'h2002) done = 1;
	end
	always @(posedge clk) if (ce && ~c_m1 && ~c_io && c_iox) n_inta = n_inta + 1;
	reg [7:0] ex [0:63]; integer nex = 0;
	task e(input [7:0] v); begin ex[nex] = v; nex = nex + 1; end endtask

	reg [7:0] prog [0:16383];
	integer i, p, h, v, c5, base;
	reg [15:0] wa;
	initial begin
		if (!$value$plusargs("scen=%d", scen)) scen = 0;
		for (p = 0; p < 2; p = p + 1) for (v = 0; v < 64; v = v + 1) for (h = 0; h < 64; h = h + 8) begin
			base = $random(seed) & 255;
			for (i = h; i < h + 8; i = i + 1) for (c5 = 0; c5 < 2; c5 = c5 + 1) begin
				wa = {p[0], i[5:0], c5[0], 2'b11, v[5:0]};
				vram[{wa, 2'd3}] = (($random(seed) & 7) == 0) ? pick_mode0($random(seed) & 255, $random(seed)) :
				                    pick_mode0(base, $random(seed));
			end
		end
		pick[0] = 8'h00; pick[1] = 8'h10; pick[2] = 8'h13; pick[3] = 8'h1C; pick[4] = 8'h20; pick[5] = 8'h22;
		pick[6] = 8'h2A; pick[7] = 8'h30; pick[8] = 8'h40; pick[9] = 8'h52; pick[10] = 8'h58; pick[11] = 8'h80;
		pick[12] = 8'h88; pick[13] = 8'h8C; pick[14] = 8'h90; pick[15] = 8'h91; pick[16] = 8'h9F; pick[17] = 8'hB0;
		pick[18] = 8'hC2; pick[19] = 8'hC5; pick[20] = 8'hC4; pick[21] = 8'hD7; pick[22] = 8'hE0; pick[23] = 8'hE3;
		pick[24] = 8'h89; pick[25] = 8'h1B; pick[26] = 8'hCB; pick[27] = 8'h00; pick[28] = 8'h21; pick[29] = 8'hC7;
		pick[30] = 8'h40; pick[31] = 8'h00;
		// the port table of tb_eq_acex without 001B (ISA A20) / 001F (WG93): they share the index of the Z84C15
		// ports 10-1F, which get descriptor 00 as in MAME; EE / EF with A15-A8 = FF; the log ports
		dset(P_FE, 1, 8'h40); dset(P_FE, 0, 8'hC2); dset(P_PN, 0, 8'hC1); dset(P_SC, 0, 8'hC0);
		dset(P_AYA, 0, 8'h90); dset(P_AYA, 1, 8'h52); dset(P_AYD, 0, 8'h91); dset(P_AYD, 1, 8'h8C);
		dset(P_CNF, 0, 8'hC6); dset(P_CNFS, 0, 8'hCE); dset(P_ALLM, 0, 8'hC3); dset(P_RGM, 0, 8'hC5);
		dset(P_HOLD, 0, 8'hCB); dset(P_AGR, 0, 8'hC4); dset(P_XCNT, 0, 8'hC7); dset(P_CBL, 0, 8'h88);
		dset(P_CBLM, 0, 8'h89); dset(P_ROMRG, 0, 8'h8F); dset(P_5C, 0, 8'h00); dset(P_SYS0, 0, 8'h00);
		dset(P_SYS1, 0, 8'h00); dset(P_CASH1, 1, 8'h00); dset(P_CASH0, 1, 8'h00);
		dset(P_ISA, 0, 8'hF2); dset(P_IDE, 1, 8'h20); dset(P_IDE, 0, 8'h20); dset(P_IDE1, 1, 8'h21);
		dset(P_IDE1, 0, 8'h21); dset(P_KMS, 1, 8'h58);
		dset(P_W1, 0, 8'hE9); dset(P_W2, 0, 8'hEA); dset(P_W3, 0, 8'hF5); dset(P_W0, 0, 8'hE0);
		for (i = 16'h0010; i < 16'h0018; i = i + 1) begin dset(i, 0, 8'h00); dset(i, 1, 8'h00); end
		dset(16'hFFEE, 0, 8'h00); dset(16'hFFEE, 1, 8'h00); dset(16'hFFEF, 0, 8'h00); dset(16'hFFEF, 1, 8'h00);
		dset(16'h2001, 0, 8'h00); dset(16'h2002, 0, 8'h00);
		dset(16'h2089, 0, 8'hC4);                    // OUT (89),A with A = 20..3F: the line port (scenario 4)
		// the program in every ROM page, the scenario at 3FFF
		for (i = 0; i < 16384; i = i + 1) prog[i] = 8'h00;
		$readmemh("build/cpu_acex.hex", prog);
		prog[16383] = scen;
		for (i = 0; i < 262144; i = i + 1) rom[i] = prog[i & 16383];
		// the cache code of scenario 3 (ROM 1000-1FFF) in the cache, all four ROM_RG[1..0] pages (RA = 01xx)
		for (i = 0; i < 65536; i = i + 1) if (i[13:12] == 2'b01) cache[{2'b01, i[15:14], i[13:0]}] = prog[i[13:0]];
		init_mem;
		if (scen == 0) begin
			e(8'hFF); e(8'h44); e(8'h5A); e(8'h5D); e(8'h55); e(8'h78); e(8'hA5); e(8'hA2); e(8'hAA); e(8'h78);
			e(8'hC3); e(8'hE0);
		end else if (scen == 2) begin
			e(8'h00); e(8'hAA); e(8'hAA); e(8'h00); e(8'hAA); e(8'hAA); e(8'h5D); e(8'hFF); e(8'hE2);
		end else if (scen == 3) begin
			// video sums ZX / attributes / graphics / palette; in the cache: sum, PUSH / POP D E H L, the copied
			// routine, INC (HL), the three self-modifying cases, the loop; the ROM byte under smc2; the end
			e(8'hF6); e(8'h8D); e(8'h06); e(8'hDC); e(8'h78); e(8'h56); e(8'h78); e(8'h12); e(8'h56); e(8'hC5);
			e(8'h54); e(8'hA7); e(8'h3D); e(8'h5B); e(8'h6A); e(8'h00); e(8'hE3);
		end else if (scen == 4) begin
			// vertical accelerator modes on page 50 run from DRAM as Flex Navigator: fill sum of a column, glyph sum
			// of a column, the last lines of the two glyph columns, the last line of the last fill column
			e(8'hA4); e(8'hD0); e(8'hFF); e(8'h80); e(8'h01); e(8'h5A); e(8'hE4);
		end else begin
			e(8'hA0); e(8'h38); e(8'h01); e(8'hA1); e(8'h22); e(8'h02); e(8'hE1);
			sinc_lo = 2 * 96;
		end

		// ---- power-up: the MAX holds /RESET; SINC_1 pulses (scenario 1: the keyboard ends its reset after 4)
		sinc_run = scen == 1;
		repeat (100) @(posedge clk);
		cmp_on = 1; chk_on = 1;
		repeat (200) @(posedge clk);
		res_drv = 1;
		while (res_w !== 1'b1) @(posedge clk);
		$display("  /RESET released at %0d ns", $time);
		ld_run = 1;
		t_end = $time + (scen == 4 ? 650000 : 400000);
		while (!done && $time < t_end) @(posedge clk);
		repeat (200) @(posedge clk);
		ld_run = 0; repeat (40) @(posedge clk);
		$display("tb_cpu_acexm (sp_z84c15 on BASE_303 and on sp_acex + sp_sram + sp_sdram, scenario %0d), %0d us simulated%0s:", scen,
			$time / 1000, done ? "" : ", PROGRAM DID NOT END");
		if (!done) errors = errors + 1;
		clkz_report; wait_oe_report; res_oe_report; cs_report; ra_report; d_oe_report; d_pin_report; ma_report;
		ras_cas_report; md_oe_report; md_pin_report; va_report; v_wr_report; vd_oe_report; vd_out_report;
		v_cs_report; wr_col_report; dac_report; dac_data_report; xacs_report; xa_oe_report; xa_pin_report;
		strobes_report;
		$display("  models: DRAM reads %0d, refreshes %0d, writes %0d; video RAM writes %0d; cache writes %0d; SINC_1 pulses %0d; INTA %0d",
			n_drd, n_rf, n_dwr, n_vwr, n_cwr, n_sinc, n_inta);
		bc_report; errors = errors + bc_err;
		$display("  T80 takes: ROM M1 %0d RD %0d, cache M1 %0d RD %0d, DRAM M1 %0d RD %0d, I/O %0d; bad %0d",
			n_lat[0], n_lat[1], n_lat[2], n_lat[3], n_lat[4], n_lat[5], n_lat[6], x_lat);
		$display("  cache: M1 %0d, RD %0d, WR %0d cycles; write buffer bytes %0d (bad %0d)", n_cm1, n_crd, n_cwrc, n_wbd, x_wbd);
		$display("  cache M1 by c_f x {PIX_RQ, MODE_RQ} 00/01/10/11: c0 %0d %0d %0d %0d, c4 %0d %0d %0d %0d, c8 %0d %0d %0d %0d",
			hist[0], hist[1], hist[2], hist[3], hist[4], hist[5], hist[6], hist[7], hist[8], hist[9], hist[10], hist[11]);
		$display("  sp_sram /WAIT sampled %0d times (stuck %0d); by c_f 0 / 4 / 8 / other x {PIX ATR MODE} 000..111:", n_ow, x_ow);
		for (wk = 0; wk < 4; wk = wk + 1) $display("    c_f code %0d: %0d %0d %0d %0d %0d %0d %0d %0d", wk, wh[wk * 8], wh[wk * 8 + 1],
			wh[wk * 8 + 2], wh[wk * 8 + 3], wh[wk * 8 + 4], wh[wk * 8 + 5], wh[wk * 8 + 6], wh[wk * 8 + 7]);
		errors = errors + x_ow;
		$display("  WR_AWG rises %0d (MA[14..12] changing at that edge %0d), INT latched %0d times", n_awg, x_awg, n_intl);
		errors = errors + x_lat + x_wbd;
		for (i = 0; i < nlg || i < nex; i = i + 1)
			if (i >= nlg || i >= nex || lg[i] !== ex[i]) begin
				$display("  log %0d: %h, expected %h", i, (i < nlg) ? lg[i] : 8'hxx, (i < nex) ? ex[i] : 8'hxx);
				errors = errors + 1;
			end
		$display("  program log: %0d entries, %0d expected", nlg, nex);
		if (xref) $display("  X on reference outputs: %0d samples", xref);
		if (xbus) $display("  X on buses: %0d samples", xbus);
		errors = errors + xref + xbus;
		mem_report;
		$display("tb_cpu_acexm: %0d errors%s", errors, weak ? " (some outputs never toggled)" : "");
		$finish;
	end
endmodule
