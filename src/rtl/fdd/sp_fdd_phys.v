`timescale 1ns / 1ps
`default_nettype none
/*
 The WD1793 of the Sprinter on a physical floppy drive (the floppy connector of the Karabas Go): the VG93 model
 (rtl/fdd/vg93: github.com/demyanenko-d/FD1793_1818VG93 as karabas-go-core-profi took it, gate-level faithful to
 the KR1818VG93 / FD1793) with a data separator and the write precompensation. After hrdy_fdc.v / fdd_glue.v of
 karabas-go-core-profi (the Beta disk interface of the Profi on its 28 MHz clk_bus: the same #FF system register,
 the same 28 MHz), changed (karabas:) for the Sprinter:
 - the bus is the one of sp_fdd: the strobes of the MAX sampled in clk_bus (rd / wr active high, a = the register
   taken at the start of the strobe, din = the CPU byte during a write), not the CPU pins;
 - the density by FDD_1440 (10K_D0 of the MAX): CLK of the model 1 MHz (720 KB, TRD: MFM 250 kbit/s) or 2 MHz
   (1.44 MB: 500 kbit/s), the RCLK half period of the separator 56 or 28 clocks (2 / 1 us); the step rates are
   those of the chip at that CLK (the TURBING of the MAX, 2 MHz from a step on, is not made);
 - the writes are queued (no WAIT of the CPU here: sp_machine has no input for one): the model takes a written
   byte within two microwords and has one input latch for the four registers, a CPU at 21 MHz writes the sector
   and the command register 2 us apart (FDRIVER2). A write of the CPU goes into a FIFO of 4; the FIFO gives the
   model one write (WE 3 clocks) when no CPU read is on, then waits GUARD periods of CLK (10: 10 / 5 us). While a
   write waits or the guard runs, INTRQ and DRQ read 0 (the model has not seen the write yet: a command would look
   finished, a data byte still requested); a register read then gives the state before the write.
 - The drive as on a Beta disk interface (the Sprinter has no motor bit: FDRIVER2 MOTORFF stops the motor by /MR):
   the drive select of the selected drive is static (karabas: the Profi core selects it only with HLD; then the
   Restore the chip makes at the end of /MR, without a head load, would step a deselected drive 255 times), MOTOR =
   HLD, READY = HLD (HRDY), HLT = #FF bit 3, /MR = #FF bit 2 (and the CPU reset).
 - Pins (fdd_in / fdd_out as the other cores: high = active, the inverters of the Go board after them):
   fdd_in = { rdata, wprt, tr00, index }, fdd_out = { wdata, wgate, side1, step, dir (1: in), motor, ds1, ds0 }.
   ds (from sp_fdd): the drive line of the selected drive, 1 DS0, 2 DS1, 0 = the selected drive is an image: then
   every output is 0 (inactive). All outputs through flip-flops (WD and the decoders are combinational).
*/
module sp_fdd_phys #(
	parameter [3:0] GUARD = 4'd10          // CLK periods after a write given to the model
) (
	input  wire        clk,                // clk_bus (28 MHz), SYSCLK of the model
	input  wire        reset,              // the CPU reset
	input  wire        hd,                 // FDD_1440: CLK 2 MHz, 500 kbit/s
	input  wire        mr_n,               // #FF bit 2
	input  wire        hlt,                // #FF bit 3
	input  wire        side1,              // #FF bit 4 = 0: side 1
	input  wire [1:0]  ds,                 // 0 no physical drive selected, 1 DS0, 2 DS1

	input  wire        rd,                 // a read strobe of a WD1793 register (active, sampled in clk)
	input  wire        wr,                 // a write strobe
	input  wire [1:0]  a,
	input  wire [7:0]  din,
	output reg  [7:0]  dout = 8'hFF,       // the register of the last read (held after the strobe)
	output wire        drq,
	output wire        intrq,

	input  wire [3:0]  fdd_in,
	output reg  [7:0]  fdd_out = 8'd0
);
	wire in_rdata = fdd_in[3], in_wprt = fdd_in[2], in_tr00 = fdd_in[1], in_index = fdd_in[0];
	wire act = ds != 2'd0;

	// ---- CLK of the model: a square wave, clk / 28 (1 MHz) or clk / 14 (2 MHz) ----
	reg [3:0] cdiv = 4'd0;
	reg fdc_clk = 1'b0;
	wire cdiv_end = cdiv >= (hd ? 4'd6 : 4'd13);   // >=: the rate may change in a period
	always @(posedge clk)
		if (cdiv_end) begin cdiv <= 4'd0; fdc_clk <= ~fdc_clk; end
		else cdiv <= cdiv + 4'd1;
	wire fdc_clk_rise = ~fdc_clk & cdiv_end;

	// ---- the write queue ----
	wire mr_s = !mr_n || reset;
	reg  [9:0] q [0:3];                    // {a, d}
	reg  [1:0] q_wa = 2'd0, q_ra = 2'd0;
	reg  [2:0] q_n = 3'd0;
	reg        wr_p = 1'b0;
	reg  [7:0] d_l = 8'd0;
	reg  [1:0] a_l = 2'd0;
	reg  [1:0] pulse = 2'd0;               // the write given to the model: WE for 3 clocks
	reg  [3:0] guard = 4'd0;
	reg  [9:0] cur = 10'd0;
	wire push = wr_p && !wr && q_n != 3'd4;   // the end of a CPU write (a full queue drops it)
	wire pop = q_n != 3'd0 && pulse == 2'd0 && guard == 4'd0 && !rd;
	always @(posedge clk) begin
		wr_p <= wr;
		if (wr) begin d_l <= din; a_l <= a; end
		if (mr_s) begin
			q_wa <= 2'd0; q_ra <= 2'd0; q_n <= 3'd0; pulse <= 2'd0; guard <= 4'd0;
		end else begin
			if (push) begin q[q_wa] <= {a_l, d_l}; q_wa <= q_wa + 2'd1; end
			if (pop) begin cur <= q[q_ra]; q_ra <= q_ra + 2'd1; pulse <= 2'd3; end
			q_n <= q_n + (push ? 3'd1 : 3'd0) - (pop ? 3'd1 : 3'd0);
			if (pulse != 2'd0) begin
				pulse <= pulse - 2'd1;
				if (pulse == 2'd1) guard <= GUARD;
			end else if (fdc_clk_rise && guard != 4'd0)
				guard <= guard - 4'd1;
		end
	end
	wire wpend = q_n != 3'd0 || pulse != 2'd0 || guard != 4'd0;

	// ---- the model ----
	wire we_m = pulse != 2'd0;
	wire re_m = rd && !we_m;
	wire [7:0] dal_o;
	wire dal_oe, m_drq, m_intrq;
	wire motor, wg, wd, step, dirc, rclk, tg43, early, late, rawread_n;
	vg93_top vg93 (
		.SYSCLK(clk), .CLK(fdc_clk), .MR_n(!mr_s),
		.CS_n(!(we_m || re_m)), .RE_n(!re_m), .WE_n(!we_m), .A(we_m ? cur[9:8] : a),
		.DAL_I(cur[7:0]), .DAL_O(dal_o), .DAL_OE(dal_oe), .DRQ(m_drq), .INTRQ(m_intrq),
		.STEP(step), .DIRC(dirc), .EARLY(early), .LATE(late), .HLD(motor), .TG43(tg43), .WG(wg), .WD(wd),
		.RCLK(rclk), .RAWREAD_n(rawread_n), .READY(motor), .TR00_n(!in_tr00), .IP_n(!in_index), .WPRT_n(!in_wprt),
		.HLT(hlt)
	);
	always @(posedge clk) if (re_m && dal_oe) dout <= dal_o;
	assign drq = m_drq && !wpend;
	assign intrq = m_intrq && !wpend;

	// ---- the separator (fdd_glue of the Profi core, HALF by the rate) ----
	wire [5:0] half_end = hd ? 6'd27 : 6'd55;     // HALF - 1
	wire [5:0] centre   = hd ? 6'd13 : 6'd27;     // HALF / 2 - 1
	reg  [2:0] rs = 3'b000;                       // RDATA synchronised (high = a flux transition)
	reg        rdl = 1'b0, rdl_d = 1'b0;          // filtered: a level must hold two samples
	always @(posedge clk) begin
		rs <= {rs[1:0], in_rdata};
		if (rs[2:1] == 2'b00 || rs[2:1] == 2'b11) rdl <= rs[2];
		rdl_d <= rdl;
	end
	wire flux = rdl && !rdl_d;                    // the start of a pulse, one clock
	assign rawread_n = !flux;
	reg  [5:0] cnt = 6'd0;
	reg        rclk_r = 1'b0;
	wire [6:0] pull = {1'b0, cnt} + {1'b0, centre};   // (cnt + C) / 2: half way to the window centre
	always @(posedge clk)
		if (flux) cnt <= pull[6:1];
		else if (cnt >= half_end) begin cnt <= 6'd0; rclk_r <= !rclk_r; end
		else cnt <= cnt + 6'd1;
	assign rclk = rclk_r;

	// ---- write precompensation (fdd_glue): a WD pulse starts one counter of delay + width; WDATA while it is 1..6
	// (213 ns); delay 3 clocks, LATE / EARLY move it by 1 clock (36 ns), by 2 inside TG43 ----
	reg wd_d = 1'b0;
	reg [3:0] pc = 4'd0;
	reg wdata = 1'b0;
	always @(posedge clk) begin
		wd_d <= wd & wg;
		if (wd & wg & !wd_d)
			case ({late, tg43, early})
				3'b110:  pc <= 4'd11;
				3'b100:  pc <= 4'd10;
				3'b011:  pc <= 4'd7;
				3'b001:  pc <= 4'd8;
				default: pc <= 4'd9;
			endcase
		else if (pc != 4'd0)
			pc <= pc - 4'd1;
		wdata <= pc != 4'd0 && pc <= 4'd6;
	end

	// ---- the pins: all 0 while no physical drive is selected ----
	always @(posedge clk) begin
		fdd_out[0] <= ds == 2'd1;
		fdd_out[1] <= ds == 2'd2;
		fdd_out[2] <= act && motor;
		fdd_out[3] <= act && dirc;
		fdd_out[4] <= act && step;
		fdd_out[5] <= act && side1;
		fdd_out[6] <= act && wg;
		fdd_out[7] <= act && wdata;
	end
endmodule
`default_nettype wire
