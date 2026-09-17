// serve.mjs - serve build/ over HTTP with CORS so the public jsbeeb can boot
// the disc straight from this machine:
//   node test/serve.mjs            (port 8765)
//   https://bbc.godbolt.org/?disc=http://localhost:8765/depthcharge.ssd&autoboot
// Browsers treat http://localhost as a secure origin, so the https page may
// fetch from it. Ctrl-C to stop.
import { createServer } from "node:http";
import { readFileSync, existsSync } from "node:fs";
import { join, normalize } from "node:path";

const root = join(process.cwd(), "build");
const port = Number(process.argv[2] || 8765);

createServer((req, res) => {
    const path = normalize(decodeURIComponent(req.url.split("?")[0])).replace(/^(\.\.[\\/])+/, "");
    const file = join(root, path);
    if (!file.startsWith(root) || !existsSync(file) || path === "/" || path === "\\") {
        res.writeHead(404, { "Access-Control-Allow-Origin": "*" });
        res.end("not found");
        return;
    }
    res.writeHead(200, {
        "Content-Type": "application/octet-stream",
        "Access-Control-Allow-Origin": "*",
        "Cache-Control": "no-store",
    });
    res.end(readFileSync(file));
    console.log(`${new Date().toISOString()} ${req.method} ${req.url}`);
}).listen(port, () => console.log(`serving ${root} on http://localhost:${port}/`));
