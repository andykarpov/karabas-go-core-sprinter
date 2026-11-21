// sp_acex (the whole ACEX: top + DCP, VIDEO2, ACCELER, AY, KBD, MOUSE) against the netlist of BASE_303.TDF (3.03a).
// CLK = 84 MHz, clk42 toggles at every CLK edge and is the reference's TG42; CE = ~clk42 (CLK42 rises at our CE edge),
// CE_N = clk42. One set of models around both, driven by the reference's pins only:
// - Z80 bus model on the reference CLKZ1 (21 / 3.5 MHz), sampling its /WAIT: M1 with refresh, memory read / write,
//   IN / OUT, INTA. Its pins change 1 ns after a CE; our module gets the pins and their next values (*_nx).
//   Opcodes for the accelerator come from the ROM (window 0), written into the ROM image at the fetch address.
// - DRAM (4 MB, 2 banks x 16 bits): row / column latched from MA after the RAS_ / CAS_ falls, CAS_0..3 = byte lanes,
//   CBR refresh, late write while WE_N is low; read data 3 ns after CAS_; the port table (page 0x40) preset with
//   the descriptors of the ports used below, the rest random.
// - video RAM (64 K x 32): read data 3 ns after VA, written at the rise of V_WR; a structured mode table.
// - ROM / cache SRAM (256 KB each) on CS_ROM / CS_CASH, RA, A[13..0], D.
// - peripherals on MD in I/O reads (random byte per cycle), the XA multiplexer (PS/2 keyboard, mouse line, tape,
//   SINC_1 / SINC_2 of the MAX), the /RESET line of the MAX.
// Buses (D, MD, VD, XA) are wires with a keeper (the bus holds its last value when nobody drives, as the original
// relies on at strobe edges); our module's *_I inputs are those wires.
// Compared every half CLK42 cycle at latency 0 (EQ_CMP): all outputs, the output enables of the bidirectional pins
// (from the netlist's I/O buffers) and the pin values.
// +scen=0 (default): ports, pages, memory in all windows, video, AY, Covox / CBL, keyboard / mouse / IDE ports, ROM /
//   cache / ISA / flash strobe, accelerator, random; +scen=1: 3.5 MHz and the original waits, CBL FIFO interrupts,
//   COPY_SINC_V, soft reset; +scen=2: keyboard (PS/2 frames, TEST_SWITCH by F12, Ctrl+Alt+Del, Alt+F12, a key held; ALL_MODE[5:0] random).
// -DK30: the k30 personality (PERS_K30 = 1) against the k30 netlist (top SP2_ACEX of upstream/tt-sprinter-bios @ 085ef3c,
//   lower-case port names, XA[3:0] inout). +mut=N (with -DK30): one k30 line forced back to its 3.03a form, the run
//   must fail (run_eq.sh acex_k30_mut).
// -DSCROLL: the SCROLL personality (PERS_SCROLL = 1) against the SCROLL netlist (top SCROLL of upstream/tt-scroll-cnf/src,
//   the port names of BASE_303); ours with the SCROLL DCP.MIF (MIF_DCP_HEX: MEM[EE] = 2041; the reload that writes it is
//   tested by dcp_scroll). +mut=N: one SCROLL line forced back to 3.03a (run_eq.sh acex_scroll_mut).
`timescale 1ns/1ps
`include "eq_cmp.vh"
module tb_eq_acex;
	reg clk = 0; always #5.952 clk = ~clk;            // 84 MHz
	reg clk42 = 0; always @(posedge clk) clk42 <= ~clk42;
	wire ce = ~clk42, ce_n = clk42;
	reg cmp_on = 0, cmp_vwr = 0;
	integer errors = 0, weak = 0;
	integer seed = 7;
	integer scen = 0;                                 // +scen=0 bus, 1 sync / CBL / soft reset, 2 keyboard
	integer mut = 0;                                  // +mut=N (K30): a k30 line forced back to 3.03a
	reg kb_done = 0;
	integer kb_ph = 0; reg ph1_done = 0;              // scenario 2: phases of the PS/2 sequence for the bus side

	// ---- Z80 pins: applied value and the value after the next CE
	reg m1_n = 1, rf_n = 1, io_n = 1, wr_n = 1, rd_n = 1, mr_n = 1;
	reg m1_nx = 1, rf_nx = 1, io_nx = 1, wr_nx = 1, rd_nx = 1, mr_nx = 1;
	reg [15:0] a = 16'hFFFF, a_nx = 16'hFFFF;
	reg [7:0] z_do = 8'hFF, do_nx = 8'hFF;
	reg z_drv = 0, drv_nx = 0;
	reg res_drv = 0, res_nx = 0;                      // the MAX on /RESET: 0 = pull low
	always @(posedge clk) if (ce) begin
		m1_n <= #1 m1_nx; rf_n <= #1 rf_nx; io_n <= #1 io_nx; wr_n <= #1 wr_nx; rd_n <= #1 rd_nx; mr_n <= #1 mr_nx;
		a <= #1 a_nx; z_do <= #1 do_nx; z_drv <= #1 drv_nx; res_drv <= #1 res_nx;
	end

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

