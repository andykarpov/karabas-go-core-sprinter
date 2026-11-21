// sp_video2 against the VIDEO2 netlist of the 3.03a AHDL (MODE = "SPRINTER"; -DK30 / -DSCROLL: the k30 / SCROLL
// netlist with that personality; +mut / +mut=N: mutations, below). CLK = 84 MHz; clk42 toggles at every
// posedge of CLK and is the reference's CLK42; our CE = ~clk42 (the edge where CLK42 rises), CE_N = clk42.
// Stimulus: a video RAM model (64 K words x 4 bytes, read data 3 ns after the address, the bus = VDO while V_WEN is
// low, bytes written at the rising V_WR of the reference) filled with random pixels / palettes and a structured mode
// table (graphics 256 / 16 colours, ZX, border, blank, frame INT); CPU writes through WR (graphics, ZX screen with
// random pages / A15', ignored ones, DOUBLE_CAS), changes of BORDER / SCR128 / mode page / blank (DIR_PORT),
// COPY_SINC_H / COPY_SINC_V pulses. Several vertical positions: CTV is loaded in both (the reference through forced
// D / ENA / SLOAD of its CTV registers, ours through a forced ctv_n, for the same rising edge) at 6, 254 (CTV8 rises
// -> CTF), 318 (wrap), then COPY_SINC_V jumps to 290; last 20 times a random CTV < 256 and a COPY_SINC_V pulse (CTF
// through 16 frames: the ZX flash bit CTF4). iverilog prints "sorry: procedural continuous assignments" for these
// forces: harmless (constant right-hand sides).
// Start: COPY_SINC_H / _V pulse brings both counter sets to the same state (the netlist powers up with the prn bits
// of CT / CTH / CTV at 1, ours at 0); CTF of ours is then copied from the reference (the netlist starts with CTV8 = 1
// and does not count that pulse); one video write before comparing (the netlist's MXWE latch is X until E_WR).
// Inputs from the top change a quarter of CLK42 after its edge: CE-side ones after a rising edge, WR after a falling.
`timescale 1ns/1ps
`include "eq_cmp.vh"
module tb_eq_video2;
	reg clk = 0; always #5.952 clk = ~clk;            // 84 MHz
	reg clk42 = 0; always @(posedge clk) clk42 <= ~clk42;
	wire ce = ~clk42, ce_n = clk42;
	reg cmp_on = 0;
	integer errors = 0, weak = 0;

	reg        csh = 0, csv = 0, wr = 1, dbl = 0;
	reg [19:0] vai = 0;
	reg [15:0] mdi = 0;
	reg  [7:0] zx_port = 0, dir_port = 0;
	wire [7:0] vdm0, vdm1, vdm2, vdm3;

	wire [5:0] ct_r, cth_r, ct_o, cth_o; wire [8:0] ctv_r, ctv_o; wire [6:0] ctf_r, ctf_o;
	wire blank_r, blank_o, wrpix_r, wrpix_o, intt_r, intt_o;
	wire [15:0] vao_r, vao_o; wire [7:0] vdo0_r, vdo1_r, vdo2_r, vdo3_r, vdo0_o, vdo1_o, vdo2_o, vdo3_o;
	wire [3:0] vwr_r, vwen_r, vwr_o, vwen_o; wire [1:0] vcs_r, vcs_o;

	video2 ref(.CLK42(clk42), .CT(ct_r), .CTH(cth_r), .CTV(ctv_r), .CTF(ctf_r), .BLANK(blank_r), .START_UP(1'b1),
		.COPY_SINC_H(csh), .COPY_SINC_V(csv), .WR(wr), .VAI(vai), .VAO(vao_r), .D(8'h00), .MDI(mdi),
		.VDO0(vdo0_r), .VDO1(vdo1_r), .VDO2(vdo2_r), .VDO3(vdo3_r), .VDM0(vdm0), .VDM1(vdm1), .VDM2(vdm2), .VDM3(vdm3),
		.V_WR(vwr_r), .V_WEN(vwen_r), .V_CS(vcs_r), .WR_PIX(wrpix_r), .ZX_PORT(zx_port), .DIR_PORT(dir_port),
		.INTT(intt_r), .DOUBLE_CAS(dbl), .MOUSE_X(10'd0), .MOUSE_Y(10'd0));
	sp_video2 dut(.CLK(clk), .CE(ce), .CE_N(ce_n), .CT(ct_o), .CTH(cth_o), .CTV(ctv_o), .CTF(ctf_o), .BLANK(blank_o),
		.COPY_SINC_H(csh), .COPY_SINC_V(csv), .WR(wr), .VAI(vai), .MDI(mdi), .DOUBLE_CAS(dbl), .VAO(vao_o),
		.VDO0(vdo0_o), .VDO1(vdo1_o), .VDO2(vdo2_o), .VDO3(vdo3_o), .VDM0(vdm0), .VDM1(vdm1), .VDM2(vdm2), .VDM3(vdm3),
		.V_WR(vwr_o), .V_WEN(vwen_o), .V_CS(vcs_o), .WR_PIX(wrpix_o), .ZX_PORT(zx_port), .DIR_PORT(dir_port),
		.INTT(intt_o), .PERS_K30(`PERS_K30_V), .PERS_SCROLL(`PERS_SCROLL_V));

	// mutations (must fail). Plain nets: iverilog evaluates another force RHS once
	integer mut = 0;
`ifdef SCROLL
	// -DSCROLL +mut=N: one SCROLL line forced back to its 3.03a form (1 SVA, 2 mode slot address, 3 WR_MODE, 4 LD_PIC,
	// 5 INTT, 6 DCOL border by WR_PIC, 7 no SHIFT load)
	wire [17:0] m_sva = {dut.sva_hi, dut.rsva[8:6], dut.mode0[3:0], dut.rsva[5:0]};
	wire [17:0] m_vam = {dir_port[3], dut.cth_e, dut.ct_e[5], 2'b11, dut.ctv_e[8:3], 2'b00};
	wire m_wrm = ~(dut.ct_e[5:3] == 3'b111) & ~(dut.ct_e[4] & dut.ct_e[3] & ~dut.mode0[5]);
	wire m_lda = dut.ct_e[5:3] == 3'd0, m_ldb = dut.ct_e[4:2] == 3'd0;
	wire m_intt = ~(dut.inttx & (dut.ctv_n[2:0] == 3'd7));
	wire m_bord = dut.bordp;
	wire m_zero = 1'b0;
	initial begin
		if (!$value$plusargs("mut=%d", mut)) mut = 0;
		#1 case (mut)
			1: force dut.sva_d = m_sva;
			2: force dut.va_mode = m_vam;
			3: force dut.scr_wr_mode = m_wrm;
			4: begin force dut.ldp_a_d = m_lda; force dut.ldp_b_d = m_ldb; end
			5: force dut.intt_d = m_intt;
			6: force dut.bord_col = m_bord;
			7: force dut.shift_ev = m_zero;
			default: ;
		endcase
	end
`define MUT_NAME (mut ? ", mutation" : "")
`else
	// -DK30 +mut: the k30 WR_PIC data forced back to 3.03a X_MODE5
	wire m_wrpic = dut.x_mode[5];
	initial if ($test$plusargs("mut")) begin mut = 1; #1 force dut.wr_pic_x = m_wrpic; end
`define MUT_NAME (mut ? ", mutation WR_PIC" : "")
`endif

	// ---- video RAM: 64 K x 32 bits (V_CS1 = 1, V_CS0 = 0 constantly: one bank)
	reg [7:0] ram [0:262143];
	assign #3 vdm0 = vwen_r[0] === 1'b0 ? vdo0_r : ram[{vao_r, 2'd0}];
	assign #3 vdm1 = vwen_r[1] === 1'b0 ? vdo1_r : ram[{vao_r, 2'd1}];
	assign #3 vdm2 = vwen_r[2] === 1'b0 ? vdo2_r : ram[{vao_r, 2'd2}];
	assign #3 vdm3 = vwen_r[3] === 1'b0 ? vdo3_r : ram[{vao_r, 2'd3}];
	reg [3:0] vwr_p = 4'hF;
	integer nwr = 0;
	always @(vwr_r) begin
		if (vwr_p[0] === 1'b0 && vwr_r[0] === 1'b1) ram[{vao_r, 2'd0}] = vdo0_r;
		if (vwr_p[1] === 1'b0 && vwr_r[1] === 1'b1) ram[{vao_r, 2'd1}] = vdo1_r;
		if (vwr_p[2] === 1'b0 && vwr_r[2] === 1'b1) ram[{vao_r, 2'd2}] = vdo2_r;
		if (vwr_p[3] === 1'b0 && vwr_r[3] === 1'b1) ram[{vao_r, 2'd3}] = vdo3_r;
		if (vwr_p !== 4'hF && vwr_r === 4'hF) nwr = nwr + 1;
		vwr_p = vwr_r;
	end

	`EQ_CMP(ct, 6, ct_o, ct_r)
	`EQ_CMP(cth, 6, cth_o, cth_r)
	`EQ_CMP(ctv, 9, ctv_o, ctv_r)
	`EQ_CMP(ctf, 7, ctf_o, ctf_r)
	`EQ_CMP(blank, 1, blank_o, blank_r)
	`EQ_CMP(intt, 1, intt_o, intt_r)
	`EQ_CMP(vao, 16, vao_o, vao_r)
	`EQ_CMP(vdo, 32, ({vdo3_o, vdo2_o, vdo1_o, vdo0_o}), ({vdo3_r, vdo2_r, vdo1_r, vdo0_r}))
	`EQ_CMP(v_wr, 4, vwr_o, vwr_r)
	`EQ_CMP(v_wen, 4, vwen_o, vwen_r)
	`EQ_CMP(v_cs, 2, vcs_o, vcs_r)
	`EQ_CMP(wr_pix, 1, wrpix_o, wrpix_r)

	// first mismatch, for diagnosis
	reg first = 1;
	always @(negedge clk) if (cmp_on && first &&
		({ct_o, cth_o, ctv_o, ctf_o, blank_o, intt_o, vao_o, vdo0_o, vdo1_o, vdo2_o, vdo3_o, vwr_o, vwen_o, vcs_o, wrpix_o} !==
		 {ct_r, cth_r, ctv_r, ctf_r, blank_r, intt_r, vao_r, vdo0_r, vdo1_r, vdo2_r, vdo3_r, vwr_r, vwen_r, vcs_r, wrpix_r})) begin
		first = 0;
		$display("first mismatch at %0t ns: ct %h/%h cth %0d/%0d ctv %0d/%0d ctf %h/%h blank %b/%b intt %b/%b vao %h/%h vwr %b/%b vwen %b/%b vcs %b/%b wrpix %b/%b",
			$time / 1000, ct_o, ct_r, cth_o, cth_r, ctv_o, ctv_r, ctf_o, ctf_r, blank_o, blank_r, intt_o, intt_r,
			vao_o, vao_r, vwr_o, vwr_r, vwen_o, vwen_r, vcs_o, vcs_r, wrpix_o, wrpix_r);
	end

	// ---- timing helpers: a quarter of CLK42 after its rising (q_rise) / falling (q_fall) edge
	task q_rise; begin @(negedge clk); while (!clk42) @(negedge clk); end endtask
	task q_fall; begin @(negedge clk); while (clk42) @(negedge clk); end endtask
	task cycles(input integer n); begin repeat (n) q_rise; end endtask

	// ---- the mode table: word {page, CTH, CT5, 11, CTV[8..3]}, byte 3 = MODE0, 2 = MODE1, 1 = MODE2
	function [7:0] pick_mode0(input integer r, input [7:0] x);
		case (r % 8)
			0:       pick_mode0 = {4'hF, 2'b11, x[1], 1'b1};          // border + blank + frame INT
			1:       pick_mode0 = {4'hF, x[3:0]};                     // border
			2, 3:    pick_mode0 = {x[7:6], x[5], 1'b1, x[3:0]};        // ZX (narrow / wide)
			4:       pick_mode0 = {x[7:6], 2'b10, x[3:0]};             // graphics 256 colours
			5:       pick_mode0 = {x[7:6], 2'b00, x[3:0]};             // graphics 16 colours
			default: pick_mode0 = x;
		endcase
	endfunction
	integer i, p, h, c5, v, base;
	reg [15:0] wa;
	initial begin
		for (i = 0; i < 262144; i = i + 1) ram[i] = $random;
		for (p = 0; p < 2; p = p + 1) for (v = 0; v < 64; v = v + 1) for (h = 0; h < 64; h = h + 8) begin
			base = $random & 255;
			for (i = h; i < h + 8; i = i + 1) for (c5 = 0; c5 < 2; c5 = c5 + 1) begin
				wa = {p[0], i[5:0], c5[0], 2'b11, v[5:0]};
				ram[{wa, 2'd3}] = (($random & 7) == 0) ? pick_mode0($random & 255, $random) : pick_mode0(base, $random);
				if (($random & 3) == 0) ram[{wa, 2'd3}] = pick_mode0(base, ram[{wa, 2'd3}] ^ 8'h0F);
			end
		end
	end

	// ---- CPU writes (WR from DFF(.., !CLK42) of the top: changes after a falling edge)
	reg wr_run = 0;
	integer kind, w;
	initial forever begin
		q_rise;
		if (wr_run) begin
			kind = $random & 15;
			vai = $random; mdi = $random; dbl = (($random & 3) == 0);
			zx_port = $random;
			if (kind < 7) begin                               // graphics: pixels, palette area, mode table area
				vai[19] = 1;
				if (kind == 1) vai[9:5] = 5'b11111;
				if (kind == 2) vai[9:8] = 2'b11;
			end else if (kind < 13) begin                     // ZX screen write
				vai[19] = 0; zx_port[6] = 1;
			end else begin                                    // neither: no video write
				vai[19] = 0; zx_port[6] = 0;
			end
			cycles(1 + ($random & 3));
			q_fall; wr = 0;
			w = 1 + ($random & 3);
			repeat (w) q_fall;
			wr = 1;
			cycles(2 + ($random & 15) + ((($random & 7) == 0) ? 200 : 0));
		end
	end

	// ---- DIR_PORT (BORDER / RGMOD) changes, COPY_SINC_H pulses
	reg port_run = 0;
	initial forever begin
		q_rise;
		if (port_run) begin
			cycles(100 + ($random & 1023));
			case ($random & 7)
				0, 1:    dir_port[7:5] = $random;
				2:       dir_port[0] = ~dir_port[0];
				3:       dir_port[3] = ~dir_port[3];
				4:       dir_port[4] = (($random & 3) == 0);
				5:       begin csh = 1; q_rise; csh = 0; end
				default: dir_port = {$random} & 8'hEF;
			endcase
		end
	end

	// ---- load CTV in both: forced D / ENA of the reference registers for one rising edge (bits 1, 5, 8 inverted)
	task load_ctv(input [8:0] v); reg [8:0] d; begin
		while (!(ct_r[5:3] == 3'd1 && ct_r[2:0] == 3'd1)) q_rise;  // away from CT5 / CTV8 / CTV edges
		q_fall;
		d = v ^ 9'h122;
		force ref.\CTV[0]~reg .d = d[0]; force ref.\CTV[1]~reg .d = d[1]; force ref.\CTV[2]~reg .d = d[2];
		force ref.\CTV[3]~reg .d = d[3]; force ref.\CTV[4]~reg .d = d[4]; force ref.\CTV[5]~reg .d = d[5];
		force ref.\CTV[6]~reg .d = d[6]; force ref.\CTV[7]~reg .d = d[7]; force ref.\CTV[8]~reg .d = d[8];
		force ref.\CTV[0]~reg .ena = 1'b1; force ref.\CTV[1]~reg .ena = 1'b1; force ref.\CTV[2]~reg .ena = 1'b1;
		force ref.\CTV[3]~reg .ena = 1'b1; force ref.\CTV[4]~reg .ena = 1'b1; force ref.\CTV[5]~reg .ena = 1'b1;
		force ref.\CTV[6]~reg .ena = 1'b1; force ref.\CTV[7]~reg .ena = 1'b1; force ref.\CTV[8]~reg .ena = 1'b1;
		force ref.\CTV[0]~reg .sload = 1'b0; force ref.\CTV[1]~reg .sload = 1'b0; force ref.\CTV[2]~reg .sload = 1'b0;
		force ref.\CTV[3]~reg .sload = 1'b0; force ref.\CTV[4]~reg .sload = 1'b0; force ref.\CTV[5]~reg .sload = 1'b0;
		force ref.\CTV[6]~reg .sload = 1'b0; force ref.\CTV[7]~reg .sload = 1'b0; force ref.\CTV[8]~reg .sload = 1'b0;
		force dut.ctv_n = v;
		q_rise;
		release dut.ctv_n;
		release ref.\CTV[0]~reg .d; release ref.\CTV[1]~reg .d; release ref.\CTV[2]~reg .d;
		release ref.\CTV[3]~reg .d; release ref.\CTV[4]~reg .d; release ref.\CTV[5]~reg .d;
		release ref.\CTV[6]~reg .d; release ref.\CTV[7]~reg .d; release ref.\CTV[8]~reg .d;
		release ref.\CTV[0]~reg .ena; release ref.\CTV[1]~reg .ena; release ref.\CTV[2]~reg .ena;
		release ref.\CTV[3]~reg .ena; release ref.\CTV[4]~reg .ena; release ref.\CTV[5]~reg .ena;
		release ref.\CTV[6]~reg .ena; release ref.\CTV[7]~reg .ena; release ref.\CTV[8]~reg .ena;
		release ref.\CTV[0]~reg .sload; release ref.\CTV[1]~reg .sload; release ref.\CTV[2]~reg .sload;
		release ref.\CTV[3]~reg .sload; release ref.\CTV[4]~reg .sload; release ref.\CTV[5]~reg .sload;
		release ref.\CTV[6]~reg .sload; release ref.\CTV[7]~reg .sload; release ref.\CTV[8]~reg .sload;
		#1 if (ctv_r !== v || ctv_o !== v) $display("load_ctv %0d failed: ref %0d ours %0d", v, ctv_r, ctv_o);
	end endtask

	integer seg;
	initial begin
		cycles(20);
		csh = 1; csv = 1; q_rise; csh = 0; csv = 0;          // the counters of both to the same state
		cycles(50);
		q_fall; dut.ctf_q = ctf_r;   // the netlist powers up with CTV8 = 1 (stored inverted): no CTF count at the sync
		// first write: the reference's MXWE latch is X until the first E_WR, F_WR of ours clears V_EN until then
		vai = 20'h80000; mdi = 16'h0000; zx_port = 0; dbl = 0;
		q_fall; wr = 0; q_fall; q_fall; wr = 1;
		cycles(30);
		wr_run = 1; port_run = 1;
		cycles(20);
		cmp_on = 1;
		for (seg = 0; seg < 5; seg = seg + 1) begin
			case (seg)
				0: load_ctv(9'd6);
				1: load_ctv(9'd254);
				2: load_ctv(9'd318);
				3: begin q_rise; csv = 1; q_rise; csv = 0; end   // CTV -> 290 (CTV8 rises)
				4: for (i = 0; i < 20; i = i + 1) begin          // CTF through 16 frames: CTV < 256, COPY_SINC_V
					load_ctv({$random} % 256); cycles(300 + ($random & 511));
					q_rise; csv = 1; q_rise; csv = 0; cycles(300 + ($random & 511));
				end
			endcase
			if (seg < 4) cycles(3 * 2688 - 500);
			$display("  segment %0d done: ctv %0d ctf %0d writes %0d", seg, ctv_r, ctf_r, nwr);
		end
		$display("tb_eq_video2 (%0s VIDEO2 vs sp_video2%0s %0d):", `PERS_NAME, `MUT_NAME, mut);
		ct_report; cth_report; ctv_report; ctf_report; blank_report; intt_report; vao_report; vdo_report;
		v_wr_report; v_wen_report; v_cs_report; wr_pix_report;
		$display("tb_eq_video2: %0d errors%s", errors, weak ? " (some outputs never toggled)" : "");
		$finish;
	end
endmodule
