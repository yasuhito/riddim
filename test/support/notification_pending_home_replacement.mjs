import assert from "node:assert/strict";
import { ChildProcess, spawnSync } from "node:child_process";
import { appendFileSync, mkdirSync, renameSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

const extension = (await import(process.env.RIDDIM_EXTENSION)).default;
const home = process.env.RIDDIM_STATE_DIR;
const id = process.env.RIDDIM_FIRST_ID;
const events = new Map();
const notices = [];
const messages = [];
let replaced = false;
const emit = ChildProcess.prototype.emit;
ChildProcess.prototype.emit = function (event, ...args) {
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
const ctx = { ui: { notify(text) { notices.push(text); } } };
events.get("session_start")({}, ctx);
appendFileSync(process.env.RIDDIM_STATUS_PATH, "blocked [at=1]: old-home claim\n");
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
assert.deepEqual(JSON.parse(scan.stdout).map((row) => row.id), [id]);
await events.get("session_shutdown")({}, ctx);
