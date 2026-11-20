// Sprinter ACEX: AT keyboard -> ZX keyboard matrix (KBD.TDF of the ACEX configuration 3.03a, the same in 2.18 / k30).
// Translated from the AHDL of Ivan Mak / Peters Plus, reconstruction of Tolik-Trek (github.com/Tolik-Trek/SP2000-ACEX).
//
// One clock CLK with the enable CE = a rising edge of the original 42 MHz (CLK42). How the AHDL maps here:
// - DFF on CLK42                  -> register updated when CE.
// - DFF clocked by another signal -> an event: the source's rising edge, seen at the CE where the source register
//                                    changes (its next value is known before the edge), so the order of the original
//                                    ripple is kept; an external clock (CLK_K) is seen one CE later.
// - asynchronous clrn / prn       -> the effective value *_e (forced while active); at a CE where it is active the
//                                    register takes the forced value (the preset / clear wins over the clock edge).
//                                    AHDL: DFF(d, clk, clrn, prn), DFFE(d, clk, clrn, prn, ena) — mind the order.
// - lpm_ram_dq with inclock CLK42, outdata UNREGISTERED -> block RAM with a registered address (= synchronous read),
//                                    write-first (the EAB output follows the written word at the latched address).
// Inputs are synchronous to CLK. Signal names follow KBD.TDF.
module sp_kbd (
	input            CLK,
	input            CE,
	input            CLK_K,      // ~15 kHz from the line counter: timeout of a PS/2 frame
	input            KBD_CC,     // PS/2 clock
	input            KBD_DD,     // PS/2 data
	input            RF_N,       // /RFSH
	input            IO_N,       // /IORQ
	input      [7:0] A,          // A[15:8]
	input            ENA,        // ZX keyboard read enabled
	input            INT_ENA,
	output     [7:0] KBO,
	output           KB_RESET,   // active low: Ctrl+Alt+Del
	output           KB_F12,
	output           KB_CTRL,
	output           KB_ALT,
	output           KB_SH,
	output           INT
);
	parameter MIF_HEX = "kbd_ini2.hex";

	// ---- frame timeout counter KB_CT: decrements on CLK_K, preset to 7 while the (registered) PS/2 clock is low
	reg        cc_q = 1'b0;               // DFF(KBD_CC, CLK42): KB_CT[].prn
	reg        clk_k_q = 1'b0;
	reg  [2:0] ct_q = 3'd0;
	wire [2:0] ct_e = cc_q ? ct_q : 3'd7;
	wire       k_rise = CLK_K & ~clk_k_q;
	wire [2:0] ct_dec = (ct_e == 3'd0) ? 3'd0 : ct_e - 3'd1;
	wire [2:0] ct_r = ~cc_q ? 3'd7 : (k_rise ? ct_dec : ct_q);     // register after this CE
	wire [2:0] ct_n = ~KBD_CC ? 3'd7 : ct_r;                        // KB_CT (effective) after this CE
	wire       ct2_fall = ct_e[2] & ~ct_n[2];                      // clock of KB_CTRL / ALT / SH / F12 / RESET

	// ---- PS/2 shift register: clocked by DFF(!KBD_CC) rising
	reg        nc_q = 1'b0, nc_p = 1'b0;
	reg [10:0] d_q = 11'd0;               // KB_D[10..0]: [0] start, [8:1] data, [9] parity, [10] stop

	// pattern matches of KB_D (AHDL B"..." strings, bit 10 first)
	wire d_f0   = d_q[8:1] == 8'hF0;                                          // XX11110000X
	wire d_e0   = d_q[8:1] == 8'hE0;                                          // XX11100000X
	wire ctrl_x = d_q[5] & d_q[3] & ~d_q[2] & ~d_q[1];                        // XXXXX1X100X
	wire alt_x  = d_q[5] & ~d_q[3] & ~d_q[2] & d_q[1];                        // XXXXX1X001X
	wire sh_x   = ~d_q[8] & ~d_q[6] & d_q[5] & ~d_q[3] &                      // XX0X01X0XXX
	              ((d_q[7] & d_q[4] & ~d_q[2] & d_q[1]) | (~d_q[7] & ~d_q[4] & d_q[2] & ~d_q[1]));
	wire xxx    = ~d_q[8] & ~d_q[7] & ~d_q[6] & ~d_q[4];                      // XX000X0XXXX
	wire f12_x  = ~d_q[5] & d_q[3] & d_q[2] & d_q[1];                         // XXXXX0X111X
	wire del_x  = ~d_q[8] & d_q[7] & d_q[6] & ~d_q[4];                        // XX011X0XXXX

	// ---- KB_OFF (break F0), KB_EXT (E0): clocked by DFF(KB_CT == 0) / DFF(KB_CT == 1) rising
	reg ct0_q = 1'b0, ct1_q = 1'b0;
	reg off_q = 1'b0, ext_q = 1'b0;

	// ---- modifiers, F12, reset: clocked by !KB_CT2 rising
	reg ctrl_q = 1'b0, alt_q = 1'b0, sh_q = 1'b0;
	reg f12_q = 1'b0;                     // prn = !(KB_CT == 1)
	reg rst_q = 1'b0;                     // prn  = !DFF(KB_CT == 1)
	wire f12_e = (ct_e == 3'd1) ? 1'b1 : f12_q;
	wire rst_e = ct1_q ? 1'b1 : rst_q;

	// ---- refresh sequencer RXA: clocked by K_CLK = DFF(/RF) rising; 00 -> 01 -> 11 -> 10 -> 00
	reg       kclk_q = 1'b0;
	reg [1:0] rxa_q = 2'd0;
	reg       g_q = 1'b0;                 // DFF(!(KB_CT == B"01X") & (RXA == 0))
	wire      kclk_rise = RF_N & ~kclk_q;
	wire [1:0] rxa_n = kclk_rise ? (g_q ? 2'd0 : {rxa_q[0], ~rxa_q[1]}) : rxa_q;
	wire      rxa0_rise = ~rxa_q[0] & rxa_n[0];
	wire      rxa1_rise = ~rxa_q[1] & rxa_n[1];

	// ---- port read: row counter KB_MA during an I/O cycle
	reg        iod_q = 1'b0;              // DFF(/IO): KB_MA[].clrn
	reg        io0_q = 1'b0;              // DFF(/IO & (RXA == 0))
	reg  [2:0] ma_q = 3'd0;
	wire [2:0] ma_e = iod_q ? 3'd0 : ma_q;
	wire [2:0] ma_r = iod_q ? 3'd0 : ma_e + 3'd1;      // clear active before the edge wins
	wire [2:0] ma_n = IO_N ? 3'd0 : ma_r;              // effective after this CE (DFF(/IO) = IO_N)
	reg        mxa_q = 1'b0;

	reg  [7:0] kdd_q = 8'd0;              // KDD[7..6].prn = !KB_CT2
	wire [7:0] kdd_e = {ct_e[2] ? 2'b11 : kdd_q[7:6], kdd_q[5:0]};
	reg  [5:0] kdxx_q = 6'd0, kdx_q = 6'd0;
	reg        ct2d_q = 1'b0;             // DFF(KB_CT == 2)

	wire [2:0] kdca = iod_q ? kdd_e[5:3] : ma_e;
	reg  [7:0] ka;
	always @* begin
		if (!io0_q)                    ka = {3'b101, kdca, 2'b11};
		else if (!(kdd_e[7] & kdd_e[6])) ka = {6'b110000, kdd_e[7], kdd_e[6]};
		else                           ka = d_q[8:1];
	end

	// ---- the table: scan code -> matrix position, and the matrix rows (256 x 8, KBD_INI2.MIF)
	reg  [7:0] mem [0:255];
	reg  [7:0] kd = 8'hFF;
	initial $readmemh(MIF_HEX, mem);
	wire wr_kbd_n = kclk_q | ~ct2d_q | ~(rxa_q == 2'd3);

	// ---- matrix read: KBD[] accumulates the selected rows, preset while P = 0
	reg        p_q = 1'b0;                // DFF(VCC, KB_MA2, clrn = !/IO & ENA)
	wire       p_e = (~IO_N & ENA) ? p_q : 1'b0;
	wire       ma2_rise = ~ma_e[2] & ma_n[2];
	reg  [5:0] kbd_q = 6'h00;
	wire [5:0] kbd_e = p_e ? kbd_q : 6'h3F;

	reg        int_q = 1'b0;

	always @(posedge CLK) if (CE) begin
		cc_q    <= KBD_CC;
		clk_k_q <= CLK_K;
		ct_q    <= ct_r;

		nc_q <= ~KBD_CC;
		nc_p <= nc_q;
		if (nc_q & ~nc_p)
			d_q <= {KBD_DD, d_q[10:1]};

		ct0_q <= ct_e == 3'd0;
		ct1_q <= ct_e == 3'd1;
		if (~ct0_q & (ct_e == 3'd0) & ~ext_q)
			off_q <= d_f0;
		if (~ct1_q & (ct_e == 3'd1))
			ext_q <= d_e0;

		if (ct2_fall) begin
			ctrl_q <= off_q ? ~(ctrl_x & xxx) & ctrl_q : (ctrl_x & xxx) | ctrl_q;
			alt_q  <= off_q ? ~(alt_x & xxx) & alt_q   : (alt_x & xxx) | alt_q;
			sh_q   <= off_q ? ~sh_x & sh_q             : sh_x | sh_q;
			f12_q  <= ~((xxx & f12_x) & ~off_q);
			rst_q  <= ~(alt_x & del_x & ~off_q & ctrl_q & alt_q);
		end else begin
			f12_q <= f12_e;
			rst_q <= rst_e;
		end

		kclk_q <= RF_N;
		g_q    <= ~(ct_e[2:1] == 2'b01) & (rxa_q == 2'd0);
		rxa_q  <= rxa_n;

		iod_q <= IO_N;
		io0_q <= IO_N & (rxa_q == 2'd0);
		ma_q  <= ma_r;
		case (ma_e)
			3'd7: mxa_q <= A[7]; 3'd6: mxa_q <= A[6]; 3'd5: mxa_q <= A[5]; 3'd4: mxa_q <= A[4];
			3'd3: mxa_q <= A[3]; 3'd2: mxa_q <= A[2]; 3'd1: mxa_q <= A[1]; default: mxa_q <= A[0];
		endcase

		kdd_q <= rxa0_rise ? {ct_e[2] ? 2'b11 : kd[7:6], kd[5:0]} : kdd_e;
		if (rxa0_rise)
			kdxx_q <= ~{kd[2:0] == 3'd5, kd[2:0] == 3'd4, kd[2:0] == 3'd3, kd[2:0] == 3'd2, kd[2:0] == 3'd1, kd[2:0] == 3'd0};
		if (rxa1_rise)
			kdx_q <= off_q ? (kd[5:0] | ~kdxx_q) : (kd[5:0] & kdxx_q);
		ct2d_q <= ct_e == 3'd2;

		if (!wr_kbd_n) begin
			mem[ka] <= {2'b11, kdx_q};
			kd      <= {2'b11, kdx_q};
		end else
			kd <= mem[ka];

		p_q   <= (ma2_rise & ~IO_N & ENA) ? 1'b1 : p_e;
		kbd_q <= p_e ? kbd_q & (kd[5:0] | {6{mxa_q}}) : 6'h3F;

		int_q <= INT_ENA ? ct_e == 3'd0 : 1'b1;   // DFF(KB_CT == 0, CLK42, , INT_ENA): prn
	end

	assign KBO      = {2'b11, kbd_e};
	assign KB_RESET = rst_e;
	assign KB_F12   = f12_e;
	assign KB_CTRL  = ctrl_q;
	assign KB_ALT   = alt_q;
	assign KB_SH    = sh_q;
	assign INT      = INT_ENA ? int_q : 1'b1;
endmodule
