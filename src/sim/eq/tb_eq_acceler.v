// sp_acceler against the ACCELER netlist of the 3.03a AHDL. CLK = 84 MHz, clk42 toggles at every CLK edge and is the
// reference's CLK42; our CE = the CLK edge where clk42 rises, CE_N = where it falls.
// Stimulus: a behavioural model of the DCP outputs the accelerator sees (CT phases, CLK_Z80 in turbo and 3.5 MHz, the
// DRAM cycle MC_BEGIN / MC_END / MC_TYPE / RAS / CAS with refresh, /IOM, the port descriptor DCPP, /WAIT, HDD_FLIP),
// a DRAM model on MD, and a Z80 bus model (M1 + refresh, memory read / write, IN / OUT, INTA) that runs the LD r,r
// accelerator commands: counter load, fill, vertical fill, copy line with CP / OR / XOR / AND (HL), vertical copy,
// LD H,H with IDE HDD_FLIP / HDDR, AGR by port C4, ALT_ACC / XCNT by port C7, IN A,(1F) / OUT (1F),A, prefixes,
// RETI / RETN, INTA, ACC_ENA off, a /RESET, plus random instructions and data.
// Every input is shared: the feedback (CONTINUE -> MC_END, ACC_ON -> /WAIT, DO -> D bus and DCPP, AO / MDO -> DRAM,
// DOUBLE_CAS -> HDD_FLIP) is taken from the reference only.
`timescale 1ns/1ps
`include "eq_cmp.vh"
module tb_eq_acceler;
	reg clk = 0; always #5.952 clk = ~clk;            // 84 MHz
	reg clk42 = 0; always @(posedge clk) clk42 <= ~clk42;
	wire ce = ~clk42, ce_n = clk42;
	reg cmp_on = 0;
	integer errors = 0, weak = 0;

	localparam K_NONE = 0, K_OP = 1, K_IO = 2, K_MEM = 3;

	// ---- Z80 pins: the bus model sets *_nx at a CLK42 falling edge (right after a CLK_Z80 edge), the pins follow at
	// the next rising edge, so the /MR, /M1 events are known before that edge
	reg m1_nx = 1, mr_nx = 1, io_nx = 1, rd_nx = 1, wr_nx = 1, rf_nx = 1;
	reg [15:0] a_nx = 0; reg [7:0] do_nx = 0, iod_nx = 0, val_nx = 0; reg [1:0] kind_nx = K_NONE;
	reg m1_n = 1, mr_n = 1, io_n = 1, rd_n = 1, wr_n = 1, rf_n = 1;
	reg [15:0] a = 0; reg [7:0] z_do = 0, io_dat = 0, val = 0; reg [1:0] kind = K_NONE;
	always @(posedge clk42) begin
		m1_n <= m1_nx; mr_n <= mr_nx; io_n <= io_nx; rd_n <= rd_nx; wr_n <= wr_nx; rf_n <= rf_nx;
		a <= a_nx; z_do <= do_nx; io_dat <= iod_nx; val <= val_nx; kind <= kind_nx;
	end
	reg reset_n = 0, acc_ena = 1, turbo = 1;

	// ---- reference outputs (feedback into the shared models)
	wire        cont_r, gl_r, on_r, dc_r, cont_o, gl_o, on_o, dc_o;
	wire [15:0] ao_r, mdo_r, ao_o, mdo_o;
	wire  [7:0] do_r, md_r, gline_r, dir_r, do_o, md_o, gline_o, dir_o;

	// ---- DCP model (DCP.TDF:255-560), CT from VIDEO2: 0 1 2 4 5 6
	reg [2:0] ct = 0, cth = 0; reg ct5 = 0, clk21 = 0, tff = 0, clk_z80 = 0;
	always @(posedge clk42) begin
		case (ct) 3'd0: ct <= 1; 3'd1: ct <= 2; 3'd2: ct <= 4; 3'd4: ct <= 5; 3'd5: ct <= 6; default: ct <= 0; endcase
		ct5 <= ct[0] & ct[2];
		if (ct5) cth <= cth + 1;                       // CT[5..3]; REFRESH = CT4
		clk21 <= ~ct[0] ^ ct[2];
		if (~ct[2] & ct[1]) tff <= ~tff;
	end
	wire zx = (clk21 & turbo) | (tff & ~turbo);       // D of CLK_Z80 = DFF(.., !CLK42)
	always @(negedge clk42) clk_z80 <= zx;

	reg mem_rw = 1;                                   // DFF(!/RF, !/MR, , MEM_RW | !/MR)
	always @(negedge mr_n) mem_rw <= ~rf_n;
	always @(posedge mr_n) mem_rw <= 1;
	reg io_rw = 1, dd1 = 1, dd2 = 1;
	wire io_rw_e = m1_n ? io_rw : 1'b1;
	wire dd1_e = io_n ? 1'b1 : dd1, dd2_e = io_n ? 1'b1 : dd2;
	reg mc_rq = 1;
	always @(negedge clk42) mc_rq <= (mem_rw & dd2_e) | (rd_n & wr_n);
	reg mcb = 1, mce = 0, mct = 1, mcw = 1, rfc = 0, rft = 1, ras = 1, cas = 1;
	wire mcb_e = (mr_n & io_n) ? 1'b1 : mcb;
	wire mce_e = (mr_n & io_n) ? 1'b0 : mce;
	wire rft_e = rfc ? rft : 1'b1;
	wire cs_ram = mr_n | (a[15:14] == 2'b00) | ~rf_n;
	always @(posedge cth[1]) if (rfc) rft <= 0;
	reg [3:0] wt = 15, w_tab = 4; reg wtz = 0, iomm = 1, iomx = 1, iom = 1, w1 = 0, w2 = 0;
	wire [3:0] wt_e = mce_e ? wt : 4'd15;
	wire iom_e = (~io_n & m1_n) ? iom : 1'b1;
	reg [7:0] dcpp = 0; reg mce_d = 0, dcp_res = 0;
	wire [7:0] dcpp_e = (mce_e & dcp_res) ? dcpp : 8'd0;
	always @(posedge clk42) begin
		io_rw <= m1_n ? io_n : 1'b1;
		dd1 <= io_n ? 1'b1 : io_rw_e;
		dd2 <= io_n ? 1'b1 : dd1_e;
		mcb <= (mr_n & io_n) ? 1'b1 : (ct == 6) ? mc_rq : mcb;
		mce <= (mr_n & io_n) ? 1'b0 : ((ct == 5) & ~mcb_e & cont_r) ? 1'b1 : mce;
		if (ct == 6) begin mct <= mc_rq | mce_e; mcw <= mc_rq | cs_ram | wr_n | mce_e; rfc <= ~mc_rq | rft_e; end
		if (~rfc) rft <= 1;
		if (~(ct[1] | (ct[0] ^ mct)) & (~mct | ~rfc)) ras <= ct[2];
		if (~(ct[1] | (ct[0] ^ ~mct)) & (~mct | ~rfc)) cas <= ct[2];
		wtz <= wt_e == 0;
		if (clk21) begin iomm <= io_rw_e | ~mce_e | wtz; iomx <= iomm; w1 <= wt_e == 0; end
		iom <= ~(~io_n & m1_n) ? 1'b1 : clk21 ? (iomx & iom_e) : iom_e;
		wt <= ~mce_e ? 4'd15 : clk21 ? (iom_e ? w_tab : wtz ? 4'd0 : wt_e - 4'd1) : wt_e;
		w2 <= w1;
		mce_d <= mce_e;
		dcp_res <= ~io_n & m1_n;
		dcpp <= ~(mce_e & dcp_res) ? 8'd0 : ~mce_d ? do_r : dcpp;   // DCPP = ACC.DO once MC_END rises
	end
	reg io_rwm = 1;                                   // DFF(!/M1, !/IO, , IO_RW | !/IO)
	wire io_rwm_set = ~io_rw_e & io_n;
	always @(negedge io_n) io_rwm <= ~m1_n;
	always @(posedge io_rwm_set) io_rwm <= 1;
	wire wait_n = (mce_e | mem_rw | (~turbo & ~on_r)) & (io_rwm | w2);

	// HDD_FLIP: toggles at the end (/IOM rising) of an access to an IDE data port (DCPP 2x), cleared when DOUBLE_CAS
	// falls; HDDR: the latched high byte of IDE
	reg hdd_flip = 0, ide_q = 0; reg [7:0] hddr = 8'h5A;
	always @(posedge clk42) ide_q <= dcpp_e[7:4] == 4'h2;
	always @(posedge iom_e) if (ide_q) begin hdd_flip <= ~hdd_flip; hddr <= $random; end
	always @(negedge dc_r) hdd_flip <= 0;
	always @(negedge reset_n) hdd_flip <= 0;

	// ---- DRAM: column address latched where CAS falls, write at the CAS rise of a write cycle
	reg [7:0] dram [0:65535]; reg [15:0] col = 0, mdi_q = 0;
	integer i;
	initial for (i = 0; i < 65536; i = i + 1) dram[i] = $random;
	always @(posedge clk42) begin
		if (ct == 1) col <= ao_r;
		if ((ct == 5) & ~mct & ~mcw) begin
			if (dc_r) begin dram[{col[15:1], 1'b1}] <= mdo_r[15:8]; dram[{col[15:1], 1'b0}] <= mdo_r[7:0]; end
			else dram[col] <= col[0] ? mdo_r[15:8] : mdo_r[7:0];
		end
		mdi_q <= (kind == K_OP || kind == K_IO) ? {val, val} : {dram[{col[15:1], 1'b1}], dram[{col[15:1], 1'b0}]};
	end
	wire [15:0] mdi = ~mcw ? mdo_r : mdi_q;           // MD is driven by ACC.MDO in a write cycle

	// ---- D bus: the ACEX drives DO on memory reads, a peripheral on IN / INTA, the CPU otherwise (one CLK42 late:
	// the bus keeps its value across the strobe edge)
	reg drv_mem = 0, drv_io = 0;
	always @(posedge clk42) begin drv_mem <= ~mr_n & ~rd_n; drv_io <= ~io_n & (~rd_n | ~m1_n); end
	wire [7:0] di = drv_mem ? do_r : drv_io ? io_dat : z_do;

	// ---- events for our module
	wire mr_ev = ce & ~mr_n & mr_nx;
	wire m1_ev = ce & ~m1_n & m1_nx;
	wire z_ev = ce_n & ~clk_z80 & zx;

	acceler ref(.CLK42(clk42), .\/RESET (reset_n), .CT(ct), .RAS(ras), .CAS(cas), .CLK_Z80(clk_z80),
		.\CONTINUE (cont_r), .MC_END(mce_e), .MC_BEGIN(mcb_e), .MC_TYPE(mct), .MC_WRITE(mcw), .AI(a), .DI(di),
		.AO(ao_r), .\DO (do_r), .\/IO (io_n), .\/RD (rd_n), .\/WR (wr_n), .\/MR (mr_n), .\/RF (rf_n), .\/M1 (m1_n),
		.\/IOM (iom_e), .DCP(dcpp_e), .MDI(mdi), .MDO(mdo_r), .MD(md_r), .G_LINE(gline_r), .GLISSER(gl_r),
		.ACC_ON(on_r), .ACC_ENA(acc_ena), .DOUBLE_CAS(dc_r), .HDDR(hddr), .HDD_FLIP(hdd_flip), .ACC_DIR(dir_r));
	sp_acceler dut(.CLK(clk), .CE(ce), .CE_N(ce_n), .RESET_N(reset_n), .CT(ct), .CAS(cas), .CLK_Z80_EV(z_ev),
		.CONTINUE(cont_o), .MC_END(mce_e), .MC_TYPE(mct), .AI(a), .DI(di), .AO(ao_o), .DO(do_o), .IO_N(io_n),
		.RD_N(rd_n), .WR_N(wr_n), .MR_N(mr_n), .MR_N_EV(mr_ev), .RF_N(rf_n), .M1_N(m1_n), .M1_N_EV(m1_ev),
		.IOM_N(iom_e), .DCP(dcpp_e), .MDI(mdi), .MDO(mdo_o), .MD(md_o), .G_LINE(gline_o), .GLISSER(gl_o),
		.ACC_ON(on_o), .ACC_ENA(acc_ena), .DOUBLE_CAS(dc_o), .HDDR(hddr), .HDD_FLIP(hdd_flip), .ACC_DIR(dir_o));

	// an X on a reference output can never compare equal: counted separately so the cause is visible
	integer xref = 0;
	always @(negedge clk) if (cmp_on && ^{cont_r, ao_r, do_r, mdo_r, md_r, gline_r, gl_r, on_r, dc_r, dir_r} === 1'bx) begin
		if (xref == 0) $display("  X on a reference output at %0d ns", $time);
		xref = xref + 1;
	end
	// coverage of internal paths (our module; equal outputs imply the same in the reference)
	integer cv_alt = 0, cv_c1f = 0, cv_vert = 0, cv_flip = 0, cv_dbl = 0, cv_blk = 0, cv_reti = 0, cv_slow = 0;
	integer cv_fn0 = 0, cv_fn1 = 0, cv_fn2 = 0, cv_fn3 = 0;
	always @(posedge clk) if (cmp_on & ce) begin
		if (dut.alt & dut.ram_wr_q) cv_alt = cv_alt + 1;
		if (dut.c1f) cv_c1f = cv_c1f + 1;
		if (dut.ACC_DIR[4] & ~dut.go & dut.go1_q) cv_vert = cv_vert + 1;
		if (mce_e & hdd_flip) cv_flip = cv_flip + 1;
		if (dc_r & ~wr_n & ~cas) cv_dbl = cv_dbl + 1;
		if (~dut.acc_blk) cv_blk = cv_blk + 1;
		if (dut.reti_q) cv_reti = cv_reti + 1;
		if (~turbo & ~cont_r) cv_slow = cv_slow + 1;
		if (dut.ram_wr_q) case (dut.fn_q) 0: cv_fn0 = cv_fn0 + 1; 1: cv_fn1 = cv_fn1 + 1; 2: cv_fn2 = cv_fn2 + 1;
			default: cv_fn3 = cv_fn3 + 1; endcase
	end

	`EQ_CMP(cont, 1, cont_o, cont_r)
	`EQ_CMP(ao, 16, ao_o, ao_r)
	`EQ_CMP(dout, 8, do_o, do_r)
	`EQ_CMP(mdo, 16, mdo_o, mdo_r)
	`EQ_CMP(md, 8, md_o, md_r)
	`EQ_CMP(gline, 8, gline_o, gline_r)
	`EQ_CMP(gliss, 1, gl_o, gl_r)
	`EQ_CMP(accon, 1, on_o, on_r)
	`EQ_CMP(dcas, 1, dc_o, dc_r)
	`EQ_CMP(accdir, 8, dir_o, dir_r)

	// ---- Z80 bus model: T-states follow CLK_Z80 (rises / falls at a CLK42 falling edge)
	task zr; begin @(negedge clk42); while (!(~clk_z80 & zx)) @(negedge clk42); end endtask
	task zf; begin @(negedge clk42); while (!(clk_z80 & ~zx)) @(negedge clk42); end endtask
	task twait; begin while (!wait_n) begin zr; zf; end end endtask
	reg [15:0] pc = 16'h4000; reg [6:0] rr = 0;
	task m1c(input [15:0] adr, input [7:0] opc, input inta); begin
		zr; rf_nx = 1; m1_nx = 0; a_nx = adr; kind_nx = inta ? K_IO : K_OP; val_nx = opc; iod_nx = opc;
		zf; if (!inta) begin mr_nx = 0; rd_nx = 0; end
		zr; zf;                                       // T2
		if (inta) begin zr; zf; io_nx = 0; zr; zf; end   // two automatic wait states, /IORQ in the first
		twait;
		zr; m1_nx = 1; mr_nx = 1; rd_nx = 1; io_nx = 1; rf_nx = 0; a_nx = {8'h3F, 1'b0, rr}; rr = rr + 1;
		kind_nx = K_NONE;                             // T3: refresh
		zf; mr_nx = 0;
		zr; zf; mr_nx = 1;                            // T4
	end endtask
	task op(input [7:0] o); begin m1c(pc, o, 0); pc = pc + 1; end endtask
	task mrd(input [15:0] adr, input forced, input [7:0] v); begin
		zr; rf_nx = 1; a_nx = adr; kind_nx = forced ? K_OP : K_MEM; val_nx = v;
		zf; mr_nx = 0; rd_nx = 0;
		zr; zf; twait;
		zr; zf; mr_nx = 1; rd_nx = 1; kind_nx = K_NONE;
	end endtask
	task opnd(input [7:0] v); begin mrd(pc, 1, v); pc = pc + 1; end endtask
	task mwr(input [15:0] adr, input [7:0] d); begin
		zr; rf_nx = 1; a_nx = adr; kind_nx = K_MEM;
		zf; mr_nx = 0; do_nx = d;
		zr; zf; wr_nx = 0; twait;
		zr; zf; mr_nx = 1; wr_nx = 1; kind_nx = K_NONE;
	end endtask
	task iocyc(input wr, input [15:0] port, input [7:0] desc, input [7:0] d); begin
		zr; rf_nx = 1; a_nx = port; kind_nx = K_IO; val_nx = desc; iod_nx = d; if (wr) do_nx = d;
		w_tab = 1 + ($random & 7);
		zr; io_nx = 0; if (wr) wr_nx = 0; else rd_nx = 0;   // T2
		zf; zr; zf; twait;                            // TW
		zr; zf; io_nx = 1; rd_nx = 1; wr_nx = 1; kind_nx = K_NONE;
	end endtask
	task outp(input [7:0] desc, input [15:0] port, input [7:0] d); begin op(8'hED); op(8'h79); iocyc(1, port, desc, d); end endtask
	task inp(input [7:0] desc, input [15:0] port, input [7:0] d); begin op(8'hED); op(8'h78); iocyc(0, port, desc, d); end endtask
	task setcnt(input [7:0] n); begin op(8'h52); op(8'h77); mwr(16'h8000 | $random, n); end endtask
	task off; begin op(8'h40); end endtask

	// accelerated block: mode m (LD r,r), then one memory access of instruction o (read or write)
	task blk(input [7:0] m, input [7:0] o, input wr, input [15:0] adr, input [7:0] d); begin
		op(m); op(o); if (wr) mwr(adr, d); else mrd(adr, 0, 0);
	end endtask

	task rnd(input integer cnt); integer n, k, r; reg [15:0] ra; begin
	for (n = 0; n < cnt; n = n + 1) begin
		r = $random & 15; ra = $random;
		case (r)
			0, 1, 2: op($random);
			3: begin k = $random & 7; op({2'b01, k[2:0], k[2:0]}); end
			4: setcnt($random & 15);
			5, 6: begin op(8'h77); mwr(ra, $random); end
			7, 8: begin op(8'h7E); mrd(ra, 0, 0); end
			9: begin k = $random & 3; op(8'hA6 | (k << 3)); mrd(ra, 0, 0); end
			10: begin k = $random & 7;
				case (k) 0: outp(8'hC4, ra, $random); 1: outp(8'hC7, ra, $random); 2: inp(8'h20, ra, $random);
				         3: outp(8'h20, ra, $random); 4: inp($random, ra, $random); default: outp($random, ra, $random); endcase end
			11: begin op(8'hDB); opnd(($random & 1) ? 8'h1F : $random); iocyc(0, ra, $random, $random); end
			12: begin op(8'h36); opnd($random); mwr(ra, $random); end
			13: begin k = $random & 3; op(k == 0 ? 8'hCB : k == 1 ? 8'hDD : k == 2 ? 8'hED : 8'hFD); op($random); end
			14: m1c(pc, $random, 1);
			default: off;
		endcase
	end
	end endtask

	initial begin
		repeat (40) @(posedge clk42); reset_n <= 1;
		repeat (4) op(8'h00);
		// fill the line buffer before comparing: copy 256 bytes
		setcnt(8'd0); blk(8'h6D, 8'h7E, 0, 16'hC000, 0); off;
		cmp_on = 1;
		// counter and plain fill, horizontal
		setcnt(8'd5); blk(8'h49, 8'h77, 1, 16'hC010, 8'hAA); off;
		setcnt(8'd1); blk(8'h49, 8'h77, 1, 16'hC0FF, 8'h55); off;
		// AGR by port C4 / CC, vertical fill with FF (GLISSER)
		outp(8'hC4, 16'h00C4, 8'h10);
		setcnt(8'd6); blk(8'h5B, 8'h77, 1, 16'hC123, 8'hFF); off;
		outp(8'hCC, 16'h00CC, 8'hFE);
		setcnt(8'd4); blk(8'h5B, 8'h36, 1, 16'hC200, 8'h3C); off;
		// copy line: read pass into the buffer, write pass out of it
		setcnt(8'd12); blk(8'h6D, 8'h7E, 0, 16'hC300, 0); op(8'h77); mwr(16'hC400, 8'h00); off;
		// logic functions over the buffer
		setcnt(8'd9);
		blk(8'h6D, 8'hA6, 0, 16'hC500, 0); op(8'hAE); mrd(16'hC600, 0, 0); op(8'hB6); mrd(16'hC700, 0, 0);
		op(8'hBE); mrd(16'hC800, 0, 0); op(8'h87); mrd(16'hC900, 0, 0); op(8'h77); mwr(16'hCA00, 8'h00); off;
		// a buffer of FF: GLISSER from the buffer
		setcnt(8'd3); blk(8'h49, 8'h77, 1, 16'hCB00, 8'hFF); off;
		blk(8'h6D, 8'h7E, 0, 16'hCB00, 0); op(8'h77); mwr(16'hCC00, 8'h00); off;
		// vertical copy
		outp(8'hC4, 16'h00C4, 8'h40);
		setcnt(8'd7); blk(8'h7F, 8'h7E, 0, 16'hD000, 0); op(8'h77); mwr(16'hD100, 8'h00); off;
		// IDE: reads of the data port toggle HDD_FLIP, LD H,H writes two bytes (HDDR, D)
		inp(8'h20, 16'h0050, 8'h11); inp(8'h20, 16'h0050, 8'h22);
		blk(8'h64, 8'h77, 1, 16'hD200, 8'h33); op(8'h77); mwr(16'hD202, 8'h44); off;
		inp(8'h20, 16'h0050, 8'h66); op(8'h64); op(8'h77); mwr(16'hD204, 8'h77);
		inp(8'h21, 16'h0150, 8'h88); op(8'h77); mwr(16'hD206, 8'h99); off;
		// IN A,(1F) / OUT (1F),A: the operand 1F is read as 07; and other operands
		op(8'hDB); opnd(8'h1F); iocyc(0, 16'h001F, 8'h10, 8'h5E);
		op(8'hD3); opnd(8'h1F); iocyc(1, 16'h001F, 8'h11, 8'h5F);
		op(8'hDB); opnd(8'h3F); iocyc(0, 16'h003F, 8'h12, 8'h60);
		op(8'hCB); op(8'hDB); opnd(8'h1F);
		// prefixes: no accelerator after CB / DD / ED / FD
		op(8'hCB); op(8'h49); op(8'h77); mwr(16'hD300, 8'h01);
		op(8'hDD); op(8'h7F); op(8'hFD); op(8'h52); op(8'hCD); op(8'h49); opnd(8'h00); opnd(8'h80); off;
		// RETI / RETN, INTA with the accelerator on
		op(8'h49); m1c(pc, 8'hFF, 1); op(8'hED); op(8'h4D); op(8'hED); op(8'h45); op(8'h77); mwr(16'hD400, 8'h02); off;
		op(8'hFB); op(8'hF3);
		// ACC_ENA = 0 clears the mode
		setcnt(8'd3); op(8'h49); @(posedge clk42) acc_ena <= 0; op(8'h77); mwr(16'hD500, 8'h03);
		@(posedge clk42) acc_ena <= 1; op(8'h77); mwr(16'hD501, 8'h04); op(8'h49); op(8'h77); mwr(16'hD502, 8'h05); off;
		// 3.5 MHz CPU clock
		@(posedge clk42) turbo <= 0;
		setcnt(8'd3); blk(8'h49, 8'h77, 1, 16'hD600, 8'h06); off; op(8'h7E); mrd(16'hD601, 0, 0);
		blk(8'h6D, 8'h7E, 0, 16'hD600, 0); off; outp(8'hC4, 16'h00C4, 8'h20);
		@(posedge clk42) turbo <= 1;
		// ALT_ACC: the second buffer address (AAGR, XCNT, XAGR) by port C7 / CF; only /RESET clears it
		setcnt(8'd8); outp(8'hC7, 16'h2E00, 8'h35);
		blk(8'h6D, 8'h7E, 0, 16'hE000, 0); op(8'h77); mwr(16'hE100, 8'h00);
		outp(8'hCF, 16'h5300, 8'hC1);
		blk(8'h7F, 8'hAE, 0, 16'hE200, 0); op(8'h77); mwr(16'hE300, 8'h00); off;
		// random instructions, data, ports; a part at 3.5 MHz
		rnd(450);
		@(posedge clk42) turbo <= 0; rnd(30); @(posedge clk42) turbo <= 1;
		off;
		// /RESET in the middle of a mode, then again
		op(8'h6D); @(posedge clk42) reset_n <= 0; repeat (30) @(posedge clk42); reset_n <= 1;
		repeat (4) op(8'h00);
		setcnt(8'd4); blk(8'h49, 8'h77, 1, 16'hF000, 8'h12); off;
		blk(8'h6D, 8'h7E, 0, 16'hF000, 0); op(8'h77); mwr(16'hF100, 8'h00); off;
		repeat (8) op(8'h00);
		$display("tb_eq_acceler (3.03a ACCELER vs sp_acceler):");
		cont_report; ao_report; dout_report; mdo_report; md_report; gline_report; gliss_report; accon_report;
		dcas_report; accdir_report;
		$display("  coverage (clocks): buffer writes CP %0d OR %0d XOR %0d AND %0d, via XCNT %0d; 1F->07 %0d; AGR+1 %0d;",
			cv_fn0, cv_fn1, cv_fn2, cv_fn3, cv_alt, cv_c1f, cv_vert);
		$display("            HDDR low byte %0d; double-byte write %0d; ACC_BLK = 0 %0d; RETI %0d; block at 3.5 MHz %0d",
			cv_flip, cv_dbl, cv_blk, cv_reti, cv_slow);
		if (xref) $display("  X on reference outputs: %0d samples", xref);
		errors = errors + xref;
		$display("tb_eq_acceler: %0d errors%s, %0d us simulated", errors, weak ? " (some outputs never toggled)" : "", $time / 1000);
		$finish;
	end
endmodule
