REM Depth Charge (Mode 7) - port of the PICO-8 original
REM Z/X steer, SPACE drops a charge (max 3), Q quits
REM Speeds are original px/frame@30 converted to sixels/frame@25Hz (x0.75)
REM The game rules run in the PLOT machine code (sixel.asm): frame% locks
REM to 25Hz, reads the keys, steers, drops charges, launches mines,
REM respawns subs, runs the clock and walks/collides everything. BASIC
REM directs: scoring, sounds, the HUD, attract and death - driven by
REM frame%'s flag byte and event queue. Everything here runs inside a
REM 40ms frame, so it is written for speed: few statements, no PROC
REM parameters, no REMs inside PROC bodies (they cost ~0.5ms a visit),
REM and no PRINT with STR$ (hud% writes numbers into screen memory).
MODE 7
*FX200,3
HIMEM=&7100
*LOAD PLOT
VDU 23;8202;0;0;0;
REM frame% counts vsync events: point EVNTV at its handler, enable them
?&220=?&7126:?&221=?&7127
*FX14,4
REM Sound envelopes (see sndtest.bas): 1 sonar,2 charge drop,3 boom,4 death
ENVELOPE 1,131,0,0,0,0,0,0,127,-6,-2,0,126,100
ENVELOPE 2,1,-5,0,0,18,0,0,127,-4,0,0,126,0
ENVELOPE 3,1,0,0,0,0,0,0,127,-3,0,0,126,0
ENVELOPE 4,2,-1,-1,-2,60,60,40,127,0,0,-2,126,126
REM PLOT's entry points and the bytes it shares with BASIC (sixel.asm header)
init%=&7100:walk%=&7112:frame%=&7115:hud%=&7118:sub%=&711B
evt%=&7120:flg%=&7121:prv%=&7122:nchg%=&7125:rng%=&7128:secs%=&712E:tick%=&712F
tab%=&7130:evq%=&7270
REM X%=1 stays set for the attract loop's OSBYTE 15,1 input buffer flush
X%=1
REM lane colours on blue water: white,cyan,yellow,green,magenta,red
DIM lane% 5
lane%?0=151:lane%?1=150:lane%?2=147:lane%?3=146:lane%?4=149:lane%?5=145
HS%=0:QT%=0:SC%=0
REPEAT
PROCattract
IF QT%=0 THEN PROCgame
UNTIL QT%
*FX13,4
*FX15,1
*FX200,0
MODE 7
END
REM Fake echo: the same enveloped ping fired 3x, staggered across the tone
REM channels (a silent sound delays each repeat) - see sndtest.bas
DEF PROCsonar
SOUND 1,1,150,40
SOUND 2,0,0,28
SOUND 2,1,150,40
SOUND 3,0,0,58
SOUND 3,1,150,40
ENDPROC
DEF PROCattract
PROCwipe
PRINT TAB(13,11);CHR$(141);CHR$(135);"DEPTH CHARGE";
PRINT TAB(13,12);CHR$(141);CHR$(135);"DEPTH CHARGE";
PRINT TAB(11,14);CHR$(134);"PRESS SPACE TO PLAY";
PROCsonar
REPEAT UNTIL INKEY(-99)=0
REPEAT
A%=19:CALL &FFF4
A%=15:CALL &FFF4
CALL walk%
UNTIL INKEY(-99) OR INKEY(-17)
IF INKEY(-17) THEN QT%=1
ENDPROC
REM A game: 60 seconds on the clock, +10 per kill. The loop is four
REM statements; frame% does the rest and raises flags/events to act on.
REM ?prv%=1: SPACE is still down from the title, so mark it held.
DEF PROCgame
PROCwipe
SC%=0:DEAD%=0:?secs%=60:?tick%=25
PROChud
!rng%=TIME OR 1
FOR I%=1 TO 3
?&70=I%:CALL sub%
NEXT
?prv%=1
REPEAT
CALL frame%
IF ?flg% THEN PROCflags
IF ?evt% THEN PROCevents
UNTIL DEAD% OR QT%
IF QT%=0 THEN PROCdie
ENDPROC
REM flags: bit 0 a charge was dropped, bit 1 Q held, bit 2 time is up
DEF PROCflags
F%=?flg%
IF F% AND 1 THEN SOUND 2,2,120,20
IF F% AND 2 THEN QT%=1
IF F% AND 4 THEN DEAD%=1
ENDPROC
REM event codes from the walker: 1-3 a sub of that type sunk, 5 a mine
REM fizzled at the surface, 6 a mine hit the ship. Charges, respawns, the
REM clock bonus and the TIME/DC fields are all handled in machine code.
DEF PROCevents
LOCAL I%
FOR I%=0 TO ?evt%-1
E%=evq%?I%
IF E%<4 THEN PROCsunk ELSE IF E%=5 THEN SOUND 0,3,6,20 ELSE DEAD%=1
NEXT
?evt%=0
ENDPROC
REM a sub sunk: 20/50/80 points by type
DEF PROCsunk
SC%=SC%+30*E%-10
SOUND 0,3,6,20
!&70=8:!&72=SC%:CALL hud%
IF SC%>HS% THEN HS%=SC%:!&70=20:!&72=HS%:CALL hud%
ENDPROC
DEF PROCdie
LOCAL I%,B%
SOUND 4,4,120,40
FOR I%=1 TO 19
B%=tab%+I%*16
IF B%?0=1 THEN B%?6=0:B%?7=0:B%?8=0:B%?9=0
NEXT
FOR I%=1 TO 5
TM%=TIME+28
REPEAT UNTIL TIME>=TM%
tab%?5=tab%?5+1
CALL walk%
NEXT
PRINT TAB(15,12);CHR$(129);"GAME OVER";
TM%=TIME+300
REPEAT UNTIL TIME>=TM%
A%=15:CALL &FFF4
ENDPROC
REM --- HUD. Labels are PRINTed once per screen; the numbers go through
REM hud% (column ?&70, row ?&71, value !&72; !&70=&108 sets col 8 row 1),
REM which writes up to 5 digits straight into screen memory in ~2ms where
REM PRINT TAB/STR$ took ~10ms. In play the machine code redraws TIME and
REM DC itself; BASIC only touches SCORE and HI.
DEF PROChud
PRINT TAB(0,0);CHR$(131);"SCORE ";CHR$(135);
PRINT TAB(15,0);CHR$(131);"HI ";CHR$(135);
PRINT TAB(0,1);CHR$(131);"TIME";TAB(7,1);CHR$(135);
PRINT TAB(15,1);CHR$(131);"DC ";CHR$(135);
!&70=8:!&72=SC%:CALL hud%
!&70=20:!&72=HS%:CALL hud%
!&70=&108:!&72=?secs%:CALL hud%
!&70=&114:!&72=3-?nchg%:CALL hud%
ENDPROC
REM a fresh screen: empty object table, sea, floor, the ship (slot 0,
REM sprite 0, parked at x=30 on the waterline y=9, never drawn yet, box
REM 6..57 x 0..74 - see sixel.asm's object table), HUD and key legend
DEF PROCwipe
LOCAL I%
FOR I%=0 TO 19
tab%?(I%*16)=0
NEXT
?evt%=0:?nchg%=0:?secs%=60
PROCscreen
PROCfloor
tab%!0=&1E000000:tab%!4=&900:tab%!8=&FFFF0000:tab%!12=&4A003906:tab%?0=1
PROChud
PRINT TAB(4,24);CHR$(134);"Z/X STEER  SPACE DROP  Q QUITS";
ENDPROC
REM sky rows 2-4: white on cyan; water rows 5-22: lane colours on blue
DEF PROCscreen
?&73=150
FOR R%=2 TO 4
?&71=R%:?&72=151:CALL init%
NEXT
?&73=148
FOR L%=0 TO 5
FOR R%=0 TO 2
?&71=5+L%*3+R%:?&72=lane%?L%
CALL init%
NEXT
NEXT
ENDPROC
REM sea floor: yellow BACKGROUND, solid colour from col 1
DEF PROCfloor
LOCAL C%,R%
R%=&7C00+23*40
?R%=147
R%?1=157
FOR C%=2 TO 39
R%?C%=&A0
NEXT
ENDPROC
