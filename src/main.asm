\ Depth Charge (Mode 7) — disc image build script for BeebAsm.
\ Game logic is BBC BASIC (game.bas, tokenised via PUTBASIC); the sixel
\ plot/sprite machine code (sixel.asm) is assembled to PLOT and *LOADed
\ by the BASIC, which sets HIMEM below it.

ORG &7400
GUARD &7C00             \ don't run into screen memory

INCLUDE "src/sixel.asm"

SAVE "PLOT", start, end

PUTBASIC "src/game.bas", "MAIN"

\ Standalone sound-test menu (audition the 4 SOUND envelopes): CHAIN"SND"
PUTBASIC "src/sndtest.bas", "SND"

\ Boot with CHAIN, not beebasm's -boot (which *RUNs — wrong for a BASIC file)
PUTTEXT "src/boot.txt", "!Boot", 0, 0
