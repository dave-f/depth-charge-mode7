REM Depth Charge (Mode 7) - sixel plot routine test
MODE 7
HIMEM=&7A00
*LOAD PLOT
VDU 23;8202;0;0;0;
init%=&7A00:plot%=&7A03:unplot%=&7A06
REM lane colours: cyan,green,yellow,magenta,red,blue
DIM lane% 5
lane%?0=150:lane%?1=146:lane%?2=147:lane%?3=149:lane%?4=145:lane%?5=148
PROCwater
REM benchmark: 1000 random plots in the water (BASIC-loop speed)
T%=TIME
FOR I%=1 TO 1000
?&70=1+RND(78)
?&71=14+RND(54)
CALL plot%
NEXT
T%=TIME-T%
PRINT TAB(0,0);"1000 PLOTS IN ";T%/100;"S = ";INT(100000/T%);"/SEC"
PRINT TAB(0,1);CHR$(134);"ANY KEY FOR BOUNCE TEST"
A%=GET
PROCwater
PRINT TAB(0,0);"BOUNCE AT 50HZ - ANY KEY QUITS"
X%=10:Y%=30:U%=1:V%=1
REPEAT
?&70=X%:?&71=Y%:CALL plot%
A%=19:CALL &FFF4
?&70=X%:?&71=Y%:CALL unplot%
X%=X%+U%:Y%=Y%+V%
IF X%<3 OR X%>78 THEN U%=-U%
IF Y%<16 OR Y%>67 THEN V%=-V%
UNTIL INKEY(0)<>-1
PROCwater
END
DEF PROCwater
REM water rows 5-22: 6 lanes x 3 char rows each
FOR L%=0 TO 5
FOR R%=0 TO 2
?&71=5+L%*3+R%:?&72=lane%?L%
CALL init%
NEXT
NEXT
ENDPROC
