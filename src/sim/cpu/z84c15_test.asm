; z84c15_test.asm: the program of tb_z84c15 (sjasmplus --raw). It reads and writes the internal ports of sp_z84c15
; and sends what it read to the testbench log port #80; the testbench compares the log with its list.
; Testbench ports (external): OUT #80 = log, OUT #81 = end, OUT #82 = command (1 feed SIO A 11 22 33 44, 2 the
; same without waiting for RDY 55 66 77 88, 3 feed SIO B 0F 8F, 4 INT until INTA, 5 / 6 Z80 clock 3.5 / 21 MHz,
; 7 feed SIO A 99, 8 / 9 / 10 ZC/TO0 period checks: counter / timer / off, 11 CTC interrupt period check), OUT #84 = log with a range check
; (1..45). IN from an external port gives port xor #A5; the INTA data on the bus is 00.
	org	0
	di
	ld	sp,#8000
	jp	main

	ds	#38-$,0
im1:	push	af
	ld	a,#38
	out	(#80),a
	pop	af
	ei
	ret

	ds	#100-$,0
main:
	; ---- 1. external ports
	in	a,(#55)			; F0
	out	(#80),a
	ld	bc,#3355
	in	a,(c)			; F0
	out	(#80),a

	; ---- 2. SCRP / SCDP: reset values, CSBR / MCR, the chip selects
	ld	b,0
scr1:	ld	a,b
	out	(#ee),a
	in	a,(#ef)			; 00 F0 FF 01 FF
	out	(#80),a
	inc	b
	ld	a,b
	cp	5
	jr	nz,scr1
	in	a,(#ee)			; 04
	out	(#80),a
	ld	a,(#feee)		; CS0 (reset: CSBR FF, MCR 01)
	ld	a,2
	out	(#ee),a
	ld	a,#fe
	out	(#ef),a
	ld	a,3
	out	(#ee),a
	out	(#ef),a			; MCR 03
	in	a,(#ef)			; 03
	out	(#80),a
	ld	a,2
	out	(#ee),a
	in	a,(#ef)			; FE
	out	(#80),a
	ld	a,(#0eee)		; CS0
	ld	a,(#eeee)		; CS0
	ld	a,(#feee)		; CS1
	ld	a,#f0
	out	(#ef),a			; CSBR F0
	ld	a,(#0eee)		; CS0
	ld	a,(#1eee)		; CS1
	ld	a,(#feee)		; CS1
	ld	a,3
	out	(#ee),a
	ld	a,1
	out	(#ef),a			; MCR 01
	ld	a,(#1eee)		; none
	ld	a,2
	out	(#ee),a
	ld	a,#ff
	out	(#ef),a			; CSBR FF

	; ---- 3. SIO A
	ld	hl,sioa_init
	ld	bc,#0919		; 9 bytes to #19
	otir
	in	a,(#19)			; RR0 44
	out	(#80),a
	ld	a,1
	out	(#82),a			; feed 11 22 33 44
	call	delay
	in	a,(#19)			; 45
	out	(#80),a
	in	a,(#18)			; 11
	out	(#80),a
	in	a,(#18)			; 22
	out	(#80),a
	in	a,(#18)			; 33
	out	(#80),a
	in	a,(#18)			; 44 (held by the feed until there was room)
	out	(#80),a
	in	a,(#19)			; 44
	out	(#80),a
	ld	a,1
	out	(#19),a
	in	a,(#19)			; RR1 01
	out	(#80),a
	ld	a,2
	out	(#82),a			; 55 66 77 88 without RDY: overrun
	call	delay
	ld	a,1
	out	(#19),a
	in	a,(#19)			; RR1 21
	out	(#80),a
	in	a,(#18)			; 55
	out	(#80),a
	in	a,(#18)			; 66
	out	(#80),a
	in	a,(#18)			; 88
	out	(#80),a
	in	a,(#19)			; 44
	out	(#80),a
	ld	a,#30
	out	(#19),a			; error reset
	ld	a,1
	out	(#19),a
	in	a,(#19)			; 01
	out	(#80),a
	ld	a,3
	out	(#19),a
	ld	a,#c0
	out	(#19),a			; Rx off
	ld	a,7
	out	(#82),a			; feed 99: dropped
	call	delay
	in	a,(#19)			; 44
	out	(#80),a
	ld	a,3
	out	(#19),a
	ld	a,#c1
	out	(#19),a

	; ---- SIO B: 7 bits, CTS = printer busy
	ld	hl,siob_init
	ld	bc,#091b
	otir
	xor	a
	out	(#1b),a
	ld	a,#10
	out	(#1b),a
	xor	a
	out	(#1b),a
	in	a,(#1b)			; RR0 64
	out	(#80),a
	ld	a,3
	out	(#82),a			; feed 0F 8F
	call	delay
	in	a,(#1b)			; 65
	out	(#80),a
	in	a,(#1a)			; 8F (7 bits: bit 7 = 1)
	out	(#80),a
	in	a,(#1a)			; 8F
	out	(#80),a
	ld	a,2
	out	(#1b),a
	ld	a,#5a
	out	(#1b),a			; WR2 5A
	ld	a,2
	out	(#1b),a
	in	a,(#1b)			; RR2 5A
	out	(#80),a

	; ---- 4. PIO
	ld	a,#cf
	out	(#1d),a
	ld	a,#f0
	out	(#1d),a			; A: mode 3, 7-4 in
	ld	a,#5a
	out	(#1c),a
	in	a,(#1c)			; (3C & F0) | (5A & 0F) = 3A
	out	(#80),a
	ld	a,#0f
	out	(#1d),a			; mode 0
	in	a,(#1c)			; 5A
	out	(#80),a
	in	a,(#1d)			; FF
	out	(#80),a
	ld	bc,#001f		; B through OUT (C) as the BIOS does (port 1F)
	ld	a,#cf
	out	(c),a
	ld	a,#3f
	out	(c),a
	ld	c,#1e
	ld	a,#c0
	out	(c),a
	in	a,(c)			; (15 & 3F) | (C0 & C0) = D5
	out	(#80),a

	; ---- 5. WDT ports
	in	a,(#f0)			; FF
	out	(#80),a
	in	a,(#f4)			; FF
	out	(#80),a

	; ---- 6. CTC0: counter 55 / 2D (as DSS MS_INIT), then timer x16, constant 16
	ld	a,#55
	out	(#10),a
	ld	a,#2d
	out	(#10),a
	ld	a,9
	out	(#82),a			; check the counter period
	call	delay
	in	a,(#10)			; 1..45
	out	(#84),a
	ld	b,24
ctc1:	call	delay
	djnz	ctc1
	ld	a,#07
	out	(#10),a			; timer, x16, constant follows, reset
	ld	a,#10
	out	(#10),a
	ld	a,10
	out	(#82),a			; check the timer period
	ld	b,10
ctc2:	call	delay
	djnz	ctc2
	ld	a,8
	out	(#82),a
	ld	a,#03
	out	(#10),a			; stop

	; ---- 7. interrupts: IM 1, IM 2 with vector FF
	im	1
	ei
	ld	a,4
	out	(#82),a
	halt				; -> 38
	ld	a,#01
	out	(#80),a
	di
	ld	hl,im2ok
	ld	(#90ff),hl
	ld	hl,im2bad
	ld	(#9000),hl
	ld	a,#90
	ld	i,a
	im	2
	ei
	ld	a,4
	out	(#82),a
	halt				; -> 22
	ld	a,#02
	out	(#80),a
	di
	im	1

	; ---- 9. CTC interrupts as uwol / TMNT set them (docs/z84c15.md 1.1): CTC2 counter on CLK/TRG2 (875 kHz)
	; -> ZC/TO2 -> CLK/TRG3, CTC3 counter with interrupt, vector base 00 to channel 0 (channel 3 -> vector 06),
	; IM 2. Constants 2 x 5 instead of 70 x A0 (period 10 x 96 CLK, the testbench checks it). The handler returns
	; through CALL to EI / RETI as TMNT: a second and a third interrupt need RETI to clear the in-service bit.
	ld	hl,im2bad
	ld	(#9100),hl
	ld	(#9102),hl
	ld	(#9104),hl
	ld	hl,ctcint
	ld	(#9106),hl
	ld	hl,im2ok
	ld	(#91ff),hl
	xor	a
	ld	(#9200),a
	ld	a,#91
	ld	i,a
	im	2
	ld	a,#57
	out	(#12),a
	ld	a,2
	out	(#12),a
	ld	a,#d7
	out	(#13),a
	ld	a,5
	out	(#13),a
	xor	a
	out	(#10),a			; vector 00
	ld	a,11
	out	(#82),a
	ei
	halt				; -> ctcint (33)
	halt
	halt
	di
	ld	a,#03
	out	(#13),a			; channel 3: interrupt off, reset
	ld	a,8
	out	(#82),a
	ei
	ld	b,8
ctc3:	call	delay			; no more CTC interrupts
	djnz	ctc3
	ld	a,4
	out	(#82),a
	halt				; external INT: vector FF -> im2ok (22)
	di
	ld	a,(#9200)
	out	(#80),a			; 3 CTC interrupts
	ld	a,#03
	out	(#12),a
	im	1

	; ---- 8. 3.5 MHz, memory with waits
	ld	a,5
	out	(#82),a
	in	a,(#55)			; F0
	out	(#80),a
	ld	hl,#4000
	ld	b,16
m1:	ld	(hl),l
	inc	hl
	djnz	m1
	ld	a,6
	out	(#82),a
	ld	hl,#4000
	ld	b,16
	xor	a
m2:	add	a,(hl)
	inc	hl
	djnz	m2
	out	(#80),a			; 0+1+..+15 = 78
	ld	a,(#5555)		; written by the testbench: 3C
	out	(#80),a
	in	a,(#18)			; nothing left in SIO A: RR0 44
	in	a,(#19)
	out	(#80),a
	out	(#81),a
	halt

im2ok:	push	af
	ld	a,#22
	out	(#80),a
	pop	af
	ei
	reti
im2bad:	push	af
	ld	a,#bb
	out	(#80),a
	pop	af
	ei
	reti

ctcint:	push	af
	ld	a,(#9200)
	inc	a
	ld	(#9200),a
	ld	a,#33
	out	(#80),a
	pop	af
	call	eireti
	ei
	ret
eireti:	ei
	reti

delay:	push	bc
	ld	b,40
dl1:	djnz	dl1
	pop	bc
	ret

sioa_init:	db	#18, 4, #05, 3, #c1, 5, #62, 1, 0	; channel reset, WR4 05, WR3 C1, WR5 62, WR1 00
siob_init:	db	#18, 4, #44, 3, #41, 5, #e0, 1, 0
