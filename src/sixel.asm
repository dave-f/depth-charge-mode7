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
\   +21 frame: the whole per-frame job for the game loop - waits until
\       two vsync events have passed (25Hz lock with a full 40ms budget;
\       two OSBYTE 19s would slip to 3 fields whenever BASIC's work ran
\       past one), flushes the keyboard buffer, scans the cursor keys,
\       Z, X and ESCAPE, steers the ship (slot 0 x +-0.75 sixel, clamped
\       6..57), lobs a charge off the port side on a Z press and the
\       starboard side on X (max 3 wet; airborne ones fall diagonally at
\       0.375 down / 0.5 out a frame until they reach the water row, then
\       sink straight down - the original's two fire buttons), rolls each sub's 1%/frame
\       mine launch, runs the game clock (secs counts down once every 25
\       frames), then falls into the walker. It keeps the HUD's TIME and
\       DC fields up to date itself (via hudnum) and reports the rest to
\       BASIC through frmflg and the event queue (see below).
\   +24 hudnum: ?&70 = column, ?&71 = row, &72/&73 = value 0-65535;
\       writes the decimal digits straight into screen memory, padded
\       with spaces to 5 cells (a BASIC PRINT TAB/STR$ costs ~10ms).
\   +27 subspawn: ?&70 = sub slot 1-3; (re)spawns a random sub there:
\       type 1-3, from the left or right edge, speed 10..57/256 a frame.
\       The walker calls the same code itself when a sub leaves or sinks.
\ No clipping: sprites must lie fully on screen.
\
\ Particles: single sixels, up to NPART at once, in their own table after
\ evq (see partplot/partage/puff). A charge hitting a sub puffs five from
\ the charge; a mine fizzling at the surface splashes three. They drift,
\ rise and die in 4-7 frames, taking each row's lane colour. Sharing cells
\ with the sprites, they are plotted at the end of every walk and unplotted
\ at the start of the next, with a "phantom" mark for a sixel a sprite had
\ already lit, so they never punch holes in the art. BASIC zeroes plife
\ (NPART bytes) in PROCwipe so a puff can't outlive its screen.
\
\ Frame bytes after the jump table (BASIC peeks/pokes these):
\   objevt  events queued since BASIC last cleared it; the codes are in
\           evq (after the object table, NSLOTS bytes): 1-3 a sub of that
\           type was sunk (score it), 5 a mine fizzled at the surface
\           (sound), 6 a mine hit the ship (death). Charges, sub expiry,
\           respawns and wreck effects never reach BASIC.
\   frmflg  set fresh by frame: bit 0 a charge was dropped (sound), bit 1
\           ESCAPE held, bit 2 the clock has run out
\   frmprv  last frame's key mask (BASIC zeroes it at game start)
\   frmkey  this frame's key mask (bits: 0 Z fire left, 1 cursor left,
\           2 cursor right, 3 ESCAPE, 4 X fire right)
\   vsync   vsync events since the last frame (bumped by evhandler)
\   nchg    charges in the water (0-3); BASIC shows 3-nchg on the HUD
\   evaddr  EQUW evhandler: BASIC copies it to EVNTV (&220) and enables
\           the vsync event with *FX14,4 (and *FX13,4 on the way out)
\   rng     16-bit LFSR state for spawns; BASIC seeds it (!rng = TIME OR 1,
\           a 4-byte poke that spills harmlessly into the pad after it)
\   spin    frames until the wet charges turn to their next pose: they
\           tumble end over end through four sprites (4, 6, 7, 8) every
\           SPINRATE frames, each starting at a random pose when it lands
\   secs    seconds left; BASIC sets 60 at the start, a kill adds 10 (max 255)
\   tick    frames until the next second (25)
\
\ Object table (20 slots of 16 bytes at objtab; poke from BASIC):
\   +0 status: 0 free, 1 active. The walker erases and frees an object
\      that expires or is hit, then acts by slot range: subs respawn,
\      charges decrement nchg and redraw DC, mines queue event 5 (expired)
\      or 6 (hit the ship), effects just go. BASIC only reads the queue.
\   +1 sprite id           +2/+3  x lo/hi (8.8 fixed, hi = sixel)
\   +4/+5 y lo/hi          +6/+7  vx lo/hi (signed 8.8, <1 sixel/frame)
\   +8/+9 vy lo/hi         +10/+11 last drawn sixel x/y (255 = never)
\   +12/+13 xmin/xmax      +14/+15 ymin/ymax (sixel, inclusive)
\ Objects whose sixel position leaves the min/max box expire. A parked
\ object (vx=vy=0) still redraws if BASIC pokes its x/y hi byte — that is
\ how the ship is steered.
\
\ Slot ranges are the collision type system: after integrating, the
\ walker box-tests charge slots against sub slots and mine slots against
\ the ship, on INK boxes (sprite header ink fields, so pads never hit).
\ Both parties of a charge/sub hit (the mine only, for mine/ship) are
\ erased and freed. Slots: 0 ship, 1-3 subs, 4-6 charges (7-8 spare),
\ 9-12 mines (13-16 spare), 17-19 effects: when a charge sinks a sub,
\ the collision pass copies the sub into a free effect slot - drawn
\ position included, so the sprite on screen simply becomes the wreck -
\ sinking (vy 38/256) to y+10 (max 61), adds 10 seconds to the clock,
\ queues the sub's type for BASIC to score, and respawns the sub.
\
\ Sprite format: EQUB width, height, ink-x, ink-y, ink-w, ink-h, then
\ height rows of CEIL(width/8) bytes, MSB first (leftmost sixel = bit 7).
\ 1 = plot, 0 = transparent (draw/erase) or background (move). The ink
\ box is the collision rectangle relative to the drawn position. Movers
\ carry a blank pad column each side — and pad rows above/below if they
\ move vertically — so an opaque move at the new position wipes the
\ trailing edge of the old.
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
zpnx   = &84        \ walker: this frame's sixel x (integration only;
zpny   = &85        \  ...collision reuses &84-&8B as the two ink boxes)
zpboxa = &84        \ &84-&87: box A x1,x2,y1,y2 (collision pass)
zpboxb = &88        \ &88-&8B: box B x1,x2,y1,y2
zpgb   = &8C        \ &8C/&8D: loadbox/eraseslot slot pointer
zpoth  = &8E        \ &8E/&8F: collision inner-loop slot pointer
zpeff  = &84        \ &84/&85: sinksub's effect-slot pointer (the collision
                    \  boxes at &84-&8B are dead once a hit is found)

