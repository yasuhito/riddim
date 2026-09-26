// A fresh Pi command must not claim yesterday's watcher after home replacement.
import assert from "node:assert/strict";
import { mkdirSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

const extension = (await import(process.env.RIDDIM_EXTENSION)).default;
const home = process.env.RIDDIM_STATE_DIR;
const events = new Map();
const notices = [];
let arm;
extension({
  on(name, handler) { events.set(name, handler); },
  registerCommand(_name, command) { arm = command.handler; },
  sendUserMessage() {},
});
const ctx = { ui: { notify(text) { notices.push(text); } } };
events.get("session_start")({}, ctx);
for (let attempt = 0; attempt < 100; attempt++) {
  await arm("", ctx);
  if (notices.at(-1) === "Riddim watcher ready") break;
  await delay(50);
}
assert.equal(notices.at(-1), "Riddim watcher ready");
if (process.env.RIDDIM_REPLACE_LOCK || process.env.RIDDIM_CORRUPT_LOCK) {
  const lock = `${home}/.notification-watcher.lock`;
  if (process.env.RIDDIM_REPLACE_LOCK) unlinkSync(lock);
  writeFileSync(lock, process.env.RIDDIM_CORRUPT_LOCK ? "corrupt" : "", { mode: 0o600 });
} else {
  renameSync(home, `${home}-old`);
  mkdirSync(home, { mode: 0o700 });
}
// No yield between replacement and probe: old watcher cannot discover it first.
await arm("", ctx);
assert.equal(notices.at(-1), "Riddim watcher FAILED; inspect pending notifications");
await events.get("session_shutdown")({}, ctx);
