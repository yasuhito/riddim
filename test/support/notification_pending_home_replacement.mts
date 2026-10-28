import assert from "node:assert/strict";
import { ChildProcess, spawnSync } from "node:child_process";
import { appendFileSync, mkdirSync, renameSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

import { extension, env, required, type LifecycleName, type LifecycleHandler, notificationIds, type FixtureContext } from "./notification_fixture.mts";
const home = env("RIDDIM_STATE_DIR");
const id = env("RIDDIM_FIRST_ID");
const events = new Map<LifecycleName, LifecycleHandler>();
const notices: string[] = [];
const messages: string[] = [];
let replaced = false;
const emit: (this: ChildProcess, event: string | symbol, ...args: unknown[]) => boolean = ChildProcess.prototype.emit;
ChildProcess.prototype.emit = function (event: string | symbol, ...args: unknown[]) {
  if (event === "close" && !replaced) {
    renameSync(home, `${home}-old`);
    mkdirSync(home, { mode: 0o700 });
    replaced = true;
  }
  return emit.call(this, event, ...args);
};

extension({
  on(name, handler) { events.set(name, handler); },
  registerCommand() {},
  sendUserMessage(text) { messages.push(text); },
});
const ctx: FixtureContext = { ui: { notify(text) { notices.push(text); } } };
required(events.get("session_start"), "session_start handler")({}, ctx);
appendFileSync(env("RIDDIM_STATUS_PATH"), "blocked [at=1]: old-home claim\n");
for (let attempt = 0; attempt < 200; attempt++) {
  if (replaced && notices.some((text) => text.includes("report remains in its original home"))) break;
  await delay(50);
}
assert.equal(replaced, true, "watcher must report the old-home claim");
assert.ok(notices.some((text) => text.includes("report remains in its original home")));
assert.equal(messages.some((text) => text.includes(`Pending IDs: ${id}`)), false,
  "old-home ID must not be delivered as a replacement-home notification");
const cli = new URL("../../bin/riddim", import.meta.url);
const scan = spawnSync(cli.pathname, ["notifications", "scan"], {
  env: { ...process.env, RIDDIM_STATE_DIR: `${home}-old` }, encoding: "utf8",
});
assert.equal(scan.status, 0, scan.stderr);
assert.deepEqual(notificationIds(scan.stdout), [id]);
await required(events.get("session_shutdown"), "session_shutdown handler")({}, ctx);
