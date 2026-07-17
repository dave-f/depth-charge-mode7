\ ---------------------------------------------------------------------------
\ Sixel routines + sprite blitter. Screen is Mode 7 at &7C00: 40x25 chars =
\ 80x75 sixels, 2x3 per cell. Sixel bits within a graphics char: TL=1 TR=2
\ ML=4 MR=8 BL=16 BR=64 (bit 5 skipped — always set, blank graphics is &A0).
\
\ Interface from BASIC (user zero page):
\   ?&70 = x sixel 0-79 (2-79 usable; col 0 holds the row colour code)
\   ?&71 = y sixel 0-74, or char row 0-24 for initrow
\   ?&72 = initrow: teletext colour code 145-151;  sprite ops: sprite id
\   ?&73 = initrow only: 0 = plain row; else a graphics colour code
\          145-151 used as the row background (cols 0-2 become codes:
\          bg colour, new-background, then ?&72 -> playfield from x=6)
\ Entry points (jump table at load address):
\   +0 initrow  +3 plot  +6 unplot  +9 sprite draw  +12 sprite erase
\   +15 sprite move (opaque: sets 1-bits AND clears 0-bits in one pass —
\       no blank interim state, so far less tearing than erase+draw; pad
\       art keeps it self-erasing for 1-sixel moves)
\   +18 object walker: one call integrates and redraws every active slot
\ No clipping: sprites must lie fully on screen.
\
\ Object table (20 slots of 16 bytes at objtab; poke from BASIC):
\   +0 status: 0 free, 1 active, 2 expired (walker sets 2 after erasing;
\      BASIC handles then clears). Walker INCs objevt per expiry, so
\      BASIC needs just one PEEK per frame to notice.
\   +1 sprite id           +2/+3  x lo/hi (8.8 fixed, hi = sixel)
\   +4/+5 y lo/hi          +6/+7  vx lo/hi (signed 8.8, <1 sixel/frame)
\   +8/+9 vy lo/hi         +10/+11 last drawn sixel x/y (255 = never)
\   +12/+13 xmin/xmax      +14/+15 ymin/ymax (sixel, inclusive)
\ Objects whose sixel position leaves the min/max box expire. A parked
\ object (vx=vy=0) still redraws if BASIC pokes its x/y hi byte — that is
\ how the ship is steered.
\
\ Sprite format: EQUB width, height, then height rows of CEIL(width/8)
\ bytes, MSB first (leftmost sixel = bit 7). 1 = plot, 0 = transparent
\ (draw/erase) or background (move). Movers carry a blank pad column each
\ side — and pad rows above/below if they move vertically — so an opaque
\ move at the new position wipes the trailing edge of the old.
\ ---------------------------------------------------------------------------

zpx    = &70
zpy    = &71
zparg  = &72        \ initrow colour / sprite id
zpmode = &73        \ blitter: 0 = draw, 1 = opaque move, &FF = erase
zprow  = &74        \ &74/&75: row base pointer
zpptr  = &76        \ &76/&77: sprite header pointer (setup only)
zpw    = &78        \ sixels left in current sprite row
zph    = &79        \ sprite rows left
zpbuf  = &7A        \ sprite bit buffer
zpbit  = &7B        \ bits left in buffer before refetch
zpm0   = &7C        \ mask for even x column at current sixel row
zpm1   = &7D        \ mask for odd x column
zpodd  = &7E        \ current column parity
zpcy   = &7F        \ current y sixel
zpwm   = &80        \ sprite width
zpslot = &81        \ &81/&82: walker's current slot pointer
zpcnt  = &83        \ walker: slots remaining
zpnx   = &84        \ walker: this frame's sixel x
zpny   = &85        \ walker: this frame's sixel y

NSLOTS   = 20
SLOTSIZE = 16

.start
    JMP initrow
    JMP plot
    JMP unplot
    JMP sprdraw
    JMP sprerase
    JMP sprmove
    JMP objwalk

.objevt
    EQUB 0          \ count of expiries since BASIC last cleared it
    EQUB 0, 0       \ pad so objtab lands on a round address
.objtab
    SKIP NSLOTS * SLOTSIZE

ASSERT objevt = &7715
ASSERT objtab = &7718

.initrow                \ colour code(s) at the left, blank graphics after
    LDY zpy
    LDA rowlo,Y
    STA zprow
    LDA rowhi,Y
    STA zprow+1
    LDY #0
    LDA zpmode          \ background wanted? prefix its colour + code 157
    BEQ initplain
    STA (zprow),Y
    INY
    LDA #157            \ new background (= current foreground)
    STA (zprow),Y
    INY
.initplain
    LDA zparg
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

