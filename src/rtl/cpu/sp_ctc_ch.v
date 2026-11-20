// One channel of the Z84C15 CTC (Z80 CTC), without interrupts (docs/z84c15.md 1.1: CTC0 = counter 55 / 2D for the
// x16 clock of SIO B; nobody enables a CTC interrupt or writes a vector).
// Control word (bit 0 = 1): 7 interrupt enable (kept, no interrupt made), 6 mode (1 counter, 0 timer), 5 prescaler
// (1 = 256, 0 = 16), 4 edge (1 rising), 3 timer trigger (1 = start at a CLK/TRG edge), 2 time constant follows,
// 1 software reset. A word with bit 0 = 0 is the vector (channel 0 only on the chip): ignored.
// Counter mode: every active edge of TRG decrements; timer mode: every 16 / 256 ticks of the system clock (SYS_CE,
// the Z80 clock). At 1 -> reload from the time constant and a ZC/TO pulse (constant 0 = 256). A new constant
// without a reset takes effect at the next reload. Read = the down counter.
// TRG is a level sampled on CLK (the source is synchronous in the core: the MAX CT3, 875 kHz).
module sp_ctc_ch (
	input            CLK,
	input            RESET,      // synchronous (the chip: /RESET stops the channels)
	input            SYS_CE,     // the system clock of the CTC (one CLK per Z80 clock)
	input            WR,         // write strobe (one CLK)
	input      [7:0] DI,
	input            TRG,
	output     [7:0] Q,
	output reg       ZC = 1'b0   // one CLK pulse
);
	reg  [7:0] ctrl = 8'd0, tc = 8'd0, cnt = 8'd0, pre = 8'd0;
	reg        wait_tc = 1'b0, run = 1'b0, armed = 1'b0;   // armed: timer waits for its trigger edge
	reg        trg_q = 1'b0;

	assign Q = cnt;
	wire edge_ = ctrl[4] ? (TRG & ~trg_q) : (~TRG & trg_q);
	wire pre_end = ctrl[5] ? (pre == 8'hFF) : (pre[3:0] == 4'hF);
	wire tick = run & (ctrl[6] ? edge_ : (SYS_CE & pre_end));

	always @(posedge CLK) begin
		trg_q <= TRG;
		ZC <= 1'b0;
		if (RESET) begin
			ctrl <= 8'd0; wait_tc <= 1'b0; run <= 1'b0; armed <= 1'b0; pre <= 8'd0;
		end else begin
			if (run & ~ctrl[6] & SYS_CE) pre <= pre + 8'd1;
			if (armed & edge_) begin armed <= 1'b0; run <= 1'b1; pre <= 8'd0; end
			if (tick) begin
				if (cnt == 8'd1) begin cnt <= tc; ZC <= 1'b1; end
				else cnt <= cnt - 8'd1;
			end
			if (WR) begin
				if (wait_tc) begin
					wait_tc <= 1'b0; tc <= DI;
					if (~run) begin
						cnt <= DI; pre <= 8'd0;
						if (ctrl[6] | ~ctrl[3]) run <= 1'b1; else armed <= 1'b1;
					end
				end else if (DI[0]) begin
					ctrl <= DI; wait_tc <= DI[2];
					if (DI[1]) begin run <= 1'b0; armed <= 1'b0; end
				end
			end
		end
	end
endmodule
