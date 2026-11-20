// Sprinter ACEX: Microsoft serial mouse receiver (MOUSE.TDF of the ACEX configuration 3.03a, the same in 2.18 / k30).
// Translated from the AHDL of Ivan Mak / Peters Plus, reconstruction of Tolik-Trek (github.com/Tolik-Trek/SP2000-ACEX).
//
// The whole module runs on the line clock CLK = DFF(CTH5) of the top (~15.6 kHz = 13 samples per 1200-baud bit):
// here every register updates at CE & CLK_EV, the CE where that clock rises. Rules: docs/translation.md.
module sp_mouse (
	input            CLK,
	input            CE,
	input            CLK_EV,     // the mouse clock (DFF(CTH5) of the top) rises at this CE
	input            MOUSE_D,    // serial data, 1200 baud 7N1, idle 1
	output     [9:0] OUT_X,
	output     [9:0] OUT_Y,
	output     [1:0] OUT_K,
	output           INT
);
	wire       ev = CE & CLK_EV;

	reg        md_q = 1'b0;                    // DFF(MOUSE_D, CLK)
	wire       imp = MOUSE_D ^ ~md_q;          // MOUSE_IMP = 0 right after an edge of the line: CT[].clrn
	reg  [3:0] ct_q = 4'd0;
	wire [3:0] ct_e = imp ? ct_q : 4'd0;

	reg  [9:0] rg_q = 10'd0;                   // RG[0] = start bit once a byte is in
	reg  [1:0] state_q = 2'd0;
	reg  [5:0] rgk_q = 6'd0;
	reg  [9:0] sum_x = 10'd0, sum_y = 10'd0;
	reg        int_q = 1'b0;

	wire [7:0] ddx = {rgk_q[1:0], rg_q[6:1]};
	wire [7:0] ddy = {rgk_q[3:2], rg_q[6:1]};

	always @(posedge CLK) if (ev) begin
		md_q <= MOUSE_D;
		ct_q <= ~imp ? 4'd0 : (ct_e == 4'd12) ? 4'd0 : ct_e + 4'd1;
		if ((ct_e == 4'd4) | ~rg_q[0])
			rg_q <= {MOUSE_D, rg_q[9:1]} | {10{~rg_q[0]}};
		if (~rg_q[0])
			state_q <= {state_q[0], rg_q[7]};
		if (rg_q[7] & ~rg_q[0])
			rgk_q <= rg_q[6:1];
		if (~rg_q[7] & (state_q == 2'd1) & ~rg_q[0])
			sum_x <= sum_x + {{2{ddx[7]}}, ddx};
		if (~rg_q[7] & (state_q == 2'd2) & ~rg_q[0])
			sum_y <= sum_y + {{2{ddy[7]}}, ddy};
		int_q <= (state_q == 2'd2) & ~rg_q[0];
	end

	assign OUT_X = sum_x;
	assign OUT_Y = sum_y;
	assign OUT_K = rgk_q[5:4];
	assign INT   = int_q;
endmodule
