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
BUFF:		equ	$80			; DMA buffer
WRITESTR:	equ	9			; BDOS print string function
FOPEN:		equ	15			; BDOS open file function
FCLOSE:		equ	16			; BDOS close file function
FREAD:		equ	20			; BDOS sequential read function
FSIZE:		equ	35			; BDOS compute file size function

GAMETOP:	equ	$ffff			; top of game cartridge location
GAMELEN:	equ	$8000			; length of game cartridge
BIOSLEN: 	equ	$2000			; length of BIOS

CR:		equ	$0d			; carriage return
LF:		equ	$0a			; line feed
EOS:		equ	'$'			; end of string marker

		org 	$0100

		ld	(OLDSP),sp		; save old stack pointer
		ld	sp,STACK		; set new stack pointer

		ld	de,FCB			; try to open file specified on command line
		ld	c,FOPEN
		call	BDOS
		inc	a			; 255 indicates failure
		jr	z,BADFILE
		ld	a,0			; clear current record
		ld	(FCBCR),a
		ld	de,GAMEADDR		; set destination address
		ld	(DEST),de

LOOP:
		ld	de,FCB			; read from file
		ld	c,FREAD
		call	BDOS
		or	a
		jr	nz,EOF			; non-zero accumulator means EOF

		ld	hl,BUFF			; copy from DMA buffer to destination
		ld	de,(DEST)
		ld	bc,$80
		ldir
		ld	(DEST),de		; increment next destination address
		jr	LOOP

EOF:	
		ld	de,FCB			; close the file
		ld	c,FCLOSE
		call	BDOS

		ld	de,SUCCESS		; tell user that game was loaded
		ld	c,WRITESTR
		call	BDOS
		jp	RUNGAME			; copy the game to the final location and run

BADFILE:	
		ld	de,NOFILE		; print error if file is not found
		ld	c,WRITESTR
		call	BDOS
		ld	sp,(OLDSP)		; restore stack pointer
		ret				; return to CP/M

NOFILE:		defb 	"file not found",CR,LF,EOS
SUCCESS:	defb	"game loaded",CR,LF,EOS

DEST:		defw	GAMEADDR		; destination pointer
OLDSP:		defw	0			; original stack pointer
 		defs	$40			; space for stack
STACK:						; top of stack

BIOS:	
		incbin "coleco.rom"		; include ColecoVision BIOS in program
RUNGAME:	
		di				; don't need interrupts anymore

		ld 	bc,GAMELEN		; copy game to $8000-$FFFF
		ld 	hl,GAMEADDR+GAMELEN-1
		ld 	de,GAMETOP
		lddr

		ld 	bc,BIOSLEN		; copy ColecoVision BIOS to $0000-$1FFF
		ld 	hl,BIOS	
		ld 	de,BOOT	
		ldir	

		jp 	BOOT			; jump to BIOS entry point
GAMEADDR:					; temporarily load game at end of program
