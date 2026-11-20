; cpu_acex.asm: the ROM program of tb_cpu_acex (sjasmplus --raw), run by sp_z84c15 on the translated ACEX and the
; BASE_303 netlist. The testbench puts the scenario number at #3FFF. Results go to the log port #2001 (descriptor
; 00 in the port table of the testbench), the end to #2002. Ports by OUT (C) / IN (C) with the full address:
; the table index of the ACEX takes A15-A13 too (EE / EF with A15-A8 = 00 would hit FE / FF).
;   scenario 0: internal ports through the bus, pages of window 3 / 1;
;   scenario 2: accelerator fill and copy, 3.5 MHz and back;
;   scenario 1: IM 1 and IM 2 (vector FF) on keyboard interrupts of the ACEX (the testbench sends a PS/2 byte
;   after the markers A0 / A1);
;   scenario 3: video RAM (ZX screen + attributes, graphics page 50 with the palette bytes 3E0-3FF of a line, the
;   video-only page 54), read back from the DRAM copy; the fastram (cache, IN (FB) / IN (7B)): a stage in DRAM
;   (window 2) fills and sums cache bytes, copies code into the cache and calls it: M1 from the cache, writes 3 T
;   apart (LD (nn),SP, PUSH with SP even / odd, CALL), read-modify-write (INC (HL), EX (SP),HL), a write followed
;   at once by the fetch of that byte / of the other byte of its word (self-modifying code), a loop.
; With ALL_MODE0 = 1 the accelerator decodes LD r,r: the code has none outside the accelerator part.
P_LOG	equ	#2001
P_END	equ	#2002
P_FE	equ	#00fe
P_ALLM	equ	#00c3
P_CNF	equ	#00c6
P_HOLD	equ	#20cb
P_W1	equ	#4089
P_W3	equ	#80f5
P_AGR	equ	#00c4
P_CASH1	equ	#00fb
P_CASH0	equ	#007b
PAY	equ	#1000			; scenario 3: the cache code (ROM 1000-1FFF copied into the cache by the testbench)

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
	cp	3
	jp	z,scen3

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

	; ---- scenario 3: video RAM and the fastram
scen3:	OUTP	P_ALLM, #00		; accelerator off, ZX screen copy (ALL_MODE0 = 0)
	jp	cash_on			; everything below runs from the cache (no ROM waits)

	; the fastram: IN (FB) puts the cache into window 0, the next fetch comes from the cache at PAY (the testbench
	; preloads the cache with ROM 1000-1FFF, i.e. the code below, as a loader would have); at its end IN (7B) gives
	; the ROM back and the next fetch is the ROM again (cash_off). Only the cache holds what the code writes:
	; the self-modifying parts work only from the cache.
	ds	PAY-5-$,0
cash_on:
	ld	bc,P_CASH1
	in	a,(c)
	assert	$ == PAY

	; the cache code: video RAM writes (ZX screen, attributes, graphics page 50 + palette bytes, page 54), sums of
	; the DRAM copies
	OUTP	P_AGR, #00		; AGR[7..6] = 0: writes to 4000-5FFF go to the video RAM too
	OUTP	P_W1, #05
	ld	hl,#4000
	ld	e,#3c
	ld	b,4
	call	fillc			; 4000..4003 = L xor 3C
	ld	hl,#5800
	ld	e,#47
	ld	b,2
	call	fillc			; 5800..5801 = L xor 47
	ld	hl,#4000
	ld	b,4
	call	sumc
	LOG
	ld	hl,#5800
	ld	b,2
	call	sumc
	LOG
	OUTP	P_AGR, #10		; graphics line 10
	OUTP	P_W1, #50		; page 50: DRAM + video RAM
	ld	hl,#4000
	ld	e,#c3
	ld	b,4
	call	fillc			; 4000..4003 = L xor C3
	ld	hl,#43f8
	ld	e,#81
	ld	b,8
	call	fillc			; 43F8..43FF = L xor 81: palette bytes of line 10
	ld	hl,#4000
	ld	b,4
	call	sumc
	LOG
	ld	hl,#43f8
	ld	b,8
	call	sumc
	LOG
	OUTP	P_W1, #54		; page 54: video RAM only (checked by the testbench)
	ld	hl,#4100
	ld	e,#99
	ld	b,4
	call	fillc
	OUTP	P_W1, #05
	jr	cache2
