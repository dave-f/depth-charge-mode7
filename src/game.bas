REM Depth Charge (Mode 7) - object walker test, real sprites
REM Z/X steer ship, SPACE drops a charge, Q quits
MODE 7
HIMEM=&7700
*LOAD PLOT
VDU 23;8202;0;0;0;
init%=&7700:walk%=&7712
evt%=&7715:tab%=&7718
REM lane colours on blue water: white,cyan,yellow,green,magenta,red
DIM lane% 5
lane%?0=151:lane%?1=150:lane%?2=147:lane%?3=146:lane%?4=149:lane%?5=145
PROCscreen
SC%=0:HS%=0:SEC%=60:LS%=-1:CA%=0:MI%=0
PROChud
PRINT TAB(0,24);CHR$(134);"Z/X STEER  SPACE DROP  Q QUITS";
REM slot 0 ship (parked; BASIC pokes x), 1-3 subs (types 0/1/2), 4 charge, 5 mine
PROCspawn(0,0,30,10,0,0,6,57,0,74)
REM subs patrol colour bands 1/3/5; band 0 is open water below the ship
PROCspawn(1,1,6,25,48,0,6,62,0,74)
PROCspawn(2,2,62,43,-30,0,6,62,0,74)
PROCspawn(3,3,10,61,16,0,6,62,0,74)
S%=30
FR%=0:T0%=TIME
REPEAT
A%=19:CALL &FFF4
IF INKEY(-98) THEN S%=S%-1
IF INKEY(-67) THEN S%=S%+1
IF S%<6 THEN S%=6
IF S%>57 THEN S%=57
tab%?3=S%
CALL walk%
IF ?evt% THEN PROCevents
IF CA%=0 AND INKEY(-99) THEN CA%=1:PROCspawn(4,4,S%+10,16,0,128,6,77,15,63):PROCdc
IF MI%=0 AND RND(100)=1 THEN PROCmine
SEC%=60-(TIME-T0%) DIV 100
IF SEC%<0 THEN SEC%=0
IF SEC%<>LS% THEN LS%=SEC%:PROCtime
FR%=FR%+1
IF FR% MOD 50=0 THEN PRINT TAB(30,0);CHR$(134);STR$(INT(FR%*1000/(TIME-T0%))/10);"HZ ";
UNTIL INKEY(-17)
PROCscreen
END
DEF PROCmine
LOCAL B%
B%=tab%+RND(3)*16
IF B%?0<>1 THEN ENDPROC
MI%=1
PROCspawn(5,5,B%?3+7,B%?5+4,0,-64,6,77,16,74)
ENDPROC
DEF PROCevents
LOCAL I%,B%
FOR I%=1 TO 5
B%=tab%+I%*16
IF B%?0=2 THEN PROChandle(I%,B%)
NEXT
?evt%=0
ENDPROC
DEF PROChandle(I%,B%)
IF I%=4 THEN CA%=0:B%?0=0:PROCdc:ENDPROC
IF I%=5 THEN MI%=0:B%?0=0:ENDPROC
REM sub re-enters from the side it is heading away from
IF B%?7>127 THEN B%?3=62 ELSE B%?3=6
B%?2=0:B%?10=255:B%?0=1
ENDPROC
DEF PROChud
PRINT TAB(0,0);CHR$(131);"SCORE ";CHR$(135);STR$(SC%);
PRINT TAB(15,0);CHR$(131);"HI ";CHR$(135);STR$(HS%);
PRINT TAB(0,1);CHR$(131);"TIME";
PRINT TAB(15,1);CHR$(131);"DC ";
PROCtime
PROCdc
ENDPROC
DEF PROCtime
PRINT TAB(5,1);CHR$(135);STR$(SEC%);" ";
ENDPROC
DEF PROCdc
PRINT TAB(18,1);CHR$(135);STR$(5-CA%);
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
