// Automatic continuity must refuse replaced or corrupt ownership evidence.
import assert from "node:assert/strict";
import { mkdirSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

const extension = (await import(process.env.RIDDIM_EXTENSION)).default;
const home = process.env.RIDDIM_STATE_DIR;
const events = new Map();
const notices = [];
extension({
  on(name, handler) { events.set(name, handler); },
  sendUserMessage() {},
});
const ctx = { ui: { notify(text) { notices.push(text); } } };
await events.get("session_start")({}, ctx);
assert.equal(notices.length, 0);
if (process.env.RIDDIM_REPLACE_LOCK || process.env.RIDDIM_CORRUPT_LOCK) {
  const lock = `${home}/.notification-watcher.lock`;
  if (process.env.RIDDIM_REPLACE_LOCK) unlinkSync(lock);
  writeFileSync(lock, process.env.RIDDIM_CORRUPT_LOCK ? "corrupt" : "", { mode: 0o600 });
} else {
  renameSync(home, `${home}-old`);
  mkdirSync(home, { mode: 0o700 });
}
for (let attempt = 0; attempt < 100 && notices.length === 0; attempt++) await delay(50);
assert.match(notices.at(-1), /Riddim watcher FAILED/);
await events.get("session_shutdown")({}, ctx);
