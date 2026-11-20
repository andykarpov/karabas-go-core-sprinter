// Sprinter ACEX: the accelerator (ACCELER.TDF of the ACEX configuration 3.03a). LD r,r opcode capture, block fill /
// copy with the logic functions AND / OR / XOR, vertical lines, the DRAM address AO, the 256-byte line buffer.
// Translated from the AHDL of Ivan Mak / Peters Plus, reconstruction of Tolik-Trek (github.com/Tolik-Trek/SP2000-ACEX).
// Rules: docs/translation.md. Signal names follow ACCELER.TDF (/X -> X_N).
//
// One clock CLK (84 MHz on the board) with two enables: CE = rising edge of the original CLK42, CE_N = its falling
// edge (XMD, DFF(MC_END) that clocks DO). Clocks of the AHDL that are not CLK42:
// - CLK_Z80 (a !CLK42 register of DCP)   -> CLK_Z80_EV, high at the CE_N where CLK_Z80 rises;
// - /MR, /M1 (Z80 pins used as clocks)   -> MR_N_EV, M1_N_EV, high at the CE where the pin rises. The pins must change
//                                           at CE (half a CLK42 after the CLK_Z80 edge that makes them), never at the
//                                           same edge as CLK_Z80_EV: the /MR registers take /M1M, the RGACC / ACC_MODE
//                                           enables (CLK_Z80 registers) as settled;
// - WR_C7 (internal CLK42 register)      -> event from its next value (ALT_ACC);
// - DFF(MC_END, !CLK42) (internal)       -> event at CE_N from its next value (DO).
// The events are gated inside (MR_N_EV, M1_N_EV with CE, CLK_Z80_EV with CE_N). Registers with an asynchronous
// clrn / prn take their effective value at every CLK edge (the forced value stays once the control goes away, as in
// the flip-flop).
// The AHDL inputs RAS, MC_BEGIN, MC_WRITE drive nothing (Quartus: "never used") and are left out; DCP[3] is unused too.
module sp_acceler (
	input             CLK,
	input             CE,          // CLK42 rising
	input             CE_N,        // CLK42 falling
	input             RESET_N,
	input       [2:0] CT,          // video phase 0,1,2,4,5,6
	input             CAS,         // DCP, active low
	input             CLK_Z80_EV,  // CLK_Z80 rises at this CE_N
	output            CONTINUE,    // to DCP: 0 = hold MC_END (the block is not finished)
	input             MC_END,
	input             MC_TYPE,     // 0 = CPU DRAM cycle
	input      [15:0] AI,          // Z80 A
	input       [7:0] DI,          // Z80 D (what is on the bus: the CPU on writes, DO on memory reads)
	output     [15:0] AO,          // DRAM / video address
	output      [7:0] DO,          // DRAM byte to the CPU and DCP
	input             IO_N,
	input             RD_N,
	input             WR_N,
	input             MR_N,
	input             MR_N_EV,     // /MR rises at this CE
	input             RF_N,
	input             M1_N,
	input             M1_N_EV,     // /M1 rises at this CE
	input             IOM_N,       // DCP /IOM
	input       [7:0] DCP,         // port descriptor DCPP
	input      [15:0] MDI,         // DRAM data bus MD
	output     [15:0] MDO,
	output      [7:0] MD,
	output      [7:0] G_LINE,
	output            GLISSER,
	output            ACC_ON,
	input             ACC_ENA,     // ALL_MODE0
	output            DOUBLE_CAS,
	input       [7:0] HDDR,
	input             HDD_FLIP,
	output reg  [7:0] ACC_DIR,
	// karabas: the effective ACC_BLK, for the top's next value of DOUBLE_CAS (= ACC_DIR6 & !START_ACC)
	output            ACC_BLK
);
	// ================= CLK_Z80 registers =================
	reg        m1m_q = 1'b0;                  // /M1M = DFF(!/M1, CLK_Z80, /RESET)
	wire       m1m = RESET_N & m1m_q;
	reg        blkz_q = 1'b0;                 // ACC_BLK.d = DFF((/IO & ACC_BLK) | (!ACC_BLK & RETI), CLK_Z80)
	reg        rgena_q = 1'b0;                // RGACC.ena = DFF(/M1 & /RF & ACC_DIR3, CLK_Z80)
	reg        modena_q = 1'b0;               // ACC_MODE.ena = DFF(LD r,r in M1, CLK_Z80)
	reg        mode3z_q = 1'b0;               // DFF(ACC_MODE3, CLK_Z80): ACC_MODE3.clrn

	// ================= /MR registers (opcode decoder) =================
	reg        prf_q = 1'b0;                  // PRF_CMD: CB / DD / ED / FD prefix
	reg        ed_q = 1'b0;                   // ED_CMD
	reg        reti_q = 1'b0;                 // RETI
	reg        ioc_q = 1'b0;                  // IN_OUT_CMD (D3 / DB), clrn = /IO
	wire       ioc = IO_N & ioc_q;
	reg  [7:0] rgacc_q = 8'd0;                // RGACC: block length
	reg  [3:0] mode_q = 4'd0;                 // ACC_MODE
	wire [2:0] mode_lo = (RESET_N & ACC_ENA) ? mode_q[2:0] : 3'd0;
	wire       mode3 = RESET_N & ~mode3z_q & mode_q[3];    // a pulse: set by LD r,r, cleared by the next CLK_Z80
	reg  [1:0] fn_q = 2'd0;                   // FN_ACC[1..0] (FN_ACC2 drives nothing)
	// STATE_EI, RETN, CB_CMD, ID_CMD drive nothing (dead in the AHDL) and are left out.

	// ================= /M1 register =================
	reg        blk_q = 1'b1;                  // ACC_BLK, prn = /RESET & ACC_MODE3
	wire       acc_blk = (RESET_N & mode3) ? blk_q : 1'b1;

	// ACC_DIR: 0 on, 1 via the buffer, 2 count, 3 load RGACC, 4 vertical (AGR + 1), 5 horizontal (AA + 1), 6 two bytes
	always @* case (mode_lo)
		3'd1: ACC_DIR = 8'b00100101;          // LD C,C  fill by constant
		3'd2: ACC_DIR = 8'b00001001;          // LD D,D  load the counter
		3'd3: ACC_DIR = 8'b00010101;          // LD E,E  fill by constant, vertical
		3'd4: ACC_DIR = 8'b01000001;          // LD H,H  double byte
		3'd5: ACC_DIR = 8'b00100111;          // LD L,L  copy line
		3'd7: ACC_DIR = 8'b00010111;          // LD A,A  copy line, vertical
		default: ACC_DIR = 8'b00000000;       // LD B,B, HALT
	endcase

	// START_ACC = 0: a CPU memory access (not M1, not refresh) with the accelerator on (the name is inverted)
	wire       start = MR_N | ~M1_N | ~RF_N | ~acc_blk | ~ACC_DIR[0] | MC_TYPE;

	// ================= CLK42 registers =================
	reg        go_q = 1'b1;                   // ACC_GO = DFFE(CAS | START_ACC, CLK42, , !/MR & /M1, CT1)
	wire       go = (~MR_N & M1_N) ? go_q : 1'b1;
	reg        go1_q = 1'b0;                  // ACC_GO_1
	reg        sta_q = 1'b0;                  // DFF(START_ACC) = AA_LOAD
	reg        c4_q = 1'b0, agrw_q = 1'b0;    // AGR write by port C4 / CC
	reg  [7:0] agr_q = 8'd0;                  // AGR, clrn = /RESET
	wire [7:0] agr = RESET_N ? agr_q : 8'd0;
	reg        rw_q = 1'b0;                   // DFF((CT0 & !/RD) | (CT1 & !/WR))
	wire       acc_c = ~go & rw_q;
	reg  [7:0] cnt_q = 8'd0;                  // ACC_CNT
	reg        iomd_q = 1'b0, c7n_q = 1'b0;   // DFF(!/IOM), DFF(!(DCP == C7 / CF))
	reg        wrc7_q = 1'b0;                 // WR_C7: low for one clock at the start of a write to port C7 / CF
	wire       wrc7_d = IOM_N | iomd_q | WR_N | c7n_q;
	reg        alt_q = 1'b0;                  // ALT_ACC = DFF(VCC, WR_C7, /RESET): set by the first C7 write, only
	wire       alt = RESET_N & alt_q;         // /RESET clears it
	reg  [9:0] aagr_q = 10'd0;                // AAGR, XCNT, XAGR: second buffer address, (XCNT, XAGR) += AAGR
	reg  [7:0] xcnt_q = 8'd0, xagr_q = 8'd0;
	reg        ae_q = 1'b1;                   // ACC_END, prn = /M1
	wire       acc_end = M1_N ? ae_q : 1'b1;
	reg        aa0_q = 1'b0;                  // DFFE(AA0, CLK42, , , CT2 & CT1): byte of MDI
	reg        gliss_q = 1'b0;                // GLISS_R
	reg  [7:0] mdox_q = 8'd0, mdoy_q = 8'd0;
	reg [15:0] mdo_q = 16'd0;
	reg        ram_wr_q = 1'b0;               // RAM_WR
	reg [15:0] aa_q = 16'd0;                  // AA

	// line buffer RAM: lpm_ram_dp, read and write address RAM_ADR, rdaddress AND q registered on CLK42 (the
	// LPM_OUTDATA default), so q follows the address two CEs later. The written word is (XMD, XMD): 8 bits kept.
	// karabas: read-first, not the write-first of translation.md rule 6: the write (RAM_WR, the CE that ends phase 6)
	// always hits the address being read, and the netlist (M9K, mixed ports) returns the old word there. Only MDO and
	// GLISSER in the read cycles of the copy modes see that word.
	reg  [7:0] mem [0:255];
	reg  [7:0] lat_q = 8'd0;                  // word read at the address latched at this CE
	reg  [7:0] ram_q = 8'd0;                  // RAM.q[7..0]
	integer i;
	initial for (i = 0; i < 256; i = i + 1) mem[i] = 8'd0;
	wire [7:0] ram_adr = alt ? xcnt_q : cnt_q;

	// ================= !CLK42 registers =================
	reg        mcen_q = 1'b0;                 // DFF(MC_END, !CLK42): clock of DO
	reg  [7:0] xmd_q = 8'd0;                  // XMD (XMDH drives nothing)
	reg  [7:0] do_q = 8'd0;

	// MD: the byte of the DRAM word chosen by AA0
	assign MD = aa0_q ? MDI[15:8] : MDI[7:0];
	reg  [7:0] xmd_d;
	always @* case (fn_q)
		2'd0: xmd_d = MD;                     // BE  CP (HL)
		2'd1: xmd_d = MD | ram_q;             // B6  OR (HL)
		2'd2: xmd_d = MD ^ ram_q;             // AE  XOR (HL)
		default: xmd_d = MD & ram_q;          // A6  AND (HL)
	endcase

	// DO[4..3].clrn = !CORRECT_1F: the operand 1F of IN A,(n) / OUT (n),A read by the CPU becomes 07. The clear is a
	// loop through DO itself (it stops once DO != 1F); here the output shows it at once and the register keeps it at
	// the next CLK edge.
	wire       c1f = ioc & (do_q == 8'h1F) & ~MR_N & ~RD_N;
	wire [7:0] do_e = c1f ? (do_q & 8'hE7) : do_q;

	// opcode patterns on DI
	wire       prf_d = (DI[7:6] == 2'b11) & DI[3] & DI[0] &
	                   ((DI[5:4] == 2'b00) & (DI[2:1] == 2'b01) |      // CB
	                    (DI[5:4] != 2'b00) & (DI[2:1] == 2'b10));      // DD / ED / FD
	wire       ldrr = (DI[4:3] == DI[1:0]) & (DI[7:6] == 2'b01) & (DI[5] == DI[2]);   // LD r,r with the same r
	wire       ioc_d = (DI[7:4] == 4'hD) & (DI[2:0] == 3'b011) & ~prf_q;           // D3 / DB
	wire       alu = DI[7] & ~DI[6] & ~prf_q;
	wire       c4 = (DCP[7:4] == 4'hC) & (DCP[2:0] == 3'b100);                    // 1100X100
	wire       c7 = (DCP[7:4] == 4'hC) & (DCP[2:0] == 3'b111);                    // 1100X111

	wire       agr_ena = ~agrw_q | (ACC_DIR[4] & ~go & go1_q);
	wire       cnt_ena = start | (acc_c & ACC_DIR[2]);
	wire       x_ena = ~wrc7_q | (ACC_DIR[1] & acc_c);
	// AA.ena: the term ACC_GO_1 & ACC_DIR6 is dead, no mode has both ACC_DIR5 and ACC_DIR6
	wire       aa_ena = start | (ACC_DIR[5] & ~(CAS | start) & (go | (go1_q & ACC_DIR[6])));
	wire [15:0] xsum = {xcnt_q, xagr_q} + {6'd0, aagr_q};
	wire       mr_ev = CE & MR_N_EV, m1_ev = CE & M1_N_EV, z_ev = CE_N & CLK_Z80_EV;

	always @(posedge CLK) begin
		// ---- CLK_Z80
		if (z_ev) begin
			m1m_q    <= RESET_N & ~M1_N;
			blkz_q   <= (IO_N & acc_blk) | (~acc_blk & reti_q);
			rgena_q  <= M1_N & RF_N & ACC_DIR[3];
			modena_q <= ~M1_N & ~prf_q & ldrr;
			mode3z_q <= mode3;
		end else
			m1m_q <= m1m;

		// ---- /MR
		if (mr_ev) begin
			if (m1m) begin
				prf_q  <= prf_d;
				ed_q   <= DI == 8'hED;
				reti_q <= ed_q & (DI == 8'h4D);
				fn_q   <= {alu & ~DI[4], alu & ~DI[3]};
			end
			ioc_q <= IO_N & (m1m ? ioc_d : ioc_q);
			if (rgena_q) rgacc_q <= DI;
			mode_q[2:0] <= (RESET_N & ACC_ENA) ? (modena_q ? DI[2:0] : mode_q[2:0]) : 3'd0;
			mode_q[3]   <= RESET_N & ~mode3z_q & (modena_q | mode_q[3]);
		end else begin
			ioc_q  <= ioc;
			mode_q <= {mode3, mode_lo};
		end

		// ---- /M1
		if (m1_ev) blk_q <= (RESET_N & mode3) ? blkz_q : 1'b1;
		else         blk_q <= acc_blk;

		// ---- CLK42 rising
		if (CE) begin
			go_q  <= (~MR_N & M1_N) ? (CT[1] ? (CAS | start) : go_q) : 1'b1;
			go1_q <= go;
			sta_q <= start;

			c4_q   <= c4;
			agrw_q <= IOM_N | WR_N | ~c4_q;
			agr_q  <= ~RESET_N ? 8'd0 : agr_ena ? (sta_q ? DI : agr + 8'd1) : agr;

			rw_q <= (CT[0] & ~RD_N) | (CT[1] & ~WR_N);
			if (cnt_ena) cnt_q <= sta_q ? rgacc_q : cnt_q - 8'd1;

			iomd_q <= ~IOM_N;
			c7n_q  <= ~c7;
			wrc7_q <= wrc7_d;
			alt_q  <= RESET_N & ((~wrc7_q & wrc7_d) | alt_q);     // ripple clock WR_C7 rises after this edge

			if (x_ena) begin
				if (sta_q) begin
					aagr_q <= {AI[9:8], DI};
					{xcnt_q, xagr_q} <= {2'b00, AI[15:10], 8'h00};
				end else
					{xcnt_q, xagr_q} <= xsum;
			end

			ae_q <= ~M1_N | ((~go & go1_q) ? ((cnt_q == 8'd1) | ~ACC_DIR[2]) : ae_q);

			if (CT[2] & CT[1]) aa0_q <= aa_q[0];
			gliss_q <= ACC_DIR[1] ? (ram_q == 8'hFF) : (DI == 8'hFF);
			mdox_q  <= (MC_END & HDD_FLIP) ? HDDR : DI;
			mdoy_q  <= ACC_DIR[6] ? HDDR : DI;
			if (CAS) mdo_q <= (IO_N & ACC_DIR[1]) ? {ram_q, ram_q} : {mdoy_q, mdox_q};

			ram_wr_q <= ~RD_N & ~go & CT[0] & ACC_DIR[1];
			if (ram_wr_q) mem[ram_adr] <= xmd_q;
			lat_q <= mem[ram_adr];             // read and write share the address: the read gets the OLD word
			ram_q <= lat_q;

			if (aa_ena) aa_q <= sta_q ? AI : aa_q + 16'd1;
		end else
			alt_q <= alt;

		// ---- CLK42 falling
		if (CE_N) begin
			mcen_q <= MC_END;
			xmd_q  <= xmd_d;
		end
		do_q <= (CE_N & ~mcen_q & MC_END) ? MD : do_e;
	end

	assign CONTINUE   = acc_end;
	assign AO         = aa_q;
	assign DO         = do_e;
	assign MDO        = mdo_q;
	assign G_LINE     = agr;
	assign GLISSER    = gliss_q;
	assign ACC_ON     = ACC_DIR[0];
	assign DOUBLE_CAS = ACC_DIR[6] & ~start;
	assign ACC_BLK    = acc_blk;
endmodule
