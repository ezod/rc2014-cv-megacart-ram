; ColecoVision Game Loader for CP/M on RC2014
;
; Works with RomWBW 512K RAM/ROM Board
; Incompatible with 64KB Pageable ROM Board due to port conflicts
;
; Assemble with sjasm. ColecoVision BIOS ROM must be in "coleco.rom"
; in the same directory where loader.asm is assembled.
;
; CP/M file loader code from https://github.com/MMaciocia/RC2014-YM2149
; Modified to load ColecoVision games by J.B. Langston

BOOT:		equ	0			; boot location
BDOS:		equ	5			; BDOS entry point
FCB:		equ	$5c			; file control block
FCBCR:		equ	FCB+$20			; FCB current record
FCBRN:		equ	FCB+$21			; FCB random access record number
BUFF:		equ	$80			; DMA buffer
WRITEC:		equ	2			; BDOS print character function
WRITESTR:	equ	9			; BDOS print string function
FOPEN:		equ	15			; BDOS open file function
FCLOSE:		equ	16			; BDOS close file function
FREAD:		equ	20			; BDOS sequential read function
FSIZE:		equ	35			; BDOS compute file size function

BIOSLEN: 	equ	$2000			; length of BIOS

MCRPORT:	equ	$0f			; megacart RAM I/O port
SLOTBASEL:	equ	$bfe0			; slot 0 read address (lower)
SLOTBASEU:	equ	$ffe0			; slot 0 read address (upper)

CR:		equ	$0d			; carriage return
LF:		equ	$0a			; line feed
EOS:		equ	'$'			; end of string marker

		org 	$0100

		ld	(OLDSP),sp		; save old stack pointer
		ld	sp,STACK		; set new stack pointer

		ld	de,FCB			; try to open file
		ld	c,FOPEN
		call	BDOS
		inc	a			; 255 indicates failure
		jp	z,BADFILE
		xor	a			; clear current record
		ld	(FCBCR),a

		ld	de,FCB			; compute file size
		ld	c,FSIZE
		call	BDOS
		ld	hl,(FCBRN)
		dec	hl
		ld	a,h
		cp	1
		jp	c,REGULAR		; no bank switching necessary for < 32KB

		ld	de,28
		cp	2
		jr	c,MEGACART		; 64KB megacart
		ld	de,24
		cp	4
		jr	c,MEGACART		; 128KB megacart
		ld	de,16
		cp	8
		jr	c,MEGACART		; 256KB megacart
		ld	de,0
		ld	hl,SLOT0		; slot 0 (containing CP/M) to be overwritten
		ld	(hl),1
		cp	16
		jr	c,MEGACART		; 512KB megacart

		ld	de,LGFILE		; print error if file is too large
		ld	c,WRITESTR
		call	BDOS
		ld	sp,(OLDSP)		; restore stack pointer
		ret				; return to CP/M

MEGACART:
		ld	(SLOTF),de		; store first slot offset

		ld	hl,SLOTBASEL		; initialize slot
		add	hl,de
		ld	(SLOT),hl

		ld	de,LOADMC		; print loading message
		ld	c,WRITESTR
		call	BDOS

		ld	a,1			; enable lower bank switching
		out	(MCRPORT),a

MEGACART_OLOOP:
		ld	hl,(SLOT)		; set lower bank slot with dummy read
		ld	de,(hl)

		ld	a,128			; set record count to 128 (16KB)
		ld	(RCOUNT),a

		ld	de,GAMEADDR		; set destination to GAMEADDR for slot 0
		ld	(DEST),de
		ld	a,l
		cp	$e0
		jr	z,MEGACART_ILOOP

		ld	de,$8000		; set destination to lower 16KB bank
		ld	(DEST),de

MEGACART_ILOOP:
		ld	de,FCB			; read from file
		ld	c,FREAD
		call	BDOS
		or	a
		jr	nz,MEGACART_EOF

		ld	hl,BUFF			; copy from DMA buffer to destination
		ld	de,(DEST)
		ld	bc,$80
		ldir

		ld	(DEST),de		; increment next destination address

		ld	a,(RCOUNT)		; read up to 16KB
		dec	a
		ld	(RCOUNT),a
		jr	nz,MEGACART_ILOOP

		ld	e,'.'			; print slot load character
		ld	c,WRITEC
		call	BDOS

		ld	de,(SLOT)		; increment slot
		inc	de
		ld	a,d			; done if slot MSB rolls over to C
		cp	$c0
		jr 	z,MEGACART_EOF
		ld	(SLOT),de
		jr	MEGACART_OLOOP

