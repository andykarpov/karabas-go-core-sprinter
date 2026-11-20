// Z84C15 of the Sprinter: Z80 (T80pa) + the peripherals the Sprinter software uses (docs/z84c15.md): SIO A / B
// receive (byte streams, 3-byte FIFO, RR0 / RR1 / RR2, WR0 commands), CTC channel 0 (channels 1-3: writes taken,
// reads FF), PIO A / B registers, SCRP / SCDP (WCR, MWBR, CSBR, MCR) with the CS0 / CS1 decode, INTA vector FF.
// Not made: WDT, INTPR (F0 / F1 / F4 are internal, writes ignored, reads FF), SIO Tx, interrupts and vectors of the
// peripherals, daisy chain, WCR / MWBR waits, CLKOUT divider.
//
// Clock and pin contract (src/rtl/acex/sp_acex.v header): one clock CLK (84 MHz) with CE / CE_N = the rising /
// falling edge of the original 42 MHz. The Z80 clock is the ACEX output CLKZ1 (21 / 3.5 MHz, changes at CE_N);
// CLKZ1_NX is its value after the next CE_N (DCP CLK_Z80_NX, valid at that CE_N). T80pa steps at the CE_N where
// CLKZ1 changes: CEN_p = CE_N & CLKZ1 rises, CEN_n = CE_N & CLKZ1 falls. Its outputs are the *_NX pins; the pins
// are a register loaded at CE, so they change one CLK after the CLKZ1 edge (the Z80 output delay of the original:
// half a 42 MHz cycle), never at CE_N. Data: an opcode is taken at the rise of T3 (T80 DInst), a memory / port read
// at the fall of T3, /WAIT at the fall of T2 / TW (docs/memtiming.md, column "Z80 / T80pa").
//
// Data in: an internal port read (A[7:0] = 10-13, 18-1F, EE, EF, F0, F1, F4) takes the internal register whatever is
// on D_I (the internal read wins over the ACEX); INTA (M1 with IORQ) takes FF (MAME: the acknowledge callback = FF).
// Writes to the internal ports are bus cycles as any: the ACEX DCP sees them too (MAME cpu_io_w tap). Data out: D_O
// / D_OE are pins too; D_OE = a write machine cycle of the T80 (from T1, as the bus model of tb_eq_acex; the data
// are valid from the rise of T2).
//
// karabas: CPU choice (docs/z84c15.md 8): T80pa (Sorgelig timing; the copy of core-tsconf / core-profi, bus timing
// checked there cycle by cycle against z80-silicon) with OUT0 = 1: the CMOS Z84C15 does OUT (C),FF for OUT (C),0.
module sp_z84c15 (
	input             CLK,
	input             CE,
	input             CE_N,
	input             CLKZ1,
	input             CLKZ1_NX,
	input             RESET_N,      // the /RESET line
	input             WAIT_N,       // the /WAIT line
	input             INT_N,
	input             NMI_N,
	// Z80 pins (change right after a CE) and their values after the next CE
	output reg        M1_N = 1'b1,
	output reg        RF_N = 1'b1,
	output reg        IO_N = 1'b1,
	output reg        WR_N = 1'b1,
	output reg        RD_N = 1'b1,
	output reg        MR_N = 1'b1,
	output reg        HALT_N = 1'b1,
	output reg [15:0] A = 16'hFFFF,
	output reg  [7:0] D_O = 8'hFF,
	output reg        D_OE = 1'b0,
	output            M1_N_NX,
	output            RF_N_NX,
	output            IO_N_NX,
	output            WR_N_NX,
	output            RD_N_NX,
	output            MR_N_NX,
	output     [15:0] A_NX,
	input       [7:0] D_I,          // the external data bus (memory, ACEX) as the CPU sees it
	output            INT_RD,       // an internal port is being read (pins): the external data are not taken
	// chip selects (MCR / CSBR, z84c015.cpp translate_memory_address): the pin address in the CS0 / CS1 range
	output            CS0,
	output            CS1,
	output reg  [7:0] CSBR = 8'hFF,
	output reg  [7:0] MCR = 8'h01,
	// SIO: byte streams (byte + one CLK strobe; hold the byte while RDY = 0), RR0 CTS / DCD bits, WR5
	input       [7:0] RXA_D,
	input             RXA_STB,
	output            RXA_RDY,
	input       [7:0] RXB_D,
	input             RXB_STB,
	output            RXB_RDY,
	input             CTSA,
	input             DCDA,
	input             CTSB,
	input             DCDB,
	output      [7:0] WR5A,
	output      [7:0] WR5B,
	// CTC: CLK/TRG inputs (levels, synchronous to CLK), ZC/TO0 pulse
	input             TRG0,
	output            ZC0,
	// PIO
	input       [7:0] PA_I,
	output      [7:0] PA_O,
	output      [7:0] PA_OE,
	input       [7:0] PB_I,
	output      [7:0] PB_O,
	output      [7:0] PB_OE
);
	// ================= CPU
	wire cen_p = CE_N & ~CLKZ1 & CLKZ1_NX;
	wire cen_n = CE_N & CLKZ1 & ~CLKZ1_NX;
	wire [7:0] cpu_di, cpu_do;
	wire mreq_n, iorq_n, rd_n, wr_n, m1_n, rfsh_n, halt_n, wr_cyc;
	wire [15:0] cpu_a;

	T80pa cpu (.RESET_n(RESET_N), .CLK(CLK), .CEN_p(cen_p), .CEN_n(cen_n), .WAIT_n(WAIT_N), .INT_n(INT_N),
		.NMI_n(NMI_N), .BUSRQ_n(1'b1), .M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n),
		.RFSH_n(rfsh_n), .HALT_n(halt_n), .BUSAK_n(), .OUT0(1'b1), .A(cpu_a), .DI(cpu_di), .DO(cpu_do),
		.R800_mode(1'b0), .REG(), .DIRSet(1'b0), .DIR(212'd0), .WRITE_CYC(wr_cyc));

	assign M1_N_NX = m1_n;  assign RF_N_NX = rfsh_n; assign IO_N_NX = iorq_n;
	assign WR_N_NX = wr_n;  assign RD_N_NX = rd_n;   assign MR_N_NX = mreq_n;
	assign A_NX = cpu_a;
	always @(posedge CLK) if (CE) begin
		M1_N <= m1_n; RF_N <= rfsh_n; IO_N <= iorq_n; WR_N <= wr_n; RD_N <= rd_n; MR_N <= mreq_n; HALT_N <= halt_n;
		A <= cpu_a; D_O <= cpu_do; D_OE <= wr_cyc;
	end

	// ================= internal I/O decode (A[7:0], as the chip)
	wire       rst = ~RESET_N;
	wire [7:0] pa = A[7:0];
	wire sel_ctc = pa[7:2] == 6'b000100;             // 10-13
	wire sel_sio = pa[7:2] == 6'b000110;             // 18-1B
	wire sel_pio = pa[7:2] == 6'b000111;             // 1C-1F
	wire sel_scr = pa[7:1] == 7'b1110111;            // EE, EF
	wire sel_wdt = (pa == 8'hF0) | (pa == 8'hF1) | (pa == 8'hF4);
	wire io_cyc  = ~IO_N & M1_N;
	wire int_sel = io_cyc & (sel_ctc | sel_sio | sel_pio | sel_scr | sel_wdt);
	assign INT_RD = int_sel & ~RD_N;
	// events at CE: the end of the write (the rise of /WR) and of the read
	wire iowr = CE & io_cyc & ~WR_N & WR_N_NX;
	wire iord = CE & io_cyc & ~RD_N & RD_N_NX;

	// ================= SIO
	wire [7:0] sa_c, sa_d, sb_c, sb_d;
	sp_sio_ch SIOA (.CLK(CLK), .RESET(rst), .WR_C(iowr & sel_sio & (pa[1:0] == 2'd1)), .RD_C(iord & sel_sio & (pa[1:0] == 2'd1)),
		.RD_D(iord & sel_sio & (pa[1:0] == 2'd0)), .DI(D_O), .Q_C(sa_c), .Q_D(sa_d), .RX_D(RXA_D), .RX_STB(RXA_STB),
		.RX_RDY(RXA_RDY), .CTS(CTSA), .DCD(DCDA), .WR5(WR5A), .RX_EN());
	sp_sio_ch SIOB (.CLK(CLK), .RESET(rst), .WR_C(iowr & sel_sio & (pa[1:0] == 2'd3)), .RD_C(iord & sel_sio & (pa[1:0] == 2'd3)),
		.RD_D(iord & sel_sio & (pa[1:0] == 2'd2)), .DI(D_O), .Q_C(sb_c), .Q_D(sb_d), .RX_D(RXB_D), .RX_STB(RXB_STB),
		.RX_RDY(RXB_RDY), .CTS(CTSB), .DCD(DCDB), .WR5(WR5B), .RX_EN());

	// ================= CTC: channel 0; 1-3 take writes and read FF
	wire [7:0] ctc0;
	sp_ctc_ch CTC0 (.CLK(CLK), .RESET(rst), .SYS_CE(cen_p), .WR(iowr & sel_ctc & (pa[1:0] == 2'd0)), .DI(D_O),
		.TRG(TRG0), .Q(ctc0), .ZC(ZC0));

	// ================= PIO
	wire [7:0] pioa, piob;
	sp_pio_port PIOA (.CLK(CLK), .RESET(rst), .WR_D(iowr & sel_pio & (pa[1:0] == 2'd0)), .WR_C(iowr & sel_pio & (pa[1:0] == 2'd1)),
		.DI(D_O), .Q(pioa), .PI(PA_I), .PO(PA_O), .OE(PA_OE));
	sp_pio_port PIOB (.CLK(CLK), .RESET(rst), .WR_D(iowr & sel_pio & (pa[1:0] == 2'd2)), .WR_C(iowr & sel_pio & (pa[1:0] == 2'd3)),
		.DI(D_O), .Q(piob), .PI(PB_I), .PO(PB_O), .OE(PB_OE));

	// ================= SCRP / SCDP (z84c015.cpp: reset SCRP 00, WCR 00, MWBR F0, CSBR FF, MCR 01)
	reg [7:0] scrp = 8'd0, wcr = 8'd0, mwbr = 8'hF0;
	always @(posedge CLK) begin
		if (rst) begin
			scrp <= 8'd0; wcr <= 8'd0; mwbr <= 8'hF0; CSBR <= 8'hFF; MCR <= 8'h01;
		end else if (iowr & sel_scr) begin
			if (~pa[0]) scrp <= D_O;
			else case (scrp)
				8'd0: wcr <= D_O;
				8'd1: mwbr <= D_O;
				8'd2: CSBR <= D_O;
				8'd3: MCR <= D_O;
				default: ;
			endcase
		end
	end
	wire [7:0] scdp = (scrp == 8'd0) ? wcr : (scrp == 8'd1) ? mwbr : (scrp == 8'd2) ? CSBR : (scrp == 8'd3) ? MCR : 8'hFF;
	wire [3:0] at = A[15:12];
	assign CS0 = MCR[0] & (at <= CSBR[3:0]);
	assign CS1 = MCR[1] & (at <= CSBR[7:4]) & (at > CSBR[3:0]);

	// ================= read data
	reg [7:0] int_q;
	always @* begin
		int_q = 8'hFF;
		if (sel_ctc & (pa[1:0] == 2'd0)) int_q = ctc0;
		if (sel_sio) case (pa[1:0]) 2'd0: int_q = sa_d; 2'd1: int_q = sa_c; 2'd2: int_q = sb_d; default: int_q = sb_c; endcase
		if (sel_pio & (pa[1:0] == 2'd0)) int_q = pioa;
		if (sel_pio & (pa[1:0] == 2'd2)) int_q = piob;
		if (sel_scr) int_q = pa[0] ? scdp : scrp;
	end
	assign cpu_di = (~M1_N & ~IO_N) ? 8'hFF : int_sel ? int_q : D_I;
endmodule