osbyte   = &FFF4

NSLOTS   = 20
SLOTSIZE = 16
SUB0     = 1        \ slot ranges double as collision types
NSUBS    = 3
CHG0     = 4
NCHGS    = 5
MINE0    = 9
NMINES   = 8
EFF0     = 17
NEFFS    = 3
NCHGUSE  = 3        \ charge/mine slots actually in play
NMINEUSE = 4
EV_FIZZ  = 5        \ event codes for BASIC (1-3 = a sub of that type sunk)
EV_HIT   = 6
TPL_CHG  = 0        \ spawn templates: offsets into tpls
TPL_MINE = 10
TPL_SUB  = 20
NPART    = 8        \ particle table size (a hit and a fizzle in one frame fit)
PUFF_HIT = 5        \ particles from a charge/sub hit, as the original
PUFF_FIZZ = 3       \ ...and from a mine fizzling at the surface
PLIFE_MIN = 4       \ particle life 4..7 frames (original 5..9 at 30fps)
SPINRATE = 8        \ frames per charge pose (original: 15 at 30fps = 0.5s)
CHG_POSE0 = 4       \ charge sprites: 4 (the vertical bar, also the airborne
CHG_POSE1 = 6       \  block) then 6, 7, 8 - a bar turning end over end

.start
    JMP initrow
    JMP plot
    JMP unplot
    JMP sprdraw
    JMP sprerase
    JMP sprmove
    JMP objwalk
    JMP frame
    JMP hudnum
    JMP subspawn
    EQUB 0, 0       \ pad: data at +&20

.objevt
    EQUB 0          \ events queued since BASIC last cleared it
.frmflg
    EQUB 0
.frmprv
    EQUB 0
.frmkey
    EQUB 0
.vsync
    EQUB 0
.nchg
    EQUB 0
.evaddr
    EQUW evhandler
