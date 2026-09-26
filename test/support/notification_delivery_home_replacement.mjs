import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { appendFileSync, lstatSync, mkdirSync, renameSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

const extension = (await import(process.env.RIDDIM_EXTENSION)).default;
const home = process.env.RIDDIM_STATE_DIR;
const id = process.env.RIDDIM_FIRST_ID;
const events = new Map();
const messages = [];
let replaced = false;
let sourceHome;
let sourceLock;
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
const ctx = { ui: { notify() {} } };
events.get("session_start")({}, ctx);
appendFileSync(process.env.RIDDIM_STATUS_PATH, "blocked [at=1]: delivery-boundary claim\n");
for (let attempt = 0; attempt < 200 && !replaced; attempt++) await delay(50);
assert.equal(replaced, true, "replacement must occur at follow-up acceptance");
const delivered = messages.find((text) => text.includes(`Pending IDs: ${id}`));
assert.ok(delivered.includes(`from home ${sourceHome}, watcher lock ${sourceLock}`));
assert.ok(delivered.includes("if changed, recover from the original home manually"));
assert.equal(delivered.includes("notification in selected home"), false);
await events.get("session_shutdown")({}, ctx);
const cli = new URL("../../bin/riddim", import.meta.url);
const scan = spawnSync(cli.pathname, ["notifications", "scan"], {
  env: { ...process.env, RIDDIM_STATE_DIR: `${home}-old` }, encoding: "utf8",
});
assert.equal(scan.status, 0, scan.stderr);
assert.deepEqual(JSON.parse(scan.stdout).map((row) => row.id), [id]);
