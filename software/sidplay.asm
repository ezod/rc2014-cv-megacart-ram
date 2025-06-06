; SID Dump Player for CP/M on RC2014
;
; Loads a SID register dump (25 register bytes per frame @ 50hz) into the
; MegaCart RAM module and plays it on a SID module.
;
; Use https://github.com/ezod/siddump with -b to dump a .sid file.
;
; Some RC2014 SID module options:
;     https://rc2014.co.uk/modules/sid-ulator-sound-module/
;     https://2014.samcoupe.com/#sidinterface

BOOT:       equ 0           ; boot location
BDOS:       equ 5           ; BDOS entry point
FCB:        equ $5c         ; file control block
FCBCR:      equ FCB+$20     ; FCB current record
BUFF:       equ $80         ; DMA buffer
WRITEC:     equ 2           ; BDOS print character function
WRITESTR:   equ 9           ; BDOS print string function
FOPEN:      equ 15          ; BDOS open file function
FCLOSE:     equ 16          ; BDOS close file function
FREAD:      equ 20          ; BDOS sequential read function

BIOSLEN:    equ $2000       ; length of BIOS

MCRPORT:    equ $0f         ; megacart RAM I/O port
SLOTBASEL:  equ $bfe0       ; slot 0 read address (lower)

SID_ADDR    equ $d4         ; SID address port
SID_DATA    equ $d5         ; SID data port
SID_REGS    equ 25          ; number of SID registers

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

    call    LOAD            ; load file

    ld      a,0             ; disable lower bank switching
    out     (MCRPORT),a

    ld      sp,(OLDSP)      ; restore stack pointer
    ret                     ; return to CP/M

LOAD:
    ld      hl,SLOTBASEL    ; initialize slot 1
    inc     hl
    ld      (SLOT),hl

    ld      de,LOADING      ; print loading message
    ld      c,WRITESTR
    call    BDOS

    ld      a,1             ; enable lower bank switching
    out     (MCRPORT),a

LOAD_OLOOP:
    ld      a,127           ; set record count to 127 (16KB minus one record)
    ld      (RCOUNT),a

    ld      hl,(SLOT)       ; set lower bank slot with dummy read
    ld      a,(hl)

    ld      de,$8000        ; set destination to lower 16KB bank
    ld      (DEST),de

LOAD_ILOOP:
    ld      de,FCB          ; read from file
    ld      c,FREAD
    call    BDOS
    or      a
    jr      nz,LOAD_EOF

    ld      hl,BUFF         ; copy from DMA buffer to destination
    ld      de,(DEST)
    ld      bc,$80
    ldir

    ld      (DEST),de       ; increment next destination address

    ld      a,(RCOUNT)      ; read up to 16KB minus one record
    dec     a
    ld      (RCOUNT),a
    jr      nz,LOAD_ILOOP

    ld      e,'.'           ; print slot load character
    ld      c,WRITEC
    call    BDOS

    ld      de,(SLOT)       ; increment slot
    inc     de
    ld      a,e             ; done if slot LSB rolls over to 0
    cp      $00
    jr      z,LOAD_EOF
    ld      (SLOT),de
    jr      LOAD_OLOOP

LOAD_EOF:
    ld      de,(SLOT)       ; store EOF slot
    ld      (EOF_SLOT),de

    ld      e,CR            ; print carriage return and linefeed
    ld      c,WRITEC
    call    BDOS
    ld      e,LF
    ld      c,WRITEC
    call    BDOS

    ld      de,FCB          ; close the file
    ld      c,FCLOSE
    call    BDOS

    ld      de,SUCCESS      ; tell user that file was loaded
    ld      c,WRITESTR
    call    BDOS

PLAY:
    ld      hl,SLOTBASEL    ; initialize slot 1
    inc     hl
    ld      (SLOT),hl

    ld      hl,(SLOT)       ; set lower bank slot with dummy read
    ld      a,(hl)

    ld      hl,$8000        ; playback start address

PLAY_FRAME:
    ld      b,0             ; SID register index

FRAME_LOOP:
    ld      a,b             ; set current SID register index
    out     (SID_ADDR),a

    ld      a,(hl)          ; output SID register data
    out     (SID_DATA),a

    inc     b               ; next SID register

    inc     hl              ; next data address
    ld      a,h
    cp      $bf
    jr      nz,FRAME_END    ; h < $bf, continue
    ld      a,l
    cp      $b0
    jr      nz,FRAME_END    ; h = $bf and l < $b0, continue
    ld      hl,(SLOT)       ; next slot
    inc     hl
    ld      (SLOT),hl
    ld      a,(hl)
    ld      hl,$8000        ; start at bottom of next slot

    ld      e,'.'           ; print slot play character
    ld      c,WRITEC
    call    BDOS

FRAME_END:
    ld      a,b
    cp      SID_REGS
    jr      nz,FRAME_LOOP

    call    DELAY

    ld      de,(EOF_SLOT)   ; loop if not on the EOF slot
    ld      c,e
    ld      de,(SLOT)
    ld      a,e
    cp      c
    jr      nz,PLAY_FRAME

    ld      de,(DEST)       ; loop if not at the EOF address
    ld      a,h
    cp      d
    jr      nz,PLAY_FRAME
    ld      a,l
    cp      e
    jr      nz,PLAY_FRAME

PLAY_END:
    ld      e,CR            ; print carriage return and linefeed
    ld      c,WRITEC
    call    BDOS
    ld      e,LF
    ld      c,WRITEC
    call    BDOS

    ld      b,SID_REGS-1    ; playback complete, silence SID
SILENCE:
    ld      a,b
    out     (SID_ADDR),a
    xor     a
    out     (SID_DATA),a
    djnz    SILENCE    

    ret

DELAY:
    ld      d,71
DELAY_OL:
    ld      e,71
DELAY_IL:
    dec     e               ; 4 cycles
    jr      nz,DELAY_IL     ; 10 cycles
    dec     d               ; 4 cycles
    jp      nz,DELAY_OL     ; 10 cycles
    ret

BADFILE:
    ld      de,NOFILE       ; print error if file is not found
    ld      c,WRITESTR
    call    BDOS
    ld      sp,(OLDSP)      ; restore stack pointer
    ret                     ; return to CP/M

NOFILE:     db  "file not found",CR,LF,EOS
LOADING:    db  "loading file...",CR,LF,EOS
SUCCESS:    db  "file loaded, playing...",CR,LF,EOS

SLOT:       dw  1           ; slot pointer
DEST:       dw  $8000       ; destination pointer
RCOUNT:     db  0           ; record counter
EOF_SLOT    dw  1           ; EOF slot
OLDSP:      dw  0           ; original stack pointer
            ds  $40         ; space for stack
STACK:                      ; top of stack