`ifdef K30
	// k30: XA[3:0] inout (XA3 = TRI(GND, GND): never driven, the multiplexer drives it)
	SP2_ACEX ref(.TG42(clk42), .CLKZ1(clkz_r), .\/wait (wait_w), .\/reset (res_w), .\/m1 (m1_n), .\/rf (rf_n),
		.\/io (io_n), .\/wr (wr_n), .\/rd (rd_n), .\/mr (mr_n), .\/HALT (1'b1), .a(a), .d(d), .cs_rom(cs_rom_r),
		.CS_CASH(cs_cash_r), .ra(ra_r), .v_cs(v_cs_r), .VA(va_r), .v_wr(v_wr_r), .VD3(vd3), .VD2(vd2), .VD1(vd1),
		.VD0(vd0), .WR_COL(wr_col_r), .DAC_DATA(dac_data_r), .DAC_WS(dac_ws_r), .DAC_BCK(dac_bck_r), .md(md),
		.ma(ma_r), .RAS_(ras_r), .CAS_(cas_r), .\/WE (we_r), .XACS(xacs_r), .XA({xa3, xa}), .SXA(sxa_r),
		.RDXA(rdxa_r), .wr_awg(wr_awg_r), .RD_KMPS(rd_kmps_r), .wr_dwg(wr_dwg_r));
	wire d_oe_r = ref.\d[0]~output .oe;
	wire md_oe_r = ref.\md[0]~output .oe;
	wire res_oe_r = ~ref.\/reset~output .i;          // open drain
	wire wait_oe_r = ref.\/wait~output .oe;
	wire cwh_r = 1'b0;                                 // no CAS_WRITE_HOLD in k30
	localparam TB_NAME = "k30 SP2_ACEX";
`else
`ifdef SCROLL
	SCROLL ref(
`else
	BASE_303 ref(
`endif
		.TG42(clk42), .CLKZ1(clkz_r), .\/WAIT (wait_w), .\/RESET (res_w), .\/M1 (m1_n), .\/RF (rf_n),
		.\/IO (io_n), .\/WR (wr_n), .\/RD (rd_n), .\/MR (mr_n), .\/HALT (1'b1), .A(a), .D(d), .CS_ROM(cs_rom_r),
		.CS_CASH(cs_cash_r), .RA(ra_r), .V_CS(v_cs_r), .VA(va_r), .V_WR(v_wr_r), .VD3(vd3), .VD2(vd2), .VD1(vd1),
		.VD0(vd0), .WR_COL(wr_col_r), .DAC_DATA(dac_data_r), .DAC_WS(dac_ws_r), .DAC_BCK(dac_bck_r), .MD(md),
		.MA(ma_r), .RAS_(ras_r), .CAS_(cas_r), .\/WE (we_r), .XACS(xacs_r), .XA(xa), .XA3(xa3), .SXA(sxa_r),
		.RDXA(rdxa_r), .WR_AWG(wr_awg_r), .RD_KMPS(rd_kmps_r), .WR_DWG(wr_dwg_r));
	// output enables of the bidirectional pins (netlist I/O buffers)
	wire d_oe_r = ref.\D[0]~output .oe;
	wire md_oe_r = ref.\MD[0]~output .oe;
	wire res_oe_r = ~ref.\/RESET~output .i;          // open drain
	wire wait_oe_r = ref.\/WAIT~output .oe;
`ifdef SCROLL
	wire cwh_r = 1'b0;                                 // no CAS_WRITE_HOLD in SCROLL
	localparam TB_NAME = "SCROLL";
`else
	wire cwh_r = ref.CAS_WRITE_HOLD.q;
	localparam TB_NAME = "3.03a BASE_303";
`endif
`endif
	wire [3:0] vd_oe_r = {ref.\VD3[0]~output .oe, ref.\VD2[0]~output .oe, ref.\VD1[0]~output .oe, ref.\VD0[0]~output .oe};
	wire xa_oe_r = ref.\XA[2]~output .oe;

	// ---- ours
	wire clkz_o, wait_oe_o, res_oe_o, cs_rom_o, cs_cash_o, wr_col_o, dac_data_o, dac_ws_o, dac_bck_o, we_o, xacs_o;
	wire sxa_o, rdxa_o, wr_awg_o, rd_kmps_o, wr_dwg_o, d_oe_o, md_oe_o, xa_oe_o;
	wire [3:0] ra_o, v_wr_o, cas_o, vd_oe_o; wire [1:0] v_cs_o, ras_o; wire [15:0] va_o, md_o; wire [14:0] ma_o;
	wire [7:0] d_o, vd0_o, vd1_o, vd2_o, vd3_o; wire [2:0] xa_o;
`ifndef MIF_DCP_HEX
`define MIF_DCP_HEX "../../rtl/acex/mif/dcp.hex"
`endif
	sp_acex #(.MIF_DCP(`MIF_DCP_HEX), .MIF_AY("../../rtl/acex/mif/ay.hex"),
		.MIF_KBD("../../rtl/acex/mif/kbd_ini2.hex")) dut(.CLK(clk), .CE(ce), .CE_N(ce_n),
		.M1_N(m1_n), .RF_N(rf_n), .IO_N(io_n), .WR_N(wr_n), .RD_N(rd_n), .MR_N(mr_n),
		.M1_N_NX(m1_nx), .RF_N_NX(rf_nx), .IO_N_NX(io_nx), .WR_N_NX(wr_nx), .RD_N_NX(rd_nx), .MR_N_NX(mr_nx),
		.A(a), .D_I(d), .D_O(d_o), .D_OE(d_oe_o), .CLKZ1(clkz_o), .WAIT_N_OE(wait_oe_o), .RESET_N_I(res_drv),
		.RESET_N_OE(res_oe_o), .CS_ROM(cs_rom_o), .CS_CASH(cs_cash_o), .RA(ra_o), .V_CS(v_cs_o), .VA(va_o),
		.V_WR(v_wr_o), .VD0_I(vd0), .VD1_I(vd1), .VD2_I(vd2), .VD3_I(vd3), .VD0_O(vd0_o), .VD1_O(vd1_o),
		.VD2_O(vd2_o), .VD3_O(vd3_o), .VD_OE(vd_oe_o), .WR_COL(wr_col_o), .DAC_DATA(dac_data_o), .DAC_WS(dac_ws_o),
		.DAC_BCK(dac_bck_o), .MD_I(md), .MD_O(md_o), .MD_OE(md_oe_o), .MA(ma_o), .RAS_(ras_o), .CAS_(cas_o),
		.WE_N(we_o), .XACS(xacs_o), .XA_I(xa), .XA_O(xa_o), .XA_OE(xa_oe_o), .XA3(xa3), .SXA(sxa_o),
		.RDXA(rdxa_o), .WR_AWG(wr_awg_o), .RD_KMPS(rd_kmps_o), .WR_DWG(wr_dwg_o), .CFG_RST(1'b0), .PERS_K30(`PERS_K30_V),
		.PERS_SCROLL(`PERS_SCROLL_V));
	// power-up: the modules start their preset registers high, as the netlist (CTH = 50, CTV = 290, KB_CT = 7 ...)
	// our pins as the reference's pins would be
	wire [7:0] d_pin_o = d_oe_o ? d_o : d;
	wire [15:0] md_pin_o = md_oe_o ? md_o : md;

	// ================= models
	// ---- Z80 Z drive, ROM, cache
	// memories start unwritten (X): a read of an unwritten byte returns a fixed pseudo-random value (no init loops)
	function [7:0] dflt(input [23:0] i, input [7:0] salt); reg [31:0] x; begin
		x = ({8'd0, i} ^ {salt, 24'd0}) * 32'h9E3779B1; dflt = x[31:24] ^ x[18:11];
	end endfunction
	reg [7:0] rom [0:262143], cache [0:262143];
	assign d = z_drv ? z_do : 8'bz;
	wire [17:0] rom_a = {ra_r, a[13:0]};
	wire [7:0] rom_q, cache_q;
	assign #2 rom_q = (rom[rom_a] === 8'hxx) ? dflt(rom_a, 8'd1) : rom[rom_a];
	assign #2 cache_q = (cache[rom_a] === 8'hxx) ? dflt(rom_a, 8'd2) : cache[rom_a];
	assign d = (cs_rom_r === 1'b0 && rd_n === 1'b0) ? rom_q : 8'bz;
	assign d = (cs_cash_r === 1'b0 && rd_n === 1'b0) ? cache_q : 8'bz;
	integer n_cwr = 0;
	always @(negedge clk) if (cs_cash_r === 1'b0 && wr_n === 1'b0 && z_drv) begin cache[rom_a] <= d; n_cwr = n_cwr + 1; end

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
	wire cpu_mw = ~mr_n & ~wr_n;                      // a CPU memory write: the DRAM does not drive MD
	wire dr_rd = ras_cyc & ~ras_r[0] & we_r & ~cpu_mw;
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

	// ================= mutations (K30): one k30 line back to its 3.03a form; the bench must fail
`ifdef K30
	// (iverilog evaluates the RHS of a force only once unless it is a plain net: the 3.03a forms are nets here)
	wire m_cas_a  = dut.dc_cas | dut.cwh_q;
	wire m_we_n   = ~dut.dw_e;
	wire m_blk_mr = dut.blk_mr_q;
	wire m_kint   = dut.all_mode_e[0];
	wire m_ena    = dut.all_mode_e[1];
	wire m_nmi    = ~dut.all_mode_e[4] & dut.kb_alt & ~dut.kb_f12;
	wire [7:0] m_dir = {dut.border[2:0], dut.rgmod_e[2], dut.rgmod_e[0], 2'b00, dut.scr128};
	wire m_rst    = (dut.kb_reset | ~dut.all_mode_e[5]) & dut.soft_reset;
	wire m_wrpic  = dut.SVIDEO.x_mode[5];
	initial begin
		#1;
		case (mut)
			1: force dut.cas_a = m_cas_a;              // CAS_A
			2: force dut.WE_N = m_we_n;                // /WE
			3: force dut.blk_mr = m_blk_mr;            // BLK_MR
			4: force dut.kint_ena = m_kint;            // KEYS.int_ena
			5: force dut.KEYS.ENA = m_ena;             // KEYS.ena
			6: force dut.nmi_x = m_nmi;                // NMI_X
			7: force dut.SVIDEO.DIR_PORT = m_dir;      // DIR_PORT[4]
			8: force dut.rst_d = m_rst;                // /RESET (Ctrl+Alt+Del by ALL_MODE5)
			9: force dut.SVIDEO.wr_pic_x = m_wrpic;    // WR_PIC
			default: ;
		endcase
	end
`endif
`ifdef SCROLL
	// SCROLL: one SCROLL line back to its 3.03a form (plain nets, as above)
	wire m_kena   = dut.all_mode_e[1];
	wire m_zxw    = dut.sp_scr & ~(a[13] & ~dut.acc_gline[7]) & ~dut.acc_gline[6] & ~dut.all_mode_e[0];
	wire [7:0] m_ayp = dut.type_[0] ? dut.ay_do : dut.dc_do;
	wire [7:0] m_kemps = ({a[10], a[8]} == 2'b01) ? dut.ms_x[7:0] : ({a[10], a[8]} == 2'b11) ? ~dut.ms_y[7:0] :
	                     {6'b111111, ~dut.ms_k[0], ~dut.ms_k[1]};
	wire [10:0] m_ayf = dut.cth0d_q ? {dut.ay_r, 1'b0} : {dut.ay_l, 1'b0};
	wire m_rst    = (dut.kb_reset | ~dut.all_mode_e[5]) & dut.soft_reset;
	wire m_nmi    = ~dut.all_mode_e[4] & dut.kb_alt & ~dut.kb_f12;
	wire m_cas_a  = dut.dc_cas | dut.cwh_q;
	wire m_we_n   = ~dut.dw_e;
	wire [17:0] m_sva = {dut.SVIDEO.sva_hi, dut.SVIDEO.rsva[8:6], dut.SVIDEO.mode0[3:0], dut.SVIDEO.rsva[5:0]};
	initial begin
		#1;
		case (mut)
			1: force dut.kena = m_kena;                // KEYS.ena
			2: force dut.zx_wen = m_zxw;               // ZX_PORT[6]
			3: force dut.ay_ports = m_ayp;             // AY/PORTS
			4: force dut.kemps = m_kemps;              // KEMPS
			5: force dut.ay_full_d = m_ayf;            // AY_CHS
			6: force dut.rst_d = m_rst;                // /RESET (Ctrl+Alt+Del by ALL_MODE5)
			7: force dut.nmi_x = m_nmi;                // NMI_X
			8: force dut.cas_a = m_cas_a;              // CAS_A
			9: force dut.WE_N = m_we_n;                // /WE
			10: force dut.SVIDEO.sva_d = m_sva;        // VIDEO2 SVA (the other video lines: video2_scroll_mut)
			default: ;
		endcase
	end
`endif

	// keyboard debug (+kdbg): IN cycles and NMI terms during the phases of scenario 2; ends after the A phase
	reg [1:0] kph_p = 0;
	always @(posedge clk) if (ce && $test$plusargs("kdbg")) begin
		if (kb_ph != 0 && dut.iord_ev) $display("%0d ph %0d IN %h: ENA %b allm %h kbo %h d %h ref d_oe %b | alt %b f12 %b nmi %b",
			$time, kb_ph, a, dut.KEYS.ENA, dut.all_mode_e, dut.kbo, d, d_oe_r, dut.kb_alt, dut.kb_f12, dut.nmi_x);
		if (kb_ph == 1 && dut.kb_alt && !dut.kb_f12) $display("%0d Alt+F12: allm %h nmi %b ma12 %b/%b", $time, dut.all_mode_e, dut.nmi_x, ma_o[12], ma_r[12]);
		if (kph_p == 2 && kb_ph == 0) $finish;
		kph_p <= kb_ph;
	end

	// ================= comparison
	`EQ_CMP(clkz, 1, clkz_o, clkz_r)
	`EQ_CMP(wait_oe, 1, wait_oe_o, wait_oe_r)
	`EQ_CMP(res_oe, 1, res_oe_o, res_oe_r)
	`EQ_CMP(cs, 2, ({cs_rom_o, cs_cash_o}), ({cs_rom_r, cs_cash_r}))
	`EQ_CMP(ra, 4, ra_o, ra_r)
	`EQ_CMP(d_oe, 1, d_oe_o, d_oe_r)
	`EQ_CMP(d_pin, 8, d_pin_o, d)
	`EQ_CMP(ma, 15, ma_o, ma_r)
	`EQ_CMP(ras_cas, 7, ({ras_o, cas_o, we_o}), ({ras_r, cas_r, we_r}))
	`EQ_CMP(md_oe, 1, md_oe_o, md_oe_r)
	`EQ_CMP(md_pin, 16, md_pin_o, md)
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
			ref.\DECODE|CAS .q, cwh_r,
			ref.\ACC|MDO ,
			{ref.\DECODE|DCPP[7] .q, ref.\DECODE|DCPP[6] .q, ref.\DECODE|DCPP[5] .q, ref.\DECODE|DCPP[4] .q,
			 ref.\DECODE|DCPP[3] .q, ref.\DECODE|DCPP[2] .q, ref.\DECODE|DCPP[1] .q, ref.\DECODE|DCPP[0] .q});
	// bus conflicts (X on a bus line)
	integer xbus = 0;
	always @(negedge clk) if (cmp_on && (^d === 1'bx || ^md === 1'bx || ^xa === 1'bx || (cmp_vwr && ^{vd0, vd1, vd2, vd3} === 1'bx))) begin
		if (xbus < 5) $display("  X on a bus at %0d ns: d %h md %h xa %b vd %h%h%h%h (z_drv %b cs_rom %b cs_cash %b rd %b d_oe %b)",
			$time, d, md, xa, vd3, vd2, vd1, vd0, z_drv, cs_rom_r, cs_cash_r, rd_n, d_oe_r);
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
	wire [127:0] sig_r = {clkz_r, wait_oe_r, res_oe_r, cs_rom_r, cs_cash_r, ra_r, d_oe_r, d, ma_r, ras_r, cas_r, we_r,
		md_oe_r, md, va_r, xacs_r, xa_oe_r, sxa_r, rdxa_r, wr_awg_r, rd_kmps_r, wr_dwg_r, wr_col_r, dac_data_r,
		dac_ws_r, dac_bck_r};
	always @(negedge clk) if (cmp_on && first && sig_o !== sig_r) begin
		first = 0;
		$display("first mismatch at %0d ns (ce_n=%b): diff %h", $time, ce_n, sig_o ^ sig_r);
		$display("  clkz %b/%b wait %b/%b res %b/%b cs %b%b/%b%b ra %h/%h d_oe %b/%b d %h/%h ma %h/%h ras %b/%b cas %b/%b we %b/%b",
			clkz_o, clkz_r, wait_oe_o, wait_oe_r, res_oe_o, res_oe_r, cs_rom_o, cs_cash_o, cs_rom_r, cs_cash_r, ra_o, ra_r,
			d_oe_o, d_oe_r, d_pin_o, d, ma_o, ma_r, ras_o, ras_r, cas_o, cas_r, we_o, we_r);
		$display("  md_oe %b/%b md %h/%h va %h/%h xacs %b/%b strobes %b/%b wr_col %b/%b dac %b%b%b/%b%b%b",
			md_oe_o, md_oe_r, md_pin_o, md, va_o, va_r, xacs_o, xacs_r, {sxa_o, rdxa_o, wr_awg_o, rd_kmps_o, wr_dwg_o},
			{sxa_r, rdxa_r, wr_awg_r, rd_kmps_r, wr_dwg_r}, wr_col_o, wr_col_r, dac_data_o, dac_ws_o, dac_bck_o,
			dac_data_r, dac_ws_r, dac_bck_r);
		$display("  z80 m1 %b rf %b io %b wr %b rd %b mr %b a %h | ours iord %b dcpp %h rd_ram %b blk_mem %b type %h",
			m1_n, rf_n, io_n, wr_n, rd_n, mr_n, a, dut.iord_e, dut.dcpp, dut.rd_ram, dut.blk_mem, dut.type_);
		$display("  ref /IORD %b DCPP %b%b%b%b%b%b%b%b", ref.\/IORD .q, ref.\DECODE|DCPP[7] .q, ref.\DECODE|DCPP[6] .q,
			ref.\DECODE|DCPP[5] .q, ref.\DECODE|DCPP[4] .q, ref.\DECODE|DCPP[3] .q, ref.\DECODE|DCPP[2] .q,
			ref.\DECODE|DCPP[1] .q, ref.\DECODE|DCPP[0] .q);
		if ($test$plusargs("stop")) #200 $finish;
	end

	// ================= coverage (our module; equal outputs imply the same paths in the reference)
	integer cv_bord = 0, cv_allm = 0, cv_rgm = 0, cv_hold = 0, cv_cblxx = 0, cv_romrg = 0, cv_isa = 0, cv_sys = 0;
	integer cv_syspg = 0, cv_cash = 0, cv_a20 = 0, cv_mdp0 = 0, cv_mdp1 = 0, cv_mdp2 = 0, cv_hddr0 = 0, cv_hddr1 = 0;
	integer cv_soft = 0, cv_xacs = 0, cv_dos = 0, cv_ixclk = 0, cv_ixset = 0, cv_cint = 0, cv_cblwr = 0, cv_cblf = 0;
	integer cv_aya = 0, cv_ayd = 0, cv_acc = 0, cv_dcas = 0, cv_pdd0 = 0, cv_pdd1 = 0, cv_pdd2 = 0, cv_pdd3 = 0;
	integer cv_kms0 = 0, cv_kms1 = 0, cv_kms2 = 0, cv_ts = 0, cv_f12 = 0, cv_nmi = 0, cv_cph = 0, cv_cpv = 0;
	integer cv_kcc = 0, cv_ms = 0, cv_tape = 0, cv_rom = 0, cv_cch = 0, cv_turbo = 0, cv_wrom = 0, cv_worig = 0;
	integer cv_vzx = 0, cv_vgr = 0, cv_glis = 0, cv_blkmr = 0, cv_kint = 0, cv_sh = 0, cv_kbo = 0, cv_kdx = 0, cv_bmw = 0, cv_bmd = 0;
	reg cvp_soft = 0, cvp_xacs = 1, cvp_dos = 1, cvp_kcc = 0, cvp_ms = 0, cvp_tape = 0, cvp_rom = 1, cvp_cch = 1, cvp_turbo = 1;
	reg cvp_ix = 1, cvp_nmi = 0, cvp_a20 = 1, cvp_wrom = 1, cvp_kint = 1;
	always @(posedge clk) if (ce & cmp_on) begin
		if (dut.iowr_ev) begin
			if (dut.bord_en_d) cv_bord = cv_bord + 1; if (dut.am_en_d) cv_allm = cv_allm + 1;
			if (dut.rgmod_en_d) cv_rgm = cv_rgm + 1; if (dut.hold_en_d) cv_hold = cv_hold + 1;
			if (dut.cbl_en_d) cv_cblxx = cv_cblxx + 1;
			if (dut.rom_en_d | (~dut.sys_n_e & dut.rom5c_d)) cv_romrg = cv_romrg + 1;
			if (dut.blk_r & dut.isa_en_d) cv_isa = cv_isa + 1;
			if (dut.sys_ena2_d) begin cv_sys = cv_sys + 1; if (~d[1]) cv_syspg = cv_syspg + 1; end
		end
		if (dut.iord_ev & dut.cash_en_d) cv_cash = cv_cash + 1;
		if (cvp_a20 & ~dut.isa_a20) cv_a20 = cv_a20 + 1; cvp_a20 = dut.isa_a20;
		if (dut.mdp_ev) begin if (dut.type_nx[0]) cv_mdp2 = cv_mdp2 + 1; else if (dut.hdd_flip & dut.hdd_data_nx) cv_mdp1 = cv_mdp1 + 1; else cv_mdp0 = cv_mdp0 + 1; end
		if (dut.hddr_ev) begin if (dut.hsel_q) cv_hddr1 = cv_hddr1 + 1; else cv_hddr0 = cv_hddr0 + 1; end
		if (~cvp_soft & dut.sr_s2_e) cv_soft = cv_soft + 1; cvp_soft = dut.sr_s2_e;
		if (cvp_xacs & ~dut.xacs_e) cv_xacs = cv_xacs + 1; cvp_xacs = dut.xacs_e;
		if (cvp_dos != dut.dos_e) cv_dos = cv_dos + 1; cvp_dos = dut.dos_e;
		if (dut.ix_ev) cv_ixclk = cv_ixclk + 1;
		if (cvp_ix & ~dut.int_x) cv_ixset = cv_ixset + 1; cvp_ix = dut.int_x;
		if (dut.cint_ev) cv_cint = cv_cint + 1;
		if (dut.cbl_wren) cv_cblwr = cv_cblwr + 1; if (dut.cblwr_fall) cv_cblf = cv_cblf + 1;
		if (~dut.aya_q & dut.aya_d) cv_aya = cv_aya + 1; if (~dut.ayd_q & dut.ayd_d) cv_ayd = cv_ayd + 1;
		if (dut.acc_dir[0]) cv_acc = cv_acc + 1; if (dut.dcas) cv_dcas = cv_dcas + 1;
		if (dut.D_OE & ~io_n & ~rd_n & ~dut.iord_e) case (dut.type_[2:1]) 0: cv_pdd0 = cv_pdd0 + 1; 1: cv_pdd1 = cv_pdd1 + 1;
			2: begin cv_pdd2 = cv_pdd2 + 1; if (dut.type_[0]) case ({a[10], a[8]}) 2'b01: cv_kms1 = cv_kms1 + 1; 2'b11: cv_kms2 = cv_kms2 + 1;
				default: cv_kms0 = cv_kms0 + 1; endcase end
			default: cv_pdd3 = cv_pdd3 + 1; endcase
		if (dut.f12_rise) begin cv_f12 = cv_f12 + 1; if (dut.ts_t) cv_ts = cv_ts + 1; end
		if (~cvp_nmi & dut.nmi_x) cv_nmi = cv_nmi + 1; cvp_nmi = dut.nmi_x;
		if (dut.copyh_q) cv_cph = cv_cph + 1; if (dut.copyv_q) cv_cpv = cv_cpv + 1;
		if (cvp_kcc != dut.kbd_cc) cv_kcc = cv_kcc + 1; cvp_kcc = dut.kbd_cc;
		if (cvp_ms != dut.mouse_d) cv_ms = cv_ms + 1; cvp_ms = dut.mouse_d;
		if (cvp_tape != dut.tape_in) cv_tape = cv_tape + 1; cvp_tape = dut.tape_in;
		if (cvp_rom & ~dut.CS_ROM) cv_rom = cv_rom + 1; cvp_rom = dut.CS_ROM;
		if (cvp_cch & ~dut.CS_CASH) cv_cch = cv_cch + 1; cvp_cch = dut.CS_CASH;
		if (cvp_turbo != dut.turbo) cv_turbo = cv_turbo + 1; cvp_turbo = dut.turbo;
		if (cvp_wrom & ~dut.wait_rom) cv_wrom = cv_wrom + 1; cvp_wrom = dut.wait_rom;
		if (~dut.wait_orig) cv_worig = cv_worig + 1;
		if (~dut.SVIDEO.e_wr) begin if (dut.SVIDEO.VAI[19]) cv_vgr = cv_vgr + 1; else cv_vzx = cv_vzx + 1; end
		if (dut.gliss) cv_glis = cv_glis + 1; if (dut.blk_mr) cv_blkmr = cv_blkmr + 1;
		if (cvp_kint != dut.k_int) cv_kint = cv_kint + 1; cvp_kint = dut.k_int;
		if (dut.cth5_rise & ~dut.sinc_2) cv_sh = cv_sh + 1;
		if (~dut.mc_write & ~dut.blk_mwr2) begin if (dut.blk_mr) cv_bmw = cv_bmw + 1; if (dut.blk_mr_d !== dut.blk_mr_q) cv_bmd = cv_bmd + 1; end
		if (dut.kbo !== 8'hFF) cv_kbo = cv_kbo + 1; if (dut.KEYS.kdx_q !== 6'h3F) cv_kdx = cv_kdx + 1;
	end
	task cov_report; begin
		$display("  coverage: port writes BORDER %0d ALL_MODE %0d RGMOD %0d HOLD %0d CBL_XX %0d ROM_RG %0d ISA_PORT %0d SYS %0d SYS_PG %0d,",
			cv_bord, cv_allm, cv_rgm, cv_hold, cv_cblxx, cv_romrg, cv_isa, cv_sys, cv_syspg);
		$display("    CASH_ON %0d, ISA_A20 pulses %0d; MDP loads MD lo / HDDR / MD hi %0d %0d %0d; HDDR loads D / MD hi %0d %0d;",
			cv_cash, cv_a20, cv_mdp0, cv_mdp1, cv_mdp2, cv_hddr0, cv_hddr1);
		$display("    soft reset %0d, XACS %0d, DOS changes %0d, INT_X clocks %0d / INT %0d, CBL_INT %0d, CBL writes %0d (strobes %0d),",
			cv_soft, cv_xacs, cv_dos, cv_ixclk, cv_ixset, cv_cint, cv_cblwr, cv_cblf);
		$display("    AY addr / data writes %0d %0d, accelerator on CEs %0d (DOUBLE_CAS %0d), IN data by TYPE[2..1] 0/1/2/3 %0d %0d %0d %0d,",
			cv_aya, cv_ayd, cv_acc, cv_dcas, cv_pdd0, cv_pdd1, cv_pdd2, cv_pdd3);
		$display("    Kempston buttons / X / Y CEs %0d %0d %0d, F12 rises %0d (TEST_SWITCH %0d), NMI %0d, COPY_SINC_H / V %0d %0d,",
			cv_kms0, cv_kms1, cv_kms2, cv_f12, cv_ts, cv_nmi, cv_cph, cv_cpv);
		$display("    KBD_CC / MOUSE_D / TAPE_IN changes %0d %0d %0d, KEYS.int changes %0d, CS_ROM %0d, CS_CASH %0d, TURBO changes %0d,",
			cv_kcc, cv_ms, cv_tape, cv_kint, cv_rom, cv_cch, cv_turbo);
		$display("    WAIT_ROM %0d, WAIT_ORIG CEs %0d, video writes ZX / graphics CEs %0d %0d, GLISSER CEs %0d, BLK_MR CEs %0d, SINC_HOLD[8..4] counts %0d",
			cv_wrom, cv_worig, cv_vzx, cv_vgr, cv_glis, cv_blkmr, cv_sh);
		$display("    ZX matrix: KBO != FF CEs %0d, KDX != 3F CEs %0d; BLK_MR in DRAM writes (MC_WRITE = 0, no other block) CEs %0d, k30 / 3.03a forms differ there %0d",
			cv_kbo, cv_kdx, cv_bmw, cv_bmd);
	end endtask
	task mark(input [8*24-1:0] name); $display("  [%0d us, %0d cycles] %0s", $time / 1000, n_ops, name); endtask

	// ================= Z80 bus model (dcp test): outputs change at the CE after a CLK_Z80 edge
	reg wait_s = 1;
	always @(negedge clk) wait_s <= wait_w;
	task zr; begin @(posedge clkz_r); #2; end endtask
	task zf; begin @(negedge clkz_r); #2; end endtask
	task wsamp; begin while (wait_s === 1'b0) begin zr; zf; end end endtask
	reg [6:0] r_reg = 0;
	integer n_ops = 0;
	task t1(input [15:0] ad, input m1); begin zr; a_nx = ad; m1_nx = ~m1; rf_nx = 1; drv_nx = 0; n_ops = n_ops + 1; end endtask
	task m1cyc(input [15:0] ad); begin
		t1(ad, 1);
		zf; mr_nx = 0; rd_nx = 0;
		zr; zf; wsamp;
		zr; m1_nx = 1; mr_nx = 1; rd_nx = 1; rf_nx = 0; a_nx = {8'h3F, 1'b0, r_reg}; r_reg = r_reg + 1;
		zf; mr_nx = 0;
		zr; zf; mr_nx = 1;
	end endtask
	task mrd(input [15:0] ad); begin
		t1(ad, 0); zf; mr_nx = 0; rd_nx = 0; zr; zf; wsamp; zr; zf; mr_nx = 1; rd_nx = 1;
	end endtask
	task mwr(input [15:0] ad, input [7:0] dv); begin
		t1(ad, 0); do_nx = dv; drv_nx = 1; zf; mr_nx = 0; zr; zf; wr_nx = 0; wsamp; zr; zf; mr_nx = 1; wr_nx = 1;
	end endtask
	task ior(input [15:0] p); begin
		t1(p, 0); periph = $random(seed); zr; io_nx = 0; rd_nx = 0; zf; zr; zf; wsamp; zr; zf; io_nx = 1; rd_nx = 1;
	end endtask
	task iow(input [15:0] p, input [7:0] dv); begin
		t1(p, 0); do_nx = dv; drv_nx = 1; zr; io_nx = 0; wr_nx = 0; zf; zr; zf; wsamp; zr; zf; io_nx = 1; wr_nx = 1;
	end endtask
	task inta; begin
		t1(16'h1234, 1); zf; zr; zf; zr; zf; io_nx = 0; zr; zf; wsamp;
		zr; m1_nx = 1; io_nx = 1; rf_nx = 0; a_nx = {8'h3F, 1'b0, r_reg}; r_reg = r_reg + 1;
		zf; mr_nx = 0; zr; zf; mr_nx = 1;
	end endtask
	task idle(input integer n); begin zr; rf_nx = 1; drv_nx = 0; repeat (n - 1) zr; end endtask
	// an instruction fetched from the ROM (window 0 = ROM): the opcode is put at that offset of every ROM page
	reg [15:0] pc = 16'h0100;
	task op(input [7:0] o); integer k; begin
		for (k = 0; k < 16; k = k + 1) rom[{k[3:0], pc[13:0]}] = o;
		m1cyc(pc); pc = {2'b00, pc[13:0] + 14'd1};
	end endtask

	// ---- ports (A: the table index bits A15 A14 A13 A7 A6 A5 A2 A1 A0) and their descriptors
	localparam [15:0] P_FE = 16'h00FE, P_PN = 16'h7FFD, P_SC = 16'h1FFD, P_AYA = 16'hFFFD, P_AYD = 16'hBFFD,
		P_CNF = 16'h00C6, P_CNFS = 16'h0086, P_ALLM = 16'h00C3, P_RGM = 16'h00C5, P_HOLD = 16'h20CB, P_AGR = 16'h00C4,
		P_XCNT = 16'h00C7, P_CBL = 16'h0088, P_CBLM = 16'h0089, P_ROMRG = 16'h008F, P_5C = 16'h005C,
		P_SYS0 = 16'h007C, P_SYS1 = 16'h003C, P_CASH1 = 16'h00FB, P_CASH0 = 16'h007B, P_A20 = 16'h001B,
		P_ISA = 16'h00F7, P_IDE = 16'h0050, P_IDE1 = 16'h2051, P_WG = 16'h001F, P_KMS = 16'hFADF,
		P_W1 = 16'h4089, P_W2 = 16'h40A9, P_W3 = 16'h80F5, P_W0 = 16'h40C9;
	task cnf(input [7:0] v); iow(P_CNF, v); endtask
	// load CBL_CNT in both (it takes 128 sample steps to the first CBL_INT otherwise): forced D / ENA / SLOAD of the
	// reference registers and our next value, for the edge where CTH1 falls
	task load_cbl_cnt(input [7:0] v); begin
		@(negedge clk); while (!(ce && dut.cth1_fall)) @(negedge clk);
		force ref.\CBL_CNT[0] .d = v[0]; force ref.\CBL_CNT[1] .d = v[1]; force ref.\CBL_CNT[2] .d = v[2];
		force ref.\CBL_CNT[3] .d = v[3]; force ref.\CBL_CNT[4] .d = v[4]; force ref.\CBL_CNT[5] .d = v[5];
		force ref.\CBL_CNT[6] .d = v[6]; force ref.\CBL_CNT[7] .d = v[7];
		force ref.\CBL_CNT[0] .ena = 1'b1; force ref.\CBL_CNT[1] .ena = 1'b1; force ref.\CBL_CNT[2] .ena = 1'b1;
		force ref.\CBL_CNT[3] .ena = 1'b1; force ref.\CBL_CNT[4] .ena = 1'b1; force ref.\CBL_CNT[5] .ena = 1'b1;
		force ref.\CBL_CNT[6] .ena = 1'b1; force ref.\CBL_CNT[7] .ena = 1'b1;
		force ref.\CBL_CNT[0] .sload = 1'b0; force ref.\CBL_CNT[1] .sload = 1'b0; force ref.\CBL_CNT[2] .sload = 1'b0;
		force ref.\CBL_CNT[3] .sload = 1'b0; force ref.\CBL_CNT[4] .sload = 1'b0; force ref.\CBL_CNT[5] .sload = 1'b0;
		force ref.\CBL_CNT[6] .sload = 1'b0; force ref.\CBL_CNT[7] .sload = 1'b0;
		force dut.cbl_cnt_r = v;
		@(negedge clk);
		release dut.cbl_cnt_r;
		release ref.\CBL_CNT[0] .d; release ref.\CBL_CNT[1] .d; release ref.\CBL_CNT[2] .d; release ref.\CBL_CNT[3] .d;
		release ref.\CBL_CNT[4] .d; release ref.\CBL_CNT[5] .d; release ref.\CBL_CNT[6] .d; release ref.\CBL_CNT[7] .d;
		release ref.\CBL_CNT[0] .ena; release ref.\CBL_CNT[1] .ena; release ref.\CBL_CNT[2] .ena; release ref.\CBL_CNT[3] .ena;
		release ref.\CBL_CNT[4] .ena; release ref.\CBL_CNT[5] .ena; release ref.\CBL_CNT[6] .ena; release ref.\CBL_CNT[7] .ena;
		release ref.\CBL_CNT[0] .sload; release ref.\CBL_CNT[1] .sload; release ref.\CBL_CNT[2] .sload;
		release ref.\CBL_CNT[3] .sload; release ref.\CBL_CNT[4] .sload; release ref.\CBL_CNT[5] .sload;
		release ref.\CBL_CNT[6] .sload; release ref.\CBL_CNT[7] .sload;
		#1 if (dut.cbl_cnt !== v) $display("load_cbl_cnt %h: ours %h", v, dut.cbl_cnt);
	end endtask

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

	// ---- random operations (accelerator off: ALL_MODE0 = 0)
	task rand_op; integer r, w; reg [15:0] ad; reg [7:0] dv; begin
		r = $random(seed) & 255; ad = $random(seed); dv = $random(seed); w = $random(seed) & 15;
		if (r < 60) op($random(seed));
		else if (r < 100) m1cyc(ad);
		else if (r < 140) mrd(ad);
		else if (r < 175) mwr(ad, dv);
		else if (r < 195) ior(ad);
		else if (r < 215) iow((w < 8) ? ad : {ad[15:8], 8'hFE}, dv);
		else if (r < 230) case (w & 7)
			0: ior(P_FE); 1: ior(P_KMS ^ {ad[2], 1'b0, ad[0], 8'h00}); 2: ior(P_AYA); 3: ior(P_IDE);
			4: iow(P_AYA, dv & 15); 5: iow(P_AYD, dv); 6: iow(P_CBL, dv); default: ior(P_WG);
		endcase
		else if (r < 236) inta;
		else idle(1 + (w & 3));
	end endtask

	integer i, j, k, p, h, v, c5, base;
	reg [15:0] wa;
	initial begin
		if (!$value$plusargs("scen=%d", scen)) scen = 0;
		if (!$value$plusargs("mut=%d", mut)) mut = 0;
		// mode table in the video RAM: word {page, CTH, CT5, 11, CTV[8..3]}, byte 3 = MODE0, 2 = MODE1, 1 = MODE2
		for (p = 0; p < 2; p = p + 1) for (v = 0; v < 64; v = v + 1) for (h = 0; h < 64; h = h + 8) begin
			base = $random(seed) & 255;
			for (i = h; i < h + 8; i = i + 1) for (c5 = 0; c5 < 2; c5 = c5 + 1) begin
				wa = {p[0], i[5:0], c5[0], 2'b11, v[5:0]};
				vram[{wa, 2'd3}] = (($random(seed) & 7) == 0) ? pick_mode0($random(seed) & 255, $random(seed)) :
				                    pick_mode0(base, $random(seed));
			end
		end
		// port table: random descriptors, then the ports used
		pick[0] = 8'h00; pick[1] = 8'h10; pick[2] = 8'h13; pick[3] = 8'h1C; pick[4] = 8'h20; pick[5] = 8'h22;
		pick[6] = 8'h2A; pick[7] = 8'h30; pick[8] = 8'h40; pick[9] = 8'h52; pick[10] = 8'h58; pick[11] = 8'h80;
		pick[12] = 8'h88; pick[13] = 8'h8C; pick[14] = 8'h90; pick[15] = 8'h91; pick[16] = 8'h9F; pick[17] = 8'hB0;
		pick[18] = 8'hC2; pick[19] = 8'hC5; pick[20] = 8'hC4; pick[21] = 8'hD7; pick[22] = 8'hE0; pick[23] = 8'hE3;
		pick[24] = 8'h89; pick[25] = 8'h1B; pick[26] = 8'hCB; pick[27] = 8'h00; pick[28] = 8'h21; pick[29] = 8'hC7;
		pick[30] = 8'h40; pick[31] = 8'h00;
		// the other table entries: random descriptors of the pick list (ddef), never the system ports C0 / C1 / C3 /
		// C6 / CE / Fx / Ex / 8F
		dset(P_FE, 1, 8'h40); dset(P_FE, 0, 8'hC2); dset(P_PN, 0, 8'hC1); dset(P_SC, 0, 8'hC0);
		dset(P_AYA, 0, 8'h90); dset(P_AYA, 1, 8'h52); dset(P_AYD, 0, 8'h91); dset(P_AYD, 1, 8'h8C);
		dset(P_CNF, 0, 8'hC6); dset(P_CNFS, 0, 8'hCE); dset(P_ALLM, 0, 8'hC3); dset(P_RGM, 0, 8'hC5);
		dset(P_HOLD, 0, 8'hCB); dset(P_AGR, 0, 8'hC4); dset(P_XCNT, 0, 8'hC7); dset(P_CBL, 0, 8'h88);
		dset(P_CBLM, 0, 8'h89); dset(P_ROMRG, 0, 8'h8F); dset(P_5C, 0, 8'h00); dset(P_SYS0, 0, 8'h00);
		dset(P_SYS1, 0, 8'h00); dset(P_CASH1, 1, 8'h00); dset(P_CASH0, 1, 8'h00); dset(P_A20, 0, 8'h1B);
		dset(P_ISA, 0, 8'hF2); dset(P_IDE, 1, 8'h20); dset(P_IDE, 0, 8'h20); dset(P_IDE1, 1, 8'h21);
		dset(P_IDE1, 0, 8'h21); dset(P_WG, 1, 8'h10); dset(P_WG, 0, 8'h14); dset(P_KMS, 1, 8'h58);
		dset(P_W1, 0, 8'hE9); dset(P_W2, 0, 8'hEA); dset(P_W3, 0, 8'hF5); dset(P_W0, 0, 8'hE0);

		if ($test$plusargs("initonly")) $finish;
		// ---- power-up: the MAX holds /RESET, SINC_1 pulses make line clocks (the keyboard ends its reset after 4)
		sinc_run = 1;
		repeat (100) @(posedge clk);
		cmp_on = 1;
		repeat (200) @(posedge clk);
		res_nx = 1;
		while (res_w !== 1'b1) @(posedge clk);
		$display("  /RESET released at %0d ns", $time);
		idle(10);
		ior(P_FE);                                     // STARTING: the port table is active
		if (scen == 2) begin
			mark("keyboard");
			iow(P_ALLM, 8'h03);                        // INT by keys, ZX matrix, accelerator on
			iow(P_HOLD, 8'h7E); sinc_lo = 2 * 96;      // COPY_SINC_H one CT4 rise after SINC_1 falls
			iow(P_W1, 8'h50); mwr(16'h4000, 8'h12); iow(P_W1, 8'h05);   // a video write: V_WR comparable
			fork
				begin
					ps2_byte(8'h07); repeat (4500) @(posedge clk);          // F12: TEST_SWITCH -> TURBO_HAND
					ps2_byte(8'h11); repeat (4500) @(posedge clk);          // Alt: NMI (and its matrix row)
					// Ctrl+Alt+Del twice (ALL_MODE5 random): 3.03a resets only with ALL_MODE5 = 1, k30 always
					ps2_byte(8'h14); repeat (4500) @(posedge clk);          // Ctrl
					ps2_byte(8'hE0); ps2_byte(8'h71); repeat (9000) @(posedge clk);   // Del (E0 71)
					ps2_byte(8'hE0); ps2_byte(8'hF0); ps2_byte(8'h71); ps2_byte(8'hF0); ps2_byte(8'h14);
					ps2_byte(8'hF0); ps2_byte(8'h11); repeat (4500) @(posedge clk);
					ps2_byte(8'h14); ps2_byte(8'h11); ps2_byte(8'hE0); ps2_byte(8'h71); repeat (9000) @(posedge clk);
					ps2_byte(8'hE0); ps2_byte(8'hF0); ps2_byte(8'h71); ps2_byte(8'hF0); ps2_byte(8'h14);
					ps2_byte(8'hF0); ps2_byte(8'h11); repeat (4500) @(posedge clk);
					// Alt+F12 (NMI_X of 3.03a, by ALL_MODE4); A held (ZX matrix reads with ALL_MODE1 0 / 1)
					kb_ph = 1; ps2_byte(8'h11); repeat (4500) @(posedge clk); ps2_byte(8'h07); repeat (9000) @(posedge clk);
					ps2_byte(8'hF0); ps2_byte(8'h07); ps2_byte(8'hF0); ps2_byte(8'h11);
					kb_ph = 2; ps2_byte(8'h1C); repeat (18000) @(posedge clk); ps2_byte(8'hF0); ps2_byte(8'h1C);
					kb_ph = 0; repeat (4500) @(posedge clk);
					kb_done = 1;
				end
				begin
					while (!kb_done) begin
						// Alt+F12: ALL_MODE4 = 0 (NMI of 3.03a enabled); A held: matrix reads with ALL_MODE1 = 0 and 1
						if (kb_ph == 1) begin if (!ph1_done) iow(P_ALLM, 8'h01); ph1_done = 1; end
						if (kb_ph == 2) begin iow(P_ALLM, 8'h01); ior(16'hFDFE); ior(16'h00FE); iow(P_ALLM, 8'h0B); ior(16'hFDFE); end
						else case ($random(seed) & 7)
							0, 1: ior({$random(seed), 8'hFE}); 2: m1cyc($random(seed)); 3: inta;
							4: iow(P_ALLM, {$random(seed)} & ((kb_ph == 1) ? 8'h2F : 8'h3F)); 5: mrd($random(seed)); default: idle(4);
						endcase
					end
				end
			join
		end else if (scen == 1) begin
			sinc_run = 0;
			mark("3.5 MHz");
			iow(P_ALLM, 8'h00);
			cnf(8'h02); repeat (4) op(8'h00);          // TB_SW = 0: 3.5 MHz, the original waits of windows 1 / 3
			mrd(16'h4000); mwr(16'h4001, 8'h01); mrd(16'hC000); mwr(16'hC001, 8'h02); mrd(16'h8000);
			iow(P_PN, 8'h04); mrd(16'hC002); mwr(16'hC003, 8'h03); ior(P_FE); iow(P_FE, 8'h02);
			iow(P_ALLM, 8'h04); mrd(16'h4000); mrd(16'hC000); iow(P_ALLM, 8'h00);
			for (i = 0; i < 8; i = i + 1) rand_op;
			cnf(8'h03); repeat (4) op(8'h00);          // turbo again
			mark("CBL FIFO interrupt");
			iow(P_CBLM, 8'hDF);                        // FIFO, stereo, interrupt, 109 kHz
			for (i = 0; i < 6; i = i + 1) iow(P_CBL, $random(seed));
			load_cbl_cnt(8'h7A);
			for (i = 0; i < 30; i = i + 1) begin
				if (i % 3 == 0) inta; else if (i % 3 == 1) iow(P_CBL, $random(seed)); else idle(8);
			end
			iow(P_CBLM, 8'hFF); for (i = 0; i < 6; i = i + 1) iow(P_CBL, $random(seed));   // 16 bit
			load_cbl_cnt(8'hFC);
			for (i = 0; i < 20; i = i + 1) begin if (i % 4 == 0) inta; else iow(P_CBL, $random(seed)); end
			idle(300); inta; idle(20);
			iow(P_CBLM, 8'h00);
			mark("COPY_SINC_V");
			iow(P_HOLD, 8'hFE); sinc_lo = 2 * 96; sinc_run = 1;
			for (i = 0; i < 30; i = i + 1) rand_op;
			iow(P_HOLD, 8'h1E); sinc2_s = 0; for (i = 0; i < 40; i = i + 1) rand_op; sinc2_s = 1;
			iow(P_HOLD, 8'hF7); for (i = 0; i < 30; i = i + 1) rand_op;
			sinc_run = 0;
			mark("soft reset");
			iow(P_SC, 8'h10); iow(P_W3, 8'hA3); mwr(16'hC000, 8'h00); idle(20);
			while (res_w !== 1'b1) @(posedge clk);
			idle(10); ior(P_FE); for (i = 0; i < 30; i = i + 1) rand_op;
		end else begin
			sinc_run = 0;
			// BIOS-like init: system ports, pages, border, video, accelerator, sound
			mark("BIOS-like init");
			iow(P_ALLM, 8'h00);                        // accelerator off, ZX screen copy on, original waits, NMI on
			iow(P_FE, 8'h05); iow(P_FE, 8'h1A); iow(P_RGM, 8'h01); iow(P_RGM, 8'h04); iow(P_RGM, 8'h00);
			iow(P_HOLD, 8'h7E);
			repeat (4) op(8'h00);
			mrd(16'h0123); mrd(16'h4000); mwr(16'h4001, 8'h11); mrd(16'h8000); mwr(16'h8002, 8'h22);
			mrd(16'hC000); mwr(16'hC003, 8'h33);
			mwr(16'h4800, 8'h44); mwr(16'h5A00, 8'h55);    // ZX screen / attributes: copied to the video RAM
			// the copy by ALL_MODE0 = 0 (3.03a, k30) / ALL_MODE3 = 1 (SCROLL)
			iow(P_ALLM, 8'h08); mwr(16'h4802, 8'h77); mwr(16'h5A01, 8'h88);
			iow(P_ALLM, 8'h09); mwr(16'h4803, 8'h99); mwr(16'h5A02, 8'hAA); iow(P_ALLM, 8'h00);
			iow(P_PN, 8'h07); mrd(16'hC100); mwr(16'hC101, 8'h66); iow(P_PN, 8'h08); mwr(16'hC000, 8'h12);
			iow(P_SC, 8'h01); mrd(16'h0200); iow(P_SC, 8'h00);
			// DOS: an M1 at 3Dxx with PN4 (BASIC 48 ROM) turns it on, any M1 above 3FFF off
			iow(P_PN, 8'h10); m1cyc(16'h3D2F); mrd(16'h0000); ior(P_WG); m1cyc(16'h4000); ior(P_WG); iow(P_PN, 8'h00);
			mark("graphics pages");
			// graphics pages: window 1 = 0x50 (video RAM copy), 0x54 (video only), 0x58 (FF transparent)
			iow(P_AGR, 8'h10); iow(P_W1, 8'h50); mwr(16'h4000, 8'hA5); mwr(16'h4123, 8'h5A); mrd(16'h4000);
			iow(P_W1, 8'h54); mwr(16'h4200, 8'h01); mwr(16'h43E0, 8'h02);
			iow(P_W1, 8'h58); mwr(16'h4300, 8'hFF); mwr(16'h4301, 8'h03);
			iow(P_W1, 8'h05);
			mark("AY");
			iow(P_AYA, 8'h07); iow(P_AYD, 8'h38); iow(P_AYA, 8'h08); iow(P_AYD, 8'h0F);
			iow(P_AYA, 8'h09); iow(P_AYD, 8'h0A); iow(P_AYA, 8'h0A); iow(P_AYD, 8'h05); ior(P_AYA);
			iow(P_AYA, 8'h00); iow(P_AYD, 8'h10); ior(P_AYA);
			iow(P_FE, 8'h10); iow(P_FE, 8'h00);           // beeper
			mark("Covox / CBL");
			iow(P_CBL, 8'h80); idle(10); iow(P_CBL, 8'h40); idle(10);
			iow(P_CBLM, 8'h8F); for (i = 0; i < 6; i = i + 1) iow({i[7:0], 8'h88}, 8'h10 * i);
			idle(20);
			iow(P_CBLM, 8'hBE); for (i = 0; i < 6; i = i + 1) iow(P_CBL, $random(seed));
			idle(30);
			iow(P_CBLM, 8'h00);
			mark("keyboard / mouse / IDE");
			iow(P_ALLM, 8'h02); ior(16'hFEFE); ior(16'h7FFE); ior(P_FE);
			ior(16'hFADF); ior(16'hFBDF); ior(16'hFFDF);
			ior(P_IDE); ior(P_IDE); iow(P_IDE, 8'h12); iow(P_IDE, 8'h34); ior(P_IDE1); iow(P_IDE1, 8'h56);
			ior(P_WG); iow(P_WG, 8'h80);
			mark("ROM / cache / ISA");
			iow(P_SYS1, 8'h00); mrd(16'h0100); mwr(16'h0101, 8'h77); iow(P_SYS0, 8'h01); mrd(16'h0100);
			iow(P_SYS0, 8'h00); mrd(16'h0200);
			ior(P_CASH1); mwr(16'h1000, 8'h99); mrd(16'h1000); mrd(16'h2001); ior(P_CASH0); mrd(16'h1000);
			iow(P_ROMRG, 8'h03); mrd(16'h0300); iow(P_5C, 8'h06); mrd(16'h0300);
			iow(P_ROMRG, 8'h12); mwr(16'h0100, 8'hAA); mwr(16'h4100, 8'hBB); mwr(16'h8100, 8'hCC); mrd(16'h0100); iow(P_ROMRG, 8'h00);
			iow(P_SC, 8'h10); iow(P_ISA, 8'hD2); mrd(16'hC000); mwr(16'hC001, 8'h01); iow(P_A20, 8'h01);
			mrd(16'hC002); iow(P_ISA, 8'h02); iow(P_SC, 8'h00);
			mark("accelerator");
			iow(P_ALLM, 8'h01);
			op(8'h52); op(8'h77); mwr(16'hC000, 8'd5);                         // LD D,D: count 5
			op(8'h49); op(8'h77); mwr(16'hC010, 8'hAA); op(8'h40);            // LD C,C: fill
			op(8'h6D); op(8'h7E); mrd(16'hC010); op(8'h77); mwr(16'hC100, 8'h00); op(8'h40);   // LD L,L: copy
			iow(P_AGR, 8'h20); iow(P_W1, 8'h50);
			op(8'h5B); op(8'h77); mwr(16'h4010, 8'h3C); op(8'h40);            // LD E,E: vertical fill, video
			op(8'h6D); op(8'hAE); mrd(16'hC100); op(8'hB6); mrd(16'hC000); op(8'h77); mwr(16'h4400, 8'h00); op(8'h40);
			iow(P_XCNT, 8'h35); op(8'h7F); op(8'h7E); mrd(16'h4400); op(8'h77); mwr(16'h4500, 8'h00); op(8'h40);
			ior(P_IDE); op(8'h64); op(8'h77); mwr(16'hC200, 8'h33); ior(P_IDE); op(8'h77); mwr(16'hC202, 8'h44); op(8'h40);
			op(8'hDB); mrd(16'h0000); ior(16'h001F);
			op(8'h49); inta; op(8'hED); op(8'h4D); op(8'h40);
			iow(P_CBLM, 8'h12); iow(P_W3, 8'hFD); op(8'h52); op(8'h77); mwr(16'hC000, 8'd4);   // accelerator into page FD: CBL
			op(8'h6D); op(8'h7E); mrd(16'h0000); op(8'h77); mwr(16'hC000, 8'h00); op(8'h40); iow(P_CBLM, 8'h00);
			iow(P_W1, 8'h05); iow(P_W3, 8'h00);
			iow(P_ALLM, 8'h00);
			mark("random");
			inta; inta;
			for (i = 0; i < 150; i = i + 1) begin
				rand_op;
				if (i == 50) iow(P_ALLM, 8'h04);
				if (i == 100) begin iow(P_W1, 8'h50); iow(P_AGR, $random(seed)); end
			end
			iow(P_W1, 8'h05);
		end
		idle(10);
		$display("tb_eq_acex (%0s vs sp_acex, scenario %0d, mutation %0d), %0d us simulated, %0d bus cycles:", TB_NAME, scen, mut,
			$time / 1000, n_ops);
		clkz_report; wait_oe_report; res_oe_report; cs_report; ra_report; d_oe_report; d_pin_report; ma_report;
		ras_cas_report; md_oe_report; md_pin_report; va_report; v_wr_report; vd_oe_report; vd_out_report;
		v_cs_report; wr_col_report; dac_report; dac_data_report; xacs_report; xa_oe_report; xa_pin_report;
		strobes_report;
		cov_report;
		$display("  models: DRAM reads %0d, refreshes %0d, writes %0d; video RAM writes %0d; cache writes %0d; SINC_1 pulses %0d",
			n_drd, n_rf, n_dwr, n_vwr, n_cwr, n_sinc);
		if (xref) $display("  X on reference outputs: %0d samples", xref);
		if (xbus) $display("  X on buses: %0d samples", xbus);
		errors = errors + xref + xbus;
		$display("tb_eq_acex: %0d errors%s", errors, weak ? " (some outputs never toggled)" : "");
		$finish;
	end
endmodule
