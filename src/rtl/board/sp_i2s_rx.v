// Sprinter on the Karabas boards: the sound of the original, the I2S stream of the ACEX to its TDA1543 (AY + CBL,
// docs/ahdl.md 4.6: DAC_BCK = CT2 7 MHz, DAC_WS = CTH1, 16 bits a channel MSB first, 218.75 kHz), back into two
// 16-bit samples for the DAC of the board and HDMI. I2S framing as sp_acex makes it: WS changes at a falling BCK,
// the MSB is on DATA one BCK later, the data changes at the falling BCK (taken here at the rising one); the LSB of a
// word is the bit at the first rising BCK after WS changed. WS = 0: left. Two's complement (as the TDA1543 takes it).
// All in CLK (84 MHz, the domain of the ACEX outputs).
module sp_i2s_rx (
	input             CLK,
	input             BCK,
	input             WS,
	input             DATA,
	output reg [15:0] LEFT = 16'd0,
	output reg [15:0] RIGHT = 16'd0
);
	reg        bck_p = 1'b0, ws_p = 1'b0;
	reg [15:0] sh = 16'd0;
	always @(posedge CLK) begin
		bck_p <= BCK;
		if (BCK & ~bck_p) begin
			ws_p <= WS;
			sh <= {sh[14:0], DATA};
			if (WS != ws_p) begin
				if (ws_p) RIGHT <= {sh[14:0], DATA};
				else      LEFT  <= {sh[14:0], DATA};
			end
		end
	end
endmodule
