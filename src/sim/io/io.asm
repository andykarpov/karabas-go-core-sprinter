; io.asm: the test program of tb_io (sjasmplus --raw), put into ROM page 8 of the BIOS image as storage.asm (the page
; the configured ACEX starts from; the loader of the BIOS still pours the bitstream). It writes the descriptors of
; port #FE (read: code 40, write: C2) and of the AY ports #FFFD / #BFFD (codes 90 / 91) into the port table (DRAM
; page 0x40, window 3 while STARTING = 0), then:
;   tape in: IN A,(#FE) with TAPE_IN = 0 (marker 20), the testbench sets TAPE_IN = 1, IN A,(#FE) again (marker 21);
;   tape out: OUT (#FE) with bit 3 = 1 (marker 22), = 0 (marker 23): the testbench reads TAPE_OUT at the markers;
;   MIDI (MIDI_TX = R14 bit 2 while R7 bit 6 = 1, else 1): R7 = 40, R14 = FB (marker 30: 0); R7 = 00 (31: 1, port A
;   an input); R7 = 40 (32: 0); R14 = 04 (33: 1); R13 selected and written with bit 2 = 0 (34: stays 1).
; Results: OUT (#01) = a data byte, OUT (#02) = a marker (the testbench reads the CPU pins; port table code 00).

	macro	LOGA			; log A
	out	(#01),a
	endm
	macro	MARK n
	ld	a,n
	out	(#02),a
	endm
	macro	PT1 idx, code		; one descriptor, both DOS values
	ld	(#c000 + (idx)),a
	ld	(#c400 + (idx)),a
	endm
	macro	PTA idx, code		; ... for all A15 / A14 / A13 (bits 8, 7, 4)
	ld	a,code
	PT1	(idx), code
	PT1	(idx) | #010, code
	PT1	(idx) | #080, code
	PT1	(idx) | #090, code
	PT1	(idx) | #100, code
	PT1	(idx) | #110, code
	PT1	(idx) | #180, code
	PT1	(idx) | #190, code
	endm
RD	equ	#200			; /WR = 1: a read
	; a delay of about B x 256 x 13 T
	macro	WAIT n
	ld	b,n
.d	djnz	.d
	endm
	; AY: register r, value v
	macro	AYW r, v
	ld	bc,#fffd
	ld	a,r
	out	(c),a
	ld	b,#bf
	ld	a,v
	out	(c),a
	endm

	org	0
main	di
	ld	sp,#bff0
	; ---- the port table: index {CNF4 CNF3 PN5 DOS /WR A15 A14 A6 A5 A13 A7 A2 A1 A0}
	; #FE: A7 A6 A5 = 111, A2..A0 = 110 (xxFE / xxE6 / ...)
	PTA	RD | #06e, #40
	PTA	#06e, #c2
	; #FFFD / #BFFD: A15 A14 A13 = 111 / 101, A7 A6 A5 = 111, A2..A0 = 101
	ld	a,#90
	PT1	#1fd, #90
	ld	a,#91
	PT1	#17d, #91
	; the first IN ends STARTING (the descriptors are used from now on)
	xor	a
	in	a,(#03)
	MARK	#10

	; ================= tape in (port #FE bit 6)
	in	a,(#fe)
	LOGA
	MARK	#20			; the testbench sets TAPE_IN = 1
	WAIT	64
	in	a,(#fe)
	LOGA
	MARK	#21

	; ================= tape out (port #FE bit 3, the XA2 latch of the board)
	ld	a,#08
	out	(#fe),a
	WAIT	16
	MARK	#22
	xor	a
	out	(#fe),a
	WAIT	16
	MARK	#23

	; ================= MIDI (AY register 14 bit 2)
	AYW	7, #40
	AYW	14, #fb
	MARK	#30
	AYW	7, #00
	MARK	#31
	AYW	7, #40
	MARK	#32
	AYW	14, #04
	MARK	#33
	AYW	13, #00
	MARK	#34

	MARK	#ff
	halt
