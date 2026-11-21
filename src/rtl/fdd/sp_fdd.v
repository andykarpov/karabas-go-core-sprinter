`timescale 1ns / 1ps
`default_nettype none
/*
 The floppy controller of the Sprinter on disk images: the WD1793 (wd1793.v of MiSTer, our 1.44 MB copy) and the
 system register of the Beta disk interface (port #FF, the "PDOS" register WR_PDOS of the MAX), two drives on the
 image files of the mcu (kg_mcu2 ENABLE_IMG, slots 0 and 1). Adapted from karabas-go-core-p4096 p4096_fdd.v.

 - The bus: register level, no data separator (the FDAT / QDAT / WDAT logic of the MAX is not made). The strobes of
   the MAX (WG_RD_N, WG_WR_N, WR_PDOS) come from the 84 MHz domain; here (CLK = clk_bus, 28 MHz, the domain of the
   sdc side) the register number is taken at the start of a strobe (A = MA[1:0] = A6..A5 of the port, from the MA
   latch of sp_machine), the write data at its end; at the end wd1793 gets a short rd / wr pulse (two ce), so the
   read side effects (the data register steps, INTRQ cleared by a status read) come after the CPU has the byte.
   DOUT is the register the strobe selects, valid while the strobe is low and after it until the next one.
 - System register #FF, write: D0 drive (A / B; D1 is not used by the BIOS: two drives), D2 /MR (0 = wd1793 in
   reset), D3 HLT (not used), D4 side (0 = side 1), D6 density (not used: the image says it). Read (through the KP11
   multiplexer of the board, RD_KMPS): D7 INTRQ, D6 DRQ, the rest 1. Cleared by RESET (the CPU reset).
 - Images, the geometry by the size: 1 474 560 = PC 1.44 MB (18 sectors of 512, wd1793 size_code 5); 737 280 =
   PC 720 KB (9 x 512, size_code 2); anything else = TRD (16 x 256, size_code 1). All are track * 2 + side in the
   image (layout 0), sectors numbered from 1.
 - Density: the MAX gives the WD1793 1 MHz (720 KB) or 2 MHz (1.44 MB, FDD_1440); at the wrong rate a real drive gives
   no ID at all, and the BIOS finds the density so (DISK_ID of FDRIVER2: Read Address with a timeout of ~140 ms,
   then the other rate). For a PC image of the other density INTRQ and DRQ of a type II / III command (read / write
   sector, read address, read / write track) do not reach the CPU (the command seems to hang); type I (restore, seek,
   step: no data) and IV work at any rate. TRD images are read at either rate (TR-DOS on the Sprinter: not checked
   which rate it sets).
 - A sector goes to / from the mcu directly (5-15 ms a sector, the time of a real drive); a drive change or a mount
   of the selected drive gives wd1793 a mount pulse with that size (a disk inserted). READY = the drive has an image.
*/
module sp_fdd (
	input  wire        clk,          // clk_bus (28 MHz)
	input  wire        reset,        // the CPU reset (the system register to 0)

	// the strobes of the MAX and the data (from the 84 MHz domain, registers there)
	input  wire        wg_rd_n,
	input  wire        wg_wr_n,
	input  wire        wr_pdos_n,
	input  wire [1:0]  a,            // MA[1:0] latched: the WD1793 register
	input  wire [7:0]  din,          // MD[15:8] (the CPU byte) during the strobe
	input  wire        fdd_1440,     // 10K_D0 of the MAX in the working mode: 2 MHz for the WD1793
	output wire [7:0]  dout,         // the WD1793 register
	output wire [7:0]  sys_q,        // the #FF read: {INTRQ, DRQ, 111111}
	input  wire [1:0]  wp,           // write protect of the drives (the image files)

	// the image files (slots 0-1 of kg_mcu2)
	input  wire [1:0]  img_mounted,
	input  wire [63:0] img_size,
	output reg  [1:0]  sdc_rd = 2'd0,
	output reg  [1:0]  sdc_wr = 2'd0,
	output reg  [31:0] sdc_sector = 32'd0,
	input  wire        sdc_busy,     // of slots 0-1 only (the owner masks them)
	input  wire        sdc_done,
	input  wire [8:0]  sdc_byte_addr,
	input  wire        sdc_byte_in_strobe,
	input  wire [7:0]  sdc_byte_in_data,
	output wire [7:0]  sdc_byte_out_data,
	output wire        active        // a sector in flight (an icon / LED)
);

// ---------------- clock enable (7 MHz), the strobes ----------------
reg [1:0] div = 2'd0;
always @(posedge clk) div <= div + 2'd1;
wire ce = div == 2'd0;

