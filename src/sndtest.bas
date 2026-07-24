REM Depth Charge - sound test / envelope audition
REM The disc still boots the game (MAIN). To audition sounds:
REM   press Q at the title to drop to BASIC, then  CHAIN"SND"
REM Four ENVELOPEs, one per starter effect - tune the numbers and rebuild.
MODE 7
*FX210,0
REM 1 SONAR PING - classic "piiing": steady high pitch, sharp attack transient
REM then a long smooth ring-out tail (best a square-wave chip can do - no reverb).
REM AD=-6 snaps to the sustain level; AS=-2 is the ~1.5s ring-out to silence.
ENVELOPE 1,131,0,0,0,0,0,0,127,-6,-2,0,126,100
REM 2 CHARGE DROP - short heavy thud: fast low pitch drop, snappy decay like 3
ENVELOPE 2,1,-5,0,0,18,0,0,127,-4,0,0,126,0
REM 3 EXPLOSION   - noise channel, full then fades (amplitude env only)
ENVELOPE 3,1,0,0,0,0,0,0,127,-3,0,0,126,0
REM 4 DEATH       - low doom tone sliding down over ~2s
ENVELOPE 4,2,-1,-1,-2,60,60,40,127,0,0,-2,126,126
PROCmenu
REPEAT
K=GET
IF K=49 PROCping
IF K=50 SOUND 2,2,120,20
IF K=51 SOUND 0,3,6,20
IF K=52 SOUND 4,4,120,40
IF K=71 OR K=103 THEN CHAIN"MAIN"
UNTIL K=81 OR K=113
*FX15,1
MODE 7
END
DEF PROCping
REM Fake echo: the exact same enveloped ping fired 3 times across the 3 tone
REM channels, staggered. A silent sound (amp 0) queued ahead of each repeat
REM delays it. All identical to the main ping - same pitch, ring-out, volume.
SOUND 1,1,150,40
SOUND 2,0,0,28
SOUND 2,1,150,40
SOUND 3,0,0,58
SOUND 3,1,150,40
ENDPROC
DEF PROCmenu
CLS
PRINT TAB(10,1);CHR$(141);CHR$(131);"DEPTH CHARGE"
PRINT TAB(10,2);CHR$(141);CHR$(131);"DEPTH CHARGE"
PRINT TAB(12,4);CHR$(134);"SOUND TEST"
PRINT
PRINT TAB(7);CHR$(131);"1";CHR$(135);"  SONAR BLIP"
PRINT TAB(7);CHR$(131);"2";CHR$(135);"  CHARGE DROP"
PRINT TAB(7);CHR$(131);"3";CHR$(135);"  EXPLOSION"
PRINT TAB(7);CHR$(131);"4";CHR$(135);"  DEATH"
PRINT
PRINT TAB(7);CHR$(133);"G";CHR$(135);"  PLAY GAME"
PRINT TAB(7);CHR$(133);"Q";CHR$(135);"  QUIT TO BASIC"
PRINT
PRINT TAB(4);CHR$(134);"Press 1-4 to hear each sound"
ENDPROC
