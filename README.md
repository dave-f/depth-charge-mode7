# Depth Charge (BBC Micro, Mode 7)

A BBC Micro port of [Depth Charge](https://github.com/dave-f/depth-charge), rendered
entirely in teletext — Mode 7, the Beeb's 1KB text mode, coaxed into being a game display.

The original is a PICO-8 take on the old arcade classic, also playable on the
[Lexaloffle BBS](https://www.lexaloffle.com/bbs/?tid=4045) (`load #depthcharge` in PICO-8).

## Why Mode 7?

For the novelty, mostly. Teletext gives you 40×25 characters; with sixel graphics
characters that's an effective 80×75 "pixels", one colour per row without spending
character cells. A game of naval silhouettes in fixed horizontal lanes turns out to
fit those constraints surprisingly well.

## Status

Early days — design notes in [notes/design.md](notes/design.md).

## Building / running

Toolchain: BBC BASIC game logic (plain text in `src/game.bas`, tokenised at build
time via BeebAsm's `PUTBASIC`) with 6502 assembler for the sixel plotting routines,
assembled to a bootable disc image via BeebAsm, tested in b2.

BeebAsm and b2 are expected in `tools/` (gitignored — grab
[beebasm](https://github.com/stardot/beebasm/releases) into `tools/beebasm/` and
[b2](https://github.com/tom-seddon/b2/releases) into `tools/b2/`). Then:

```powershell
.\build.ps1        # assemble build\depthcharge.ssd
.\build.ps1 -run   # ...and boot it in b2
```
