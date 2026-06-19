// node inspect-router.js
const fs = require("fs");
const path = require("path");
const content = fs.readFileSync(path.join(__dirname, "lib", "abis.ts"), "utf8");

const marker = "export const PositionRouterAbi = ";
const start = content.indexOf(marker);
if (start === -1) { console.log("NOT FOUND"); process.exit(1); }
const arrayStart = content.indexOf("[", start);
let depth = 0, end = -1;
for (let i = arrayStart; i < content.length; i++) {
  if (content[i] === "[") depth++;
  if (content[i] === "]") { depth--; if (depth === 0) { end = i + 1; break; } }
}
const abi = JSON.parse(content.slice(arrayStart, end));
console.log("=== PositionRouterAbi ===");
for (const e of abi) {
  if (e.type === "function") {
    const ins = (e.inputs || []).map(i => i.type + " " + i.name).join(", ");
    const outs = (e.outputs || []).map(o => o.type + (o.name ? " " + o.name : "")).join(", ");
    console.log("  " + e.name + "(" + ins + ") " + e.stateMutability + (outs ? " returns (" + outs + ")" : ""));
  }
}