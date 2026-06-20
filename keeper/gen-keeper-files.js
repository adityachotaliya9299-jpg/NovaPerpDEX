const fs = require("fs");
const path = require("path");

const ROOT = path.resolve(__dirname, "..");
const abisContent = fs.readFileSync(path.join(ROOT, "frontend/lib/abis.ts"), "utf8");
const deployment = JSON.parse(
  fs.readFileSync(path.join(ROOT, "frontend/lib/deployments/11155111.json"), "utf8")
);

function extractAbi(name) {
  const marker = "export const " + name + "Abi = ";
  const start = abisContent.indexOf(marker);
  if (start === -1) throw new Error(`${name}Abi not found in abis.ts`);
  const arrayStart = abisContent.indexOf("[", start);
  let depth = 0, end = -1;
  for (let i = arrayStart; i < abisContent.length; i++) {
    if (abisContent[i] === "[") depth++;
    if (abisContent[i] === "]") {
      depth--;
      if (depth === 0) { end = i + 1; break; }
    }
  }
  return JSON.parse(abisContent.slice(arrayStart, end));
}

const names = ["OrderBook", "StopLossManager", "LiquidationEngine", "MarginManager"];
let out = "// Auto-extracted from frontend/lib/abis.ts by keeper/gen-keeper-files.js\n";
out += "// Regenerate after any contract interface change or redeploy:\n";
out += "//   node keeper/gen-keeper-files.js\n\n";
for (const name of names) {
  out += `export const ${name}Abi = ${JSON.stringify(extractAbi(name), null, 2)};\n\n`;
}
fs.writeFileSync(path.join(__dirname, "abis.js"), out);
console.log("Wrote keeper/abis.js");

fs.writeFileSync(path.join(__dirname, "deployment.json"), JSON.stringify(deployment, null, 2));
console.log("Wrote keeper/deployment.json");