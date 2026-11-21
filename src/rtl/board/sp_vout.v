// Sprinter on the Karabas boards: the video output. The original has no RGB pins on the ACEX: the palette word read
// from the video RAM in the palette slots is caught by the latch of the RGB DAC at the rise of WR_COL (docs/ahdl.md
// 3.2; here the word is PAL_Q of the sp_sram palette shadow, stable over that rise; tb_mem.vh checks it against the
// reference bus there). WR_COL rises twice a 7 MHz cycle, evenly: a dot of 14 MHz, 896 a line (64 us), 312 / 320
// lines (T320 of the MAX). The syncs of the monitor come from the MAX (SINC_H 64 dots, SINC_V 4 lines); the picture
// position against them is set by the software (HOLD, port CB), so this module follows the syncs, not the ACEX.
//
// Palette word -> colour: MAME (sprinter.cpp vram_w) has R, G, B at byte offsets 0, 1, 2 of the 4-byte entry; byte
// offset 0 (VXA[1:0] = 00) is lane 3 of the video RAM word (V_WR[3], sp_video2 v_en_d), so R = PAL_Q[31:24],
// G = [23:16], B = [15:8] (8 bits each, the DAC width of the original not checked: docs/ahdl.md 6 question 8).
//
// Write side (CLK = 84 MHz): dot x counts the WR_COL rises from the SINC_H rise (x 0..63 = the sync), line v the
// SINC_H rises from the SINC_V rise (v 0..3 = the sync); each line into one half of a 2 x 1024 x 24 buffer.
// Read side (CLK28 = CLK / 3 of the same PLL, aligned: 1792 clocks a line exactly): each finished line read twice,
// one dot a clock (line doubler), 896 x 624 / 640 at 28 MHz = 50.1 / 48.8 Hz. The line start crosses as a toggle.
// Output window (DE): dots H0 .. H0+719, lines V0 .. V0+287 (720 x 576); HSYNC = dots 0..63, VSYNC = output lines
// of v 0..3, positive (as kg_hdmi_ft takes them). The window: set from the board (26112101: BIOS text from dot ~221 / line ~48);
// H0 = 176 is the latest a 720-dot window can start in the 896-dot line.
// ON = 0 (the ACEX empty, the configuration loading): black.
module sp_vout #(
	parameter [9:0] H0 = 10'd176,     // board 26112101 with 120: the BIOS / SETUP picture started at dot ~221, right edge cut
	parameter [8:0] V0 = 9'd24        // and at line ~48 (V0 = 14); the software moves it further (HOLD, SETUP X / Y position)
) (
	input             CLK,
	input             WR_COL,
	input      [31:0] PAL_Q,
	input             SINC_H,
	input             SINC_V,
	input             ON,
	input             CLK28,
	output reg  [7:0] R = 8'd0,
	output reg  [7:0] G = 8'd0,
	output reg  [7:0] B = 8'd0,
	output reg        HS = 1'b0,
	output reg        VS = 1'b0,
	output reg        DE = 1'b0
);
	// ================= write side
	reg        wcol_p = 1'b0, sh_p = 1'b0, sv_p = 1'b0;
	reg  [9:0] x = 10'd1023;
	reg  [8:0] v = 9'd0;
	reg        wbank = 1'b0;
	reg        ltog = 1'b0;
	reg  [8:0] rd_line = 9'd0;      // the line just finished and its half of the buffer (for the read side)
	reg        rd_bank = 1'b0;
	reg        on_r = 1'b0;
	wire       h_rise = SINC_H & ~sh_p;
	wire       px = WR_COL & ~wcol_p;
	wire [9:0] wx = h_rise ? 10'd0 : x;
	reg [23:0] lbuf [0:2047];
	always @(posedge CLK) begin
		wcol_p <= WR_COL;
		sh_p <= SINC_H;
		on_r <= ON;
		if (px & (wx < 10'd896))
			lbuf[{wbank ^ h_rise, wx}] <= on_r ? PAL_Q[31:8] : 24'd0;
		if (h_rise) begin
			x <= px ? 10'd1 : 10'd0;
			wbank <= ~wbank;
			ltog <= ~ltog;
			rd_line <= v;
			rd_bank <= wbank;
			sv_p <= SINC_V;
			v <= (SINC_V & ~sv_p) ? 9'd0 : (v == 9'd511) ? v : v + 9'd1;
		end else if (px & (x != 10'd1023))
			x <= x + 10'd1;
	end

	// ================= read side (CLK28)
	reg        lt_r = 1'b0, lt_rr = 1'b0;
	reg  [9:0] ox = 10'd0;
	reg        half = 1'b0;
	reg  [8:0] lr = 9'd0;
	reg        rb = 1'b0;
	reg        on28 = 1'b0;
	always @(posedge CLK28) begin
		lt_r <= ltog;
		lt_rr <= lt_r;
		on28 <= on_r;
		if (lt_r ^ lt_rr) begin
			ox <= 10'd0; half <= 1'b0; lr <= rd_line; rb <= rd_bank;
		end else if (ox == 10'd895) begin
			ox <= 10'd0; half <= 1'b1;
		end else
			ox <= ox + 10'd1;
	end
	reg [23:0] q = 24'd0;
	reg        de0 = 1'b0, hs0 = 1'b0, vs0 = 1'b0;
	always @(posedge CLK28) begin
		q   <= lbuf[{rb, ox}];
		de0 <= (ox >= H0) & (ox < H0 + 10'd720) & (lr >= V0) & (lr < V0 + 9'd288);
		hs0 <= ox < 10'd64;
		vs0 <= lr < 9'd4;
		R   <= (de0 & on28) ? q[23:16] : 8'd0;
		G   <= (de0 & on28) ? q[15:8] : 8'd0;
		B   <= (de0 & on28) ? q[7:0] : 8'd0;
		DE  <= de0;
		HS  <= hs0;
		VS  <= vs0;
	end
endmodule
