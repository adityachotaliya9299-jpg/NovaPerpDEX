const fs = require("fs");
const path = require("path");

const abisContent = fs.readFileSync(
  path.join(__dirname, "..", "frontend", "lib", "abis.ts"),
  "utf8"
);

function extractAbi(name) {
  const marker = "export const " + name + "Abi = ";
  const start = abisContent.indexOf(marker);
  if (start === -1) throw new Error(`${name}Abi not found`);
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

const names = ["OrderBook", "MarginManager", "LiquidationEngine", "FundingRateEngine"];
for (const name of names) {
  const abi = extractAbi(name);
  fs.writeFileSync(
    path.join(__dirname, "abis", `${name}.json`),
    JSON.stringify(abi, null, 2)
  );
  console.log(`Wrote subgraph/abis/${name}.json`);
}