.rng
    EQUW &ACE1      \ any non-zero seed; BASIC reseeds from TIME
    SKIP 2          \ pad (BASIC's 4-byte poke of rng spills here)
.spin
    EQUB SPINRATE   \ frames until wet charges turn to their next pose
    SKIP 1
.secs
    EQUB 0
.tick
    EQUB 25
.objtab
    SKIP NSLOTS * SLOTSIZE
.evq
    SKIP NSLOTS         \ this frame's event codes
.plife                  \ particles, as parallel arrays: frames left (0 = free;
    SKIP NPART          \  bit 7 = phantom, see partplot), x and y in 8.8,
.pxlo                   \  vx/vy signed /256. BASIC zeroes plife in PROCwipe.
    SKIP NPART
.pxhi
    SKIP NPART
.pylo
    SKIP NPART
.pyhi
    SKIP NPART
.pvx
    SKIP NPART
.pvy
    SKIP NPART

ASSERT objevt = &6E20
ASSERT frmflg = &6E21
ASSERT frmprv = &6E22
ASSERT nchg   = &6E25
ASSERT evaddr = &6E26
ASSERT rng    = &6E28
ASSERT spin   = &6E2C
ASSERT secs   = &6E2E
ASSERT tick   = &6E2F
ASSERT objtab = &6E30
ASSERT evq    = &6F70
ASSERT plife  = &6F84

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
    CLC                 \ point the fetcher at the bitmap (header + 6)
    LDA zpptr
    ADC #6
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
    JSR partage         \ particles: unplot, age, integrate (plotted again
    LDA #LO(objtab)     \  after the collision pass, see partplot)
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
    LDA #0
    STA (zpslot),Y      \ freed; now by slot range (index = NSLOTS - zpcnt)
    LDA #NSLOTS
    SEC
    SBC zpcnt
    BEQ ownext          \ 0: the ship (never expires in practice)
    CMP #CHG0
    BCC owsub
    CMP #MINE0
    BCC owchg
    CMP #EFF0
    BCS ownext          \ effect: just gone
    LDA #PUFF_FIZZ      \ mine reached the surface: a splash where it was
    JSR puff            \  (zpx/zpy still hold the erase position)
    LDA #EV_FIZZ
    JSR pushev
    JMP ownext
.owchg
    DEC nchg            \ charge sank out of range
    JSR showdc
    JMP ownext
.owsub
    TAX                 \ sub left the screen: straight back in
    JSR respawn
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
.owdone                 \ fall through into the collision pass

\ --- collision pass (runs at the end of every objwalk) --------------------

.collide
    LDA #LO(objtab + CHG0*SLOTSIZE)     \ charges vs subs
    STA zpslot
    LDA #HI(objtab + CHG0*SLOTSIZE)
    STA zpslot+1
    LDA #NCHGS
    STA zpcnt
.chgloop
    LDY #0
    LDA (zpslot),Y
    CMP #1
    BEQ chgactive
    JMP chgnext         \ (the hit path below is too long for a branch)
.chgactive
    LDA zpslot          \ charge ink box -> A
    STA zpgb
    LDA zpslot+1
    STA zpgb+1
    LDX #0
    JSR loadbox
    LDA #LO(objtab + SUB0*SLOTSIZE)
    STA zpoth
    LDA #HI(objtab + SUB0*SLOTSIZE)
    STA zpoth+1
    LDA #NSUBS
    STA zpwm            \ sub counter (blitter-idle here; see hit path)
.subloop
    LDY #0
    LDA (zpoth),Y
    CMP #1
    BNE subnext
    LDA zpoth           \ sub ink box -> B
    STA zpgb
    LDA zpoth+1
    STA zpgb+1
    LDX #4
    JSR loadbox
    JSR boxhit
    BEQ subnext
    LDA zpslot          \ hit: the charge is spent
    STA zpgb
    LDA zpslot+1
    STA zpgb+1
    JSR eraseslot       \ (clobbers zpwm - we leave the sub loop anyway)
    LDY #0
    TYA
    STA (zpslot),Y
    DEC nchg
    JSR showdc
    LDY #3              \ a puff of particles from the middle of the charge
    LDA (zpslot),Y
    CLC
    ADC #1
    STA zpx
    LDY #5
    LDA (zpslot),Y
    CLC
    ADC #2
    STA zpy
    LDA #PUFF_HIT
    JSR puff
    LDA zpoth           \ the sub: becomes a wreck in place (erased only if
    STA zpgb            \ no effect slot is free), tell BASIC its type to
    LDA zpoth+1         \ score, 10 seconds on the clock, respawn
    STA zpgb+1
    JSR sinksub
    BCS hitwreck
    LDA zpoth
    STA zpgb
    LDA zpoth+1
    STA zpgb+1
    JSR eraseslot
.hitwreck
    LDY #1
    LDA (zpoth),Y
    JSR pushev
    LDA secs
    CMP #246
    BCS hitnobonus      \ clock capped at 255
    CLC
    ADC #10
    STA secs
.hitnobonus
    JSR showtime
    LDA zpoth           \ slot index from the pointer (the subs share
    SEC                 \ objtab's page)
    SBC #LO(objtab)
    LSR A
    LSR A
    LSR A
    LSR A
    TAX
    JSR respawn
    JMP chgnext
.subnext
    CLC
    LDA zpoth
    ADC #SLOTSIZE
    STA zpoth
    BCC subsame
    INC zpoth+1
.subsame
    DEC zpwm
    BEQ chgnext
    JMP subloop
.chgnext
    CLC
    LDA zpslot
    ADC #SLOTSIZE
    STA zpslot
    BCC chgsame
    INC zpslot+1
.chgsame
    DEC zpcnt
    BEQ mines
    JMP chgloop

.mines                  \ mines vs the ship
    LDA objtab          \ ship slot 0 status
    CMP #1
    BEQ minesgo
    JMP partplot
.minesgo
    LDA #LO(objtab)     \ ship ink box -> A, once (erases can't touch it)
    STA zpgb
    LDA #HI(objtab)
    STA zpgb+1
    LDX #0
    JSR loadbox
    LDA #LO(objtab + MINE0*SLOTSIZE)
    STA zpslot
    LDA #HI(objtab + MINE0*SLOTSIZE)
    STA zpslot+1
    LDA #NMINES
    STA zpcnt
.minloop
    LDY #0
    LDA (zpslot),Y
    CMP #1
    BNE minnext
    LDA zpslot          \ mine ink box -> B
    STA zpgb
    LDA zpslot+1
    STA zpgb+1
    LDX #4
    JSR loadbox
    JSR boxhit
    BEQ minnext
    LDA zpslot          \ hit: mine dies; BASIC decides the ship's fate
    STA zpgb
    LDA zpslot+1
    STA zpgb+1
    JSR eraseslot
    LDY #0
    TYA
    STA (zpslot),Y
    LDA #EV_HIT
    JSR pushev
.minnext
    CLC
    LDA zpslot
    ADC #SLOTSIZE
    STA zpslot
    BCC minsame
    INC zpslot+1
.minsame
    DEC zpcnt
    BEQ coldone
    JMP minloop
.coldone                \ fall through into the particle plot pass

\ --- particles ------------------------------------------------------------
\ Single sixels sharing the cells with the sprites, so they must never clear
\ a bit a sprite set. Two passes make that safe: partplot, at the very end of
\ the walk, plots each particle and marks it phantom if its sixel was already
\ lit; partage, at the very start of the next walk, unplots the non-phantom
\ ones. Nothing else draws in between, so only our own bits get cleared.

.partplot               \ pass B: bounds-check and plot every live particle
    LDX #NPART-1
.pbloop
    LDA plife,X
    BEQ pbnext
    AND #&7F            \ phantom is judged afresh every frame
    STA plife,X
    LDA pxhi,X          \ off the playfield (control cells, HUD, floor,
    CMP #6              \  legend): gone
    BCC pbkill
    CMP #80
    BCS pbkill
    LDA pyhi,X
    CMP #6
    BCC pbkill
    CMP #69
    BCS pbkill
    STA zpy
    LDA pxhi,X
    STA zpx
    STX zpcnt
    JSR calc            \ A = mask, Y = col
    STA zpm0
    AND (zprow),Y
    BEQ pbset
    LDX zpcnt           \ already lit by a sprite: phantom, leave it alone
    LDA plife,X
    ORA #&80
    STA plife,X
    BMI pbnext
.pbkill
    LDA #0
    STA plife,X
    BEQ pbnext
.pbset
    LDA zpm0
    ORA (zprow),Y
    STA (zprow),Y
    LDX zpcnt
.pbnext
    DEX
    BPL pbloop
    RTS

.partage                \ pass A: unplot, age and integrate every live particle
    LDX #NPART-1
.paloop
    LDA plife,X
    BEQ panext
    BMI paage           \ phantom: the lit bit was a sprite's, not ours
    STX zpcnt
    LDA pxhi,X
    STA zpx
    LDA pyhi,X
    STA zpy
    JSR unplot
    LDX zpcnt
.paage
    LDA plife,X
    AND #&7F
    SEC
    SBC #1
    STA plife,X
    BEQ panext          \ expired
    LDA pvx,X           \ x += vx, sign-extended
    LDY #0
    BPL paxadd
    DEY
.paxadd
    CLC
    ADC pxlo,X
    STA pxlo,X
    TYA
    ADC pxhi,X
    STA pxhi,X
    LDA pvy,X           \ y += vy
    LDY #0
    BPL payadd
    DEY
.payadd
    CLC
    ADC pylo,X
    STA pylo,X
    TYA
    ADC pyhi,X
    STA pyhi,X
.panext
    DEX
    BPL paloop
    RTS

.puff                   \ A = how many particles from (zpx, zpy): each starts
    TAX                 \ at x + 0..3, drifts +-0.25 sixel/frame, rises 0..0.75
    LDY #0              \ a frame, lives 4..7 frames. Table full: the rest are
.puffloop               \ dropped. (The original: x+0..3, +-0.4px, 0..1px up,
    LDA plife,Y         \ 5..9 frames at 30fps.)
    BEQ pufffree
    INY
    CPY #NPART
    BNE puffloop
    RTS
.pufffree
    JSR rnd
    AND #3
    CLC
    ADC #PLIFE_MIN
    STA plife,Y
    JSR rnd
    AND #3
    CLC
    ADC zpx
    STA pxhi,Y
    LDA zpy
    STA pyhi,Y
    LDA #&80            \ start mid-sixel
    STA pxlo,Y
    STA pylo,Y
    JSR rnd             \ vx: -64..63 (arithmetic shift right)
    CMP #&80
    ROR A
    STA pvx,Y
    JSR rnd             \ vy: -(0..191)
    AND #&BF
    EOR #&FF
    CLC
    ADC #1
    STA pvy,Y
    DEX
    BNE puffloop
    RTS

.pushev                \ evq[objevt++] = event code in A; full = dropped
    LDX objevt
    CPX #NSLOTS
    BCS pushfull
    STA evq,X
    INC objevt
.pushfull
    RTS

.sinksub                \ sub (zpoth) was sunk: copy it into a free effect
                        \ slot as a sinking wreck. C set = done, the wreck
                        \ owns the sub's drawn sprite; C clear = no free slot
    LDX #EFF0
    LDY #NEFFS
    JSR findfree
    BCC sinkdone
    LDY #1              \ +1..+7 sprite, x, y, vx: as the sub had them
.sinkcopy
    LDA (zpoth),Y
    STA (zpgb),Y
    INY
    CPY #8
    BNE sinkcopy
    LDA #38             \ +8/+9 vy = 38/256 sixel/frame
    STA (zpgb),Y
    INY
    LDA #0
    STA (zpgb),Y
    INY
    LDA (zpoth),Y       \ +10/+11 last drawn: the sub's - the sprite stays
    STA (zpgb),Y        \  on screen and the wreck just carries on from it
    INY
    LDA (zpoth),Y
    STA (zpgb),Y
    INY
    LDA #6              \ +12/+13 xmin/xmax as a sub's
    STA (zpgb),Y
    INY
    LDA #62
    STA (zpgb),Y
    INY
    LDA #0              \ +14 ymin
    STA (zpgb),Y
    LDY #5
    LDA (zpoth),Y       \ +15 ymax = sub y + 10, capped so the wreck stays
    CLC                 \  above the sea floor
    ADC #10
    CMP #62
    BCC sinkcap
    LDA #61
.sinkcap
    LDY #15
    STA (zpgb),Y
    LDY #0
    LDA #1
    STA (zpgb),Y
    SEC
.sinkdone
    RTS

.slotptr                \ X = slot index -> (zpgb) = its slot
    TXA
    LSR A
    LSR A
    LSR A
    LSR A
    CLC
    ADC #HI(objtab)
    STA zpgb+1
    TXA
    ASL A
    ASL A
    ASL A
    ASL A
    CLC
    ADC #LO(objtab)
    STA zpgb
    BCC slotok
    INC zpgb+1
.slotok
    RTS

.findfree               \ X = first slot, Y = how many: C set and (zpgb) = the
    STY zpodd           \ first free one, else C clear. X ends on the slot found.
    JSR slotptr
.ffloop
    LDY #0
    LDA (zpgb),Y
    BEQ fffound
    CLC
    LDA zpgb
    ADC #SLOTSIZE
    STA zpgb
    BCC ffsame
    INC zpgb+1
.ffsame
    INX
    DEC zpodd
    BNE ffloop
    CLC
    RTS
.fffound
    SEC
    RTS

.copytpl                \ (zpgb) +6..+15 = template X: vx, vy, last drawn, box
    LDY #6
.ctloop
    LDA tpls,X
    STA (zpgb),Y
    INX
    INY
    CPY #16
    BNE ctloop
    RTS

.tpls
    EQUB 0,0, 96,0, &FF,&FF, 6,74,8,64      \ charge: airborne, falls at
                                            \  96/256 (vx set by dropchg;
                                            \  frsplash switches to 0/38)
    EQUB 0,0, &DA,&FF, &FF,&FF, 6,77,13,74  \ mine: rises at -38/256; ymin 13
                                            \  so its ink reaches the hull
    EQUB 0,0, 0,0, &FF,&FF, 6,62,0,74       \ sub (vx set by respawn)
.bandy
    EQUB 0, 24, 42, 60  \ sub patrol bands (drawn y) by slot

.loadbox                \ (zpgb) = slot; X = 0 -> box A, 4 -> box B
    LDY #1
    LDA (zpgb),Y        \ sprite id -> header
    ASL A
    TAY
    LDA sprtab,Y
    STA zpptr
    LDA sprtab+1,Y
    STA zpptr+1
    LDY #3
    LDA (zpgb),Y        \ sixel x
    LDY #2
    CLC
    ADC (zpptr),Y       \ + ink-x
    STA zpboxa,X        \ x1
    LDY #4
    CLC
    ADC (zpptr),Y       \ + ink-w
    SEC
    SBC #1
    STA zpboxa+1,X      \ x2
    LDY #5
    LDA (zpgb),Y        \ sixel y
    LDY #3
    CLC
    ADC (zpptr),Y       \ + ink-y
    STA zpboxa+2,X      \ y1
    LDY #5
    CLC
    ADC (zpptr),Y       \ + ink-h
    SEC
    SBC #1
    STA zpboxa+3,X      \ y2
    RTS

.boxhit                 \ -> A=1 (and Z clear) if boxes A and B overlap
    LDA zpboxb          \ b.x1 <= a.x2 ?
    CMP zpboxa+1
    BEQ bh1
    BCS bhno
.bh1
    LDA zpboxa          \ a.x1 <= b.x2 ?
    CMP zpboxb+1
    BEQ bh2
    BCS bhno
.bh2
    LDA zpboxb+2        \ b.y1 <= a.y2 ?
    CMP zpboxa+3
    BEQ bh3
    BCS bhno
.bh3
    LDA zpboxa+2        \ a.y1 <= b.y2 ?
    CMP zpboxb+3
    BEQ bh4
    BCS bhno
.bh4
    LDA #1
    RTS
.bhno
    LDA #0
    RTS

.eraseslot              \ erase (zpgb) slot's sprite at its last drawn spot
    LDY #10
    LDA (zpgb),Y
    CMP #&FF
    BEQ erdone          \ never drawn
    STA zpx
    LDY #11
    LDA (zpgb),Y
    STA zpy
    LDY #1
    LDA (zpgb),Y
    STA zparg
    LDA #&FF
    JMP sprgo
.erdone
    RTS

\ --- frame: sync, input, steer, then walk ---------------------------------

.frame
    LDA vsync           \ 25Hz lock: wait for the 2nd vsync since last frame
    CMP #2
    BCC frame
    LDA #0              \ (not -2: a frame that overran just resyncs)
    STA vsync
    LDA #15             \ flush the keyboard buffer so held keys don't
    LDX #1              \ type into BASIC when the game exits
    JSR osbyte
    LDA #0
    STA frmkey
    LDX #&BD            \ X      (INKEY -67)   scanned high bit first:
    JSR keytest         \ each ROL shifts the earlier keys up one
    ROL frmkey
    LDX #&8F            \ ESCAPE (INKEY -113; *FX200 makes it a plain key)
    JSR keytest
    ROL frmkey
    LDX #&86            \ cursor right (INKEY -122)
    JSR keytest
    ROL frmkey
    LDX #&E6            \ cursor left  (INKEY -26)
    JSR keytest
    ROL frmkey
    LDX #&9E            \ Z      (INKEY -98)
    JSR keytest
    ROL frmkey
    LDA frmkey          \ left: ship x -= 0.75 sixel (8.8), clamp at 6
    AND #2
    BEQ frnoleft
    SEC
    LDA objtab+2
    SBC #&C0
    STA objtab+2
    LDA objtab+3
    SBC #0
    STA objtab+3
    CMP #6
    BCS frnoleft
    LDA #6
    STA objtab+3
    LDA #0
    STA objtab+2
.frnoleft
    LDA frmkey          \ right: ship x += 0.75 sixel, clamp at 57
    AND #4
    BEQ frnoright
    CLC
    LDA objtab+2
    ADC #&C0
    STA objtab+2
    LDA objtab+3
    ADC #0
    STA objtab+3
    CMP #58
    BCC frnoright
    LDA #57
    STA objtab+3
    LDA #0
    STA objtab+2
.frnoright
    LDA #0
    STA frmflg
    LDA frmprv          \ rising edges: Z lobs a charge to port, X to
    EOR #&FF            \  starboard (both in one frame: two charges)
    AND frmkey
    STA zpcnt           \ (zpw/zpwm belong to hudnum, which showdc calls)
    AND #1
    BEQ frnoleft2
    LDA #0
    STA zpwm
    JSR dropchg
    BCC frnoleft2       \ three already wet: nothing dropped
    LDA #1              \ flags bit 0: a charge was dropped
    STA frmflg
.frnoleft2
    LDA zpcnt
    AND #16
    BEQ frnofire
    LDA #1
    STA zpwm
    JSR dropchg
    BCC frnofire
    LDA #1
    STA frmflg
.frnofire
    LDA frmkey
    STA frmprv
    AND #8              \ flags bit 1: ESCAPE held
    BEQ frnoquit
    LDA frmflg
    ORA #2
    STA frmflg
.frnoquit
    LDA secs            \ the clock: a second every 25 frames, stops at 0
    BEQ frnosec
    DEC tick
    BNE frnosec
    LDA #25
    STA tick
    DEC secs
    BNE frshowt
    LDA frmflg
    ORA #4              \ flags bit 2: time is up
    STA frmflg
.frshowt
    JSR showtime
.frnosec
    LDX #SUB0           \ each active sub rolls for a mine launch
.frmine
    JSR slotptr
    LDY #0
    LDA (zpgb),Y
    CMP #1
    BNE frminenext
    JSR rnd             \ 16-bit roll < 655 = 1.0%/frame, as the original
    STA zpw
    JSR rnd
    CMP #2
    BCC frlaunch
    BNE frminenext
    LDA zpw
    CMP #143
    BCS frminenext
.frlaunch
    JSR launch
.frminenext
    INX
    CPX #SUB0+NSUBS
    BNE frmine
    DEC spin            \ charges: land the airborne ones, turn the wet ones
    LDX #CHG0
.frsplash
    JSR slotptr
    LDY #0
    LDA (zpgb),Y
    CMP #1
    BNE frsplnext
    LDY #6
    LDA (zpgb),Y        \ vx lo 0: wet - spinning
    BEQ frspin
    LDY #5
    LDA (zpgb),Y        \ y < 14: ink still above the waterline
    CMP #14
    BCC frsplnext
    LDA #0              \ splash: stop drifting, sink slowly at 38/256
    LDY #6              \  (the original's 19 felt slow here)
    STA (zpgb),Y
    INY
    STA (zpgb),Y
    LDY #8
    LDA #38
    STA (zpgb),Y
    JSR rnd             \ and start the spin at a random pose
    AND #3
    TAY
    LDA poses,Y
    LDY #1
    STA (zpgb),Y
    BNE frsplnext
.frspin
    LDA spin            \ only on a pose-change frame
    BNE frsplnext
    LDY #1
    LDA (zpgb),Y        \ next pose: 4 -> 6 -> 7 -> 8 -> 4
    CMP #CHG_POSE0
    BNE frspinnext
    LDA #CHG_POSE1-1
.frspinnext
    CLC
    ADC #1
    CMP #CHG_POSE1+3
    BNE frspinset
    LDA #CHG_POSE0
.frspinset
    STA (zpgb),Y
    STA zparg
    LDY #10
    LDA (zpgb),Y
    CMP #&FF
    BEQ frsplnext       \ not drawn yet: the walker will draw the new pose
    STA zpx
    INY
    LDA (zpgb),Y
    STA zpy
    TXA
    PHA
    LDA #1              \ redraw in place: the opaque move wipes the old pose
    JSR sprgo
    PLA
    TAX
.frsplnext
    INX
    CPX #CHG0+NCHGUSE
    BNE frsplash
    LDA spin
    BNE frspindone
    LDA #SPINRATE
    STA spin
.frspindone
    JMP objwalk
.poses
    EQUB CHG_POSE0, CHG_POSE1, CHG_POSE1+1, CHG_POSE1+2

.dropchg                \ zpwm = 0: lob a charge off the port side, 1: off
                        \ the starboard side; C set if dropped. Starts at
                        \ deck height beside the hull, falling 0.375 down
                        \ and 0.5 outward a frame until frsplash lands it.
                        \ From the screen edge it lands outside the box
                        \ and is simply lost, as the original's went off
                        \ screen.
    LDA nchg
    CMP #NCHGUSE
    BCS dropno
    LDX #CHG0
    LDY #NCHGUSE
    JSR findfree
    BCC dropno
    LDX #TPL_CHG
    JSR copytpl         \ vy 96/256, box 6..76 x 8..64
    LDY #1
    LDA #4              \ charge sprite
    STA (zpgb),Y
    LDY #2
    LDA #0
    STA (zpgb),Y
    LDY #4
    STA (zpgb),Y
    LDY #5
    LDA #10             \ y = 10: ink rows 11-14 level with the hull
    STA (zpgb),Y
    LDA zpwm            \ (read before showdc's hudnum reuses it)
    BNE dropright
    LDA objtab+3        \ port: x = ship x - 5 (ink 2 clear of the bow),
    SEC                 \  vx = -128/256
    SBC #5
    LDY #3
    STA (zpgb),Y
    LDY #7
    LDA #&FF
    STA (zpgb),Y
    BNE dropgo
.dropright
    LDA objtab+3        \ starboard: x = ship x + 21, vx = +128/256
    CLC
    ADC #21
    LDY #3
    STA (zpgb),Y
    LDY #7
    LDA #0
    STA (zpgb),Y
.dropgo
    LDY #6
    LDA #&80
    STA (zpgb),Y
    LDY #0
    LDA #1
    STA (zpgb),Y
    INC nchg
    JSR showdc
    SEC
    RTS
.dropno
    CLC
    RTS

.launch                 \ a mine from sub (zpgb), X preserved
    LDA zpgb
    STA zpeff
    LDA zpgb+1
    STA zpeff+1
    TXA
    PHA
    LDX #MINE0
    LDY #NMINEUSE
    JSR findfree
    BCC launchdone      \ four already up
    LDX #TPL_MINE
    JSR copytpl         \ rises at -38/256, box 6..77 x 13..74
    LDY #1
    LDA #5              \ mine sprite
    STA (zpgb),Y
    LDY #2
    LDA #0
    STA (zpgb),Y
    LDY #4
    STA (zpgb),Y
    LDY #3
    LDA (zpeff),Y       \ x = sub x + 7 (the conning tower)
    CLC
    ADC #7
    STA (zpgb),Y
    LDY #5
    LDA (zpeff),Y       \ y = sub y - 5
    SEC
    SBC #5
    STA (zpgb),Y
    LDY #0
    LDA #1
    STA (zpgb),Y
.launchdone
    PLA
    TAX
    RTS

.subspawn               \ BASIC entry: ?&70 = sub slot 1-3
    LDX zpx
.respawn                \ X = sub slot 1-3: a new random sub in it
    JSR slotptr
    TXA
    PHA
    LDX #TPL_SUB
    JSR copytpl         \ vy 0, never drawn, box 6..62 x 0..74
    PLA
    TAX
    LDY #5
    LDA bandy,X         \ y = the slot's patrol band
    STA (zpgb),Y
    LDA #0
    LDY #4
    STA (zpgb),Y
    LDY #2
    STA (zpgb),Y
.rstype
    JSR rnd             \ type 1-3, uniform (reject 0)
    AND #3
    BEQ rstype
    LDY #1
    STA (zpgb),Y
.rsspeed
    JSR rnd             \ speed 10..57 /256 a frame (reject 48-63)
    AND #63
    CMP #48
    BCS rsspeed
    CLC
    ADC #10
    STA zpw
    JSR rnd
    AND #1
    BNE rsleft
    LDY #3              \ from the left edge, heading right
    LDA #6
    STA (zpgb),Y
    LDY #6
    LDA zpw
    STA (zpgb),Y
    INY
    LDA #0
    STA (zpgb),Y
    JMP rsgo
.rsleft
    LDY #3              \ from the right edge, heading left
    LDA #62
    STA (zpgb),Y
    LDY #6
    LDA #0
    SEC
    SBC zpw
    STA (zpgb),Y
    INY
    LDA #&FF
    STA (zpgb),Y
.rsgo
    LDY #0
    LDA #1
    STA (zpgb),Y
    RTS

.rnd                    \ 16-bit Galois LFSR (taps &B400) -> A = next byte
    LSR rng+1
    ROR rng
    BCC rnddone
    LDA rng+1
    EOR #&B4
    STA rng+1
.rnddone
    LDA rng
    RTS

.showtime               \ HUD TIME field <- secs
    LDA #8
    STA zpx
    LDA secs
    STA zparg
    LDA #1
    STA zpy
    LDA #0
    STA zpmode
    JMP hudnum

.showdc                 \ HUD DC field <- 3 - nchg
    LDA #20
    STA zpx
    LDA #3
    SEC
    SBC nchg
    STA zparg
    LDA #1
    STA zpy
    LDA #0
    STA zpmode
    JMP hudnum

.hudnum                 \ ?&70 col, ?&71 row, &72/&73 value -> 5 cells
    LDY zpy
    LDA rowlo,Y
    STA zprow
    LDA rowhi,Y
    STA zprow+1
    LDA zpx
    CLC
    ADC #5
    STA zpwm            \ column to pad up to
    LDY zpx
    LDX #0              \ 10000, 1000, 100, 10
    STX zph             \ has a digit been written yet?
.hnpow
    LDA #0
    STA zpw             \ this digit
.hnsub
    LDA zparg           \ value >= power? (16-bit compare)
    CMP pow10lo,X
    LDA zpmode
    SBC pow10hi,X
    BCC hnnext
    LDA zparg           \ value -= power
    SEC
    SBC pow10lo,X
    STA zparg
    LDA zpmode
    SBC pow10hi,X
    STA zpmode
    INC zpw
    JMP hnsub
.hnnext
    LDA zpw
    BNE hnemit
    LDA zph
    BEQ hnskip          \ leading zero
    LDA #0
.hnemit
    ORA #&30
    STA (zprow),Y
    INY
    LDA #1
    STA zph
.hnskip
    INX
    CPX #4
    BNE hnpow
    LDA zparg           \ units, always written
    ORA #&30
    STA (zprow),Y
    INY
.hnpad
    CPY zpwm
    BCS hndone
    LDA #&20
    STA (zprow),Y
    INY
    JMP hnpad
.hndone
    RTS
.pow10lo
    EQUB LO(10000), LO(1000), LO(100), LO(10)
.pow10hi
    EQUB HI(10000), HI(1000), HI(100), HI(10)

.evhandler              \ EVNTV: A = event number; 4 = vsync
    PHA
    CMP #4
    BNE evdone
    INC vsync
.evdone
    PLA
    RTS

.keytest                \ X = negative INKEY number -> carry set if held
    LDA #129
    LDY #&FF
    JSR osbyte
    CPX #&FF
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
    EQUW sprcharge      \ 4: depth charge, pad all round (it flies diagonally);
                        \    also the first pose of the wet charge's spin
    EQUW sprmine        \ 5: mine, pad rows above/below
    EQUW sprchg1        \ 6-8: the other three poses of the spinning charge,
    EQUW sprchg2        \    same box and ink box as 4 so the hit test and
    EQUW sprchg3        \    the in-place redraw don't care which is showing

.sprship
    EQUB 22, 6
    EQUB 4, 1, 14, 5    \ hit box: the tapered hull only, so mines can't
                        \ trigger on the empty corners under the deck
                        \ (original's kill zone is ~half the ship too)
    EQUB %00000000, %00000000, %00000000   \ ......................
    EQUB %00000000, %01101100, %00000000   \ .........##.##........
    EQUB %01111111, %11111111, %11111000   \ .####################.
    EQUB %01111111, %11111111, %11111000   \ .####################.
    EQUB %00111111, %11111111, %11110000   \ ..##################..
    EQUB %00001111, %11111111, %11000000   \ ....##############....

.sprsub0
    EQUB 17, 8
    EQUB 1, 1, 15, 7    \ ink box (top pad row so the sinking anim self-erases)
    EQUB %00000000, %00000000, %00000000   \ .................
    EQUB %00000000, %10000000, %00000000   \ ........#........
    EQUB %00000000, %10000000, %00000000   \ ........#........
    EQUB %00011111, %11111100, %00000000   \ ...###########...
    EQUB %00111111, %11111110, %00000000   \ ..#############..
    EQUB %01111101, %01011111, %00000000   \ .#####.#.#.#####.
    EQUB %01111111, %11111111, %00000000   \ .###############.
    EQUB %00111111, %11111110, %00000000   \ ..#############..

.sprsub1
    EQUB 17, 8
    EQUB 1, 1, 15, 7    \ ink box (top pad row so the sinking anim self-erases)
    EQUB %00000000, %00000000, %00000000   \ .................
    EQUB %00000000, %10000000, %00000000   \ ........#........
    EQUB %00000000, %10000000, %00000000   \ ........#........
    EQUB %00011111, %11111100, %00000000   \ ...###########...
    EQUB %00111111, %11111110, %00000000   \ ..#############..
    EQUB %01111010, %10101111, %00000000   \ .####.#.#.#.####.
    EQUB %01111111, %11111111, %00000000   \ .###############.
    EQUB %00111111, %11111110, %00000000   \ ..#############..

.sprsub2
    EQUB 17, 8
    EQUB 1, 1, 15, 7    \ ink box (top pad row so the sinking anim self-erases)
    EQUB %00000000, %00000000, %00000000   \ .................
    EQUB %00000000, %10000000, %00000000   \ ........#........
    EQUB %00000000, %10000000, %00000000   \ ........#........
    EQUB %00011111, %11111100, %00000000   \ ...###########...
    EQUB %00111111, %11111110, %00000000   \ ..#############..
    EQUB %01111110, %00111111, %00000000   \ .######...######.
    EQUB %01111111, %11111111, %00000000   \ .###############.
    EQUB %00111111, %11111110, %00000000   \ ..#############..

.sprcharge              \ pose 0: vertical bar (and the airborne block)
    EQUB 6, 6
    EQUB 2, 1, 2, 4     \ ink box: the bar, whatever pose is showing
    EQUB %00000000                         \ ......
    EQUB %00110000                         \ ..##..
    EQUB %00110000                         \ ..##..
    EQUB %00110000                         \ ..##..
    EQUB %00110000                         \ ..##..
    EQUB %00000000                         \ ......

\ Sixels are wider than they are tall (about 1.4:1), so the horizontal bar
\ and the diagonals are drawn a sixel thicker than the vertical bar to look
\ the same weight.

.sprchg1                \ pose 1: leaning /
    EQUB 6, 6
    EQUB 2, 1, 2, 4
    EQUB %00000000                         \ ......
    EQUB %00011000                         \ ...##.
    EQUB %00111000                         \ ..###.
    EQUB %01110000                         \ .###..
    EQUB %01100000                         \ .##...
    EQUB %00000000                         \ ......

.sprchg2                \ pose 2: horizontal bar
    EQUB 6, 6
    EQUB 2, 1, 2, 4
    EQUB %00000000                         \ ......
    EQUB %00000000                         \ ......
    EQUB %01111000                         \ .####.
    EQUB %01111000                         \ .####.
    EQUB %01111000                         \ .####.
    EQUB %00000000                         \ ......

.sprchg3                \ pose 3: leaning \
    EQUB 6, 6
    EQUB 2, 1, 2, 4
    EQUB %00000000                         \ ......
    EQUB %01100000                         \ .##...
    EQUB %01110000                         \ .###..
    EQUB %00111000                         \ ..###.
    EQUB %00011000                         \ ...##.
    EQUB %00000000                         \ ......

.sprmine
    EQUB 3, 5
    EQUB 0, 1, 3, 3     \ ink box
    EQUB %00000000                         \ ...
    EQUB %10100000                         \ #.#
    EQUB %01000000                         \ .#.
    EQUB %10100000                         \ #.#
    EQUB %00000000                         \ ...
.end
