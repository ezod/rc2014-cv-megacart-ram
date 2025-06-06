; ColecoVision Game Loader for CP/M on RC2014
;
; Works with RomWBW 512K RAM/ROM Board
; Incompatible with stock 64KB Pageable ROM Board due to port conflicts
; See https://github.com/jblang/TMS9918A/issues/12 for a hack!
;
; Assemble with sjasm. ColecoVision BIOS ROM must be in "coleco.rom"
; in the same directory where loader.asm is assembled.
;
; CP/M file loader code from https://github.com/MMaciocia/RC2014-YM2149
; Modified to load ColecoVision games by J.B. Langston
; MegaCart support and other enhancements by Aaron Mavrinac

BOOT:       equ 0           ; boot location
BDOS:       equ 5           ; BDOS entry point
FCB:        equ $5c         ; file control block
FCBCR:      equ FCB+$20     ; FCB current record
FCBRN:      equ FCB+$21     ; FCB random access record number
BUFF:       equ $80         ; DMA buffer
WRITEC:     equ 2           ; BDOS print character function
WRITESTR:   equ 9           ; BDOS print string function
FOPEN:      equ 15          ; BDOS open file function
FCLOSE:     equ 16          ; BDOS close file function
FREAD:      equ 20          ; BDOS sequential read function
FSIZE:      equ 35          ; BDOS compute file size function

BIOSLEN:    equ $2000       ; length of BIOS

MCRPORT:    equ $0f         ; megacart RAM I/O port
SLOTBASEL:  equ $bfe0       ; slot 0 read address (lower)
SLOTBASEU:  equ $ffe0       ; slot 0 read address (upper)

CR:         equ $0d         ; carriage return
LF:         equ $0a         ; line feed
EOS:        equ '$'         ; end of string marker

    org     $0100

    ld      (OLDSP),sp      ; save old stack pointer
    ld      sp,STACK        ; set new stack pointer

    ld      de,FCB          ; try to open file
    ld      c,FOPEN
    call    BDOS
    inc     a               ; 255 indicates failure
    jp      z,BADFILE
    xor     a               ; clear current record
    ld      (FCBCR),a

    ld      de,FCB          ; compute file size
    ld      c,FSIZE
    call    BDOS
    ld      hl,(FCBRN)
    dec     hl
    ld      a,h
    cp      1
    jp      c,REGULAR       ; no bank switching necessary for < 32KB

    ld      e,28
    cp      2
    jr      c,MEGACART      ; 64KB megacart
    ld      e,24
    cp      4
    jr      c,MEGACART      ; 128KB megacart
    ld      e,16
    cp      8
    jr      c,MEGACART      ; 256KB megacart
    ld      e,0
    cp      16
    jr      c,MEGACART      ; 512KB megacart

    ld      de,LGFILE       ; print error if file is too large
    ld      c,WRITESTR
    call    BDOS
    ld      sp,(OLDSP)      ; restore stack pointer
    ret                     ; return to CP/M

MEGACART:
    ld      a,e             ; store first slot offset
    ld      (SLOT0),a

    ld      hl,SLOTBASEL    ; initialize slot
    add     hl,de
    ld      (SLOT),hl

    ld      de,LOADMC       ; print loading message
    ld      c,WRITESTR
    call    BDOS

    ld      a,1             ; enable lower bank switching
    out     (MCRPORT),a

    ld      de,GAMEADDR     ; set destination to GAMEADDR for slot 0
    ld      (DEST),de

MEGACART_OLOOP:
    ld      a,128           ; set record count to 128 (16KB)
    ld      (RCOUNT),a

    ld      hl,(SLOT)       ; set lower bank slot with dummy read
    ld      a,(hl)

    ld      a,l             ; skip setting destination for slot 0
    cp      $e0
    jr      z,MEGACART_ILOOP

    ld      de,$8000        ; set destination to lower 16KB bank
    ld      (DEST),de

MEGACART_ILOOP:
    ld      de,FCB          ; read from file
    ld      c,FREAD
    call    BDOS
    or      a
    jr      nz,MEGACART_EOF

    ld      hl,BUFF         ; copy from DMA buffer to destination
    ld      de,(DEST)
    ld      bc,$80
    ldir

    ld      (DEST),de       ; increment next destination address

    ld      a,(RCOUNT)      ; read up to 16KB
    dec     a
    ld      (RCOUNT),a
    jr      nz,MEGACART_ILOOP

    ld      e,'.'           ; print slot load character
    ld      c,WRITEC
    call    BDOS

    ld      de,(SLOT)       ; increment slot
    inc     de
    ld      a,e             ; done if slot LSB rolls over to 0
    cp      $00
    jr      z,MEGACART_EOF
    ld      (SLOT),de
    jr      MEGACART_OLOOP

