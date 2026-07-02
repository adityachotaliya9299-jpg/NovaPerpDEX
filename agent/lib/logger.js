/**
 * Minimal structured logger. Writes JSON lines so Railway's log aggregator can parse them, and also human-readable lines on stdout in debug mode.
 */
const LOG_LEVEL = process.env.LOG_LEVEL ?? "info";

function timestamp() {
  return new Date().toISOString();
}

function log(level, context, message, data = {}) {
  const entry = { ts: timestamp(), level, context, message, ...data };
  if (LOG_LEVEL === "debug") {
    const dataStr = Object.keys(data).length
      ? " " + JSON.stringify(data)
      : "";
    console.log(`[${entry.ts}] [${level.toUpperCase()}] [${context}] ${message}${dataStr}`);
  } else {
    console.log(JSON.stringify(entry));
  }
}

module.exports = {
  info: (ctx, msg, data) => log("info", ctx, msg, data),
  debug: (ctx, msg, data) => log("debug", ctx, msg, data),
  warn: (ctx, msg, data) => log("warn", ctx, msg, data),
  error: (ctx, msg, data) => log("error", ctx, msg, data),
};