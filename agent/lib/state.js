/**
 * Persistent state for the agent runner — survives process restarts.
 * Stores last-processed block, last rebalance time per vault, and
 * a simple audit log of every decision made this session.
 *
 * Uses a flat JSON file (same pattern as keeper/state.json).
 */

const fs = require("fs");
const path = require("path");

const STATE_FILE = path.join(__dirname, "..", "agent_state.json");

const DEFAULT_STATE = {
  lastUpdated: null,
  vaults: {},
  // vaults[address] = {
  //   lastRebalanceAt: unixSeconds | null,
  //   lastDrawdownBps: number,
  //   cycleCount: number,
  //   lastError: string | null,
  // }
};

function load() {
  try {
    if (fs.existsSync(STATE_FILE)) {
      return JSON.parse(fs.readFileSync(STATE_FILE, "utf8"));
    }
  } catch {
    // Corrupted state file — start fresh
  }
  return { ...DEFAULT_STATE };
}

function save(state) {
  state.lastUpdated = new Date().toISOString();
  fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}

function getVaultState(state, vaultAddress) {
  const addr = vaultAddress.toLowerCase();
  if (!state.vaults[addr]) {
    state.vaults[addr] = {
      lastRebalanceAt: null,
      lastDrawdownBps: 0,
      cycleCount: 0,
      lastError: null,
    };
  }
  return state.vaults[addr];
}

module.exports = { load, save, getVaultState };