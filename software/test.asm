BOOT:       equ 0           ; boot location
BDOS:       equ 5           ; BDOS entry point
WRITEC:     equ 2           ; BDOS print character function
WRITESTR:   equ 9           ; BDOS print string function

MCRPORT:    equ $0f         ; megacart RAM I/O port
SLOTBASEL:  equ $bfe0       ; slot 0 read address (lower)

CR:         equ $0d         ; carriage return
LF:         equ $0a         ; line feed
SPACE:      equ $20         ; space
EOS:        equ '$'         ; end of string marker

    org     $0100

    ld      (OLDSP),sp      ; save old stack pointer
    ld      sp,STACK        ; set new stack pointer

    ld      de,LOWERMSG
    ld      c,WRITESTR
    call    BDOS

    ld      a,1             ; enable lower bank switching
    out     (MCRPORT),a

    ld      de,SLOTBASEL
    ld      (SLOT),de

LOWER_WLOOP:
    ld  hl,(SLOT)           ; set slot with dummy read
    ld  a,(hl)

    ld      a,l             ; set a value
    call    PRINTA
    ld      ($8000),a
    ld      a,($8000)
    call    PRINTA
    ld      e,CR
    ld      c,WRITEC
    call    BDOS
    ld      e,LF
    ld      c,WRITEC
    call    BDOS

    ld      de,(SLOT)       ; increment the slot
    inc     de
    ld      (SLOT),de
    ld      a,d
    cp      $c0
    jr      nz,LOWER_WLOOP

    ld      de,SLOTBASEL
    ld      (SLOT),de

LOWER_RLOOP:
    ld      hl,(SLOT)       ; set slot with dummy read
    ld      a,(hl)

    ld      a,($8000)       ; read and check value
    call    COMPARE
    ld      de,(SLOT)       ; increment the slot
    inc     de
    ld      (SLOT),de
    ld      a,d
    cp      $c0
    jr      nz,LOWER_RLOOP

    ld      a,0             ; disable bank switching
    out     (MCRPORT),a

    ei                      ; re-enable interrupts

    ld      sp,(OLDSP)
    rst     $00

COMPARE:
    push    hl
    push    af
    ld      a,l
    call    PRINTA
    pop     af
    call    PRINTA
    pop     hl
    cp      l
    jr      z,CMP_PASS
    ld      de,FAIL
    ld      c,WRITESTR
    call    BDOS
    jr      CMP_RET
CMP_PASS:
    ld      de,PASS
    ld      c,WRITESTR
    call    BDOS
CMP_RET:
    ret

PRINTA:
    push    af
    push    af
    rra
    rra
    rra
    rra
    and     $0f
    add     a,$30
    cp      $3a
    jr      c,PRINTA_M
    add     a,7
PRINTA_M:
    ld      e,a
    ld      c,WRITEC
    call    BDOS
    pop     af
    and     $0f
    add     a,$30
    cp      $3a
    jr      c,PRINTA_L
    add     a,7
PRINTA_L:
    ld      e,a
    ld      c,WRITEC
    call    BDOS
    ld      e,SPACE
    ld      c,WRITEC
    call    BDOS
    pop     af
    ret

LOWERMSG:   db  "Testing lower banks...",CR,LF,EOS
PASS:       db  "PASS",CR,LF,EOS
FAIL:       db  "FAIL",CR,LF,EOS

SLOT:       dw  0           ; slot pointer
OLDSP:      dw  0           ; original stack pointer
            ds  $40         ; space for stack
STACK:                      ; top of stack
