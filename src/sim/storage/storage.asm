; storage.asm: the test program of tb_storage (sjasmplus --raw), put into ROM page 8 of the BIOS 3.04 image (the
; page the configured ACEX starts from; the BIOS loader at 0x30000 still pours the bitstream). It fills the port
; table (DRAM page 0x40, window 3 while STARTING = 0) with the descriptors of the IDE, WD1793 and system ports as
; the BIOS does (docs/mame.md: codes 10-17, 20-29, 2A / 2B), then:
;   IDE (primary channel = HDD2, OUT (#21BC)): READ SECTORS of LBA 0 on the master (an INI chain with BC = #0050:
;   B = 00 the word, B = FF the latched high byte, as HDRIVER6), the status of the absent slave and of the empty
;   secondary channel (HDD1);
;   FDD (command / status at #0F as FDRIVER2: #1F is also the PIO B control of the Z84C15, whose internal
;   read wins): drive A (1.44 MB image, 2 MHz: OUT (#21BD)) seek track 79, side 1, sector 18; drive B (720 KB or TRD, 1 MHz:
;   OUT (#01BD)) track 79, side 1, sector 9; drive A again at the wrong rate (720 KB): no INTRQ / DRQ in a timeout.
; Results: OUT (#01) = a data byte, OUT (#02) = a marker (the testbench reads the CPU pins; port table code 00).
; No CALL before the stack page is known: the stack is in window 2 (page 02).

	macro	LOGA			; log A
	out	(#01),a
	endm
	macro	MARK n
	ld	a,n
	out	(#02),a
	endm
	; one descriptor: idx = the offset in page 0x40 without DOS (bit 10), both DOS values written
	macro	PT1 idx, code
	ld	(#c000 + (idx)),a
	ld	(#c400 + (idx)),a
	endm
	; ... for all A15 / A14 / A13 (bits 8, 7, 4)
	macro	PTA idx, code
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
	; ... for all A15 / A13, A14 as given (the IDE registers: A14 selects 1F2-1F5 / 1F6-1F7)
	macro	PTB idx, code
	ld	a,code
	PT1	(idx), code
	PT1	(idx) | #010, code
	PT1	(idx) | #100, code
	PT1	(idx) | #110, code
	endm
RD	equ	#200			; /WR = 1: a read
A14	equ	#080
	; IDE status poll: wait for BSY = 0 (then A = status)
	macro	IDE_NBSY
.w	ld	bc,#4053
	in	a,(c)
	bit	7,a
	jr	nz,.w
	endm

	org	0
main	di
	ld	sp,#bff0
	; ---- the port table: index {CNF4 CNF3 PN5 DOS /WR A15 A14 A6 A5 A13 A7 A2 A1 A0}
	; IDE: data (any A15..A13), registers 1F1-1F5 (A14 = 0), 1F6 / 1F7 / 3F6 / 3F7 (A14 = 1)
	PTA	RD | #040, #20
	PTA	#040, #20
	PTB	RD | #041, #21
	PTB	RD | #042, #22
	PTB	RD | #043, #23
	PTB	RD | #044, #24
	PTB	RD | #045, #25
	PTB	RD | A14 | #042, #26
	PTB	RD | A14 | #043, #27
	PTB	RD | A14 | #044, #28
	PTB	RD | A14 | #045, #29
	PTB	#041, #21
	PTB	#042, #22
	PTB	#043, #23
	PTB	#044, #24
	PTB	#045, #25
	PTB	A14 | #042, #26
	PTB	A14 | #043, #27
	PTB	A14 | #044, #28
	; WD1793 1F / 3F / 5F / 7F (A7 = 0, A2..A0 = 111, A6 A5 = register), #FF (A7 A6 A5 = 111)
	PTA	RD | #007, #10
	PTA	RD | #027, #11
	PTA	RD | #047, #12
	PTA	RD | #067, #13
	PTA	RD | #06f, #15
	PTA	#007, #10
	PTA	#027, #11
	PTA	#047, #12
	PTA	#067, #13
	PTA	#06f, #14
	; #01BD / #21BD: 720 / 1440 (A13); #01BC / #21BC: HDD1 / HDD2 (A13)
	ld	a,#16
	PT1	#02d, #16
	ld	a,#17
	PT1	#03d, #17
	ld	a,#2a
	PT1	#02c, #2a
	ld	a,#2b
	PT1	#03c, #2b
	; the accelerator part (docs/memtiming.md 8): ALL_MODE (C3) at #204E, read of #204E = code 00 (nobody drives D),
	; the line port (C4) at #89, window 1 (E9) at #A2
	ld	a,#c3
	PT1	#056, #c3
	xor	a
	PT1	RD | #056, #00
	PTA	#009, #c4
	PTA	#02a, #e9
	; the first IN ends STARTING (the descriptors are used from now on)
	xor	a
	in	a,(#03)
	MARK	#10

	; ================= IDE
	ld	bc,#21bc		; HDD2 = primary
	out	(c),a
	IDE_NBSY
	LOGA				; status of the master (image: 50)
	ld	bc,#4152
	ld	a,#e0			; LBA, master
	out	(c),a
	ld	bc,#0152
	ld	a,1
	out	(c),a
	ld	bc,#0153
	xor	a
	out	(c),a
	ld	bc,#0154
	out	(c),a
	ld	bc,#0155
	out	(c),a
	ld	bc,#0052		; read back the count (TEST_HDD_DRV of the BIOS): reads at A8 = 0
	in	a,(c)
	LOGA
	ld	bc,#4153
	ld	a,#20			; READ SECTORS
	out	(c),a
.drq	ld	bc,#4053
	in	a,(c)
	bit	7,a
	jr	nz,.drq
	LOGA				; status at DRQ (58)
	bit	3,a
	jp	z,.ide_err
	ld	hl,#8000
	ld	bc,#0050
	ld	e,0
.rd	ini
	ini
	dec	e
	jr	nz,.rd
	ld	bc,#4053
	in	a,(c)
	LOGA				; status after the block (50)
	MARK	#11
	ld	hl,#8000
	ld	de,512
.lg	ld	a,(hl)
	LOGA
	inc	hl
	dec	de
	ld	a,d
	or	e
	jr	nz,.lg
	MARK	#12
	; WRITE SECTORS of LBA 1 (an OUTI chain with BC = #0150 as HDRIVER6: OUTI puts B - 1 on A8..A15, B = 00 the
	; low byte into the latch, B = FF the word), then READ SECTORS of LBA 1 back
	ld	hl,#8000
	ld	de,0
.fill	ld	a,e
	xor	d
	xor	#a5
	add	a,d
	ld	(hl),a
	inc	hl
	inc	de
	bit	1,d
	jr	z,.fill
	ld	a,1
	ld	bc,#0153
	out	(c),a
	ld	bc,#0152
	out	(c),a
	ld	bc,#4153
	ld	a,#30			; WRITE SECTORS
	out	(c),a
.wdrq	ld	bc,#4053
	in	a,(c)
	bit	7,a
	jr	nz,.wdrq
	LOGA				; status at DRQ (58)
	ld	hl,#8000
	ld	bc,#0150
	ld	e,0
.wro	outi
	outi
	dec	e
	jr	nz,.wro
.wbsy	ld	bc,#4053
	in	a,(c)
	bit	7,a
	jr	nz,.wbsy
	LOGA				; status after the write (50)
	ld	hl,#8000		; clear the buffer
	ld	de,#8001
	ld	bc,511
	ld	(hl),0
	ldir
	ld	a,1
	ld	bc,#0152
	out	(c),a
	ld	bc,#4153
	ld	a,#20
	out	(c),a
.rdrq	ld	bc,#4053
	in	a,(c)
	bit	7,a
	jr	nz,.rdrq
	LOGA
	ld	hl,#8000
	ld	bc,#0050
	ld	e,0
.rd1	ini
	ini
	dec	e
	jr	nz,.rd1
	MARK	#13
	ld	hl,#8000
	ld	de,512
.lg1	ld	a,(hl)
	LOGA
	inc	hl
	dec	de
	ld	a,d
	or	e
	jr	nz,.lg1
	MARK	#14
	; the slave: no image -> 00
	ld	bc,#4152
	ld	a,#f0
	out	(c),a
	ld	bc,#4053
	in	a,(c)
	LOGA
	ld	bc,#0052
	in	a,(c)
	LOGA
	; the secondary channel: no device -> 00
	ld	bc,#01bc
	out	(c),a
	ld	bc,#4053
	in	a,(c)
	LOGA
	ld	bc,#21bc
	out	(c),a
	ld	bc,#4152
	ld	a,#e0
	out	(c),a
	jr	.fdd
.ide_err
	MARK	#1e

	; ================= FDD
.fdd	MARK	#20
	ld	a,#3c			; drive A, side 0, /MR = 1
	out	(#ff),a
	ld	a,#21			; 1.44 MB
	out	(#bd),a
	ld	d,79
	ld	e,#2c			; drive A, side 1
	ld	a,18
	ld	ix,.fa
	jp	fdd_read
.fa	MARK	#21
	ld	a,#3d			; drive B
	out	(#ff),a
	ld	a,#01			; 720 KB
	out	(#bd),a
	ld	d,79
	ld	e,#2d			; drive B, side 1
	ld	a,9
	ld	ix,.fb
	jp	fdd_read
.fb	MARK	#22
	; drive A at the wrong rate: Read Address, no INTRQ / DRQ within the timeout
	ld	a,#3c
	out	(#ff),a
	ld	a,#c0
	out	(#0f),a
	ld	hl,#0800
.wr	in	a,(#ff)
	and	#c0
	jr	nz,.wr_seen
	dec	hl
	ld	a,h
	or	l
	jr	nz,.wr
	MARK	#23			; timeout: as a real drive at the wrong rate
	jr	.wr_ok
.wr_seen
	MARK	#2e
.wr_ok	ld	a,#21			; back to 1.44: Read Address works
	out	(#bd),a
	ld	a,#c0
	out	(#0f),a
.ra	in	a,(#ff)
	and	#c0
	jr	z,.ra
	jp	p,.ra_drq
	MARK	#2f			; INTRQ without data
	jr	.end
.ra_drq	ld	b,6
	ld	c,#7f
	ld	hl,#8000
.ra1	in	a,(#ff)
	and	#c0
	jr	z,.ra1
	jp	m,.ra2
	in	a,(c)
	ld	(hl),a
	inc	hl
	djnz	.ra1
.ra2	MARK	#24
	ld	hl,#8000
	ld	b,4			; C, H, R, N of the ID
.ra3	ld	a,(hl)
	LOGA
	inc	hl
	djnz	.ra3
.end	MARK	#30
	; ================= an undriven data bus (pull-ups D0..D7) and the accelerator, as BIOS 3.04 does around its
	; ZX screen output (IN of ALL_MODE, AND #FE, OUT, then the saved value back) before Flex Navigator draws with
	; the vertical fill: the IN must give FF, else the restore turns the accelerator off (docs/memtiming.md 8)
	ld	bc,#204e
	in	a,(c)
	LOGA				; FF
	ld	e,a
	and	#fe
	out	(c),a
	ld	a,e
	out	(c),a			; ALL_MODE = the value read: FF, accelerator on
	ld	a,#50
	out	(#a2),a			; window 1 = graphics page 50
	ld	hl,#8100
	ld	a,8
	ld	d,d			; the counter: 8
	ld	(hl),a
	ld	b,b
	ld	a,#20
	out	(#89),a			; line 20
	ld	hl,#4000
	ld	a,#5a
	ld	e,e			; vertical fill: 4000 on lines 20..27 = 5A
	ld	(hl),a
	ld	b,b
	ld	d,#20
.vl	ld	a,d
	out	(#89),a
	ld	a,(#4000)
	LOGA				; 5A x 8
	inc	d
	bit	3,d
	jr	z,.vl
	MARK	#ff
	halt

; read one sector: D track, E the system register for it (drive, side), A sector; returns to IX. Logs the status of the seek, the byte count, the
; status at the end and the bytes.
fdd_read
	ld	(#bf00),a
.nb	in	a,(#0f)			; not busy
	rrca
	jr	c,.nb
	ld	a,d
	out	(#7f),a
	ld	a,#18			; SEEK
	out	(#0f),a
.si	in	a,(#ff)
	rlca
	jr	nc,.si
	in	a,(#0f)
	LOGA
	in	a,(#3f)			; the track register
	LOGA
	ld	a,e			; the system register: drive, side
	out	(#ff),a
	ld	a,(#bf00)
	out	(#5f),a
	ld	hl,#8000
	ld	c,#7f
	ld	a,#80			; READ SECTOR
	out	(#0f),a
.w	in	a,(#ff)
	and	#c0
	jr	z,.w
	jp	m,.done
	ini
	jr	.w
.done	in	a,(#0f)
	LOGA
	ld	de,#8000
	or	a
	sbc	hl,de
	ld	a,h
	LOGA
	ld	a,l
	LOGA
	ld	b,h
	ld	c,l
	ld	hl,#8000
.lg	ld	a,(hl)
	LOGA
	inc	hl
	dec	bc
	ld	a,b
	or	c
	jr	nz,.lg
	jp	(ix)
