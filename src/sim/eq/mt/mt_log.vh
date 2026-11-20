	// ---- memory timing log (analysis only): one line per CE / CE_N edge, values BEFORE the edge (what the edge samples)
	integer mt_fd, mt_n = 0;
	reg [8*64-1:0] mt_fn; initial begin if (!$value$plusargs("mtlog=%s", mt_fn)) mt_fn = "build/mt/log.txt"; mt_fd = $fopen(mt_fn, "w"); end
	wire [7:0] mt_dpicx = dut.SVIDEO.dpicx;
	always @(posedge clk) if (cmp_on && (ce || ce_n)) begin
		mt_n = mt_n + 1;
		$fwrite(mt_fd, "%0d %s ct=%02o vcm=%0d va=%h b=%0d vwr=%h vdoe=%h | wpic=%b wcol=%b wmode=%b lpic=%b lcol=%b ldpic=%b m0=%h blank=%b bordp=%b vla_d=%0d | dpic_ld=%b dcol_ld=%b mode_ld=%b mxwe=%b vwe=%b | ras=%b cas=%h we=%b ma=%h mdoe=%b mdi=%h mdo=%h mcb=%b mct=%b mcw=%b mce=%b mrq=%b rfc=%b | do_ld=%b xmd=%b dcpp_ld=%b mdp_ev=%b hddr_ev=%b | csr=%b csc=%b ra=%h a=%h mr=%b rd=%b wr=%b io=%b m1=%b rf=%b clkz=%b wait=%b doe=%b d=%h wtr=%0d | ewr=%b ewrd=%b vxa=%h vxd=%h%h%h%h wrcolpin=%b dbl=%b vlan=%h | colm=%h coli=%h ddclr=%b mced=%b ior=%b\n",
			mt_n, ce ? "C" : "N", dut.SVIDEO.ct_e, dut.SVIDEO.vcm, dut.VA, dut.SVIDEO.vla[1:0], dut.V_WR, dut.VD_OE,
			dut.SVIDEO.wr_pic, dut.SVIDEO.wr_col, dut.SVIDEO.wr_mode, dut.SVIDEO.lwr_pic, dut.SVIDEO.lwr_col,
			dut.SVIDEO.ld_pic, dut.SVIDEO.mode0, dut.SVIDEO.blank, dut.SVIDEO.bordp, dut.SVIDEO.vla_d,
			ce & ~dut.SVIDEO.lwr_pic & dut.SVIDEO.ld_pic, ce & ~dut.SVIDEO.blank & ~dut.SVIDEO.lwr_col & ~dut.SVIDEO.bordp,
			ce & dut.SVIDEO.wr_mode_rise, dut.SVIDEO.mxwe, dut.SVIDEO.v_we,
			dut.RAS_[0], dut.CAS_, dut.WE_N, dut.MA, dut.MD_OE, md, dut.MD_O, dut.mc_begin, dut.mc_type, dut.mc_write,
			dut.mc_end, dut.DECODE.mc_rq_q, dut.DECODE.rfc_q,
			ce_n & ~dut.ACC.mcen_q & dut.mc_end, ce_n, ce & ~dut.DECODE.mced_q & dut.DECODE.dd_clr, ce & dut.mdp_ev, ce & dut.hddr_ev,
			dut.CS_ROM, dut.CS_CASH, dut.RA, a, mr_n, rd_n, wr_n, io_n, m1_n, rf_n, dut.CLKZ1, dut.WAIT_N_OE, dut.D_OE, d, dut.wt_r, dut.SVIDEO.e_wr, dut.SVIDEO.e_wrd, dut.SVIDEO.vxa, dut.SVIDEO.vxd3, dut.SVIDEO.vxd2, dut.SVIDEO.vxd1, dut.SVIDEO.vxd0, dut.WR_COL, dut.SVIDEO.dbl, dut.SVIDEO.vla_n, {2'b00, dut.DECODE.ga[3:2], dut.DECODE.q[7:4], dut.DECODE.ga[7:4]}, {2'b00, dut.DECODE.cnf_e[4:3], 8'h40}, dut.DECODE.dd_clr, dut.DECODE.mced_q, dut.DECODE.io_rw);
	end

	// data check: the byte D_PIC0 / DCOL take vs the video RAM byte of the VA that carried their strobe (set two CEs before)
	reg [15:0] mt_va_p1 = 0; integer mt_ok = 0, mt_bad = 0;
	reg [17:0] mt_ix; reg [7:0] mt_ex;
	always @(posedge clk) if (ce) begin
		if (cmp_on && ((~dut.SVIDEO.lwr_pic & dut.SVIDEO.ld_pic) || (~dut.SVIDEO.blank & ~dut.SVIDEO.lwr_col & ~dut.SVIDEO.bordp))) begin
			mt_ix = {mt_va_p1, dut.SVIDEO.vla_d};
			mt_ex = (vram[mt_ix] === 8'hxx) ? dflt(mt_ix, 8'd5) : vram[mt_ix];
			if (mt_ex === dut.SVIDEO.dpicx) mt_ok = mt_ok + 1; else mt_bad = mt_bad + 1;
		end
		mt_va_p1 <= dut.VA;
	end
	reg mt_done = 0;
	always @(posedge clk) if (!mt_done && $time > 196000) begin mt_done = 1; $display("  mt data check: %0d equal, %0d differ", mt_ok, mt_bad); end