\ --- sprite blitter -------------------------------------------------------

.sprdraw
    LDA #0
    BEQ sprgo
.sprerase
    LDA #&FF
    BNE sprgo
.sprmove
    LDA #1
.sprgo
    STA zpmode
    LDA zparg           \ sprite id -> header address
    ASL A
    TAX
    LDA sprtab,X
    STA zpptr
    LDA sprtab+1,X
    STA zpptr+1
    LDY #0
    LDA (zpptr),Y
    STA zpwm
    INY
    LDA (zpptr),Y
    STA zph
    CLC                 \ point the fetcher at the bitmap (header + 2)
    LDA zpptr
    ADC #2
    STA sprfetch+1
    LDA zpptr+1
    ADC #0
    STA sprfetch+2
    LDA zpy
    STA zpcy
.sprrow
    LDX zpcy            \ row base + even/odd mask pair for this sixel row
    LDY ydiv3,X
    LDA rowlo,Y
    STA zprow
    LDA rowhi,Y
    STA zprow+1
    LDA ymod3,X
    ASL A
    TAX
    LDA masks,X
    STA zpm0
    LDA masks+1,X
    STA zpm1
    LDA zpx
    LSR A               \ char col; carry = x AND 1
    TAY
    LDA #0
    ROL A
    STA zpodd
    LDA zpwm
    STA zpw
    LDA #0              \ empty buffer: rows are byte-aligned
    STA zpbit
.sprbit
    DEC zpbit
    BPL sprnofetch
.sprfetch
    LDA &FFFF           \ operand patched in sprgo, then walks the bitmap
    STA zpbuf
    INC sprfetch+1
    BNE sprfetched
    INC sprfetch+2
.sprfetched
    LDA #7
    STA zpbit
.sprnofetch
    ASL zpbuf
    PHP                 \ carry = this sixel's bit
    LDX zpodd
    BNE sproddmask
    LDA zpm0
    BNE sprhavemask     \ masks are never zero: always taken
.sproddmask
    LDA zpm1
.sprhavemask
    PLP
    BCS sprbitset
    LDX zpmode          \ 0-bit: only opaque move writes (clears)
    CPX #1
    BEQ sprclear
    BNE sprskip
.sprbitset
    LDX zpmode          \ 1-bit: draw/move set, erase clears
    BEQ sprset
    CPX #1
    BEQ sprset
.sprclear
    EOR #&FF
    AND (zprow),Y
    STA (zprow),Y
    JMP sprskip
.sprset
    ORA (zprow),Y
    STA (zprow),Y
.sprskip
    LDA zpodd           \ advance one sixel column
    EOR #1
    STA zpodd
    BNE sprsamecell
    INY
.sprsamecell
    DEC zpw
    BNE sprbit
    INC zpcy            \ next sprite row
    DEC zph
    BEQ sprdone
    JMP sprrow
.sprdone
    RTS

\ --- object walker --------------------------------------------------------

.objwalk
    LDA #LO(objtab)
    STA zpslot
    LDA #HI(objtab)
    STA zpslot+1
    LDA #NSLOTS
    STA zpcnt
.owloop
    LDY #0
    LDA (zpslot),Y
    CMP #1
    BEQ owactive
    JMP ownext
.owactive
    CLC                 \ x += vx (signed 8.8)
    LDY #2
    LDA (zpslot),Y
    LDY #6
    ADC (zpslot),Y
    LDY #2
    STA (zpslot),Y
    LDY #3
    LDA (zpslot),Y
    LDY #7
    ADC (zpslot),Y
    LDY #3
    STA (zpslot),Y
    STA zpnx
    CLC                 \ y += vy
    LDY #4
    LDA (zpslot),Y
    LDY #8
    ADC (zpslot),Y
    LDY #4
    STA (zpslot),Y
    LDY #5
    LDA (zpslot),Y
    LDY #9
    ADC (zpslot),Y
    LDY #5
    STA (zpslot),Y
    STA zpny
    LDA zpnx            \ out of the bounds box -> expire
    LDY #12
    CMP (zpslot),Y
    BCC owexpire
    LDY #13
    LDA (zpslot),Y
    CMP zpnx
    BCC owexpire
    LDA zpny
    LDY #14
    CMP (zpslot),Y
    BCC owexpire
    LDY #15
    LDA (zpslot),Y
    CMP zpny
    BCC owexpire
    LDY #10             \ redraw only if the sixel position changed
    LDA (zpslot),Y
    CMP zpnx
    BNE owdraw
    LDY #11
    LDA (zpslot),Y
    CMP zpny
    BNE owdraw
    JMP ownext
