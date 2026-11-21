// Sprinter on the Karabas boards: the AT keyboard of the original from the PS/2 set 2 bytes of the MCU (kg_mcu2
// PS2_CODE with PS2_KIND = 0). The Sprinter reads the keyboard twice (docs/z84c15.md 1.2, 5): the ACEX KBD module
// (ZX matrix, Ctrl+Alt+Del, F12 turbo, INT) takes the lines KBD_CC / KBD_DD through the XA multiplexer, the software
// (SETUP, BIOS, DSS) polls the scan codes on SIO A of the Z84C15 (RxCA = CLK, RxDA = DATA, x1). So each byte is sent
// as an 11-bit AT frame on the lines (start 0, 8 data LSB first, odd parity, stop 1) and, at the end of the frame
// (when the ACEX KBD module takes it too), given to SIO A as a byte (RX_STB). Never waits for the SIO: with its
// FIFO full (software not reading, e.g. a ZX program) the byte overruns there as on the chip, and the ACEX lines
// (Ctrl+Alt+Del, F12, the ZX matrix) keep working. RX_RDY is not used.
//
// Frame timing (CLK = 84 MHz, BIT_T clocks a bit): data changes at the start of the bit, the clock is low from 1/5
// to 7/10 of the bit (the device side of PS/2: the host samples at the falling edge). 80 us a bit = 12.5 kHz.
// Gap between frames GAP_T: the ACEX frame logic (sp_kbd KB_CT) counts the line clock (64 us) while the PS/2 clock
// is high and handles the byte at counts 3 .. 0, i.e. 7 lines = 448 us after the stop bit; a new frame before that
// would be lost, so the gap is 1 ms. The clock high time in a frame (~40 us) stays below one line.
// 16-byte FIFO in front (a key is 1..8 bytes); a byte with the FIFO full is dropped (OVF).
// PS2_WR comes from the link clock (CLK / 3, aligned): edge-detected here.
module sp_kbd_tx #(
	parameter integer BIT_T = 6720,       // 80 us
	parameter integer GAP_T = 84000       // 1 ms
) (
	input            CLK,
	input            RESET,
	input            PS2_WR,
	input      [7:0] PS2_CODE,
	output reg       KBD_CC = 1'b1,
	output reg       KBD_DD = 1'b1,
	output reg [7:0] RX_D = 8'd0,         // SIO A byte stream
	output reg       RX_STB = 1'b0,
	input            RX_RDY,
	output reg       OVF = 1'b0
);
	reg       wr_p = 1'b0;
	wire      wr_ev = PS2_WR & ~wr_p;
	reg [7:0] fifo [0:15];
	reg [3:0] wp = 4'd0, rp = 4'd0;
	reg [4:0] n = 5'd0;

	localparam [1:0] S_IDLE = 2'd0, S_BIT = 2'd1, S_SIO = 2'd2, S_GAP = 2'd3;
	reg  [1:0] st = S_IDLE;
	reg [16:0] t = 17'd0;
	reg  [3:0] bn = 4'd0;
	reg [10:0] sh = 11'h7FF;
	reg  [7:0] cur = 8'd0;
	wire       take = (st == S_IDLE) & (n != 5'd0);
	always @(posedge CLK) begin
		wr_p <= PS2_WR;
		RX_STB <= 1'b0;
		if (wr_ev) begin
			if (n == 5'd16) OVF <= 1'b1;
			else begin fifo[wp] <= PS2_CODE; wp <= wp + 4'd1; end
		end
		n <= n + {4'd0, wr_ev & (n != 5'd16)} - {4'd0, take};
		case (st)
			S_IDLE: if (take) begin
				cur <= fifo[rp]; rp <= rp + 4'd1;
				sh  <= {1'b1, ~^fifo[rp], fifo[rp], 1'b0};
				bn  <= 4'd0; t <= 17'd0; st <= S_BIT;
			end
			S_BIT: begin
				t <= t + 17'd1;
				if (t == 17'd0) KBD_DD <= sh[0];
				if (t == BIT_T / 5) KBD_CC <= 1'b0;
				if (t == BIT_T * 7 / 10) KBD_CC <= 1'b1;
				if (t == BIT_T - 1) begin
					t <= 17'd0; sh <= {1'b1, sh[10:1]}; bn <= bn + 4'd1;
					if (bn == 4'd10) begin KBD_DD <= 1'b1; st <= S_SIO; end
				end
			end
			S_SIO: begin RX_D <= cur; RX_STB <= 1'b1; st <= S_GAP; end
			default: begin
				t <= t + 17'd1;
				if (t == GAP_T - 1) begin t <= 17'd0; st <= S_IDLE; end
			end
		endcase
		if (RESET) begin
			st <= S_IDLE; KBD_CC <= 1'b1; KBD_DD <= 1'b1; n <= 5'd0; wp <= 4'd0; rp <= 4'd0; t <= 17'd0;
		end
	end
endmodule
