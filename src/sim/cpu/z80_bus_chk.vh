// Z80 bus shape checker (included into a testbench): the pins of a CPU against the cycles of the behavioural Z80 of
// tb_eq_acex (m1cyc / mrd / mwr / ior / iow / inta / idle, src/sim/eq/tb_eq_acex.v), T state by T state.
// The testbench provides: clk, ce, ce_n, the Z80 clock zclk and its value after the next CE_N zclk_nx (valid at
// ce_n), the pins c_m1, c_mr, c_io, c_rd, c_wr, c_rf (active low) and c_a, the /WAIT line c_wait, and chk_on.
// 1. The pins change only at the CE right after a CE_N where zclk changed (one CLK after the Z80 clock edge).
// 2. A T state = (strobes active after its rise | after its fall), /WAIT taken at its falling edge (the value before
//    that CE_N, as the bus model's wsamp). The T states must form these cycles (W = the state repeats while /WAIT
//    was low at its fall):
//    M1   T1 (M1 | M1 MR RD), T2 (M1 MR RD | M1 MR RD) W, T3 (RF | MR RF), T4 (MR RF | RF)
//    INTA T1 (M1 | M1), T2 (M1 | M1), TW1 (M1 | M1 IO), TW2 (M1 IO | M1 IO) W, T3, T4 as in M1
//    MRD  T1 ( | MR RD), T2 (MR RD | MR RD) W, T3 (MR RD | )
//    MWR  T1 ( | MR), T2 (MR | MR WR) W, TW (MR WR | MR WR) W, T3 (MR WR | )
//    IOR  T1 ( | ), T2 (IO RD | IO RD), TW (IO RD | IO RD) W, T3 (IO RD | )        IOW: WR for RD
//    idle ( | )   (T1 of an I/O cycle looks the same)
// 3. The address changes only at a rise that starts a cycle (state idle) or at the rise of T3 of M1 / INTA.
	integer bc_err = 0, bc_n_m1 = 0, bc_n_mrd = 0, bc_n_mwr = 0, bc_n_ior = 0, bc_n_iow = 0, bc_n_inta = 0, bc_n_wait = 0;
	localparam [5:0] BC_M1 = 6'b100000, BC_MR = 6'b010000, BC_IO = 6'b001000, BC_RD = 6'b000100, BC_WR = 6'b000010,
		BC_RF = 6'b000001;
	localparam BS_IDLE = 0, BS_M1 = 1, BS_T3 = 2, BS_T4 = 3, BS_I2 = 4, BS_IW1 = 5, BS_IW2 = 6, BS_RD = 7, BS_RD3 = 8,
		BS_W2 = 9, BS_WW = 10, BS_W3 = 11, BS_IOW = 12, BS_IO3 = 13;
	wire [5:0] bc_act = ~{c_m1, c_mr, c_io, c_rd, c_wr, c_rf};
	reg  [5:0] bc_prev = 6'd0, bc_r = 6'd0, bc_iot = 6'd0;
	reg [15:0] bc_pa = 16'd0;
	reg        bc_zedge = 1'b0, bc_zrise = 1'b0, bc_wait_f = 1'b1;
	integer    bs = BS_IDLE;
	task bc_fail(input [8*16-1:0] m, input [5:0] r, input [5:0] f); begin
		if (bc_err < 10) $display("  bus: %0s at %0d ns (state %0d): T = (%b | %b) [M1 MR IO RD WR RF]", m, $time, bs, r, f);
		bc_err = bc_err + 1; bs = BS_IDLE;
	end endtask
	task bc_tstate(input [5:0] r, input [5:0] f, input w); begin
		if (w === 1'b0) bc_n_wait = bc_n_wait + 1;
		case (bs)
			BS_IDLE:
				if (r == BC_M1 && f == (BC_M1 | BC_MR | BC_RD)) bs = BS_M1;
				else if (r == BC_M1 && f == BC_M1) bs = BS_I2;
				else if (r == 6'd0 && f == (BC_MR | BC_RD)) bs = BS_RD;
				else if (r == 6'd0 && f == BC_MR) bs = BS_W2;
				else if (r == 6'd0 && f == 6'd0) ;
				else if ((r == (BC_IO | BC_RD) || r == (BC_IO | BC_WR)) && f == r) begin bs = BS_IOW; bc_iot = r; end
				else bc_fail("cycle start", r, f);
			BS_M1:  if (r == (BC_M1 | BC_MR | BC_RD) && f == r) begin if (w) begin bs = BS_T3; bc_n_m1 = bc_n_m1 + 1; end end
			        else bc_fail("M1 T2 / TW", r, f);
			BS_T3:  if (r == BC_RF && f == (BC_MR | BC_RF)) bs = BS_T4; else bc_fail("M1 T3", r, f);
			BS_T4:  if (r == (BC_MR | BC_RF) && f == BC_RF) bs = BS_IDLE; else bc_fail("M1 T4", r, f);
			BS_I2:  if (r == BC_M1 && f == BC_M1) bs = BS_IW1; else bc_fail("INTA T2", r, f);
			BS_IW1: if (r == BC_M1 && f == (BC_M1 | BC_IO)) bs = BS_IW2; else bc_fail("INTA TW1", r, f);
			BS_IW2: if (r == (BC_M1 | BC_IO) && f == r) begin if (w) begin bs = BS_T3; bc_n_inta = bc_n_inta + 1; end end
			        else bc_fail("INTA TW2", r, f);
			BS_RD:  if (r == (BC_MR | BC_RD) && f == r) begin if (w) bs = BS_RD3; end else bc_fail("MRD T2 / TW", r, f);
			BS_RD3: if (r == (BC_MR | BC_RD) && f == 6'd0) begin bs = BS_IDLE; bc_n_mrd = bc_n_mrd + 1; end
			        else bc_fail("MRD T3", r, f);
			BS_W2:  if (r == BC_MR && f == (BC_MR | BC_WR)) bs = w ? BS_W3 : BS_WW; else bc_fail("MWR T2", r, f);
			BS_WW:  if (r == (BC_MR | BC_WR) && f == r) begin if (w) bs = BS_W3; end else bc_fail("MWR TW", r, f);
			BS_W3:  if (r == (BC_MR | BC_WR) && f == 6'd0) begin bs = BS_IDLE; bc_n_mwr = bc_n_mwr + 1; end
			        else bc_fail("MWR T3", r, f);
			BS_IOW: if (r == bc_iot && f == r) begin if (w) bs = BS_IO3; end else bc_fail("IO TW", r, f);
			BS_IO3: if (r == bc_iot && f == 6'd0) begin
			            bs = BS_IDLE; if (bc_iot[1]) bc_n_iow = bc_n_iow + 1; else bc_n_ior = bc_n_ior + 1;
			        end else bc_fail("IO T3", r, f);
			default: bc_fail("state", r, f);
		endcase
	end endtask
	always @(posedge clk) begin
		if (ce_n) begin bc_zedge <= zclk !== zclk_nx; bc_zrise <= !zclk && zclk_nx; end
		if (ce_n && zclk && !zclk_nx) bc_wait_f <= c_wait;
	end
	always @(negedge clk) if (ce_n && chk_on) begin     // half a CLK after a CE edge: the pins of this CE
		if (bc_act != bc_prev && !bc_zedge) begin
			if (bc_err < 10) $display("  bus: pins changed at %0d ns without a Z80 clock edge before (%b -> %b)", $time, bc_prev, bc_act);
			bc_err = bc_err + 1;
		end
		if (bc_zedge && c_a !== bc_pa && !(bc_zrise && (bs == BS_IDLE || bs == BS_T3))) begin
			if (bc_err < 10) $display("  bus: address changed inside a cycle at %0d ns (%h -> %h, state %0d)", $time, bc_pa, c_a, bs);
			bc_err = bc_err + 1;
		end
		if (bc_zedge) begin
			if (bc_zrise) bc_r = bc_act;
			else bc_tstate(bc_r, bc_act, bc_wait_f);
		end
		bc_prev = bc_act; bc_pa = c_a;
	end
	task bc_report; begin
		$display("  bus shape: %0d errors; cycles M1 %0d, MRD %0d, MWR %0d, IOR %0d, IOW %0d, INTA %0d; T states with /WAIT low %0d",
			bc_err, bc_n_m1, bc_n_mrd, bc_n_mwr, bc_n_ior, bc_n_iow, bc_n_inta, bc_n_wait);
	end endtask