reg rd_q = 1'b0, wr_q = 1'b0, pd_q = 1'b0;          // the strobes sampled here (1 = active)
reg rd_p = 1'b0, wr_p = 1'b0;                       // the pulses to wd1793
reg [1:0] a_s = 2'd0;
reg [7:0] d_s = 8'd0;
reg [7:0] sys = 8'h00;
reg [7:0] cmd = 8'h00;                              // the last command (the rate check)
always @(posedge clk) begin
	rd_q <= !wg_rd_n;
	wr_q <= !wg_wr_n;
	pd_q <= !wr_pdos_n;
	if ((!wg_rd_n && !rd_q) || (!wg_wr_n && !wr_q)) a_s <= a;   // the start of a strobe
	if (!wg_wr_n || !wr_pdos_n) d_s <= din;                    // the data until the end of the strobe
	if (rd_q && wg_rd_n) rd_p <= 1'b1; else if (ce) rd_p <= 1'b0;
	if (wr_q && wg_wr_n) wr_p <= 1'b1; else if (ce) wr_p <= 1'b0;
	if (reset) sys <= 8'h00;
	else if (pd_q && wr_pdos_n) sys <= d_s;
	if (wr_q && wg_wr_n && a_s == 2'd0) cmd <= d_s;
end
wire drv = sys[0];

// ---------------- the images of the drives ----------------
reg [20:0] size0 = 21'd0, size1 = 21'd0;
reg [1:0] here = 2'd0;
reg drv_d = 1'b0;
reg [3:0] mnt_cnt = 4'd0;                           // the mount pulse of wd1793 (several ce)
always @(posedge clk) begin
	if (img_mounted[0]) begin size0 <= img_size[20:0]; here[0] <= img_size != 64'd0 && img_size[63:21] == 43'd0; end
	if (img_mounted[1]) begin size1 <= img_size[20:0]; here[1] <= img_size != 64'd0 && img_size[63:21] == 43'd0; end
	drv_d <= drv;
	if (img_mounted[drv] || drv != drv_d)
		mnt_cnt <= 4'd15;
	else if (ce && mnt_cnt != 4'd0)
		mnt_cnt <= mnt_cnt - 4'd1;
end
wire [20:0] size_sel = drv ? size1 : size0;
wire hd = size_sel == 21'd1474560;
wire dd_pc = size_sel == 21'd737280;
wire [2:0] size_code = hd ? 3'd5 : dd_pc ? 3'd2 : 3'd1;
wire rate_ok = !(hd || dd_pc) || (hd == fdd_1440) || !cmd[7] || cmd[7:4] == 4'hD;

// ---------------- wd1793 ----------------
wire [31:0] sd_lba;
wire sd_rd, sd_wr;
reg sd_ack = 1'b0;
reg [8:0] sd_buff_addr_r = 9'd0;
reg [7:0] sd_buff_dout = 8'd0;
reg sd_buff_wr = 1'b0;
wire [7:0] sd_buff_din;
wire drq, intrq;
localparam ST_IDLE = 3'd0, ST_RD = 3'd1, ST_RD_WAIT = 3'd2, ST_WR = 3'd3, ST_WR_WAIT = 3'd4, ST_END = 3'd5;
reg [2:0] st = ST_IDLE;
wire [8:0] sd_buff_addr = (st == ST_WR || st == ST_WR_WAIT) ? sdc_byte_addr : sd_buff_addr_r;

wd1793 #(.RWMODE(1), .EDSK(0)) vg (
	.clk_sys(clk), .ce(ce), .reset(reset || !sys[2]), .io_en(1'b1),
	.rd(rd_p), .wr(wr_p), .addr(a_s), .din(d_s), .dout(dout),
	.drq(drq), .intrq(intrq), .busy(),
	.wp(wp[drv]), .size_code(size_code), .layout(1'b0), .side(!sys[4]), .ready(here[drv]),
	.img_mounted(mnt_cnt != 4'd0), .img_size(size_sel), .prepare(),
	.sd_lba(sd_lba), .sd_rd(sd_rd), .sd_wr(sd_wr), .sd_ack(sd_ack),
	.sd_buff_addr(sd_buff_addr), .sd_buff_dout(sd_buff_dout), .sd_buff_din(sd_buff_din), .sd_buff_wr(sd_buff_wr),
	.input_active(1'b0), .input_addr(21'd0), .input_data(8'd0), .input_wr(1'b0),
	.buff_addr(), .buff_read(), .buff_din(8'd0)
);

assign sys_q = {intrq && rate_ok, drq && rate_ok, 6'b111111};

// ---------------- sd_* of wd1793 <-> sdc_* of the mcu (as p4096_fdd) ----------------
reg cur = 1'b0;
assign sdc_byte_out_data = sd_buff_din;
assign active = st != ST_IDLE;
always @(posedge clk) begin
	sd_buff_wr <= 1'b0;
	if (reset) begin
		st <= ST_IDLE; sdc_rd <= 2'd0; sdc_wr <= 2'd0; sd_ack <= 1'b0;
	end else case (st)
		ST_IDLE:
			if ((sd_rd || sd_wr) && here[drv]) begin
				cur <= drv;
				sdc_sector <= sd_lba;
				sd_ack <= 1'b1;
				st <= sd_rd ? ST_RD : ST_WR;
			end
		ST_RD: begin
			sdc_rd[cur] <= 1'b1;
			if (sdc_busy && sdc_rd[cur]) begin
				sdc_rd <= 2'd0;
				st <= ST_RD_WAIT;
			end
		end
		ST_RD_WAIT: begin
			if (sdc_byte_in_strobe) begin
				sd_buff_addr_r <= sdc_byte_addr;
				sd_buff_dout <= sdc_byte_in_data;
				sd_buff_wr <= 1'b1;
			end
			if (sdc_done) st <= ST_END;
		end
		ST_WR: begin
			sdc_wr[cur] <= 1'b1;
			if (sdc_busy && sdc_wr[cur]) begin
				sdc_wr <= 2'd0;
				st <= ST_WR_WAIT;
			end
		end
		ST_WR_WAIT:
			if (sdc_done) st <= ST_END;
		default: begin                       // ST_END: wd1793 sees sd_ack fall, then its request ends
			sd_ack <= 1'b0;
			if (!sd_rd && !sd_wr) st <= ST_IDLE;
		end
	endcase
end

endmodule
`default_nettype wire
