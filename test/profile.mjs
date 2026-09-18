// profile.mjs - a BBC BASIC line profiler on the emulator. Boots the game (run
// from the repo root), plays N fields, and attributes every CPU cycle to the
// BASIC line the interpreter was executing (its statement pointer at &0B/&0C),
// or to "MC" when the CPU is in the PLOT code (&7000-&7BFF, including the
// frame entry's vsync wait). Time inside MOS calls made by a statement
// (PRINT, SOUND, CALL &FFF4) lands on that statement's line, which is the
// point. Lines are matched to src/game.bas by order (PUTBASIC keeps it).
//   node test/profile.mjs [B-DFS1.2|Master] [fields=600] [dropEvery=0] [top=30]
import { readFileSync } from "node:fs";
import { MachineSession } from "../node_modules/jsbeeb/src/machine-session.js";
const model = process.argv[2] || "B-DFS1.2";
const fields = Number(process.argv[3] || 600);
const dropEvery = Number(process.argv[4] || 0);
const top = Number(process.argv[5] || 30);
const onlyEvt = Number(process.argv[6] || 0);   // attribute only frames whose walker queued >= this many events

const src = readFileSync("src/game.bas", "utf8").replace(/\r\n/g, "\n").split("\n").filter((l, i, a) => i < a.length - 1 || l !== "");

const s = new MachineSession(model, { tube: false });
await s.initialise(); await s.boot(30);
s.loadDisc("build/depthcharge.ssd");
s.keyDown(16); s.reset(true); await s.runFrames(50); s.keyUp(16); await s.runFrames(250);
s.keyDown(32); await s.runFrames(3); s.keyUp(32); await s.runFrames(60);

// map program text addresses -> line index. Line: &0D, line hi, line lo, len, tokens...
const rb = (a) => s._machine.readbyte(a);
const page = rb(0x18) << 8;
const lines = [];   // {start, end, no}
for (let a = page; ; ) {
    if (rb(a) !== 0x0d) throw new Error("lost sync in program text at &" + a.toString(16));
    const hi = rb(a + 1);
    if (hi === 0xff) break;
    const len = rb(a + 3);
    lines.push({ start: a, end: a + len, no: (hi << 8) | rb(a + 2) });
    a += len;
}
if (lines.length !== src.length) console.error(`warning: ${lines.length} lines in memory, ${src.length} in src/game.bas`);
const lineAt = (ptr) => {
    let lo = 0, hi = lines.length - 1;
    while (lo <= hi) {
        const m = (lo + hi) >> 1;
        if (ptr < lines[m].start) hi = m - 1;
        else if (ptr >= lines[m].end) lo = m + 1;
        else return m;
    }
    return -1;
};

const F = 39936, MS = 2000;
const cost = new Float64Array(lines.length);
const mosCost = new Float64Array(lines.length);   // of which: CPU in the MOS (&C000+): OS calls + interrupts
const visits = new Uint32Array(lines.length);
let mc = 0, other = 0, last = s.elapsedCycles, lastLine = -2;
let curEvt = 0, framesCounted = 0, frameOn = onlyEvt === 0;
const [, wlo, whi] = s.readMemory(0x7012, 3);
const walk = wlo | (whi << 8);
const cpu = s._machine.processor;
const evHook = cpu.debugWrite.add((addr, val) => {
    if (addr === 0x7020 && val > 0) { curEvt = val; if (onlyEvt && val >= onlyEvt && !frameOn) { frameOn = true; framesCounted++; } }
    return false;
});
const hook = cpu.debugInstruction.add((pc) => {
    const now = s.elapsedCycles, d = now - last; last = now;
    if (pc === walk) { curEvt = 0; if (onlyEvt) frameOn = false; else framesCounted++; }
    if (!frameOn) return false;
    if (pc >= 0x7000 && pc < 0x7c00) { mc += d; return false; }
    const li = lineAt(rb(0x0b) | (rb(0x0c) << 8));
    if (li < 0) { other += d; return false; }
    cost[li] += d;
    if (pc >= 0xc000) mosCost[li] += d;
    if (li !== lastLine) { visits[li]++; lastLine = li; }
    return false;
});
if (dropEvery > 0) {
    for (let done = 0; done < fields; done += dropEvery) {
        s.keyDown(32); await s.runFor(F * 4); s.keyUp(32);
        await s.runFor(F * Math.max(1, Math.min(dropEvery, fields - done) - 4));
    }
} else {
    await s.runFor(F * fields);
}
hook.remove(); evHook.remove();

const total = cost.reduce((a, b) => a + b, 0) + mc + other;
console.log(`${model}: ${fields} fields = ${(fields * F / MS / 1000).toFixed(1)}s. MC ${(mc / MS).toFixed(0)}ms (${(100 * mc / total).toFixed(0)}%, incl. vsync wait), BASIC ${(cost.reduce((a, b) => a + b, 0) / MS).toFixed(0)}ms, other ${(other / MS).toFixed(0)}ms`);
if (onlyEvt) console.log(`only frames with >= ${onlyEvt} events: ${framesCounted} frames, BASIC ${(cost.reduce((a, b) => a + b, 0) / MS / Math.max(1, framesCounted)).toFixed(1)}ms per such frame`);
console.log("note: the line after CALL frame% is booked the frame entry's OS calls and the vsync wait's interrupts (BASIC moves its line pointer on before the CALL runs)");
console.log("  total ms  MOS ms   visits  ms/visit  line");
const order = [...cost.keys()].sort((a, b) => cost[b] - cost[a]).slice(0, top);
for (const i of order) {
    if (!cost[i]) break;
    const ms = cost[i] / MS;
    console.log(`  ${ms.toFixed(1).padStart(8)} ${(mosCost[i] / MS).toFixed(1).padStart(7)}  ${String(visits[i]).padStart(7)}  ${(ms / Math.max(1, visits[i])).toFixed(2).padStart(8)}  ${lines[i].no}: ${(src[i] ?? "?").slice(0, 66)}`);
}
process.exit(0);
