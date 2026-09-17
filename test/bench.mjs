// bench.mjs - what do BBC BASIC statements cost? Types a benchmark program
// into a clean machine and prints its output: centiseconds per 1000 runs
// of each statement inside FOR/NEXT (subtract the empty loop). Line 140
// overflows on purpose-ish (I%*&1000000 past 127); read up to it.
//   node test/bench.mjs [B-DFS1.2|Master]
import { MachineSession } from "../node_modules/jsbeeb/src/machine-session.js";
const model = process.argv[2] || "B-DFS1.2";
const s = new MachineSession(model, { tube: false });
await s.initialise(); await s.boot(30);
const prog = `
10 MODE 7:DIM T% 400:tab%=T%:B%=T%:C%=T%+16:M%=9:N=1000
20 T=TIME:FOR I%=1 TO N:NEXT:PRINT "empty loop     ";TIME-T
30 T=TIME:FOR I%=1 TO N:C%?1=5:NEXT:PRINT "byte poke      ";TIME-T
40 T=TIME:FOR I%=1 TO N:C%!6=&FFDA0000:NEXT:PRINT "word poke      ";TIME-T
50 T=TIME:FOR I%=1 TO N:C%?3=B%?3+7:NEXT:PRINT "peek add poke  ";TIME-T
60 T=TIME:FOR I%=1 TO N:C%?1=5:C%?2=0:C%?3=B%?3+7:C%?4=0:C%?5=B%?5-5:NEXT:PRINT "5 pokes 1 line ";TIME-T
70 T=TIME:FOR I%=1 TO N:IF tab%?144 THEN M%=10:IF tab%?160 THEN M%=11:IF tab%?176 THEN M%=12
75 NEXT:PRINT "if chain(false)";TIME-T
80 T=TIME:FOR I%=1 TO N:R%=RND(25):NEXT:PRINT "rnd            ";TIME-T
90 T=TIME:FOR I%=1 TO N:IF R%<4 THEN IF tab%?(R%*16)=1 THEN M%=1
95 NEXT:PRINT "if r<4 (false) ";TIME-T
100 T=TIME:FOR I%=1 TO N:PROCa:NEXT:PRINT "proc 0 params  ";TIME-T
110 T=TIME:FOR I%=1 TO N:PROCb(I%):NEXT:PRINT "proc 1 param   ";TIME-T
120 T=TIME:FOR I%=1 TO N:PROCc(I%,1,2,3,4,5,6,7,8,9):NEXT:PRINT "proc 10 params ";TIME-T
130 T=TIME:FOR I%=1 TO N:X%=tab%+I%*16:NEXT:PRINT "tab+i*16       ";TIME-T
140 T=TIME:FOR I%=1 TO N:X%=I%+I%*256+I%*65536+I%*&1000000:NEXT:PRINT "3 muls         ";TIME-T
150 T=TIME:FOR I%=1 TO N:PRINT TAB(19,1);CHR$(135);STR$(3);:NEXT:PRINT "print hud      ";TIME-T
160 T=TIME:FOR I%=1 TO N:X%=?&7418:NEXT:PRINT "peek abs       ";TIME-T
170 T=TIME:FOR I%=1 TO N:IF ?&7418 THEN M%=1
175 NEXT:PRINT "if peek (false)";TIME-T
180 T=TIME:FOR I%=1 TO N:S%=60-(TIME-T)DIV 100:NEXT:PRINT "sec calc       ";TIME-T
190 T=TIME:FOR I%=1 TO N:CALL &FFE7:NEXT:PRINT "call (osnewl)  ";TIME-T
200 T=TIME:FOR I%=1 TO N:X%=V% AND &FFFF:NEXT:PRINT "and            ";TIME-T
210 END
220 DEF PROCa:ENDPROC
230 DEF PROCb(A%):ENDPROC
240 DEF PROCc(A%,B%,C%,D%,E%,F%,G%,H%,J%,K%):ENDPROC
`;
await s.loadBasic(prog);
await s.type("RUN\r");
const out = await s.runUntilPrompt(120);
console.log(model);
console.log(out);
process.exit(0);
