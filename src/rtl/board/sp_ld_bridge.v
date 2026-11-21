// Sprinter on the Karabas boards: the ROM bytes of the MCU loader (kg_mcu2 LD_*, kind 0, in the 28 MHz clock of the
// link) into the loader port of sp_sram (84 MHz). The BIOS image (256 KB, core.json "roms" address 0) goes to the
// ROM region of the SRAM: byte b -> word ROM_BASE + b[17:1], lane b[0] (0 = D[7:0]), as sp_sram reads it.
//
// Clocks: CLK = 84 MHz, the link clock is CLK / 3 from the same PLL (edges aligned), so LD_WR (one link clock = 3 CLK)
// is edge-detected here and LD_ADDR / LD_DATA (registers of the link, held until the next byte, >= 250 ns) are taken
// at that edge. A byte every 250 ns at most; sp_sram takes one in a free slot (<= 12 CLK while the machine is held
// in reset, the case of the boot); the 16-entry FIFO covers the slower slots of a running machine.
// BUSY: bytes still on the way (the top holds the machine in reset until it is low).
module sp_ld_bridge #(
	parameter [20:0] ROM_BASE = 21'h040000
) (
	input             CLK,
	input             LD_WR,          // kg_mcu2 (link clock): one clock per byte
	input             LD_ROM,         // the byte is a ROM byte (LD_KIND = 0 and LD_ACTIVE)
	input      [17:0] LD_ADDR,        // byte address in the ROM (256 KB)
	input       [7:0] LD_DATA,
	output reg        REQ = 1'b0,     // sp_sram LD_*
	output reg [20:0] A = 21'd0,
	output reg  [1:0] BE = 2'b00,
	output reg [15:0] D = 16'd0,
	input             ACK,
	output            BUSY,
	output reg        OVF = 1'b0      // a byte came with the FIFO full (sticky; should never happen)
);
	reg        wr_p = 1'b0;
	wire       wr_ev = LD_WR & ~wr_p & LD_ROM;
	reg [25:0] fifo [0:15];
	reg  [3:0] wp = 4'd0, rp = 4'd0;
	reg  [4:0] n = 5'd0;
	wire       pop = ~REQ & (n != 5'd0);
	always @(posedge CLK) begin
		wr_p <= LD_WR;
		if (wr_ev) begin
			if (n == 5'd16) OVF <= 1'b1;
			else begin fifo[wp] <= {LD_ADDR, LD_DATA}; wp <= wp + 4'd1; end
		end
		if (ACK) REQ <= 1'b0;
		else if (pop) begin
			REQ <= 1'b1;
			A   <= ROM_BASE + {4'd0, fifo[rp][25:9]};
			BE  <= fifo[rp][8] ? 2'b10 : 2'b01;
			D   <= {fifo[rp][7:0], fifo[rp][7:0]};
			rp  <= rp + 4'd1;
		end
		n <= n + {4'd0, wr_ev & (n != 5'd16)} - {4'd0, pop & ~ACK};
	end
	assign BUSY = REQ | (n != 5'd0);
endmodule