MEGACART_EOF:
		ld	e,CR			; print carriage return and linefeed
		ld	c,WRITEC
		call	BDOS
		ld	e,LF
		ld	c,WRITEC
		call	BDOS

		ld	de,FCB			; close the file
		ld	c,FCLOSE
		call	BDOS

		ld	a,0			; disable lower bank switching
		out	(MCRPORT),a

		ld	a,($8000)		; verify magic number
		cp	$55
		jr	z,MEGACART_55
		cp	$aa
		jr	z,MEGACART_AA
MEGACART_55:
		ld	a,($8001)
		cp	$aa
		jr	z,MEGACART_LOADED
		jr	MEGACART_FAIL
MEGACART_AA:
		ld	a,($8001)
		cp	$55
		jr	z,MEGACART_LOADED
		jr	MEGACART_FAIL

MEGACART_LOADED:
		ld	de,SUCCESS		; tell user that game was loaded
		ld	c,WRITESTR
		call	BDOS

		di				; don't need interrupts anymore

		ld	a,2			; enable upper bank switching
		out	(MCRPORT),a

		ld	de,(SLOTF)		; set upper bank to first slot with dummy read
		ld	hl,SLOTBASEU
		add	hl,de
		ld	de,(hl)

		ld	a,(SLOT0)		; check if this is a 512KB ROM
		or	a
		jr	z,MEGACART_CVBIOS

		ld 	bc,$4000		; move first 16KB of 512KB ROM to slot 0
		ld 	hl,GAMEADDR+$4000-1
		ld 	de,$ffff
		lddr

MEGACART_CVBIOS:
		ld 	bc,BIOSLEN		; copy ColecoVision BIOS to $0000-$1FFF
		ld 	hl,BIOS
		ld 	de,BOOT
		ldir

		jp 	BOOT			; jump to BIOS entry point

MEGACART_FAIL:
		ld	de,MEGACARTERR
		ld	c,WRITESTR
		call 	BDOS
		ld	sp,(OLDSP)		; restore stack pointer
		ret				; return to CP/M

REGULAR:
		ld	de,LOADRG		; print loading message
		ld	c,WRITESTR
		call	BDOS

		ld	de,GAMEADDR		; set destination address
		ld	(DEST),de

REGULAR_LOOP:
		ld	de,FCB			; read from file
		ld	c,FREAD
		call	BDOS
		or	a
		jr	nz,REGULAR_EOF

		ld	hl,BUFF			; copy from DMA buffer to destination
		ld	de,(DEST)
		ld	bc,$80
		ldir
		ld	(DEST),de		; increment next destination address
		jr	REGULAR_LOOP

REGULAR_EOF:
		ld	de,FCB			; close the file
		ld	c,FCLOSE
		call	BDOS

		ld	de,SUCCESS		; tell user that game was loaded
		ld	c,WRITESTR
		call	BDOS

		di				; don't need interrupts anymore

		ld 	bc,$8000		; copy game to $8000-$FFFF
		ld 	hl,GAMEADDR+$8000-1
		ld 	de,$ffff
		lddr

		ld 	bc,BIOSLEN		; copy ColecoVision BIOS to $0000-$1FFF
		ld 	hl,BIOS
		ld 	de,BOOT
		ldir

		jp 	BOOT			; jump to BIOS entry point

BADFILE:
		ld	de,NOFILE		; print error if file is not found
		ld	c,WRITESTR
		call	BDOS
		ld	sp,(OLDSP)		; restore stack pointer
		ret				; return to CP/M

NOFILE:		db 	"file not found",CR,LF,EOS
LGFILE:		db	"file too large",CR,LF,EOS
LOADRG:		db	"loading regular game",CR,LF,EOS
LOADMC:		db	"loading MegaCart game",CR,LF,EOS
MEGACARTERR:	db	"error loading MegaCart",CR,LF,EOS
SUCCESS:	db	"game loaded",CR,LF,EOS

SLOT0:		db	0			; set for 512KB ROM (has slot 0 content)
SLOTF:		dw	0			; first slot offset
SLOT:		dw	0			; slot pointer
DEST:		dw	GAMEADDR		; destination pointer
RCOUNT:		db	0			; record counter
OLDSP:		dw	0			; original stack pointer
		ds	$40			; space for stack
STACK:						; top of stack

BIOS:
		incbin "coleco.rom"		; include ColecoVision BIOS in program

GAMEADDR:					; temporarily load game at end of program
