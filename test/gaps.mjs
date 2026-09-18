// gaps.mjs - where does the frame time go? Boots the game (run from the repo
// root), plays N fields, and reports:
//   - a histogram of walker-to-walker gaps in fields (a 25Hz game is all 2s;
//     14-19 field gaps are the death sequence's deliberate waits)
//   - the BASIC+walker work per frame (walker start to the next CALL frame%),
//     in ms, grouped by what that frame had to do: the frame flags MC wrote
//     (1 fire, 2 quit, 4 slow tick) and how many events the walker queued
//   node test/gaps.mjs [B-DFS1.2|Master] [fields=500] [dropEvery=0]
//   dropEvery: tap Z/X (alternating) every that many fields, so kills land in the window
import { MachineSession } from "../node_modules/jsbeeb/src/machine-session.js";
const model = process.argv[2] || "B-DFS1.2";
const fields = Number(process.argv[3] || 500);
const dropEvery = Number(process.argv[4] || 0);   // fields between fire taps (0 = idle ship)
const s = new MachineSession(model, { tube: false });
await s.initialise(); await s.boot(30);
s.loadDisc("build/depthcharge.ssd");
s.keyDown(16); s.reset(true); await s.runFrames(50); s.keyUp(16); await s.runFrames(250);
s.keyDown(32); await s.runFrames(3); s.keyUp(32); await s.runFrames(60);

const F = 39936;
const MS = 2000;                       // cycles per ms
const FRAME_ENTRY = 0x6E15;            // JMP frame in the jump table
const [op, lo, hi] = s.readMemory(0x6E12, 3);
const walk = lo | (hi << 8);
const cpu = s._machine.processor;
let flg = 0, cur = null, drops = 0;
const frames = [];                      // {start, gap, flg, evt, work}
const h1 = cpu.debugInstruction.add((pc) => {
    if (pc === walk) {
        const now = s.elapsedCycles;
        cur = { start: now, gap: frames.length ? (now - frames.at(-1).start) / F : 0, flg, evt: 0, work: 0 };
        frames.push(cur);
    } else if (pc === FRAME_ENTRY && cur) {
        cur.work = (s.elapsedCycles - cur.start) / MS;
    }
    return false;
});
const h2 = cpu.debugWrite.add((addr, val) => {
    if (addr === 0x6E21) flg = val;                 // frmflg written by frame
    if (addr === 0x6E20 && val > 0 && cur) cur.evt = val;   // objevt bumped by walker
    return false;
});
if (dropEvery > 0) {
    // tap Z and X alternately every dropEvery fields so charges (and kills) happen
    for (let done = 0; done < fields; done += dropEvery) {
        const fireKey = (drops++ & 1) ? 88 : 90; s.keyDown(fireKey); await s.runFor(F * 4); s.keyUp(fireKey);
        await s.runFor(F * Math.max(1, Math.min(dropEvery, fields - done) - 4));
    }
} else {
    await s.runFor(F * fields);
}
h1.remove(); h2.remove();

const hist = {};
for (const f of frames.slice(1)) hist[Math.round(f.gap)] = (hist[Math.round(f.gap)] ?? 0) + 1;
console.log(JSON.stringify({ model, frames: frames.length, gapHist: hist }));

// work by frame type (skip frames the death sequence swallowed: work = 0)
const cats = {};
for (const f of frames) {
    if (!f.work) continue;
    const k = `flg=${f.flg} evt=${f.evt}`;
    const c = (cats[k] ??= { n: 0, sum: 0, max: 0 });
    c.n++; c.sum += f.work; c.max = Math.max(c.max, f.work);
}
console.log("work per frame (walker start -> next CALL frame%), ms; budget 40 minus vsync wait");
for (const [k, c] of Object.entries(cats).sort((a, b) => b[1].max - a[1].max)) {
    console.log(`  ${k.padEnd(14)} n=${String(c.n).padStart(3)}  mean ${(c.sum / c.n).toFixed(1).padStart(5)}  max ${c.max.toFixed(1).padStart(5)}`);
}
// a frame whose work passes 40ms misses its vsync: the next frame starts late
// (the gap rounds to 2 when the overrun is small, so list by work, not gap)
const late = frames.filter((f) => f.work > 40 && f.work < 200);
console.log(`frames over the 40ms budget: ${late.length} of ${frames.length}`);
for (const f of late) console.log(`  work ${f.work.toFixed(1)}ms  flg=${f.flg} evt=${f.evt}  -> gap to next ${(frames[frames.indexOf(f) + 1]?.gap ?? 0).toFixed(2)} fields`);
process.exit(0);
