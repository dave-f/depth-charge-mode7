// gaps.mjs - which BASIC event coincides with each long frame? Boots the
// game (run from the repo root), idles N fields, and logs every walker-to-
// walker gap over 2.5 fields with the frame flags MC wrote and the events it
// queued. Gaps of 14-19 fields are the death sequence, not a problem.
//   node test/gaps.mjs [B-DFS1.2|Master] [fields=500]
import { MachineSession } from "../node_modules/jsbeeb/src/machine-session.js";
const model = process.argv[2] || "B-DFS1.2";
const fields = Number(process.argv[3] || 500);
const s = new MachineSession(model, { tube: false });
await s.initialise(); await s.boot(30);
s.loadDisc("build/depthcharge.ssd");
s.keyDown(16); s.reset(true); await s.runFrames(50); s.keyUp(16); await s.runFrames(250);
s.keyDown(32); await s.runFrames(3); s.keyUp(32); await s.runFrames(60);

const F = 39936;
const [op, lo, hi] = s.readMemory(0x7412, 3);
const walk = lo | (hi << 8);
const cpu = s._machine.processor;
let last = 0, flg = 0, evt = 0;
const frames = []; // {gap, flg, evt, slots}
const h1 = cpu.debugInstruction.add((pc) => {
    if (pc === walk) {
        const now = s.elapsedCycles;
        if (last) frames.push({ gap: (now - last) / F, flg, evt, slots: [] });
        last = now; flg = 0; evt = 0;
    }
    return false;
});
const h2 = cpu.debugWrite.add((addr, val) => {
    if (addr === 0x7419) flg = val;                 // frmflg written by frame
    if (addr === 0x7418 && val > 0) evt = val;      // objevt bumped by walker
    return false;
});
await s.runFor(F * fields);
h1.remove(); h2.remove();
// the events of frame i are handled by BASIC during gap i+1
const hist = {};
for (const f of frames) hist[Math.round(f.gap)] = (hist[Math.round(f.gap)] ?? 0) + 1;
console.log(JSON.stringify({ model, frames: frames.length, hist }));
for (let i = 1; i < frames.length; i++) {
    if (frames[i].gap > 2.5) {
        const prev = frames[i - 1];
        const q = s.readMemory(0x7560, 20);
        console.log(`gap ${frames[i].gap.toFixed(2)} fields  flg=${prev.flg} (1 fire,2 quit,4 slowtick)  evt=${prev.evt}  this-frame flg=${frames[i].flg} evt=${frames[i].evt}`);
    }
}
process.exit(0);