.owdraw
    LDA zpnx
    STA zpx
    LDY #10
    STA (zpslot),Y
    LDA zpny
    STA zpy
    LDY #11
    STA (zpslot),Y
    LDY #1
    LDA (zpslot),Y
    STA zparg
    LDA #1              \ opaque move: pad self-erases 1-sixel steps
    JSR sprgo
    JMP ownext
.owexpire
    LDY #10
    LDA (zpslot),Y
    CMP #&FF
    BEQ owfree          \ never drawn: nothing to erase
    STA zpx
    LDY #11
    LDA (zpslot),Y
    STA zpy
    LDY #1
    LDA (zpslot),Y
    STA zparg
    LDA #&FF
    JSR sprgo           \ erase at last drawn position
.owfree
    LDY #0
    LDA #2
    STA (zpslot),Y
    INC objevt
.ownext
    CLC
    LDA zpslot
    ADC #SLOTSIZE
    STA zpslot
    BCC owsame
    INC zpslot+1
.owsame
    DEC zpcnt
    BEQ owdone
    JMP owloop
.owdone
    RTS

\ --- tables ---------------------------------------------------------------

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

\ --- sprites --------------------------------------------------------------
\ Movers are padded with blank edge columns/rows (see header comment), so
\ the drawn position is the pad's top-left, one sixel up/left of the ink.

\ Art ported from the PICO-8 cart (depth.p8) at 5/8 scale, hand-pixelled:
\ silhouettes pooled, detail (funnels, taper, portholes) redrawn at sixel
\ scale. Sub porthole rows distinguish the three score types; the original
\ uses one sub sprite for both directions, so we do too. Charge and mine
\ are 1:1 with the source art.

.sprtab
    EQUW sprship        \ 0: ship, pad cols each side
    EQUW sprsub0        \ 1: sub type 0 (20 pts), pad cols each side
    EQUW sprsub1        \ 2: sub type 1 (50 pts)
    EQUW sprsub2        \ 3: sub type 2 (80 pts)
    EQUW sprcharge      \ 4: depth charge, pad rows above/below
    EQUW sprmine        \ 5: mine, pad rows above/below

.sprship
    EQUB 22, 5
    EQUB %00000000, %01101100, %00000000   \ .........##.##........
    EQUB %01111111, %11111111, %11111000   \ .####################.
    EQUB %01111111, %11111111, %11111000   \ .####################.
    EQUB %00111111, %11111111, %11110000   \ ..##################..
    EQUB %00001111, %11111111, %11000000   \ ....##############....

.sprsub0
    EQUB 17, 7
    EQUB %00000000, %10000000, %00000000   \ ........#........
    EQUB %00000000, %10000000, %00000000   \ ........#........
    EQUB %00011111, %11111100, %00000000   \ ...###########...
    EQUB %00111111, %11111110, %00000000   \ ..#############..
    EQUB %01111101, %01011111, %00000000   \ .#####.#.#.#####.
    EQUB %01111111, %11111111, %00000000   \ .###############.
    EQUB %00111111, %11111110, %00000000   \ ..#############..

.sprsub1
    EQUB 17, 7
    EQUB %00000000, %10000000, %00000000   \ ........#........
    EQUB %00000000, %10000000, %00000000   \ ........#........
    EQUB %00011111, %11111100, %00000000   \ ...###########...
    EQUB %00111111, %11111110, %00000000   \ ..#############..
    EQUB %01111010, %10101111, %00000000   \ .####.#.#.#.####.
    EQUB %01111111, %11111111, %00000000   \ .###############.
    EQUB %00111111, %11111110, %00000000   \ ..#############..

.sprsub2
    EQUB 17, 7
    EQUB %00000000, %10000000, %00000000   \ ........#........
    EQUB %00000000, %10000000, %00000000   \ ........#........
    EQUB %00011111, %11111100, %00000000   \ ...###########...
    EQUB %00111111, %11111110, %00000000   \ ..#############..
    EQUB %01111110, %00111111, %00000000   \ .######...######.
    EQUB %01111111, %11111111, %00000000   \ .###############.
    EQUB %00111111, %11111110, %00000000   \ ..#############..

.sprcharge
    EQUB 2, 6
    EQUB %00000000                         \ ..
    EQUB %11000000                         \ ##
    EQUB %11000000                         \ ##
    EQUB %11000000                         \ ##
    EQUB %11000000                         \ ##
    EQUB %00000000                         \ ..

.sprmine
    EQUB 3, 5
    EQUB %00000000                         \ ...
    EQUB %10100000                         \ #.#
    EQUB %01000000                         \ .#.
    EQUB %10100000                         \ #.#
    EQUB %00000000                         \ ...
.end
