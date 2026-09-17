// probe.mjs - headless jsbeeb harness for the Mode 7 Depth Charge port.
//
// Boots build/depthcharge.ssd in the jsbeeb that jsbeeb-mcp ships (npm install
// puts it in node_modules), optionally plays a key script, then reports:
//   --txt          the 1KB Mode 7 screen at &7C00 as 25 lines of text
//                  (sixel cells shown by ink density: ' ' '.' '+' '#';
//                  teletext control codes as '~')
//   --png FILE     the active display area as a PNG
//   --mem ADDR:LEN print LEN bytes at hex ADDR (e.g. 7130:16 = ship slot)
//   --rate N       count game frames (vsync-locked walker starts) over
//                  exactly N fields of 39,936 cycles. The game locks to two
//                  fields a frame, so a healthy game gives N/2 calls; fewer
//                  means dropped frames. The attract loop syncs once, so N.
//
// Key script: --script "SPACE:2,.:50,Z:40,X:40,SPACE:2,.:200"
//   KEY:FRAMES holds KEY for that many fields then releases it; '.' idles.
//   Keys: SPACE Z X Q SHIFT, or any single letter/digit.
//
//   node test/probe.mjs --txt --png shot.png
//   node test/probe.mjs --script "SPACE:2,.:100" --rate 100 --txt
import { writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { MachineSession } from "../node_modules/jsbeeb/src/machine-session.js";
import pkg from "../node_modules/jsbeeb/package.json" with { type: "json" };
const jsbeebVersion = pkg.version;

const args = process.argv.slice(2);
const opt = (name, dflt) => {
    const i = args.indexOf(name);
    return i >= 0 ? args[i + 1] : dflt;
};
const flag = (name) => args.includes(name);

const ssd = resolve(opt("--ssd", "build/depthcharge.ssd"));
const model = opt("--model", "B-DFS1.2");
const bootFrames = Number(opt("--boot", 250));
const script = opt("--script", "");
const rateFields = Number(opt("--rate", 0));
const png = opt("--png", "");

const KEYS = { SPACE: 32, SHIFT: 16, RETURN: 13, Z: 90, X: 88, Q: 81 };
const keyCode = (k) => KEYS[k.toUpperCase()] ?? k.toUpperCase().charCodeAt(0);

const FIELD_CYCLES = 39936;
// Frames are stamped at the walker proper, not at the BASIC CALL: the frame
// entry spins on the vsync counter first, so the walker's start is the
// vsync-locked instant the player sees. walk% (&7112) is JMP objwalk, so
// the walker's address is read from that JMP's operand once the disc is up.
let walkAddr = 0;

console.error(`[jsbeeb ${jsbeebVersion}] model ${model}, ${ssd}`);

const s = new MachineSession(model, { tube: false });
await s.initialise();
await s.boot(30);
s.loadDisc(ssd);
s.keyDown(16);
s.reset(true);
await s.runFrames(50);
s.keyUp(16);
await s.runFrames(bootFrames);

for (const step of script.split(",").map((x) => x.trim()).filter(Boolean)) {
    const [key, n] = step.split(":");
    const frames = Number(n ?? 1);
    if (key === ".") {
        await s.runFrames(frames);
        continue;
    }
    const code = keyCode(key);
    s.keyDown(code);
    await s.runFrames(frames);
    s.keyUp(code);
    await s.runFrames(1);
}

if (rateFields > 0) {
    const [op, lo, hi] = s.readMemory(0x7112, 3);
    if (op !== 0x4c) throw new Error("walk% at &7112 is not a JMP - PLOT not loaded?");
    walkAddr = lo | (hi << 8);
    let walks = 0;
    const stamps = [];
    const hook = s._machine.processor.debugInstruction.add((pc) => {
        if (pc === walkAddr) {
            walks++;
            stamps.push(s.elapsedCycles);
        }
        return false;
    });
    const t0 = s.elapsedCycles;
    await s.runFor(FIELD_CYCLES * rateFields);
    const cycles = s.elapsedCycles - t0;
    hook.remove();
    // gaps between walker calls, in fields (a 25Hz game is exactly 2.0)
    const gaps = stamps.slice(1).map((c, i) => (c - stamps[i]) / FIELD_CYCLES);
    const hist = {};
    for (const g of gaps) hist[Math.round(g)] = (hist[Math.round(g)] ?? 0) + 1;
    console.log(JSON.stringify({ fields: rateFields, cycles, walkCalls: walks, fieldsPerFrame: hist }));
}

const mem = opt("--mem", "");
if (mem) {
    const [addr, len] = mem.split(":");
    const bytes = s.readMemory(parseInt(addr, 16), Number(len ?? 16));
    console.log("&" + addr.toUpperCase() + ": " + bytes.map((b) => b.toString(16).toUpperCase().padStart(2, "0")).join(" "));
}

if (flag("--txt")) {
    const mem = s.readMemory(0x7c00, 1000);
    const pop = (b) => [b & 1, b & 2, b & 4, b & 8, b & 16, b & 64].filter(Boolean).length;
    for (let r = 0; r < 25; r++) {
        let line = "";
        for (let c = 0; c < 40; c++) {
            const b = mem[r * 40 + c];
            if (b >= 0xa0) line += [" ", ".", ".", "+", "+", "#", "#"][pop(b)];
            else if (b >= 0x80) line += "~";
            else if (b >= 0x20 && b < 0x7f) line += String.fromCharCode(b);
            else line += "?";
        }
        console.log(String(r).padStart(2, " ") + "|" + line + "|");
    }
}

if (png) {
    writeFileSync(png, await s.screenshotActive());
    console.error(`wrote ${png}`);
}
process.exit(0);
