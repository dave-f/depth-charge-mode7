REM Depth Charge (Mode 7) - object walker test
REM Z/X steer ship, SPACE drops a charge, Q quits
MODE 7
HIMEM=&7700
*LOAD PLOT
VDU 23;8202;0;0;0;
init%=&7700:walk%=&7712
evt%=&7715:tab%=&7718
DIM lane% 5
lane%?0=150:lane%?1=146:lane%?2=147:lane%?3=149:lane%?4=145:lane%?5=148
PROCscreen
PRINT TAB(0,0);"Z/X STEER  SPACE DROP  Q QUITS"
REM slot 0 ship (parked; BASIC pokes x), 1-3 subs in lanes 0/2/4, 4 charge
PROCspawn(0,0,30,8,0,0,2,57,0,74)
PROCspawn(1,1,2,15,48,0,2,62,0,74)
PROCspawn(2,1,62,33,-30,0,2,62,0,74)
PROCspawn(3,1,10,51,16,0,2,62,0,74)
CA%=0
S%=30
FR%=0:T0%=TIME
REPEAT
A%=19:CALL &FFF4
IF INKEY(-98) THEN S%=S%-1
IF INKEY(-67) THEN S%=S%+1
IF S%<2 THEN S%=2
IF S%>57 THEN S%=57
tab%?3=S%
CALL walk%
IF ?evt% THEN PROCevents
IF CA%=0 AND INKEY(-99) THEN CA%=1:PROCspawn(4,2,S%+7,13,0,128,0,73,12,61)
FR%=FR%+1
IF FR% MOD 50=0 THEN PRINT TAB(33,0);INT(FR%*1000/(TIME-T0%))/10;"HZ ";
UNTIL INKEY(-17)
PROCscreen
END
DEF PROCevents
LOCAL I%,B%
FOR I%=1 TO 4
B%=tab%+I%*16
IF B%?0=2 THEN PROChandle(I%,B%)
NEXT
?evt%=0
ENDPROC
DEF PROChandle(I%,B%)
IF I%=4 THEN CA%=0:B%?0=0:ENDPROC
REM sub re-enters from the side it is heading away from
IF B%?7>127 THEN B%?3=62 ELSE B%?3=2
B%?2=0:B%?10=255:B%?0=1
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
REM sky rows 2-4 white, water rows 5-22 in lane colours
FOR R%=2 TO 4
?&71=R%:?&72=151:CALL init%
NEXT
FOR L%=0 TO 5
FOR R%=0 TO 2
?&71=5+L%*3+R%:?&72=lane%?L%
CALL init%
NEXT
NEXT
ENDPROC
