; cpu_acex.asm: the ROM program of tb_cpu_acex (sjasmplus --raw), run by sp_z84c15 on the translated ACEX and the
; BASE_303 netlist. The testbench puts the scenario number at #3FFF. Results go to the log port #2001 (descriptor
; 00 in the port table of the testbench), the end to #2002. Ports by OUT (C) / IN (C) with the full address:
; the table index of the ACEX takes A15-A13 too (EE / EF with A15-A8 = 00 would hit FE / FF).
;   scenario 0: internal ports through the bus, pages of window 3 / 1;
;   scenario 2: accelerator fill and copy, 3.5 MHz and back;
;   scenario 1: IM 1 and IM 2 (vector FF) on keyboard interrupts of the ACEX (the testbench sends a PS/2 byte
;   after the markers A0 / A1).
; With ALL_MODE0 = 1 the accelerator decodes LD r,r: the code has none outside the accelerator part.
P_LOG	equ	#2001
P_END	equ	#2002
P_FE	equ	#00fe
P_ALLM	equ	#00c3
P_CNF	equ	#00c6
P_HOLD	equ	#20cb
P_W1	equ	#4089
P_W3	equ	#80f5

	macro	OUTP port, val		; OUT (C),A of val to port (BC lost)
	ld	bc,port
	ld	a,val
	out	(c),a
	endm
	macro	LOG			; log A
	ld	bc,P_LOG
	out	(c),a
	endm

	org	0
	di
	ld	sp,#bff0
	jp	init

	ds	#38-$,0

im1:	push	af
	push	bc
	ld	a,#38
	LOG
	pop	bc
	pop	af
	ei
	ret

	ds	#100-$,0
init:	ld	bc,0			; the register file of the T80 is X in the simulation (INIT 0 in the FPGA)
	ld	de,0
	ld	hl,0
	exx
	ld	bc,0
	ld	de,0
	ld	hl,0
	ld	ix,0
	ld	iy,0
start:	ld	bc,P_FE
	in	a,(c)			; STARTING: the port table is active
	ld	a,(#3fff)
	cp	1
	jp	z,scen1
	cp	2
	jp	z,scen2

	; ---- scenario 0
	; internal ports: the internal data win over the ACEX
	OUTP	#ffee, 2
	ld	bc,#ffef
	in	a,(c)			; CSBR FF
	LOG
	ld	bc,#0019
	in	a,(c)			; SIO A RR0 44
	LOG
	OUTP	#0010, #55		; CTC0 counter
	OUTP	#0010, #2d
	; pages: window 3 = page 10 / 11
	OUTP	P_W3, #10
	ld	e,#5a
	call	fill
	OUTP	P_W3, #11
	ld	e,#a5
	call	fill
	OUTP	P_W3, #10
	call	check			; 5A 5D 55 78
	OUTP	P_W3, #11
	call	check			; A5 A2 AA 78
	OUTP	P_W1, #05
	ld	a,#c3
	ld	(#4123),a
	ld	a,(#4123)		; C3
	LOG
	ld	a,#e0
	jp	theend

	; ---- scenario 2: accelerator: count 5, fill C021.. with AA, copy C021.. to C040..
scen2:	OUTP	P_W3, #10
	xor	a
	ld	(#c020),a
	ld	(#c026),a
	ld	a,#5d
	ld	(#c007),a
	OUTP	P_ALLM, #01
	; while LD D,D is the mode, every memory access (also an operand read) loads the counter: the registers are
	; set before it
	ld	e,#aa
	ld	a,5
	ld	hl,#c021
	ld	d,d			; load the counter
	ld	(hl),a			; counter = 5
	ld	a,e
	ld	c,c			; fill
	ld	(hl),a			; C021..C025 = AA
	ld	b,b
	ld	de,#c040
	ld	l,l			; copy a line
	ld	a,(hl)			; C021..C025 -> buffer
	ex	de,hl
	ld	(hl),a			; buffer -> C040..C044
	ld	b,b
	OUTP	P_ALLM, #00
	ld	a,(#c020)		; 00
	LOG
	ld	a,(#c021)		; AA
	LOG
	ld	a,(#c025)		; AA
	LOG
	ld	a,(#c026)		; 00
	LOG
	ld	a,(#c040)		; AA
	LOG
	ld	a,(#c044)		; AA
	LOG
	; 3.5 MHz and back
	OUTP	P_CNF, #02
	ld	a,(#c007)		; 5D
	LOG
	OUTP	#ffee, 2
	ld	bc,#ffef
	in	a,(c)			; CSBR FF
	LOG
	OUTP	P_CNF, #03
	ld	a,#e2
	jp	theend

	; ---- scenario 1: interrupts
scen1:	OUTP	P_HOLD, #7e
	OUTP	P_ALLM, #03		; INT by the keyboard (ALL_MODE0), ZX matrix
	OUTP	P_W3, #10
	im	1
	ld	a,#a0
	LOG
	ei
	halt				; -> 38
	di
	ld	a,#01
	LOG
	ld	hl,im2ok
	ld	(#c1ff),hl
	ld	hl,im2bad
	ld	(#c100),hl
	ld	a,#c1
	ld	i,a
	im	2
	ld	a,#a1
	LOG
	ei
	halt				; -> 22
	di
	ld	a,#02
	LOG
	im	1
	OUTP	P_ALLM, #00
	ld	a,#e1

theend:	LOG				; E0 / E1 / E2: the end
	ld	bc,P_END
	out	(c),a
	halt

im2ok:	push	af
	push	bc
	ld	a,#22
	LOG
	pop	bc
	pop	af
	ei
	reti
im2bad:	push	af
	push	bc
	ld	a,#bb
	LOG
	pop	bc
	pop	af
	ei
	reti

fill:	ld	hl,#c000		; C000..C00F = L xor E
	ld	b,16
f1:	ld	a,l
	xor	e
	ld	(hl),a
	inc	hl
	djnz	f1
	ret
check:	ld	a,(#c000)
	LOG
	ld	a,(#c007)
	LOG
	ld	a,(#c00f)
	LOG
	ld	hl,#c000
	ld	d,16
	xor	a
c1:	add	a,(hl)
	inc	hl
	dec	d
	jr	nz,c1
	LOG
	ret
