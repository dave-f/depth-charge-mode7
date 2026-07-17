REM Depth Charge (Mode 7) - port of the PICO-8 original
REM Z/X steer, SPACE drops a charge (max 3), Q quits
REM Speeds are original px/frame@30 converted to sixels/frame@25Hz (x0.75)
MODE 7
*FX200,3
HIMEM=&7500
*LOAD PLOT
VDU 23;8202;0;0;0;
init%=&7500:walk%=&7512
evt%=&7515:tab%=&7518
REM X%=1 stays set for the per-frame OSBYTE 15,1 input buffer flush
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
*FX15,1
*FX200,0
MODE 7
END
DEF PROCattract
PROCwipe
PRINT TAB(13,11);CHR$(141);CHR$(135);"DEPTH CHARGE";
PRINT TAB(13,12);CHR$(141);CHR$(135);"DEPTH CHARGE";
PRINT TAB(11,14);CHR$(134);"PRESS SPACE TO PLAY";
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
OS%=-1
FR%=0:T0%=TIME
REPEAT
A%=19:CALL &FFF4
A%=19:CALL &FFF4
A%=15:CALL &FFF4
K%=0
IF INKEY(-98) THEN K%=-192
IF INKEY(-67) THEN K%=192
SX%=SX%+K%
IF SX%<1536 THEN SX%=1536
IF SX%>57*256 THEN SX%=57*256
tab%?3=SX% DIV 256
K%=INKEY(-99)
IF K% AND OS%=0 AND CC%<3 THEN PROCdrop
OS%=K%
CALL walk%
IF ?evt% THEN PROCevents
IF MN%<4 THEN PROCmines
IF DEAD%=0 THEN SEC%=60-(TIME-TB%) DIV 100
IF SEC%<0 THEN SEC%=0
IF SEC%<>LS% THEN LS%=SEC%:PROCtime
IF SEC%=0 THEN DEAD%=1
FR%=FR%+1
IF FR% MOD 50=0 THEN PRINT TAB(30,0);CHR$(134);STR$(INT(FR%*1000/(TIME-T0%))/10);"HZ ";
IF INKEY(-17) THEN QT%=1
UNTIL DEAD% OR QT%
IF QT%=0 THEN PROCdie
ENDPROC
DEF PROCdie
LOCAL I%,B%
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
DEF PROCdrop
LOCAL C%,M%
M%=0
FOR C%=4 TO 6
IF tab%?(C%*16)=0 AND M%=0 THEN M%=C%
NEXT
IF M%=0 THEN ENDPROC
CC%=CC%+1
PROCdc
REM sink quicker than the original's rate (19)
PROCspawn(M%,4,(SX% DIV 256)+10,16,0,38,6,77,15,64)
ENDPROC
DEF PROCmines
LOCAL I%,B%
FOR I%=1 TO 3
IF RND(100)=1 THEN B%=tab%+I%*16:IF B%?0=1 AND MN%<4 THEN PROClmine(B%)
NEXT
ENDPROC
DEF PROClmine(B%)
LOCAL M%,C%
M%=0
FOR C%=9 TO 12
IF tab%?(C%*16)=0 AND M%=0 THEN M%=C%
NEXT
IF M%=0 THEN ENDPROC
MN%=MN%+1
REM ymin 13: mine ink reaches the hull's bottom row before expiring
REM rise quicker than the original's rate (-19)
PROCspawn(M%,5,B%?3+7,B%?5-5,0,-38,6,77,13,74)
ENDPROC
DEF PROCevents
LOCAL I%,B%
FOR I%=1 TO 19
B%=tab%+I%*16
IF B%?0>1 THEN PROChandle(I%,B%)
NEXT
?evt%=0
ENDPROC
DEF PROChandle(I%,B%)
LOCAL ST%
ST%=B%?0
B%?0=0
IF I%>=17 THEN ENDPROC
IF I%>=9 THEN MN%=MN%-1:IF ST%=3 THEN DEAD%=1
IF I%>=9 THEN ENDPROC
IF I%>=4 THEN CC%=CC%-1:PROCdc:ENDPROC
REM sub: sunk scores, buys time and sinks as an effect; then relaunch
IF ST%=3 THEN SC%=SC%+30*B%?1-10:TB%=TB%+1000:PROCscore:PROCsink(B%)
PROCnewsub(I%)
ENDPROC
DEF PROCnewsub(I%)
LOCAL V%,X%
V%=9+RND(48)
X%=6
IF RND(2)=1 THEN X%=62:V%=-V%
PROCspawn(I%,RND(3),X%,bandy%?I%,V%,0,6,62,0,74)
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
C%?1=B%?1
C%?2=B%?2:C%?3=B%?3
C%?4=B%?4:C%?5=B%?5
C%?6=B%?6:C%?7=B%?7
C%?8=38:C%?9=0
C%?10=255:C%?11=255
C%?12=6:C%?13=62:C%?14=0:C%?15=T%
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
SX%=30*256
PROCspawn(0,0,30,9,0,0,6,57,0,74)
PROChud
PRINT TAB(4,24);CHR$(134);"Z/X STEER  SPACE DROP  Q QUITS";
ENDPROC
DEF PROCspawn(N%,SP%,X%,Y%,VX%,VY%,M0%,M1%,M2%,M3%)
LOCAL B%,V%
B%=tab%+N%*16
B%?1=SP%
B%?2=0:B%?3=X%
B%?4=0:B%?5=Y%
V%=VX%:IF V%<0 THEN V%=V%+65536
B%?6=V% AND 255:B%?7=V% DIV 256
V%=VY%:IF V%<0 THEN V%=V%+65536
B%?8=V% AND 255:B%?9=V% DIV 256
B%?10=255:B%?11=255
B%?12=M0%:B%?13=M1%:B%?14=M2%:B%?15=M3%
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
