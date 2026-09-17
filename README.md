# Depth Charge (BBC Micro, Mode 7)

A BBC Micro port of [Depth Charge](https://github.com/dave-f/depth-charge), rendered
entirely in teletext — Mode 7, the Beeb's 1KB text mode, coaxed into being a game display.

The original is a PICO-8 take on the old arcade classic, also playable on the
[Lexaloffle BBS](https://www.lexaloffle.com/bbs/?tid=4045) (`load #depthcharge` in PICO-8).

## Why Mode 7?

For the novelty, mostly. Teletext gives you 40×25 characters; with sixel graphics
characters that's an effective 80×75 "pixels", one colour per row without spending
character cells. A game of naval silhouettes in fixed horizontal lanes turns out to
fit those constraints surprisingly well — and background colour codes buy a blue
sea and cyan sky for three character cells a row.

## Status

Playable. Steer the ship, depth-charge the subs, dodge the mines they float up
at you; 60 seconds on the clock, +10 per kill, 20/50/80 points by sub type,
session high score. Compared to the original it fields 3 subs / 3 charges /
4 mines (the Beeb's 75 sixels of water want a less crowded ocean than 128px did)
and drops straight down rather than lobbing left/right.

Sound is in: four `ENVELOPE`s (sonar ping on the title, charge drop, explosion,
death), with a standalone audition menu on the disc (`CHAIN"SND"`). Still to come,
maybe: the original's particle puffs and charge bubble animation. Design decisions
and layout maths live in [notes/design.md](notes/design.md).

## Controls

| Key | Action |
|---|---|
| `Z` / `X` | steer ship left / right |
| `SPACE` | drop a depth charge (max 3 wet) |
| `Q` | quit to BASIC |

## How it works

- **Engine** (`src/sixel.asm`, 6502 via BeebAsm): sixel plot/unplot, a
  data-driven sprite blitter with an opaque "move" mode (draw + self-erase in
  one pass — no tearing), and an object walker: a 20-slot table of fixed-point
  positions/velocities integrated, bounds-checked, collision-tested (ink-box
  overlap) and redrawn-on-move in a single `CALL` per frame.
- **Game logic** (`src/game.bas`, BBC BASIC kept as plain text in git,
  tokenised onto the disc at build time by BeebAsm's `PUTBASIC`): input,
  spawning, scoring, and the attract/death loop — the walker reports expiries
  and hits through one event byte, so BASIC's frame cost is a handful of
  statements. Locked to 25Hz by double vsync.
- Sprites are ported from the PICO-8 cart's sheet at 5/8 scale, hand-pixelled.

## Building / running

BeebAsm and b2 are expected in `tools/` (gitignored — grab
[beebasm](https://github.com/stardot/beebasm/releases) into `tools/beebasm/` and
[b2](https://github.com/tom-seddon/b2/releases) into `tools/b2/`). Then:

```powershell
.\build.ps1        # assemble build\depthcharge.ssd (bootable)
.\build.ps1 -run   # ...and boot it in b2
```

The `.ssd` also works in BeebEm, jsbeeb, or on real hardware from a Gotek/MMC.
