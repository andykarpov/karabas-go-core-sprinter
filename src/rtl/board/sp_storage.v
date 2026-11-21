`timescale 1ns / 1ps
`default_nettype none
// Sprinter storage on SD images and the read data of the peripherals on MD (docs/storage.md):
// - IDE: hdf_ata (modules/rtl/mcu, as core-p4096 / core-profi) on the primary channel = HDD2 of the MAX (XHD2_CS:
//   the BIOS selects it by OUT (#21BC) = descriptor 2B, "Set HDD2"; MAME also calls ata 0 / code 2B primary), master =
//   image slot 4, slave = slot 5. The secondary channel (HDD1, XHD1_CS) has no device: it reads 00. 16-bit data:
//   the word is on MD[15:0] (the ACEX keeps the high byte in HDDR), the registers on MD[7:0]. No IORDY / /WAIT (the
//   MAX does not use XHR_RDY either: the timing of the IDE comes from the wait table of the ACEX), and hdf_ata needs
//   none: a sector is in its buffer before DRQ.
// - FDD: sp_fdd (wd1793 + the system register #FF), drives A / B = image slots 0 / 1.
// - Read data: an IDE read (XHD_RD), a WD1793 register (WG_RD_N), the system register #FF (RD_KMPS with the KP11
//   select MA2 = FDD_C0 latched) and the CMOS read (CMOS_DRD, the byte from CMOS_Q: the hook for sp_cmos) are put on
//   MD from the start of their strobe to the end of the CPU I/O cycle (IORQ_N high): the ACEX takes the byte at the
//   rise of its /IOMM (MDP) and the high IDE byte at the end of /RD (HDDR). The 8-bit devices are on MD[15:8] (the
//   ACEX reads type 7 ports from there), a copy on MD[7:0]. A read of a channel / device / port with nothing behind it
//   gives 00 (not the last value the bus keeper holds: the BIOS test of a drive writes a register and reads it back).
// - Clocks: CLK = clk_sys (84 MHz, the machine), CLK_BUS = clk_bus (28 MHz = CLK / 3, the same PLL, the edges
//   aligned): the controllers and the sdc side of kg_mcu2 run on CLK_BUS; the strobes, the register number and the
//   write data reach them from CLK registers (frozen from the start of a strobe until 12 CLK after its end), taken
//   again on CLK_BUS for hdf_ata (its task file logic then sees CLK_BUS registers only), so they stay put while
//   hdf_ata ends the access (two CLK_BUS after the strobe rise) and while sp_fdd takes the data.
// - The IDE reset of hdf_ata: XHD_RES of the MAX (power-up) or the CPU /RESET (a reset in the middle of a transfer
//   must not leave the device in DRQ for the next boot; as core-p4096 with its machine reset).
module sp_storage (
	input  wire        CLK,
	input  wire        CLK_BUS,
	input  wire        RESET,          // power-up (CLK_BUS): the images forgotten
	// ---- the machine (CLK)
	input  wire        CPU_RES_N,      // the CPU /RESET (the system register #FF cleared)
	input  wire        IORQ_N,         // the CPU /IORQ: the end of the I/O cycle releases MD
	input  wire [15:0] MD,             // the MD bus (the write data of the ACEX)
	input  wire  [3:0] HDD_C,          // the control word latched from MA
	input  wire  [2:0] FDD_C,
	input  wire  [2:0] HD_A,           // the IDE register
	input  wire  [1:0] WG_A,           // MA[1:0] latched: the WD1793 register (A6..A5 of the port)
	input  wire        XHD_RES,        // the IDE /RESET of the MAX (low until the first frame)
	input  wire        XHD_RD,
	input  wire        XHD_WR,
	input  wire  [2:1] XHD1_CS,        // HDD1: the secondary channel (no device)
	input  wire  [2:1] XHD2_CS,        // HDD2: the primary channel (hdf_ata): [1] CS1FX (1F0-1F7), [2] CS3FX (3F6-3F7)
	input  wire        WG_RD_N,
	input  wire        WG_WR_N,
	input  wire        WR_PDOS,
	input  wire        RD_KMPS,
	input  wire        FDD_1440,
	input  wire        CMOS_DRD,       // hook: the read strobe of the DS12887 (sp_cmos)
	input  wire  [7:0] CMOS_Q,         // hook: its read byte (valid while CMOS_DRD is low)
	output reg  [15:0] PER_D = 16'h0000,
	output reg         PER_OE = 1'b0,
	// ---- the image files of kg_mcu2 (CLK_BUS): floppies slots 0-1, hard disks slots 4-5
	input  wire  [7:0] SDC_IMG_MOUNTED,
	input  wire [63:0] SDC_IMG_SIZE,
	output wire  [7:0] SDC_RD,
	output wire  [7:0] SDC_WR,
	output wire [31:0] SDC_SECTOR,
	input  wire        SDC_BUSY,
	input  wire        SDC_DONE,
	input  wire        SDC_ERROR,
	input  wire  [2:0] SDC_SLOT,
	input  wire        SDC_BYTE_IN_STROBE,
	input  wire  [8:0] SDC_BYTE_ADDR,
	input  wire  [7:0] SDC_BYTE_IN_DATA,
	output wire  [7:0] SDC_BYTE_OUT_DATA,
	input  wire  [7:0] IMG_WP,
	output wire        HDD_LED,
	output wire        FDD_ACTIVE
);
	// ================= CLK: the strobes, frozen address / data for the controllers
	reg  [2:0] ide_a = 3'd0;
	reg  [1:0] ide_cs_n = 2'b11;
	reg        ide_rd_n = 1'b1, ide_wr_n = 1'b1, ide_res = 1'b1;
	reg [15:0] ide_d = 16'd0;
	reg        ide_on = 1'b0;                      // the access is for the primary channel
	reg  [3:0] ide_hold = 4'd0;
	reg        ide_st_p = 1'b0;
	wire       ide_st = ~XHD_RD | ~XHD_WR;
	always @(posedge CLK) begin
		ide_st_p <= ide_st;
		ide_rd_n <= XHD_RD;
		ide_wr_n <= XHD_WR;
		ide_res  <= ~XHD_RES | ~CPU_RES_N;
		if (ide_st) ide_hold <= 4'd12; else if (ide_hold != 4'd0) ide_hold <= ide_hold - 4'd1;
		// the register and the channel: taken at the first CLK of a strobe (the CS of the MAX changes with it)
		if (~(ide_st & ide_st_p) & (ide_hold == 4'd0 | ide_st)) begin
			ide_a    <= HD_A;
			ide_cs_n <= XHD2_CS;
			ide_on   <= XHD2_CS != 2'b11;
		end
		if (~XHD_WR) ide_d <= MD;                   // the word until the end of the write strobe
	end

	reg  [1:0] wg_a = 2'd0;
	reg        wg_rd_n = 1'b1, wg_wr_n = 1'b1, wg_pdos_n = 1'b1, wg_1440 = 1'b1, res_r = 1'b1;
	reg  [7:0] wg_d = 8'd0;
	always @(posedge CLK) begin
		wg_rd_n   <= WG_RD_N;
		wg_wr_n   <= WG_WR_N;
		wg_pdos_n <= WR_PDOS;
		wg_1440   <= FDD_1440;
		res_r     <= ~CPU_RES_N;
		if (WG_RD_N & WG_WR_N & wg_rd_n & wg_wr_n) wg_a <= WG_A;   // frozen during a strobe and its end
		if (~WG_WR_N | ~WR_PDOS) wg_d <= MD[15:8];
	end

	// ================= CLK_BUS: the controllers
	wire        hdf_dev, hdf_dev1_here;
	wire  [1:0] hdf_rd, hdf_wr;
	wire [31:0] hdf_sector;
	wire  [7:0] hdf_out_data;
	wire [15:0] hdf_dout;
	wire        hdf_own = SDC_SLOT[2:1] == 2'b10;
	wire        fdd_own = SDC_SLOT[2:1] == 2'b00;
	reg         res_bus = 1'b1;
	always @(posedge CLK_BUS) res_bus <= res_r;
	// the IDE bus again on CLK_BUS
	reg  [2:0] b_a = 3'd0;
	reg  [1:0] b_cs_n = 2'b11;
	reg        b_rd_n = 1'b1, b_wr_n = 1'b1, b_res = 1'b1;
	reg [15:0] b_d = 16'd0;
	always @(posedge CLK_BUS) begin
		b_a    <= ide_a;
		b_cs_n <= ide_on ? ide_cs_n : 2'b11;
		b_rd_n <= ide_rd_n | ~ide_on;
		b_wr_n <= ide_wr_n | ~ide_on;
		b_d    <= ide_d;
		b_res  <= ide_res;
	end
	hdf_ata #(.ENABLE_RDB(0)) hdf(.clk(CLK_BUS), .reset(RESET), .ata_reset(b_res), .dev0_en(1'b1),
		.dev(hdf_dev), .dev1_here(hdf_dev1_here), .a(b_a), .cs_n(b_cs_n),
		.rd_n(b_rd_n), .wr_n(b_wr_n), .din(b_d), .dout(hdf_dout),
		.img_mounted(SDC_IMG_MOUNTED[5:4]), .img_size(SDC_IMG_SIZE), .sdc_rd(hdf_rd), .sdc_wr(hdf_wr),
		.sdc_sector(hdf_sector), .sdc_busy(SDC_BUSY & hdf_own), .sdc_done(SDC_DONE & hdf_own),
		.sdc_error(SDC_ERROR), .sdc_byte_in_strobe(SDC_BYTE_IN_STROBE & hdf_own), .sdc_byte_addr(SDC_BYTE_ADDR),
		.sdc_byte_in_data(SDC_BYTE_IN_DATA), .sdc_byte_out_data(hdf_out_data), .led(HDD_LED));

	wire  [1:0] fdd_rd, fdd_wr;
	wire [31:0] fdd_sector;
	wire  [7:0] fdd_out_data, fdd_dout, fdd_sys_q;
	sp_fdd fdd(.clk(CLK_BUS), .reset(res_bus), .wg_rd_n(wg_rd_n), .wg_wr_n(wg_wr_n), .wr_pdos_n(wg_pdos_n),
		.a(wg_a), .din(wg_d), .fdd_1440(wg_1440), .dout(fdd_dout), .sys_q(fdd_sys_q), .wp(IMG_WP[1:0]),
		.img_mounted(SDC_IMG_MOUNTED[1:0]), .img_size(SDC_IMG_SIZE), .sdc_rd(fdd_rd), .sdc_wr(fdd_wr),
		.sdc_sector(fdd_sector), .sdc_busy(SDC_BUSY & fdd_own), .sdc_done(SDC_DONE & fdd_own),
		.sdc_byte_addr(SDC_BYTE_ADDR), .sdc_byte_in_strobe(SDC_BYTE_IN_STROBE & fdd_own),
		.sdc_byte_in_data(SDC_BYTE_IN_DATA), .sdc_byte_out_data(fdd_out_data), .active(FDD_ACTIVE));

	// one request at a time, the lowest slot first (kg_l2_img): the floppies (0-1) before the hard disks (4-5)
	assign SDC_RD = {2'b00, hdf_rd, 2'b00, fdd_rd};
	assign SDC_WR = {2'b00, hdf_wr, 2'b00, fdd_wr};
	assign SDC_SECTOR = (fdd_rd != 2'd0 || fdd_wr != 2'd0) ? fdd_sector : hdf_sector;
	assign SDC_BYTE_OUT_DATA = fdd_own ? fdd_out_data : hdf_out_data;

	// the read data of the controllers registered on CLK_BUS (their register muxes stay inside CLK_BUS; the CLK_BUS ->
	// CLK path below is then register -> a few LUTs -> register in one CLK)
	reg [15:0] hdf_q = 16'h0000;
	reg  [7:0] fdd_q = 8'hFF, fdd_sq = 8'hFF;
	always @(posedge CLK_BUS) begin
		hdf_q  <= hdf_dout;
		fdd_q  <= fdd_dout;
		fdd_sq <= fdd_sys_q;
	end

	// ================= CLK: the read data on MD (PER_D / PER_OE of sp_machine)
	// (the register number reaches the controllers 1 CLK + 1 CLK_BUS after the strobe falls and their data 1 CLK_BUS
	// later: ~110 ns of a strobe of 270 ns (IDE) / 415 ns (WD1793); the ACEX takes the byte at ~310 ns, tb_storage)
	wire       r_ide  = ~XHD_RD;
	wire       r_wg   = ~WG_RD_N;
	// #FF: the KP11 half (MA2 = 1) of the word 701F with its strobe bit (MA4 = FDD_C2; the idle word between I/O
	// cycles and the type 7 ports without a device, 7000-7003 ISA, have none)
	wire       r_sys  = ~RD_KMPS & (HDD_C == 4'b0000) & FDD_C[0] & FDD_C[2];
	wire       r_cmos = ~CMOS_DRD;
	always @(posedge CLK) begin
		if (r_ide)       PER_D <= ide_on ? hdf_q : 16'h0000;
		else if (r_wg)   PER_D <= {fdd_q, fdd_q};
		else if (r_sys)  PER_D <= {fdd_sq, fdd_sq};
		else if (r_cmos) PER_D <= {CMOS_Q, CMOS_Q};
		if (r_ide | r_wg | r_sys | r_cmos) PER_OE <= 1'b1;
		else if (IORQ_N) PER_OE <= 1'b0;
	end
endmodule
`default_nettype wire
