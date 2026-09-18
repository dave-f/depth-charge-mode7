# Design notes — Depth Charge Mode 7 port

## Decisions locked during implementation (2026-07-17)

- **Max 3 subs at once** (not the original's 5) — Mode 7's 54 water sixels
  can't breathe with more. Subs patrol colour bands 1/3/5 (y = 25/43/61);
  band 0 stays open water so the top sub isn't crowding the ship.
- Ship rides the waterline at y=10 (hull bottom on the last sky row).
- Water rows carry background codes (blue via 157), sky rows cyan; the
  colour boundary is the waterline. Playfield left edge is x=6 (cols 0-2
  of coloured rows are control cells). Lane colours, surface down:
  white, cyan, yellow, green, magenta, red.
- One sub sprite for both directions (the original doesn't flip either);
  porthole rows distinguish the three score types.
- Engine: object table + walker in MC (see src/sixel.asm header), BASIC
  is director only. Mock scene runs ~35Hz.
- **2026-09-17: 25Hz for real.** Measured in jsbeeb (`test/probe.mjs --rate`),
  the BASIC loop was taking 3-4 fields a frame (12-17Hz): BASIC alone cost
  ~40ms, and two `OSBYTE 19`s slip to 3 fields as soon as the work exceeds
  one. Fix: a machine-code `frame` entry does the vsync wait (EVNTV counter,
  full 40ms budget), key scan, steering and fire edge-detect, then walks;
  the walker queues expired/hit slot numbers so BASIC handles only those.
  That got quiet play to 50 frames per 100 fields but a kill still cost
  ~135ms of BASIC (a BBC BASIC line profiler, `test/profile.mjs`, showed
  PRINT TAB/STR$ at 7-11ms each, RND at 3-4ms, ~1ms per plain statement).
  So the rules moved into the machine code too: charges drop on the SPACE
  edge, mines launch on a 1%/frame LFSR roll per sub, subs respawn when
  they leave or sink, a sunk sub leaves a wreck effect and adds 10s, the
  clock counts frames, and `hudnum` writes TIME/DC digits into screen
  memory. BASIC is left with scoring, sounds, attract and death: a
  four-statement loop, ~10ms a frame, ~25ms on a kill. Result: 50/50
  frames on Model B and Master; in 30s of play with kills, 5 frames ran
  0-8ms over budget on the B (a late start, not a dropped frame). PLOT now
  lives at &7100 (HIMEM=&7100) with ~250 bytes spare under the screen.
- **2026-09-18: particles.** The original's two puffs ported: five sixels
  from the charge when it sinks a sub, three from a mine that fizzles at the
  surface; x+0..3, drift ±0.25 and rise 0..0.75 sixel/frame, life 4-7 frames
  (its ±0.4px, 0..1px, 5-9 frames at 30fps, scaled). Own 8-entry table, not
  object slots. Sixels share cells with sprites, so they are plotted at the
  end of the walk and unplotted at the start of the next, and one plotted
  onto an already-lit sixel is marked phantom and left alone: no holes in
  the art, ever. Colour is the row's lane colour (white splash on the cyan
  sky). The wreck now takes over the sub's drawn sprite instead of erasing
  and redrawing it a frame later. PLOT moved to &7000 (HIMEM=&7000) for the
  room; ~160 bytes spare. Frame rate unchanged (748/749 gaps at 2 fields).

Ported from the PICO-8 original (128×128, 30fps). Reference implementation:
`C:\Dev\depth-charge\depth.p8` (v1.1 — includes the mine-launch fix; left- and
right-moving subs both drop mines).

## Screen layout

Mode 7: 40×25 chars = 80×75 sixels (2×3 per cell). Screen memory at &7C00, 1KB.

| Rows (char) | Content |
|---|---|
| 0–1 | HUD: score / high / time / charges-remaining (plain text — free in Mode 7) |
| 2–4 | Sky + ship at surface (ship ~20 sixels wide, ~5 tall) |
| 5–22 | Water: six sub lanes × 3 char rows (9 sixels) each |
| 23–24 | Sea floor / spare (or drop to 5 lanes if cramped) |

## Colour strategy

- One control code in column 0 per row sets that row's graphics colour — costs 2
  sixels of playfield at the left edge, nothing else.
- Sub lanes align exactly to char rows → each lane can have its own colour with no
  mid-row cost. Subs never leave their lane.
- Charges/mines cross rows vertically and simply inherit each row's colour
  (reads as depth attenuation).
- Vertical colour changes are free; avoid any horizontal colour changes in play area.

## Object sizes (from 128px original → 80 sixels, ~0.62×)

| Object | PICO-8 | Mode 7 sixels |
|---|---|---|
| Ship | 32×8 | ~20×5 |
| Sub | 24×16 (body 24×8) | ~15×10 (body ~15×5) |
| Charge / mine | 8×8 | ~5×5 |
| Particles | 1px | 1 sixel |

## Movement & timing

- 25Hz frame loop (two fields), locked by counting vsync events; see the
  2026-09-17 decision above. (Original plan: 50Hz via OSBYTE 19.)
- Keep fractional x positions internally (original sub speeds are 0.05–0.3 px/frame
  effective); round to sixels only at draw time to avoid stutter between speed tiers.
- PICO-8 `time%n` modulo counters map directly to a frame counter.

## Implementation

- BBC BASIC for game logic; inline 6502 assembler for sixel plot/erase/sprite
  routines writing directly to &7C00 (OSWRCH too slow).
- Sprite routine: sixel (x,y) → cell address + bit within graphics char; OR to draw,
  AND-mask to erase. Graphics chars are &20 + 6-bit sixel pattern (bit 6 always set
  for the graphics range &A0+... check exact encoding when implementing).
- Sound: done (see `src/game.bas` init block and `src/sndtest.bas`). The original's
  4 effects were fire, explosion, death, reset jingle (cart sfx 0,2,3,4); the port
  swaps the jingle for a sonar ping on the title screen.

## Gameplay parity checklist (from depth.p8 v1.1)

*Superseded where it conflicts with the locked decisions above: the port fields
3 subs / 3 charges / 4 mines, charges drop straight down, and the title plays a
sonar ping in place of the reset jingle. Kept as the record of the original.*

- 60s timer, +10s per sub sunk; scores 20/50/80 by sub type
- Max 5 charges in flight, 5 subs, 8 mines; 6 lanes with occupancy flags
- Mine launch: 1%/frame per sub while on-screen (both directions — v1.1 fix!)
- Charge physics: fast fall + drift above waterline, slow sink below
- Death: mine under ship at surface, or timer out; sinking-ship anim then reset
- High score kept across games (session only)

## Toolchain

- BeebAsm to build; output .ssd disc image
- Emulators: b2 / BeebEm / jsbeeb for dev; real hardware someday