MEGACART_EOF:
    ld      e,CR            ; print carriage return and linefeed
    ld      c,WRITEC
    call    BDOS
    ld      e,LF
    ld      c,WRITEC
    call    BDOS

    ld      de,FCB          ; close the file
    ld      c,FCLOSE
    call    BDOS

    ld      a,0             ; disable lower bank switching
    out     (MCRPORT),a

    ld      a,($8000)       ; verify magic number
    cp      $55
    jr      z,MEGACART_55
    cp      $aa
    jr      z,MEGACART_AA
MEGACART_55:
    ld      a,($8001)
    cp      $aa
    jr      z,MEGACART_LOADED
    jr      MEGACART_FAIL
MEGACART_AA:
    ld      a,($8001)
    cp      $55
    jr      z,MEGACART_LOADED
    jr      MEGACART_FAIL

MEGACART_LOADED:
    ld      de,SUCCESS      ; tell user that game was loaded
    ld      c,WRITESTR
    call    BDOS

    di                      ; don't need interrupts anymore

    ld      a,(SLOT0)       ; enable upper bank switching with mirroring
    ld      d,0
    ld      e,a
    add     a,2
    out     (MCRPORT),a

    ld      hl,SLOTBASEU    ; set upper bank to first slot with dummy read
    add     hl,de
    ld      a,(hl)

    ld      a,e             ; check if this is a 512KB ROM
    or      a
    jr      nz,LB_BOOT      ; if not, load ColecoVision BIOS and boot

    ld      bc,$4000        ; move first 16KB of 512KB ROM to slot 0
    ld      hl,GAMEADDR+$4000-1
    ld      de,$ffff
    lddr

    jr      LB_BOOT         ; load ColecoVision BIOS and boot

MEGACART_FAIL:
    ld      de,MCERR
    ld      c,WRITESTR
    call    BDOS
    ld      sp,(OLDSP)      ; restore stack pointer
    ret                     ; return to CP/M

REGULAR:
    ld      de,LOADRG       ; print loading message
    ld      c,WRITESTR
    call    BDOS

    ld      de,GAMEADDR     ; set destination address
    ld      (DEST),de

REGULAR_LOOP:
    ld      de,FCB          ; read from file
    ld      c,FREAD
    call    BDOS
    or      a
    jr      nz,REGULAR_EOF

    ld      hl,BUFF         ; copy from DMA buffer to destination
    ld      de,(DEST)
    ld      bc,$80
    ldir
    ld      (DEST),de       ; increment next destination address
    jr      REGULAR_LOOP

REGULAR_EOF:
    ld      de,FCB          ; close the file
    ld      c,FCLOSE
    call    BDOS

    ld      de,SUCCESS      ; tell user that game was loaded
    ld      c,WRITESTR
    call    BDOS

    di                      ; don't need interrupts anymore

    ld      bc,$8000        ; copy game to $8000-$FFFF
    ld      hl,GAMEADDR+$8000-1
    ld      de,$ffff
    lddr

LB_BOOT:
    ld      bc,LB_END-LB    ; move BIOS load code up to GAMEADDR space
    ld      hl,LB           ; (so as not to overwrite it with BIOS)
    ld      de,GAMEADDR
    ldir

    jp      GAMEADDR        ; run BIOS load and boot

LB:
    ld      bc,BIOSLEN      ; copy ColecoVision BIOS to $0000-$1FFF
    ld      hl,BIOS
    ld      de,BOOT
    ldir
    jp      BOOT            ; jump to BIOS entry point
LB_END:     equ $

BADFILE:
    ld      de,NOFILE       ; print error if file is not found
    ld      c,WRITESTR
    call    BDOS
    ld      sp,(OLDSP)      ; restore stack pointer
    ret                     ; return to CP/M

NOFILE:     db  "file not found",CR,LF,EOS
LGFILE:     db  "file too large",CR,LF,EOS
LOADRG:     db  "loading regular game",CR,LF,EOS
LOADMC:     db  "loading MegaCart game",CR,LF,EOS
MCERR:      db  "error loading MegaCart",CR,LF,EOS
SUCCESS:    db  "game loaded",CR,LF,EOS

SLOT0:      db  0           ; first slot offset
SLOT:       dw  0           ; slot pointer
DEST:       dw  GAMEADDR    ; destination pointer
RCOUNT:     db  0           ; record counter
OLDSP:      dw  0           ; original stack pointer
            ds  $40         ; space for stack
STACK:                      ; top of stack

BIOS:
    incbin  "coleco.rom"    ; include ColecoVision BIOS in program

GAMEADDR:                   ; temporarily load game at end of program
