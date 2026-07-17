\ Depth Charge (Mode 7) — disc image build script for BeebAsm.
\ Game logic is BBC BASIC (game.bas, tokenised via PUTBASIC); the sixel
\ routines below are assembled to PLOT and *LOADed by the BASIC.

\ ---------------------------------------------------------------------------
\ Sixel routines. Screen is Mode 7 at &7C00: 40x25 chars = 80x75 sixels,
\ 2x3 per cell. Sixel bits within a graphics char: TL=1 TR=2 ML=4 MR=8
\ BL=16 BR=64 (bit 5 skipped — always set, so blank graphics is &A0).
\
\ Interface from BASIC (user zero page):
\   ?&70 = x sixel 0-79 (2-79 usable; col 0 holds the colour code)
\   ?&71 = y sixel 0-74, or char row 0-24 for initrow
\   ?&72 = teletext colour code 145-151 for initrow
\ Entry points: CALL &7A00 initrow, &7A03 plot, &7A06 unplot
\ ---------------------------------------------------------------------------

zpx   = &70
zpy   = &71
zpcol = &72
zprow = &74             \ &74/&75: pointer to row base in screen RAM

ORG &7A00
GUARD &7C00             \ don't run into screen memory

.start
    JMP initrow
    JMP plot
    JMP unplot

.initrow                \ colour code at col 0, blank graphics across the rest
    LDY zpy
    LDA rowlo,Y
    STA zprow
    LDA rowhi,Y
    STA zprow+1
    LDY #0
    LDA zpcol
    STA (zprow),Y
    LDA #&A0
.initloop
    INY
    STA (zprow),Y
    CPY #39
    BNE initloop
    RTS

.calc                   \ -> A = sixel mask, Y = char col, (zprow) = row base
    LDX zpy
    LDY ydiv3,X
    LDA rowlo,Y
    STA zprow
    LDA rowhi,Y
    STA zprow+1
    LDA ymod3,X
    ASL A
    TAX
    LDA zpx
    LSR A               \ char col; carry = x AND 1
    TAY
    BCC calceven
    INX
.calceven
    LDA masks,X
    RTS

.plot
    JSR calc
    ORA (zprow),Y
    STA (zprow),Y
    RTS

.unplot
    JSR calc
    EOR #&FF
    AND (zprow),Y       \ clears our bit; &A0 base bits survive the mask
    STA (zprow),Y
    RTS

.rowlo
FOR n, 0, 24
    EQUB LO(&7C00+n*40)
NEXT
.rowhi
FOR n, 0, 24
    EQUB HI(&7C00+n*40)
NEXT
.ydiv3
FOR n, 0, 74
    EQUB INT(n/3)
NEXT
.ymod3
FOR n, 0, 74
    EQUB n-3*INT(n/3)
NEXT
.masks
    EQUB 1,2,4,8,16,64
.end

SAVE "PLOT", start, end

\ ---------------------------------------------------------------------------

PUTBASIC "src/game.bas", "MAIN"

\ Boot with CHAIN, not beebasm's -boot (which *RUNs — wrong for a BASIC file)
PUTTEXT "src/boot.txt", "!Boot", 0, 0
