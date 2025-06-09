; SID Dump Player for CP/M on RC2014
;
; Plays SID register dumps in the following format:
;   - 3x 32 byte strings for title, author, and release
;   - SID register frames captured at 50hz:
;     - 2-byte bitfield indicating which register groups have changed
;       since the last frame
;     - the data for the changed register groups
;
; where the register groups are:
;
;   Bit   Registers       Function
;   ---   ---------       --------
;    0    $d400, $d401    frequency voice 1
;    1    $d402, $d403    pulse wave duty cycle voice 1
;    2    $d404           control register voice 1
;    3    $d405, $d406    ADSR voice 1
;    4    $d407, $d408    frequency voice 2
;    5    $d409, $d40a    pulse wave duty cycle voice 2
;    6    $d40b           control register voice 2
;    7    $d40c, $d40d    ADSR voice 2
;    8    $d40e, $d40f    frequency voice 3
;    9    $d410, $d411    pulse wave duty cycle voice 3
;   10    $d412           control register voice 3
;   11    $d413, $d414    ADSR voice 3
;   12    $d415, $d416    filter cutoff
;   13    $d417           filter resonance and routing
;   14    $d418           filter mode and main volume
;
; Use https://github.com/ezod/siddump with -b to dump a .sid file.
;
; Some RC2014 SID module options:
;     https://rc2014.co.uk/modules/sid-ulator-sound-module/
;     https://2014.samcoupe.com/#sidinterface
;
; This implementation depends on the MegaCart RAM module, but could be
; modified to use other bank-switching RAM or limited to small files.

BOOT:       equ 0           ; boot location
BDOS:       equ 5           ; BDOS entry point
FCB:        equ $5c         ; file control block
FCBCR:      equ FCB+$20     ; FCB current record
BUFF:       equ $80         ; DMA buffer
CONIO:      equ 6           ; BDOS console I/O function
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
SID_GRPS    equ 15          ; number of SID register groups

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
    ld      de,LOADING      ; print loading message
    ld      c,WRITESTR
    call    BDOS

    ld      a,1             ; enable lower bank switching
    out     (MCRPORT),a

    ld      hl,SLOTBASEL+1  ; initialize slot 1
    ld      (SLOT),hl

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
    jp      nz,LOAD_EOF

    ld      hl,BUFF         ; copy from DMA buffer to destination
    ld      de,(DEST)
    ld      bc,$80
    ldir

    ld      (DEST),de       ; increment next destination address

    ld      a,(RCOUNT)      ; read up to 16KB minus one record
    dec     a
    ld      (RCOUNT),a
    jp      nz,LOAD_ILOOP

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
    call    NEWLINE

    ld      de,(SLOT)       ; store EOF slot
    ld      (EOF_SLOT),de

    ld      de,FCB          ; close the file
    ld      c,FCLOSE
    call    BDOS

PLAY:
    ld      hl,SLOTBASEL+1  ; initialize slot 1
    ld      (SLOT),hl
    ld      a,(hl)          ; set lower bank slot with dummy read

    ld      de,TITLE
    ld      c,WRITESTR
    call    BDOS
    ld      hl,$8000
    call    PRINT_STRING

    ld      de,AUTHOR
    ld      c,WRITESTR
    call    BDOS
    ld      hl,$8020
    call    PRINT_STRING

    ld      de,RELEASED
    ld      c,WRITESTR
    call    BDOS
    ld      hl,$8040
    call    PRINT_STRING

    ld      hl,$8060        ; start of frame data

PLAY_NEXT:
    ld      bc,(EOF_SLOT)   ; loop if not on the EOF slot
    ld      a,(SLOT)
    cp      c
    jr      c,PLAY_FRAME

    ld      de,(DEST)       ; loop if not at the EOF address
    ld      a,h
    cp      d
    jr      c,PLAY_FRAME
    ld      a,l
    cp      e
    jr      c,PLAY_FRAME

PLAY_END:
    ld      b,SID_REGS-1    ; playback complete, silence SID
SILENCE:
    ld      a,b
    out     (SID_ADDR),a
    xor     a
    out     (SID_DATA),a
    djnz    SILENCE

    ret

PLAY_FRAME:
    ld      e,(hl)          ; read bitfield (LSB)
    call    INC_ADDR
    ld      d,(hl)          ;               (MSB)
    call    INC_ADDR

    ld      ix,GRP_START
    ld      iy,GRP_LEN
    ld      b,SID_GRPS

GROUP_LOOP:
    push    bc              ; preserve group counter

    srl     d
    rr      e
    jp      nc,GROUP_SKIP   ; if bit not set, skip this group

    ld      c,(ix)          ; C = starting SID register
    ld      a,(iy)
    ld      b,a             ; B = length

GROUP_WRITE:
    ld      a,c
    out     (SID_ADDR),a
    ld      a,(hl)
    out     (SID_DATA),a
    call    INC_ADDR
    inc     c
    djnz    GROUP_WRITE

GROUP_SKIP:
    inc     ix
    inc     iy
    pop     bc              ; restore group counter
    djnz    GROUP_LOOP

FRAME_END:
    push    hl
    ld      c,CONIO
    ld      e,$ff
    call    BDOS
    pop     hl
    cp      'q'
    jr      z,PLAY_END

DELAY:
    ld      d,66
DELAY_OL:
    ld      e,66
DELAY_IL:
    dec     e               ; 4 cycles
    jr      nz,DELAY_IL     ; 10 cycles
    dec     d               ; 4 cycles
    jp      nz,DELAY_OL     ; 10 cycles

    jr      PLAY_NEXT

INC_ADDR:
    inc     hl              ; next data address
    ld      a,h
    cp      $bf
    ret     nz
    ld      a,l
    cp      $80
    ret     nz
    ld      hl,(SLOT)       ; next slot
    inc     hl
    ld      (SLOT),hl
    ld      a,(hl)
    ld      hl,$8000        ; start at bottom of next slot
    ret

PRINT_STRING:
    ld      b,32            ; max 32 bytes
PRINT_LOOP:
    ld      a,(hl)          ; load next character
    or      a               ; check for null terminator
    jr      z,PRINT_END
    ld      e,a
    ld      c,WRITEC
    push    hl
    call    BDOS
    pop     hl
    inc     hl
    djnz    PRINT_LOOP
PRINT_END:
    call    NEWLINE
    ret

NEWLINE:
    ld      e,CR            ; print carriage return and linefeed
    ld      c,WRITEC
    call    BDOS
    ld      e,LF
    ld      c,WRITEC
    call    BDOS
    ret

BADFILE:
    ld      de,NOFILE       ; print error if file is not found
    ld      c,WRITESTR
    call    BDOS
    ld      sp,(OLDSP)      ; restore stack pointer
    ret                     ; return to CP/M

NOFILE:     db  "file not found",CR,LF,EOS
LOADING:    db  "loading file...",EOS

TITLE:      db "Title     : ",EOS
AUTHOR:     db "Author    : ",EOS
RELEASED:   db "Released  : ",EOS

GRP_START:  db 0,2,4,5,7,9,11,12,14,16,18,19,21,23,24
GRP_LEN:    db 2,2,1,2,2,2,1,2,2,2,1,2,2,1,1

SLOT:       dw  1           ; slot pointer
DEST:       dw  $8000       ; destination pointer
RCOUNT:     db  0           ; record counter
EOF_SLOT    dw  1           ; EOF slot
OLDSP:      dw  0           ; original stack pointer
            ds  $40         ; space for stack
STACK:                      ; top of stack
