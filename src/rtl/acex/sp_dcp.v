// Sprinter ACEX: port / memory dispatcher DCP (DCP.TDF of the ACEX configuration 3.03a, UPDATE = 1): the port decoder
// table MEM 256x16 (DCP.MIF), the page / config registers, the DRAM cycle (RAS / CAS / MA phases), the Z80 clock,
// the wait states. Translated from the AHDL of Ivan Mak / Peters Plus, reconstruction of Tolik-Trek
// (github.com/Tolik-Trek/SP2000-ACEX). Rules: docs/translation.md.
//
// CLK = 84 MHz; CE = the rising edge of the original CLK42, CE_N = its falling edge (CLK_Z80, MC_RQ, PGS, RD_KP11
// are !CLK42 registers in the AHDL). CE and CE_N alternate.
// Inputs are synchronous to CLK. The Z80 strobes (/IO /RD /WR /MR /RF /M1), A and DI must change only right after a
// CE edge (a Z80 output delay of half a CLK42 cycle after the CLK_Z80 edge); the AHDL uses some strobes as clocks,
// so the *_EV inputs say at which CE the strobe edge happens (computed by the top from the value the strobe
// registers are about to take):
//   IOWR_EV    /IOWR = /IO | /WR | !/M1 rises (end of an OUT): clock of PN, SC, SYS, CNF, AROM16, TB_SW
//   IOREL_EV   /IO | !/M1 rises (end of an I/O cycle): the async preset of /IOM, whose rising edge clocks HDD_FLIP
//   MR_FALL_EV /MR falls: clock of MEM_RW
//   IO_FALL_EV /IO falls: clock of IO_RWM
//   REFRESH_EV REFRESH (= CT4 of the top, a CLK42 register) rises: clock of RFT
//   DCAS_FALL_EV DOUBLE_CAS (ACCELER) falls: clears HDD_FLIP (DCP:526)
// MD (the DRAM byte, ACCELER DO) may change after CE or CE_N.
module sp_dcp (
	input             CLK,
	input             CE,
	input             CE_N,
	input             RESET_N,
	output            RES_N,
	input       [2:0] CT,
	input             CONTINUE,
	output            RAS,
	output            CAS,
	output            MC_END,
	output            MC_BEGIN,
	output            MC_TYPE,
	output            MC_WRITE,
	input      [15:0] A,
	input       [7:0] DI,
	output      [7:0] DO,
	output     [11:0] MA,
	output      [1:0] MCA,
	input             TURBO_HAND,
	output            CLK_Z80,
	output            TURBO,
	input             IO_N,
	input             RD_N,
	input             WR_N,
	input             MR_N,
	input             RF_N,
	input             M1_N,
	input             IOWR_EV,
	input             IOREL_EV,
	input             MR_FALL_EV,
	input             IO_FALL_EV,
	output            WAIT_N,
	output            IOM_N,
	output            IOMM_N,
	input       [7:0] MD,
	output     [17:14] RA,
	output     [11:0] PAGE,
	output      [3:0] TYPE,
	output            CS_ROM,
	output            CS_RAM,
	output            V_RAM,
	output            PORT,
	input             DOS,
	output            WR_DWG,
	output            WR_TM9,
	output            WR_AWG,
	output            RD_KP11,
	output            KP11_MIX,
	input             REFRESH_EV,
	input       [9:0] G_LINE,
	output      [9:0] GA,
	output            GRAF,
	output            SP_SCR,
	output            SP_SA,
	output            SCR128,
	input             TEST_R,
	output            HDD_DATA,
	output            HDD_FLIP,
	output            RAM,
	output            BLK_R,
	output            PN4Q,
	input             ACC_ON,
	output      [7:0] DCPP,
	input             DCAS_FALL_EV,
	input             BLK_MEM,
	// karabas: next values for the top, which uses some outputs as clocks (MDP by /IOMM, HDDR by /IOMM and RAS,
	// DOUBLE_CAS through MC_TYPE, ACCELER by CLK_Z80): the value after this CE (CLK_Z80_NX: after the next CE_N;
	// IOM_N_NX: the register part, with the asynchronous preset from the pins as they are now). Valid at CE.
	output            IOMM_N_NX,
	output            IOM_N_NX,
	output            RAS_NX,
	output            MC_TYPE_NX,
	output            CLK_Z80_NX,
	output      [3:0] TYPE_NX,
	output            HDD_DATA_NX
);
	parameter MIF_HEX = "dcp.hex";
	// karabas: REFRESH_REG = 1 when REFRESH is a CLK42 register switching at the same edge as RFC (in the top it is
	// CT4 of VIDEO2): RFT is then clocked while its preset RFC still has the value before the edge (a race in the
	// original; the netlist of the whole ACEX resolves it so: an active RFC before the edge swallows the clock).
	// 0 = REFRESH changes after the edge (the DCP test, tb_eq_dcp): RFC is seen with its new value.
	parameter REFRESH_REG = 0;

	wire ct0 = CT[0], ct1 = CT[1], ct2 = CT[2];
	wire ph6 = ct1 & ct2;                      // CT1 & CT2: phase 6
	wire ph5 = ct0 & ct2;                      // CT0 & CT2: phase 5

	// ---- /RES = DFFE(VCC, CLK42, , , CT0) (DCP:260): meant as a pulse after the configuration (power-up 0 until the
	// first CT0), the preset of the registers below. karabas: Quartus removes it as stuck at VCC and powers the
	// preset registers up as 1 (they are stored inverted); the same here: res_q = 1, those registers start at 1.
	// (A literal pulse would differ from the reference in the first CLK42 cycle and flip the parity of KP11_MIX.)
	wire res_q = 1'b1;

	// ---- MEM 256x16 (lpm_ram_dp, DCP.MIF): rdaddress, wraddress, data, wren and the output all registered on
	// CLK42 (LPM_* = REGISTERED, the netlist has port_b_data_out_clock): MEM.q = the word at PGS two CEs ago.
	// Both addresses = PGS.
	reg [15:0] mem [0:255];
	initial $readmemh(MIF_HEX, mem);
	reg [15:0] arr_q = 16'd0;                  // the array word at the address latched at the last CE
	reg [15:0] q = 16'd0;                      // MEM.q: output register

	// ---- page / config registers, clocked by /IOWR (DCP:649-672)
	reg  [7:0] pn_q = 8'd0, sc_q = 8'd0, cnf_q = 8'd0;
	reg        sys_q = 1'b0, arom16_q = 1'b0, tb_sw_q = 1'b1;
	wire [7:0] cnf_e = RESET_N ? cnf_q : 8'd0;              // clrn = /RESET
	wire       sys_e = RESET_N & sys_q;
	wire       arom16_e = RESET_N & arom16_q;
	wire       tb_sw_e = ~RESET_N | tb_sw_q;               // prn = /RESET
	wire       sc_clr = ~RESET_N | cnf_e[6];               // SC.clrn = /RESET & !CNF6 (Scorpion off)
	wire       pn_clr_lo = ~RESET_N | cnf_e[5];            // PN[5..0].clrn = /RESET & !CNF5
	wire       pn_clr_hi = ~RESET_N | ~cnf_e[7];           // PN[7..5].clrn = /RESET & CNF7
	wire       pn_clr5 = pn_clr_lo & pn_clr_hi;            // PN5 in both: the two clrn are ORed (DCP:671-672)
	wire [7:0] sc_e = sc_clr ? 8'd0 : sc_q;
	wire [7:0] pn_e = {pn_clr_hi ? 2'b00 : pn_q[7:6], pn_clr5 ? 1'b0 : pn_q[5], pn_clr_lo ? 5'd0 : pn_q[4:0]};

	// ---- STARTING = LCELL(/RESET & (STARTING or !(/IO or /RD))) (DCP:715): a latch, set by the first IN
	reg  st_q = 1'b0;
	wire starting = RESET_N & (st_q | ~(IO_N | RD_N));

	// ---- page decoder (DCP:680-712)
	wire       scl  = ~(sc_e[0] & sys_e);                  // SC_LCELL (CASH_ON = GND)
	wire       spr1 = ~sc_e[1] & DOS;                      // SPR_[1..0]: expansion / dos / basic128 / basic48
	wire       spr0 = ~sc_e[1] & (pn_e[4] | ~DOS);
	wire [5:0] pg3 = {~pn_e[7], 1'b1, (sc_e[4] & ~cnf_e[7]) | (cnf_e[7] & pn_e[6]), pn_e[2:0]};
	// NMI_ENA = VCC, CASH_ON = GND (UPDATE = 1)
	wire [5:0] pg0 = {1'b1, 1'b0, sc_e[0] | ~sys_e, arom16_e & ~(sc_e[0] & sys_e),
	                  (spr1 & scl) | ~sys_e, (spr0 & scl) | ~sys_e};
	reg  [5:0] mpgs;
	always @* case (A[15:14])
		2'd0: mpgs = pg0;
		2'd1: mpgs = 6'b101001;                            // E9
		2'd2: mpgs = 6'b101010;                            // EA
		default: mpgs = pg3;
	endcase
	reg  [3:0] ra;
	always @* casez ({TEST_R, sys_e})
		2'b?0: ra = {~arom16_e, 3'b000};                   // system 0 / 1
		2'b01: ra = {~arom16_e, 1'b0, spr1, spr0};          // expansion / dos / basic
		default: ra = {3'b001, spr0};                       // test
	endcase

	// ---- memory cycle synchroniser (DCP:409-480)
	reg  mc_rq_q = 1'b0;                       // MC_RQ: !CLK42
	reg  mcb_q = 1'b1, mce_q = 1'b0, mct_q = 1'b1, mcw_q = 1'b1;
	wire mrio_idle = MR_N & IO_N;
	wire mc_begin = mrio_idle | mcb_q;         // MC_BEGIN.prn = !(/MR & /IO)
	wire mc_end = ~mrio_idle & mce_q;          // MC_END.clrn = !(/MR & /IO)
	wire mc_type = ~res_q | mct_q;             // prn = /RES
	wire mc_write = ~res_q | mcw_q;
	reg  rfc_q = 1'b0, rft_q = 1'b1;           // rft_q holds the effective RFT (prn = RFC)
	reg  ras_q = 1'b1, cas_q = 1'b1;
	wire ras_e = ~res_q | ras_q, cas_e = ~res_q | cas_q;

	// IO_RW = DFF(/IO, CLK42, , /M1); the two-stage copy for MC_RQ with prn = !/IO
	reg  io_rw_q = 1'b1, s1_q = 1'b1, s2_q = 1'b1;
	wire io_rw = ~M1_N | io_rw_q;
	wire s1_e = IO_N | s1_q, s2_e = IO_N | s2_q;
	// "anti gluk" (DCP:490-492): MEM_RW = DFF(!/RF or BLK_MEM, !/MR, , LCELL(MEM_RW or !/MR)): captured at the fall
	// of /MR, 1 while /MR is high; IO_RWM = DFF(!/M1, !/IO, , LCELL(IO_RW or !/IO)): captured at the fall of /IO,
	// set while /IO is high and IO_RW still 0
	reg  mem_rw_q = 1'b1, io_rwm_q = 1'b1;
	wire mem_rw = MR_N | mem_rw_q;
	wire io_rwm = (~io_rw & IO_N) | io_rwm_q;

	// ---- graphics page (DCP:607-613)
	reg  graf_q = 1'b0;
	wire graf_x = q[7:4] == 4'b0101;
	wire blk_c = (graf_x ^ graf_q) & ~mc_type;
	wire [9:0] ga = graf_q ? {1'b1, G_LINE[8:0]} : {2'b00, q[3:0], A[13:10]};

	// ---- clocks (DCP:262-281)
	reg  clk21_q = 1'b0, t35_q = 1'b0, clkz_q = 1'b0;
	reg  tb1_q = 1'b1, turbo_q = 1'b0;         // TURBO = DFF(DFFE(TB_SW & TURBO_HAND, CLK_Z80, , /RESET, !/RF), CLK42)
	wire tb1_e = ~RESET_N | tb1_q;
	wire clkz_d = (clk21_q & turbo_q) | (t35_q & ~turbo_q);

	// ---- address multiplexer, peripheral strobes (DCP:283-404)
	reg  [1:0] ma_ct_q = 2'd0;
	reg [11:0] ma_q = 12'd0;
	reg  [1:0] mca_q = 2'd0;
	reg  [2:0] hdd_a_q = 3'd0;                 // HDD_A[2..0] (HDD_A3 is never used)
	reg  wr_tm9_q = 1'b1, rd_kp11_q = 1'b1, kp11_q = 1'b0;
	wire wr_tm9_e = ~res_q | wr_tm9_q, rd_kp11_e = ~res_q | rd_kp11_q;
	reg  awg_q = 1'b1, awg_y = 1'b0;           // WR_AWGX = DFF(GND, !WR_TM9, , DFF(WR_AWGX, CLK42)): effective value

	// ---- I/O strobes, waits (DCP:494-567)
	reg  iomm_q = 1'b1, iomx_q = 1'b1, iomy_q = 1'b1, iomz_q = 1'b1, iom_q = 1'b1;
	reg  ports_x_q = 1'b0;
	wire iomm_e = ~res_q | iomm_q, iomx_e = ~res_q | iomx_q;
	wire iomy_e = ~ports_x_q | iomy_q, iomz_e = ~ports_x_q | iomz_q;    // prn = PORTS_X
	wire iom_force = IO_N | ~M1_N;             // /IOM.prn = !/IO & /M1
	wire iom_e = iom_force | iom_q;
	reg  [3:0] wt_q = 4'hF;
	wire [3:0] wt_e = mc_end ? wt_q : 4'hF;    // WT_CT[].prn = MC_END
	reg  wt0_q = 1'b0, wt01_q = 1'b0;          // DFF(WT_CT == 0), DFF(WT_CT == B"000X")
	reg  w1_q = 1'b0, w2_q = 1'b0, nio_q = 1'b0;
	wire w2_e = nio_q | w2_q;                  // prn = NO_IO_WAIT = !nio_q
	reg  hz_q = 1'b0, hdd_data_q = 1'b0, hdd_flip_q = 1'b0;
	wire hdd_ena = q[7:5] == 3'b101;
	reg  [3:0] w_tab;
	always @* case ({turbo_q, q[14:12]})
		4'd0, 4'd1, 4'd5:             w_tab = 4'd2;
		4'd2, 4'd3, 4'd4:             w_tab = 4'd1;
		4'd6, 4'd12, 4'd13, 4'd14:    w_tab = 4'd7;
		4'd8, 4'd9:                   w_tab = 4'd2;
		4'd10, 4'd11:                 w_tab = 4'd4;
		default:                      w_tab = 4'd10;   // 7, 15
	endcase

	// ---- descriptor registers DCPP / DD (DCP:618-639)
	reg  dcp_res_q = 1'b0, mced_q = 1'b0;      // DCP_RES, DFF(MC_END)
	reg  [7:0] dcpp_q = 8'd0, dd_q = 8'd0;
	wire dd_clr = ~(mc_end & dcp_res_q);       // clrn = MC_END & DCP_RES
	wire [7:0] dcpp_e = dd_clr ? 8'd0 : dcpp_q;
	wire [7:0] dd_e = dd_clr ? 8'd0 : dd_q;
	wire [7:0] dd_d = (MD[7:4] == 4'hF) ? {2'b11, pg3} : MD;
	wire dcp_cx = dcpp_e[7:4] == 4'b1100;
	// SYS_ENA, SC / PN enables = DFF(DCP_CX & ...): only read at the /IOWR edge, which comes after the CLK42 edge, so
	// they are seen with their new values = the D of these registers (the registers themselves are not needed)
	wire sys_ena_n = dcp_cx & (dcpp_e[2:0] == 3'b110);
	wire sc_ena_n = dcp_cx & (dcpp_e[2:0] == 3'b000);
	wire pn_ena_n = dcp_cx & (dcpp_e[2:0] == 3'b001);

	reg  [7:0] pgs_q = 8'd0;                   // PGS: !CLK42
	reg  m1_q = 1'b0, m2_q = 1'b0, memwr_q = 1'b0;
	wire memwr = ~IO_N & memwr_q;              // MEM_WR.clrn = !/IO

	// HDD_FLIP clocked by the rise of /IOM (its preset, IOREL_EV): data and enable from CLK42 registers at their new
	// values (MEM.q after this CE = arr_q; DFF(DCPP == 0010XXXX) after this CE = its D)
	wire flip_ev = IOREL_EV & ~iom_e;
	wire flip_ena = (arr_q[7:5] == 3'b101) & (dcpp_e[7:4] == 4'b0010);
	wire flip_d = ~hdd_flip_q & (arr_q[11:8] == 4'd0);

	// the next WR_TM9 (for the fall that clocks WR_AWGX)
	wire wr_tm9_n = ~res_q ? 1'b1 : clk21_q ? (~ma_ct_q[1] | (~IO_N & ~ports_x_q)) : wr_tm9_q;
	wire tm9_fall = wr_tm9_e & ~wr_tm9_n;

	// MA_ (DCP:357-380)
	reg [11:0] x_adr, ma_d;
	always @* begin
		case ({io_rw, ma_ct_q[0]})
			2'b00: x_adr = {1'b0, cnf_e[4], pn_e[5], DOS, WR_N, A[15], A[14], A[6], A[5], A[13], A[7], A[2]};
			2'b01: x_adr = {2'b00, cnf_e[4:3], 8'h40};
			2'b10: x_adr = {1'b0, ga[3], ga[1:0], A[9:2]};
			default: x_adr = {2'b00, ga[3:2], q[7:4], ga[7:4]};
		endcase
		case ({io_rw, ma_ct_q[1]})
			2'b01: ma_d = {hdd_a_q, q[8:6], q[5] & ~iomz_e, q[4] & ~iomy_e, WR_N, q[2], A[6:5]};
			2'b11: ma_d = {hdd_a_q, 5'b00000, WR_N, 1'b1, A[6:5]};
			default: ma_d = x_adr;
		endcase
	end
	reg [2:0] hdd_a_d;
	always @* case ({A[14], A[2:0]})
		4'd1: hdd_a_d = 3'd1;  4'd2: hdd_a_d = 3'd2;  4'd3: hdd_a_d = 3'd3;  4'd4: hdd_a_d = 3'd4;
		4'd5: hdd_a_d = 3'd5;  4'd10: hdd_a_d = 3'd6; 4'd11: hdd_a_d = 3'd7;
		4'd12: hdd_a_d = 3'd6; 4'd13: hdd_a_d = 3'd7;   // 14, 15 -> HDD_A3 set, [2..0] = 6, 7
		default: hdd_a_d = 3'd0;
	endcase

	wire tick = CE | CE_N;
	always @(posedge CLK) begin
		// ---- async-forced registers keep their effective value at every edge
		if (tick) begin
			st_q <= starting;
			mem_rw_q <= mem_rw; io_rwm_q <= io_rwm;
			io_rw_q <= io_rw; s1_q <= s1_e; s2_q <= s2_e;
			mcb_q <= mc_begin; mce_q <= mc_end;
			wt_q <= wt_e;
			iom_q <= iom_e;
			dcpp_q <= dcpp_e; dd_q <= dd_e;
			memwr_q <= memwr;
			cnf_q <= cnf_e; sys_q <= sys_e; arom16_q <= arom16_e; tb_sw_q <= tb_sw_e;
			sc_q <= sc_e; pn_q <= pn_e;
			tb1_q <= tb1_e;
			if (~RESET_N) hdd_flip_q <= 1'b0;
		end

		if (CE) begin

			// clocks
			clk21_q <= ~ct0 ^ ct2;
			t35_q <= t35_q ^ (~ct2 & ct1);
			turbo_q <= tb1_e;

			// RAM: the array word of the address latched last CE -> output register; this CE latches PGS and writes.
			// The read port sees the old word in the cycle of a write to the same address (mixed-port read during
			// write = old data, as the reference M9K: the written byte reaches MEM.q two CEs after the write edge)
			q <= arr_q;
			arr_q <= mem[pgs_q];
			if (memwr) mem[pgs_q] <= {q[15:8], DI};

			// memory cycle
			if (ph6) begin
				mcb_q <= mrio_idle | mc_rq_q;
				rfc_q <= ~mc_rq_q | rft_q;
				mca_q <= A[1:0];
			end
			if (~mrio_idle & ph5 & ~mc_begin & CONTINUE & ~blk_c) mce_q <= 1'b1;
			if (~res_q) begin mct_q <= 1'b1; mcw_q <= 1'b1; end
			else if (ph6) begin
				mct_q <= mc_rq_q | mc_end;
				mcw_q <= mc_rq_q | CS_RAM | WR_N | mc_end;
			end
			// RFT: d = GND at the rise of REFRESH, prn = RFC (new value)
			if (~(ph6 ? (~mc_rq_q | rft_q) : rfc_q)) rft_q <= 1'b1;
			else if (REFRESH_EV & (~REFRESH_REG | rfc_q)) rft_q <= 1'b0;
			if (~res_q) begin ras_q <= 1'b1; cas_q <= 1'b1; end
			else begin
				if (~(ct1 | (ct0 ^ mc_type)) & (~mc_type | ~rfc_q)) ras_q <= ct2;
				if (~(ct1 | (ct0 ^ ~mc_type)) & (~mc_type | ~rfc_q)) cas_q <= ct2 | blk_c;
			end

			io_rw_q <= ~M1_N | IO_N;
			s1_q <= IO_N | io_rw;
			s2_q <= IO_N | s1_e;
			if (MR_FALL_EV) mem_rw_q <= ~RF_N | BLK_MEM;
			if (IO_FALL_EV) io_rwm_q <= ~M1_N;

			if (ph5) graf_q <= graf_x;

			// address multiplexer, strobes
			if (clk21_q) begin
				ma_ct_q <= (ct2 & ~ct1) ? 2'd0 : ma_ct_q + 2'd1;
				ma_q <= ma_d;
			end
			hdd_a_q <= hdd_a_d;
			wr_tm9_q <= wr_tm9_n;
			awg_y <= awg_q;
			if (~awg_q) awg_q <= 1'b1;            // prn = the new DFF(WR_AWGX) = 0
			else if (tm9_fall) awg_q <= 1'b0;

			// I/O strobes and waits
			wt0_q <= wt_e == 4'd0;
			wt01_q <= wt_e[3:1] == 3'd0;
			if (~res_q) begin iomm_q <= 1'b1; iomx_q <= 1'b1; end
			else if (clk21_q) begin
				iomm_q <= io_rw | ~mc_end | wt0_q;
				iomx_q <= iomm_e;
			end
			if (~ports_x_q) begin iomy_q <= 1'b1; iomz_q <= 1'b1; end
			else if (clk21_q) begin
				iomy_q <= iomx_e | ~mc_end | wt01_q;
				iomz_q <= (A[8] ^ RD_N) | iomx_e | ~mc_end | wt01_q;
			end
			ports_x_q <= (dcpp_e[7:4] == 4'b0010) | (dcpp_e[7:4] == 4'b0001);
			if (iom_force) iom_q <= 1'b1;
			else if (clk21_q) iom_q <= iomx_e & iom_e;
			if (~mc_end) wt_q <= 4'hF;
			else if (clk21_q) wt_q <= iom_e ? w_tab : wt0_q ? 4'd0 : wt_e - 4'd1;
			if (clk21_q) w1_q <= wt_e == 4'd0;
			w2_q <= nio_q ? 1'b1 : w1_q;
			nio_q <= (A[7:5] == 3'b111) & A[2] & ~turbo_q & DOS;

			hz_q <= q[11:8] == 4'd0;
			hdd_data_q <= hdd_ena & hz_q & ports_x_q;
			if (~RESET_N | DCAS_FALL_EV) hdd_flip_q <= 1'b0;
			else if (flip_ev & flip_ena) hdd_flip_q <= flip_d;

			// descriptors
			dcp_res_q <= starting & ~IO_N & M1_N;
			mced_q <= mc_end;
			if (dd_clr) begin dcpp_q <= 8'd0; dd_q <= 8'd0; end
			else if (~mced_q) begin dcpp_q <= MD; dd_q <= dd_d; end

			// page / config registers on the rise of /IOWR
			if (IOWR_EV & sys_ena_n) begin
				if (RESET_N) begin
					cnf_q <= (DI & {8{DI[2]}}) | (cnf_e & ~{8{DI[2]}});
					arom16_q <= (DI[0] & ~DI[1]) | (arom16_e & DI[1]);
					tb_sw_q <= (DI[0] & DI[1]) | (tb_sw_e & ~DI[1]);
					sys_q <= ~A[6];
				end
			end
			if (IOWR_EV & sc_ena_n & ~sc_clr) sc_q <= DI;
			if (IOWR_EV & pn_ena_n) begin
				if (~pn_clr_hi) pn_q[7:6] <= DI[7:6];
				if (~pn_clr5) pn_q[5] <= DI[5];
				if (~pn_clr_lo) pn_q[4:0] <= DI[4:0];
			end

			// MEM_WR = DFFE(DCPP7 & DCPP6 & STARTING & DFF(DFF(MC_END & !/WR)), CLK42, !/IO, , CT1)
			m1_q <= mc_end & ~WR_N;
			m2_q <= m1_q;
			if (IO_N) memwr_q <= 1'b0;
			else if (ct1) memwr_q <= dcpp_e[7] & dcpp_e[6] & starting & m2_q;
		end

		if (CE_N) begin
			clkz_q <= clkz_d;
			if (~clkz_q & clkz_d & ~RF_N & RESET_N) tb1_q <= tb_sw_e & TURBO_HAND;
			mc_rq_q <= (mem_rw & s2_e) | (RD_N & WR_N);
			if (res_q & clk21_q) rd_kp11_q <= ma_ct_q != 2'd0;
			else if (~res_q) rd_kp11_q <= 1'b1;
			if (~rd_kp11_e & (~res_q | (clk21_q ? ma_ct_q != 2'd0 : rd_kp11_q))) kp11_q <= ~kp11_q;
			pgs_q <= (IO_N & ~(A[14] & A[15] & ~starting)) ? {2'b11, mpgs} : mc_end ? dd_e : 8'd0;
		end
	end

	assign RES_N    = res_q;
	assign RAS      = ras_e;
	assign CAS      = cas_e;
	assign MC_END   = mc_end;
	assign MC_BEGIN = mc_begin;
	assign MC_TYPE  = mc_type;
	assign MC_WRITE = mc_write;
	assign DO       = q[7:0];                  // ADR8_MEM = GND
	assign MA       = ma_q;
	assign MCA      = mca_q;
	assign CLK_Z80  = clkz_q;
	assign TURBO    = turbo_q;
	// /MR_WAIT = MC_END or MEM_RW or /CASH or (!TURBO & !ACC_ON), /CASH = GND (UPDATE = 1)
	// /IO_WAIT = IO_RWM or DFF(DFFE(WT_CT == 0, CLK21), prn = NO_IO_WAIT)
	assign WAIT_N   = (io_rwm | w2_e) & (mc_end | mem_rw | (~turbo_q & ~ACC_ON));
	assign IOM_N    = iom_e;
	assign IOMM_N   = iomm_e;
	assign RA       = ra;
	assign PAGE     = q[11:0];
	assign TYPE     = q[15:12];
	assign RAM      = ~(A[14] | A[15] | (sc_e[0] & sys_e));
	assign CS_ROM   = MR_N | ~RAM | ~RF_N;
	assign CS_RAM   = MR_N | RAM | ~RF_N;
	assign V_RAM    = pn_e[2];
	assign PORT     = (q[15:12] != 4'd0) | IO_N | (RD_N & WR_N);
	assign WR_DWG   = ~mc_begin;
	assign WR_TM9   = wr_tm9_e;
	assign WR_AWG   = awg_q;
	assign RD_KP11  = rd_kp11_e;
	assign KP11_MIX = kp11_q;
	assign GA       = ga;
	assign GRAF     = graf_q;
	assign SP_SCR   = (A[15:14] == 2'd1) ? ~graf_q :
	                  (A[15:14] == 2'd3) ? ~graf_q & (pg3[5:4] == 2'b11) & ~pg3[3] & pg3[2] & pg3[0] : 1'b0;
	assign SP_SA    = A[15] & pg3[1];
	assign SCR128   = pn_e[3];
	assign HDD_DATA = hdd_data_q;
	assign HDD_FLIP = RESET_N & hdd_flip_q;
	assign BLK_R    = sc_e[4];                 // UPDATE = 1
	assign PN4Q     = pn_e[4];
	assign DCPP     = dcpp_e;
	// next values (res_q = 1)
	assign IOMM_N_NX   = clk21_q ? (io_rw | ~mc_end | wt0_q) : iomm_q;
	assign IOM_N_NX    = iom_force | (clk21_q ? (iomx_e & iom_e) : iom_q);
	assign RAS_NX      = (~(ct1 | (ct0 ^ mc_type)) & (~mc_type | ~rfc_q)) ? ct2 : ras_q;
	assign MC_TYPE_NX  = ph6 ? (mc_rq_q | mc_end) : mct_q;
	assign CLK_Z80_NX  = clkz_d;
	assign TYPE_NX     = arr_q[15:12];
	assign HDD_DATA_NX = hdd_ena & hz_q & ports_x_q;
endmodule
