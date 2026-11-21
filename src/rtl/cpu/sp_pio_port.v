// One port of the Z84C15 PIO (Z80 PIO), registers only (docs/z84c15.md 1.3: the software sets modes 0 / 3 and writes
// data; no handshake, no interrupts). Control words: xx001111 = mode (bits 7-6; mode 3 = the next byte is the
// direction mask, 1 = input), xxxx0111 = interrupt control (bit 4: the mask follows; taken and ignored), xxxx0011 =
// interrupt enable (ignored), xxxxxxx0 = vector (ignored). Reset: mode 1 (input), as the chip. Data read: mode 0 =
// the output register, 1 / 2 = the inputs, 3 = inputs on the input bits, the output register on the others.
// OE: which bits drive out (mode 0: all, mode 3: the output bits).
module sp_pio_port (
	input            CLK,
	input            RESET,
	input            WR_D,
	input            WR_C,
	input      [7:0] DI,
	output     [7:0] Q,
	input      [7:0] PI,
	output reg [7:0] PO = 8'd0,
	output     [7:0] OE
);
	reg [1:0] mode = 2'd1;
	reg [7:0] dir = 8'hFF;
	reg       exp_dir = 1'b0, exp_mask = 1'b0;

	assign Q  = (mode == 2'd0) ? PO : (mode == 2'd3) ? ((PI & dir) | (PO & ~dir)) : PI;
	assign OE = (mode == 2'd0) ? 8'hFF : (mode == 2'd3) ? ~dir : 8'h00;

	always @(posedge CLK) begin
		if (RESET) begin
			mode <= 2'd1; exp_dir <= 1'b0; exp_mask <= 1'b0;
		end else begin
			if (WR_D) PO <= DI;
			if (WR_C) begin
				if (exp_dir) begin dir <= DI; exp_dir <= 1'b0; end
				else if (exp_mask) exp_mask <= 1'b0;
				else if (DI[3:0] == 4'hF) begin mode <= DI[7:6]; exp_dir <= DI[7:6] == 2'd3; end
				else if (DI[3:0] == 4'h7) exp_mask <= DI[4];
			end
		end
	end
endmodule
