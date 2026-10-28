import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { appendFileSync, lstatSync, mkdirSync, renameSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

import { extension, env, required, type LifecycleName, type LifecycleHandler, type FixtureContext, notificationIds } from "./notification_fixture.mts";
const home = env("RIDDIM_STATE_DIR");
const id = env("RIDDIM_FIRST_ID");
const events = new Map<LifecycleName, LifecycleHandler>();
const messages: string[] = [];
let replaced = false;
let sourceHome: string | undefined;
let sourceLock: string | undefined;
extension({
  on(name, handler) { events.set(name, handler); },
  registerCommand() {},
  sendUserMessage(text) {
    if (text.includes(`Pending IDs: ${id}`) && !replaced) {
      const homeStat = lstatSync(home);
      const lockStat = lstatSync(`${home}/.notification-watcher.lock`);
      sourceHome = `${homeStat.dev}:${homeStat.ino}`;
      sourceLock = `${lockStat.dev}:${lockStat.ino}`;
      renameSync(home, `${home}-old`);
      mkdirSync(home, { mode: 0o700 });
      replaced = true;
    }
    messages.push(text);
  },
});
const ctx: FixtureContext = { ui: { notify() {} } };
required(events.get("session_start"), "session_start handler")({}, ctx);
appendFileSync(env("RIDDIM_STATUS_PATH"), "blocked [at=1]: delivery-boundary claim\n");
for (let attempt = 0; attempt < 200 && !replaced; attempt++) await delay(50);
assert.equal(replaced, true, "replacement must occur at follow-up acceptance");
const delivered = required(messages.find((text) => text.includes(`Pending IDs: ${id}`)), "delivered follow-up");
assert.ok(delivered.includes(`from home ${sourceHome}, watcher lock ${sourceLock}`));
assert.ok(delivered.includes("if changed, recover from the original home manually"));
assert.equal(delivered.includes("notification in selected home"), false);
await required(events.get("session_shutdown"), "session_shutdown handler")({}, ctx);
const cli = new URL("../../bin/riddim", import.meta.url);
const scan = spawnSync(cli.pathname, ["notifications", "scan"], {
  env: { ...process.env, RIDDIM_STATE_DIR: `${home}-old` }, encoding: "utf8",
});
assert.equal(scan.status, 0, scan.stderr);
assert.deepEqual(notificationIds(scan.stdout), [id]);