fillc:	ld	a,l			; (HL..) = L xor E, B bytes
	xor	e
	ld	(hl),a
	inc	hl
	djnz	fillc
	ret
sumc:	xor	a			; A = the sum of B bytes from HL
sc1:	add	a,(hl)
	inc	hl
	djnz	sc1
	ret
	; the fastram itself
cache2:	ld	(#1f00),sp		; two writes 3 T apart, one word
	ld	hl,#2000		; 2000..200F = L xor 5A: writes from code in the cache
	ld	b,16
cf1:	ld	a,l
	xor	#5a
	ld	(hl),a
	inc	hl
	djnz	cf1
	ld	hl,#2000
	ld	b,16
	xor	a
cs1:	add	a,(hl)
	inc	hl
	djnz	cs1
	LOG
	ld	hl,tpl			; a routine copied inside the cache (LDIR: read, write, read ...)
	ld	de,#1800
	ld	bc,tpl_len
	ldir
	ld	sp,#3000
	ld	hl,#1234
	push	hl			; 2FFF / 2FFE: one word
	ld	sp,#2fff
	ld	de,#5678
	push	de			; 2FFE / 2FFD: two words
	ld	de,0
	pop	bc			; 5678
	ld	sp,#2ffe
	pop	hl			; 1256: 12 from 2FFF (first push), 56 from 2FFE (second)
	ld	d,b
	ld	e,c
	ld	bc,P_LOG
	ld	a,d
	out	(c),a			; 56
	ld	a,e
	out	(c),a			; 78
	ld	a,h
	out	(c),a			; 12
	ld	a,l
	out	(c),a			; 56
	ld	sp,#2f00
	call	#1800			; the copied routine: CALL = two writes 3 T apart, EX (SP),HL twice
	out	(c),a			; A from the routine: C5
	ld	hl,#2008		; read-modify-write
	inc	(hl)
	inc	(hl)
	ld	a,(hl)
	out	(c),a			; 08 xor 5A + 2 = 54
	align	2
	nop
	ld	a,#a7
	ld	(smc1+1),a		; the write, then the fetch of the other byte of its word, then the byte
smc1:	ld	a,#00
	assert	(smc1 & 1) == 0
	out	(c),a			; A7
	ld	a,#3c			; INC A
	ld	(smc2),a		; the written byte fetched at once as the opcode
smc2:	nop
	out	(c),a			; 3D
	align	2
	ld	a,#5b
	ld	(smc3+1),a		; the operand in the next word
smc3:	ld	a,#00
	assert	(smc3 & 1) == 1
	out	(c),a			; 5B
	ld	hl,#2000		; a loop from the cache: 34 T (c_f rotates)
	ld	b,16
	xor	a
	ld	c,a
lp:	add	a,(hl)
	xor	b
	inc	c
	inc	hl
	djnz	lp
	LOG
	ld	sp,(#1f00)		; the stack again: the two bytes written first
	ld	bc,P_CASH0
	in	a,(c)			; the ROM back in window 0
cash_off:				; the ROM after the cache code
	ld	a,(smc2)		; the ROM byte (00 = NOP), not the 3C written into the cache
	LOG
	ld	a,#e3
	jp	theend
tpl:	ex	(sp),hl			; (copied to 1800 in the cache) read-modify-write of the return address, twice
	ex	(sp),hl
	ld	a,#c5
	ret
tpl_len	equ	$-tpl
	assert	$ <= #2000
