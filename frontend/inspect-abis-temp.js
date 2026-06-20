const fs = require("fs");
const content = fs.readFileSync("lib/abis.ts", "utf8");

function extractAbi(name) {
  const marker = "export const " + name + "Abi = ";
  const start = content.indexOf(marker);
  if (start === -1) return null;
  const arrayStart = content.indexOf("[", start);
  let depth = 0, end = -1;
  for (let i = arrayStart; i < content.length; i++) {
    if (content[i] === "[") depth++;
    if (content[i] === "]") {
      depth--;
      if (depth === 0) { end = i + 1; break; }
    }
  }
  return JSON.parse(content.slice(arrayStart, end));
}

["OrderBook", "StopLossManager", "LiquidationEngine"].forEach((name) => {
  const abi = extractAbi(name);
  if (!abi) {
    console.log(name + ": NOT FOUND");
    return;
  }
  console.log("=== " + name + " ===");
  abi
    .filter((e) => e.type === "function")
    .forEach((e) => {
      const ins = (e.inputs || []).map((i) => i.type + " " + i.name).join(", ");
      const outs = (e.outputs || [])
        .map((o) => o.type + (o.name ? " " + o.name : ""))
        .join(", ");
      console.log(
        e.name + "(" + ins + ") " + e.stateMutability + (outs ? " returns (" + outs + ")" : "")
      );
    });
  console.log("");
});