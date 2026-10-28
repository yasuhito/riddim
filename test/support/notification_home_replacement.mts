// Automatic continuity must refuse replaced or corrupt ownership evidence.
import assert from "node:assert/strict";
import { mkdirSync, renameSync, unlinkSync, writeFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

import { extension, env, required, type LifecycleName, type LifecycleHandler, type FixtureContext } from "./notification_fixture.mts";
const home = env("RIDDIM_STATE_DIR");
const events = new Map<LifecycleName, LifecycleHandler>();
const notices: string[] = [];
extension({
  on(name, handler) { events.set(name, handler); },
  sendUserMessage() {},
});
const ctx: FixtureContext = { ui: { notify(text) { notices.push(text); } } };
await required(events.get("session_start"), "session_start handler")({}, ctx);
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
assert.match(required(notices.at(-1), "failure notice"), /Riddim watcher FAILED/);
await required(events.get("session_shutdown"), "session_shutdown handler")({}, ctx);
