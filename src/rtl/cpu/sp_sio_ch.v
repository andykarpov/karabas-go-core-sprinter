// One channel of the Z84C15 SIO, the part the Sprinter software uses (docs/z84c15.md 1.2, 5): asynchronous
// receive only, fed by a byte stream (the line generators of the core give a byte at the end of its frame) instead of
// a receiver on RxD / RxC. A 3-byte receive FIFO, RR0 (Rx available, Tx empty, CTS / DCD as given), RR1 (overrun),
// RR2 (the vector register, channel B), WR0 pointer and the commands reset ext / status (2), channel reset (3) and
// error reset (6). WR1 .. WR7 are kept only as far as they matter: WR3 (Rx enable, bits per character), WR2, WR5
// (DTR / RTS bits, an output). Not made: Tx, interrupts and vectors, sync modes, CRC, parity / framing errors (a byte
// is taken whatever its parity, the software does not look). Chars of less than 8 bits: the bits above are 1
// (Zilog SIO / SCC behaviour as remembered, not checked on a chip; the software ignores bit 7 of the mouse bytes).
// The byte with an overrun: a byte coming with the FIFO full replaces the last one and sets the sticky overrun flag
// (RR1 bit 5) until an error reset. RX_RDY = the FIFO has room: a feed holds its byte while it is 0.
module sp_sio_ch (
	input            CLK,
	input            RESET,      // synchronous
	input            WR_C,       // control write (one CLK)
	input            RD_C,       // control read done (one CLK, at the end of the read cycle): pointer back to 0
	input            RD_D,       // data read done: the FIFO pops
	input      [7:0] DI,
	output     [7:0] Q_C,        // control read data (register by the pointer)
	output     [7:0] Q_D,        // data read data (the FIFO head)
	input      [7:0] RX_D,       // byte stream
	input            RX_STB,
	output           RX_RDY,
	input            CTS,        // RR0 bit 5 as the software reads it (1 = /CTS pin low)
	input            DCD,        // RR0 bit 3
	output reg [7:0] WR5 = 8'd0,
	output           RX_EN       // WR3 bit 0
);
	reg  [2:0] ptr = 3'd0;
	reg  [7:0] wr2 = 8'd0, wr3 = 8'd0;
	reg  [7:0] f0 = 8'hFF, f1 = 8'hFF, f2 = 8'hFF;
	reg  [1:0] cnt = 2'd0;
	reg        ovr = 1'b0;

	assign RX_EN  = wr3[0];
	assign RX_RDY = cnt != 2'd3;
	// bits per character (WR3[7:6]): 00 = 5, 10 = 6, 01 = 7, 11 = 8
	wire [7:0] cmask = (wr3[7:6] == 2'b11) ? 8'h00 : (wr3[7:6] == 2'b01) ? 8'h80 : (wr3[7:6] == 2'b10) ? 8'hC0 : 8'hE0;
	wire [7:0] rx_c  = RX_D | cmask;

	wire [7:0] rr0 = {1'b0, 1'b1, CTS, 1'b0, DCD, 1'b1, 1'b0, cnt != 2'd0};
	wire [7:0] rr1 = {2'b00, ovr, 4'b0000, 1'b1};
	assign Q_C = (ptr[1:0] == 2'd1) ? rr1 : (ptr[1:0] == 2'd2) ? wr2 : rr0;
	assign Q_D = f0;

	wire push = RX_STB & wr3[0];
	wire pop  = RD_D & (cnt != 2'd0);

	always @(posedge CLK) begin
		if (RESET) begin
			ptr <= 3'd0; wr2 <= 8'd0; wr3 <= 8'd0; WR5 <= 8'd0; cnt <= 2'd0; ovr <= 1'b0;
		end else begin
			// FIFO
			if (pop & push) begin
				f0 <= (cnt == 2'd1) ? rx_c : f1; f1 <= (cnt == 2'd2) ? rx_c : f2; f2 <= rx_c;
			end else if (pop) begin
				f0 <= f1; f1 <= f2; cnt <= cnt - 2'd1;
			end else if (push) begin
				case (cnt)
					2'd0: f0 <= rx_c;
					2'd1: f1 <= rx_c;
					default: f2 <= rx_c;        // 2: the third; 3: overrun, the last one replaced
				endcase
				if (cnt != 2'd3) cnt <= cnt + 2'd1; else ovr <= 1'b1;
			end
			// registers
			if (WR_C) begin
				if (ptr == 3'd0) begin
					ptr <= DI[2:0];
					case (DI[5:3])
						3'd3: begin               // channel reset
							wr3 <= 8'd0; WR5 <= 8'd0; cnt <= 2'd0; ovr <= 1'b0;
						end
						3'd6: ovr <= 1'b0;          // error reset
						default: ;                  // null, reset ext / status (RR0 follows its inputs), the rest
					endcase
				end else begin
					ptr <= 3'd0;
					case (ptr)
						3'd2: wr2 <= DI;
						3'd3: wr3 <= DI;
						3'd5: WR5 <= DI;
						default: ;
					endcase
				end
			end
			if (RD_C) ptr <= 3'd0;
		end
	end
endmodule
