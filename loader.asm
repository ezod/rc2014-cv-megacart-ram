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
WRITESTR:	equ	9			; BDOS print string function
FOPEN:		equ	15			; BDOS open file function
FCLOSE:		equ	16			; BDOS close file function
FREAD:		equ	20			; BDOS sequential read function
FSIZE:		equ	35			; BDOS compute file size function

BIOSLEN: 	equ	$2000			; length of BIOS

MCRPORT:	equ	$2f			; megacart RAM I/O port
SLOTBASE:	equ	$ffe0			; slot 0 read address

CR:		equ	$0d			; carriage return
LF:		equ	$0a			; line feed
EOS:		equ	'$'			; end of string marker

		org 	$0100

		ld	(OLDSP),sp		; save old stack pointer
		ld	sp,STACK		; set new stack pointer

		ld	de,FCB			; try to compute file size
		ld	c,FSIZE
		call	BDOS
		inc	a			; 255 indicates failure
		jp	z,BADFILE
		ld	hl,(FCBRN)
		dec	hl
		ld	a,h
		cp	1
		jp	c,REGULAR		; no bank switching necessary for < 32KB

		ld	de,SLOTBASE+28
		cp	2
		jr	c,MEGACART		; 64KB megacart
		ld	de,SLOTBASE+24
		cp	4
		jr	c,MEGACART		; 128KB megacart
		ld	de,SLOTBASE+16
		cp	8
		jr	c,MEGACART		; 256KB megacart
		ld	de,SLOTBASE
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
		ld	(SLOT),de		; store initial slot offset

		ld	a,1			; enable lower bank switching
		out	(MCRPORT),a

		ld	de,FCB			; open file
		ld	c,FOPEN
		call	BDOS
		xor	a			; clear current record
		ld	(FCBCR),a

MEGACART_OLOOP:
		ld	hl,(SLOT)		; set lower bank slot with dummy read
		ld	de,(hl)

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
		jr	MEGACART_ILOOP

		ld	de,(SLOT)

		ld	a,e 			; if this is slot 0, skip moving data
		cp	$e0
		jr	nz,MEGACART_NEXT

MEGACART_NEXT:
		inc	de			; next slot

		ld	a,e			; done if slot LSB rolls over to 0
		or	a
		jr 	z,MEGACART_EOF

		ld	(SLOT),de
		jr	MEGACART_OLOOP

MEGACART_EOF:
		ld	de,FCB			; close the file
		ld	c,FCLOSE
		call	BDOS

		ld	de,SUCCESS		; tell user that game was loaded
		ld	c,WRITESTR
		call	BDOS

		di				; don't need interrupts anymore

		ld	a,2			; enable upper bank switching
		out	(MCRPORT),a
		ld	hl,SLOTBASE		; set upper bank to slot 0 with dummy read
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

REGULAR:
		ld	de,FCB			; open file
		ld	c,FOPEN
		call	BDOS
		xor	a			; clear current record
		ld	(FCBCR),a
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
SUCCESS:	db	"game loaded",CR,LF,EOS

SLOT0:		db	0			; set for 512KB ROM (has slot 0 content)
SLOT:		dw	0			; slot pointer
DEST:		dw	GAMEADDR		; destination pointer
OLDSP:		dw	0			; original stack pointer
		ds	$40			; space for stack
STACK:						; top of stack

BIOS:
		incbin "coleco.rom"		; include ColecoVision BIOS in program

GAMEADDR:					; temporarily load game at end of program
