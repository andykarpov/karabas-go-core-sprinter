// Sprinter on the Karabas boards: the Microsoft serial mouse of the original from the USB mouse of the MCU (kg_mcu2
// MS_X / MS_Y signed deltas, MS_B buttons, MS_WR). Read twice, as the keyboard (docs/z84c15.md 1.2, 5): the ACEX
// MOUSE module (sp_mouse) takes the line MOUSE_D through the XA multiplexer, the DSS driver polls SIO B of the
// Z84C15 (7 bits). Each packet (3 bytes: 1 L R Y7 Y6 X7 X6 / 0 X5..X0 / 0 Y5..Y0, Y positive = down as USB) goes
// out on MOUSE_D at 1200 baud, start 0, 7 data LSB first, two stop bits (fits 7N1 of the BIOS and 7E1 of DSS), and
// every byte at the end of its frame into SIO B (RX_STB; never waits: a full SIO FIFO overruns as on the chip, the
// ACEX line keeps going; RX_RDY is not used).
// The deltas are summed between packets (saturated at +-511) and sent in steps of at most +-127; a packet goes when
// the sum is not 0 or the buttons changed. MS_WR comes from the link clock (CLK / 3, aligned): edge-detected.
module sp_ms_tx #(
	parameter integer BIT_T = 70000       // 1200 baud at 84 MHz
) (
	input            CLK,
	input            RESET,
	input            MS_WR,
	input      [7:0] MS_X,
	input      [7:0] MS_Y,
	input      [2:0] MS_B,                // [0] left, [1] right
	output reg       MOUSE_D = 1'b1,
	output reg [7:0] RX_D = 8'd0,         // SIO B byte stream
	output reg       RX_STB = 1'b0,
	input            RX_RDY
);
	reg        wr_p = 1'b0;
	wire       wr_ev = MS_WR & ~wr_p;
	reg  signed [9:0] ax = 10'sd0, ay = 10'sd0;
	reg  [1:0] bt = 2'b00, bs = 2'b00;      // buttons now / sent

	function signed [9:0] sat10(input signed [10:0] v);
		sat10 = (v > 11'sd511) ? 10'sd511 : (v < -11'sd511) ? -10'sd511 : v[9:0];
	endfunction
	function signed [7:0] step8(input signed [9:0] v);
		step8 = (v > 10'sd127) ? 8'sd127 : (v < -10'sd127) ? -8'sd127 : v[7:0];
	endfunction

	localparam [1:0] S_IDLE = 2'd0, S_BIT = 2'd1, S_SIO = 2'd2;
	reg  [1:0] st = S_IDLE;
	reg [16:0] t = 17'd0;
	reg  [3:0] bn = 4'd0;
	reg  [1:0] by = 2'd0;                  // byte of the packet
	reg  [9:0] sh = 10'h3FF;
	reg [20:0] pk = 21'd0;                 // the packet: bytes 3, 2, 1 (7 bits each)
	wire signed [7:0] px = step8(ax), py = step8(ay);
	wire       go = (st == S_IDLE) & ((ax != 10'sd0) | (ay != 10'sd0) | (bt != bs));
	wire signed [10:0] ax_n = $signed({ax[9], ax}) + (wr_ev ? $signed({{3{MS_X[7]}}, MS_X}) : 11'sd0) -
	                          (go ? $signed({{3{px[7]}}, px}) : 11'sd0);
	wire signed [10:0] ay_n = $signed({ay[9], ay}) + (wr_ev ? $signed({{3{MS_Y[7]}}, MS_Y}) : 11'sd0) -
	                          (go ? $signed({{3{py[7]}}, py}) : 11'sd0);
	always @(posedge CLK) begin
		wr_p <= MS_WR;
		RX_STB <= 1'b0;
		ax <= sat10(ax_n);
		ay <= sat10(ay_n);
		if (wr_ev) bt <= MS_B[1:0];
		case (st)
			S_IDLE: if (go) begin
				bs <= bt;
				pk <= {1'b0, py[5:0], 1'b0, px[5:0], 1'b1, bt[0], bt[1], py[7:6], px[7:6]};
				sh <= {2'b11, 1'b1, bt[0], bt[1], py[7:6], px[7:6], 1'b0};
				by <= 2'd0; bn <= 4'd0; t <= 17'd0; st <= S_BIT;
			end
			S_BIT: begin
				t <= t + 17'd1;
				if (t == 17'd0) MOUSE_D <= sh[0];
				if (t == BIT_T - 1) begin
					t <= 17'd0; sh <= {1'b1, sh[9:1]}; bn <= bn + 4'd1;
					if (bn == 4'd9) st <= S_SIO;
				end
			end
			default: begin
				RX_D <= {1'b0, pk[6:0]}; RX_STB <= 1'b1;
				pk <= {7'd0, pk[20:7]};
				sh <= {2'b11, pk[13:7], 1'b0};
				bn <= 4'd0; t <= 17'd0;
				by <= by + 2'd1;
				st <= (by == 2'd2) ? S_IDLE : S_BIT;
			end
		endcase
		if (RESET) begin
			st <= S_IDLE; MOUSE_D <= 1'b1; ax <= 10'sd0; ay <= 10'sd0; bt <= 2'b00; bs <= 2'b00; t <= 17'd0;
		end
	end
endmodule
