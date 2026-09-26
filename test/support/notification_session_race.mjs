// Exercise the extension boundary with real CLI watcher subprocesses and a
// controllable Pi follow-up promise. No model, credentials, or user session.
import assert from "node:assert/strict";
import { readFileSync, appendFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

const extension = (await import(process.env.RIDDIM_EXTENSION)).default;
const status = process.env.RIDDIM_STATUS_PATH;
const first = process.env.RIDDIM_FIRST_ID;
const second = first.replace(/\.1$/, ".2");
const notices = [];
const messages = [];
let rejectOld;
let oldOffered = false;

function fakePi() {
  const events = new Map();
  let command;
  const pi = {
    on(name, handler) { events.set(name, handler); },
    registerCommand(_name, value) { command = value.handler; },
    sendUserMessage(text, options) {
      assert.equal(options.deliverAs, "followUp");
      messages.push(text);
      if (text.includes(first) && !oldOffered) {
        oldOffered = true;
        return new Promise((_resolve, reject) => { rejectOld = reject; });
      }
    },
  };
  const ctx = { ui: { notify(text, kind) { notices.push({ text, kind }); } } };
  extension(pi);
  return {
    start: () => events.get("session_start")({}, ctx),
    shutdown: () => events.get("session_shutdown")({}, ctx),
    arm: () => command("", ctx),
  };
}

async function until(predicate) {
  for (let attempt = 0; attempt < 200; attempt++) {
    if (predicate()) return;
    await delay(50);
  }
  throw new Error(`timed out waiting for notification: ${JSON.stringify({ messages, notices })}`);
}

const old = fakePi();
old.start();
appendFileSync(status, "blocked [at=1]: first claim\n");
await until(() => oldOffered);
// Exercise the stricter same-factory lifecycle: the pending continuation still
// closes over the old epoch even if the next session reuses this extension.
await old.shutdown();
const successor = old;
successor.start();
await until(() => messages.filter((text) => text.includes(first)).length === 2);
rejectOld(new Error("late old-session rejection"));
await delay(100);
assert.equal(messages.length, 2, "old callback must not notify the new session");
assert.equal(notices.length, 0, "old callback must not claim a failure in the new session");
await successor.arm();
assert.deepEqual(notices.at(-1), { text: "Riddim watcher ready", kind: "info" });
appendFileSync(status, "done [at=2]: second claim\n");
await until(() => messages.some((text) => text.includes(second)));
await successor.arm();
assert.deepEqual(notices.at(-1), { text: "Riddim watcher ready", kind: "info" });
await delay(700); // The verified owner has had time to reconcile its exclusions.
assert.equal(messages.filter((text) => text.includes(first)).length, 2,
  "old callback must not remove the successor's accepted identity");
assert.equal(readFileSync(status, "utf8").split("\n").filter(Boolean).length, 2);
await successor.shutdown();
