// Run with: node inspect-abis.js
// Prints every function and event signature for the contracts needed to
// build Phase 7.3 (orders/stop-loss), 7.4 (LP vault/staking), and 7.5
// (dashboard), read directly from the real generated lib/abis.ts.
const fs = require("fs");
const path = require("path");

const filePath = path.join(__dirname, "lib", "abis.ts");
const content = fs.readFileSync(filePath, "utf8");

const targets = ["OrderBookAbi", "StopLossManagerAbi", "LPVaultAbi", "RewardDistributorAbi"];

for (const name of targets) {
  const marker = "export const " + name + " = ";
  const start = content.indexOf(marker);
  if (start === -1) {
    console.log("=== " + name + " === NOT FOUND in lib/abis.ts");
    continue;
  }
  const arrayStart = content.indexOf("[", start);
  // Find the matching closing bracket by counting depth.
  let depth = 0;
  let end = -1;
  for (let i = arrayStart; i < content.length; i++) {
    if (content[i] === "[") depth++;
    if (content[i] === "]") {
      depth--;
      if (depth === 0) {
        end = i + 1;
        break;
      }
    }
  }
  if (end === -1) {
    console.log("=== " + name + " === Could not parse (bracket matching failed)");
    continue;
  }
  const jsonText = content.slice(arrayStart, end);
  let abi;
  try {
    abi = JSON.parse(jsonText);
  } catch (e) {
    console.log("=== " + name + " === JSON parse failed: " + e.message);
    continue;
  }

  console.log("=== " + name + " ===");
  for (const entry of abi) {
    if (entry.type === "function") {
      const ins = (entry.inputs || []).map((i) => i.type + " " + i.name).join(", ");
      const outs = (entry.outputs || [])
        .map((o) => o.type + (o.name ? " " + o.name : ""))
        .join(", ");
      console.log(
        "  " +
          entry.name +
          "(" +
          ins +
          ") " +
          entry.stateMutability +
          (outs ? " returns (" + outs + ")" : "")
      );
    } else if (entry.type === "event") {
      const ins = (entry.inputs || []).map((i) => i.type + " " + i.name).join(", ");
      console.log("  event " + entry.name + "(" + ins + ")");
    } else if (entry.type === "error") {
      const ins = (entry.inputs || []).map((i) => i.type + " " + i.name).join(", ");
      console.log("  error " + entry.name + "(" + ins + ")");
    }
  }
  console.log("");
}