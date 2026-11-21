// DS12887 (CMOS / RTC) of the Sprinter on the MC146818 register set of the MCU (docs/rtc.md, option c): the
// registers, the time and the EEPROM live in the firmware (rtc_mode 0), the core reads their mirror in kg_l2_rtc
// (kg_mcu2 RTC_*) and sends its writes there (RTC_COALESCE 1: a SETUP save of ~150 writes loses none).
//
// The bus of the chip (Intel mode, multiplexed on MD[15:8]) as the MAX makes it (sp_max: CMOS_AS active 1, CMOS_DWR
// and CMOS_DRD active 0, registered at 10K_CLK from the control word of the DCP):
// - address: MD[14:8] while CMOS_AS is 1, kept when it falls (OUT #DFBD). A7 is not decoded (128 bytes; the BIOS
//   never sends >= #80).
// - write: MD[15:8] sampled every clock while CMOS_DWR is 0, the last sample written when it rises (OUT #BFBD; the
//   chip takes the data at the rising /WR).
// - read: Q = the register of the latched address, OE = !CMOS_DRD (IN #FFBD); the board puts {Q, FF} on PER_D with
//   PER_OE = OE (sp_machine keeps MD after that, md_keep, until the ACEX takes it at the end of the cycle).
//   Overrides of the read (what the firmware does not give, docs/rtc.md 4.2):
//     C (#0C) = #50: PF + UF, the state of a real chip not read for a second; BIOS 3.06 CMOSINIT resets the clock
//                    to its build date when C is not #50 (the firmware sends 00);
//     D (#0D) = #80: VRT;
//     A (#0A) bit 7 (UIP) = 0: nobody waits for it, the mirror never updates in the middle of a read.
//   The seconds come with the 500 ms packets of the firmware: their edge is up to 0.5 s late (accepted).
//
// Clocks: CLK (clk_sys, 84 MHz) has the bus; CLK_BUS (clk_bus, 28 MHz = CLK / 3 from the same PLL, edges aligned)
// is the clock of kg_mcu2. The address and data cross as registers held for microseconds (re-registered in CLK_BUS),
// the write as a toggle (RTC_WR_N low one CLK_BUS clock), RTC_DO is registered in CLK. A write reaches the mirror
// ~4 CLK_BUS clocks after CMOS_DWR rises, a new address is readable ~3 later: the next I/O cycle of the CPU (the
// CMOS_TEST of the BIOS reads right after its write) comes more than 0.5 us later.
module sp_cmos (
	input             CLK,
	input      [15:0] MD,
	input             CMOS_AS,
	input             CMOS_DWR,
	input             CMOS_DRD,
	output reg  [7:0] Q = 8'hFF,      // read data for MD[15:8]
	output            OE,             // drive it (PER_OE)
	// kg_mcu2 RTC side
	input             CLK_BUS,
	output reg  [7:0] RTC_A = 8'd0,
	output reg  [7:0] RTC_DI = 8'd0,
	output            RTC_WR_N,
	input       [7:0] RTC_DO
);
	// ---- CLK: the bus
	reg  [6:0] a = 7'd0;
	reg  [7:0] d_cap = 8'd0, d = 8'd0;
	reg        dwr_q = 1'b1, wr_tgl = 1'b0;
	always @(posedge CLK) begin
		if (CMOS_AS) a <= MD[14:8];
		if (~CMOS_DWR) d_cap <= MD[15:8];
		dwr_q <= CMOS_DWR;
		if (CMOS_DWR & ~dwr_q) begin           // the rising /WR: the last sample
			d <= d_cap;
			wr_tgl <= ~wr_tgl;
		end
	end

	// ---- CLK_BUS: kg_mcu2
	reg tgl_s = 1'b0, tgl_d = 1'b0;
	always @(posedge CLK_BUS) begin
		RTC_A  <= {1'b0, a};
		RTC_DI <= d;
		tgl_s  <= wr_tgl;
		tgl_d  <= tgl_s;
	end
	assign RTC_WR_N = ~(tgl_s ^ tgl_d);

	// ---- CLK: the read data with the overrides
	always @(posedge CLK)
		case (a)
			7'h0A:   Q <= {1'b0, RTC_DO[6:0]};
			7'h0C:   Q <= 8'h50;
			7'h0D:   Q <= 8'h80;
			default: Q <= RTC_DO;
		endcase
	assign OE = ~CMOS_DRD;
endmodule
