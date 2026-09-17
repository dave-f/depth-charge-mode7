REM Depth Charge (Mode 7) - port of the PICO-8 original
REM Z/X steer, SPACE drops a charge (max 3), Q quits
REM Speeds are original px/frame@30 converted to sixels/frame@25Hz (x0.75)
REM Per-frame work (vsync, keys, steering) is in the PLOT code's frame%
REM entry; BASIC here only reacts to its flag bytes (see sixel.asm header)
MODE 7
*FX200,3
HIMEM=&7400
*LOAD PLOT
VDU 23;8202;0;0;0;
REM frame% counts vsync events: point EVNTV at its handler, enable them
?&220=?&741E:?&221=?&741F
*FX14,4
REM Sound envelopes (see sndtest.bas): 1 sonar,2 charge drop,3 boom,4 death
ENVELOPE 1,131,0,0,0,0,0,0,127,-6,-2,0,126,100
ENVELOPE 2,1,-5,0,0,18,0,0,127,-4,0,0,126,0
ENVELOPE 3,1,0,0,0,0,0,0,127,-3,0,0,126,0
ENVELOPE 4,2,-1,-1,-2,60,60,40,127,0,0,-2,126,126
init%=&7400:walk%=&7412:frame%=&7415
evt%=&7418:flg%=&7419:prv%=&741A:tab%=&7420:evq%=&7560
REM X%=1 stays set for the attract loop's OSBYTE 15,1 input buffer flush
X%=1
REM lane colours on blue water: white,cyan,yellow,green,magenta,red
DIM lane% 5
lane%?0=151:lane%?1=150:lane%?2=147:lane%?3=146:lane%?4=149:lane%?5=145
REM band y is the drawn position: ink sits one row lower (top pad row)
DIM bandy% 3
bandy%?1=24:bandy%?2=42:bandy%?3=60
HS%=0:QT%=0:SC%=0:SEC%=60:CC%=0
REPEAT
PROCattract
IF QT%=0 THEN PROCgame
UNTIL QT%
*FX13,4
*FX15,1
*FX200,0
MODE 7
END
DEF PROCsonar
REM Fake echo: the same enveloped ping fired 3x, staggered across the tone
REM channels (a silent sound delays each repeat) - see sndtest.bas
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
DEF PROCgame
PROCwipe
SC%=0:CC%=0:MN%=0:DEAD%=0:SEC%=60:LS%=-1:TB%=TIME
PROChud
LOCAL I%
FOR I%=1 TO 3
PROCnewsub(I%)
NEXT
REM SPACE is still down from the title: mark it held so it doesn't fire
?prv%=1
REPEAT
CALL frame%
IF ?flg% THEN PROCflags
IF ?evt% THEN PROCevents
SEC%=60-(TIME-TB%) DIV 100
IF SEC%<>LS% THEN PROCtick
UNTIL DEAD% OR QT%
IF QT%=0 THEN PROCdie
ENDPROC
DEF PROCflags
F%=?flg%
IF (F% AND 1) AND CC%<3 THEN PROCdrop
IF F% AND 2 THEN QT%=1
IF (F% AND 4) AND MN%<4 THEN PROCmines
ENDPROC
DEF PROCtick
IF SEC%<1 THEN SEC%=0:DEAD%=1
LS%=SEC%
PROCtime
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
REM --- spawning. These run inside the 40ms frame, so they are written for
REM speed: no FOR scans, no 10-parameter PROCspawn (parameter passing is
REM slow in BBC BASIC), and the slot's 4-byte fields poked as words:
REM   !6  = vx lo/hi, vy lo/hi       !10 = &FFFF last-drawn (never) + 2 pad
REM   !12 = xmin, xmax, ymin, ymax   (see sixel.asm object table)
DEF PROCdrop
REM CC%<3, so one of the charge slots 4-6 is free
M%=4
IF tab%?64 THEN M%=5:IF tab%?80 THEN M%=6
CC%=CC%+1
PROCdc
SOUND 2,2,120,20
C%=tab%+M%*16
REM from under the ship, sinking at 38/256 (quicker than the original's 19)
C%?1=4:C%?2=0:C%?3=tab%?3+10:C%?4=0:C%?5=16
C%!6=&260000
C%!10=&FFFF
C%!12=&400F4D06
C%?0=1
ENDPROC
DEF PROCmines
REM every 4th frame (frame% slow tick): each sub 1-in-25 = 1%/frame
R%=RND(25)
IF R%<4 THEN IF tab%?(R%*16)=1 THEN PROClmine(tab%+R%*16)
ENDPROC
DEF PROClmine(B%)
REM MN%<4, so one of the mine slots 9-12 is free
M%=9
IF tab%?144 THEN M%=10:IF tab%?160 THEN M%=11:IF tab%?176 THEN M%=12
MN%=MN%+1
C%=tab%+M%*16
REM from the conning tower, rising at -38/256 (quicker than the original's
REM -19); ymin 13 so the mine's ink reaches the hull's bottom row first
C%?1=5:C%?2=0:C%?3=B%?3+7:C%?4=0:C%?5=B%?5-5
C%!6=&FFDA0000
C%!10=&FFFF
C%!12=&4A0D4D06
C%?0=1
ENDPROC
DEF PROCnewsub(I%)
C%=tab%+I%*16
V%=9+RND(48)
IF RND(2)=1 THEN C%?3=62:V%=-V% ELSE C%?3=6
C%?1=RND(3):C%?2=0:C%?4=0:C%?5=bandy%?I%
C%!6=V% AND &FFFF
C%!10=&FFFF
C%!12=&4A003E06
C%?0=1
ENDPROC
DEF PROCevents
REM the walker queues the slot numbers it expired/hit in evq%
LOCAL I%
FOR I%=0 TO ?evt%-1
PROChandle(evq%?I%)
NEXT
?evt%=0
ENDPROC
DEF PROChandle(I%)
B%=tab%+I%*16
ST%=B%?0:B%?0=0
IF I%>3 THEN PROCother(I%):ENDPROC
REM sub: sunk scores, buys time and sinks as an effect; then relaunch
IF ST%=3 THEN SC%=SC%+30*B%?1-10:TB%=TB%+1000:PROCscore:PROCsink(B%):SOUND 0,3,6,20
PROCnewsub(I%)
ENDPROC
DEF PROCother(I%)
REM charge expired, or a mine gone: fizzled at the surface or into the ship
IF I%<9 THEN CC%=CC%-1:PROCdc:ENDPROC
IF I%>16 THEN ENDPROC
MN%=MN%-1
IF ST%=3 THEN DEAD%=1 ELSE SOUND 0,3,6,20
ENDPROC
DEF PROCsink(B%)
LOCAL E%,C%,T%
E%=0
FOR C%=17 TO 19
IF tab%?(C%*16)=0 AND E%=0 THEN E%=C%
NEXT
IF E%=0 THEN ENDPROC
C%=tab%+E%*16
T%=B%?5+10
IF T%>61 THEN T%=61
REM copy sprite, x, y, vx from the sunk sub (its status byte is already 0)
C%!0=B%!0
C%!4=B%!4
REM vy=38 sinks it; last-drawn &FFFF = never (the collision pass erased it)
C%!8=38+&FFFF0000
C%!12=6+62*256+T%*&1000000
C%?0=1
ENDPROC
DEF PROCscore
PRINT TAB(7,0);CHR$(135);STR$(SC%);
IF SC%>HS% THEN HS%=SC%:PRINT TAB(19,0);CHR$(135);STR$(HS%);
ENDPROC
DEF PROChud
PRINT TAB(0,0);CHR$(131);"SCORE ";CHR$(135);STR$(SC%);"   ";
PRINT TAB(15,0);CHR$(131);"HI ";CHR$(135);STR$(HS%);
PRINT TAB(0,1);CHR$(131);"TIME";
PRINT TAB(15,1);CHR$(131);"DC ";
PROCtime
PROCdc
ENDPROC
DEF PROCtime
PRINT TAB(7,1);CHR$(135);STR$(SEC%);" ";
ENDPROC
DEF PROCdc
PRINT TAB(19,1);CHR$(135);STR$(3-CC%);
ENDPROC
DEF PROCwipe
LOCAL I%
FOR I%=0 TO 19
tab%?(I%*16)=0
NEXT
?evt%=0
PROCscreen
PROCfloor
PROCspawn(0,0,30,9,0,0,6,57,0,74)
PROChud
PRINT TAB(4,24);CHR$(134);"Z/X STEER  SPACE DROP  Q QUITS";
ENDPROC
DEF PROCspawn(N%,SP%,X%,Y%,VX%,VY%,M0%,M1%,M2%,M3%)
REM 4-byte pokes keep this cheap: a spawn happens inside the frame budget
LOCAL B%
B%=tab%+N%*16
REM +2/+3 x lo/hi, +4/+5 y lo/hi (lo bytes 0)
B%!2=X%*256+Y%*&1000000
REM +6 vx, +8 vy: signed 16-bit words (AND masks vx to its low word)
B%!6=(VX% AND &FFFF)+VY%*65536
REM +10/+11 last drawn = never (+12/+13 overwritten just below)
B%!10=&FFFF
REM +12..+15 bounds box xmin,xmax,ymin,ymax
B%!12=M0%+M1%*256+M2%*65536+M3%*&1000000
B%?1=SP%
B%?0=1
ENDPROC
DEF PROCscreen
REM sky rows 2-4: white on cyan; water rows 5-22: lane colours on blue
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
DEF PROCfloor
REM yellow BACKGROUND: solid colour from col 1, no fg code cells needed
LOCAL C%,R%
R%=&7C00+23*40
?R%=147
R%?1=157
FOR C%=2 TO 39
R%?C%=&A0
NEXT
ENDPROC
