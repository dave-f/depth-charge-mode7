# Design notes — Depth Charge Mode 7 port

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

- 50Hz frame loop, sync via OSBYTE 19 (*FX 19).
- Keep fractional x positions internally (original sub speeds are 0.05–0.3 px/frame
  effective); round to sixels only at draw time to avoid stutter between speed tiers.
- PICO-8 `time%n` modulo counters map directly to a frame counter.

## Implementation

- BBC BASIC for game logic; inline 6502 assembler for sixel plot/erase/sprite
  routines writing directly to &7C00 (OSWRCH too slow).
- Sprite routine: sixel (x,y) → cell address + bit within graphics char; OR to draw,
  AND-mask to erase. Graphics chars are &20 + 6-bit sixel pattern (bit 6 always set
  for the graphics range &A0+... check exact encoding when implementing).
- Sound: 4 effects to port (fire, explosion, death, reset jingle) via SOUND/ENVELOPE;
  noise channel for explosions. PICO-8 cart sfx 0,2,3,4 (sfx 1 unused in original).

## Gameplay parity checklist (from depth.p8 v1.1)

- 60s timer, +10s per sub sunk; scores 20/50/80 by sub type
- Max 5 charges in flight, 5 subs, 8 mines; 6 lanes with occupancy flags
- Mine launch: 1%/frame per sub while on-screen (both directions — v1.1 fix!)
- Charge physics: fast fall + drift above waterline, slow sink below
- Death: mine under ship at surface, or timer out; sinking-ship anim then reset
- High score kept across games (session only)

## Toolchain

- BeebAsm to build; output .ssd disc image
- Emulators: b2 / BeebEm / jsbeeb for dev; real hardware someday
