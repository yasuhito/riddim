// Exercise the extension boundary with real CLI watcher subprocesses and a
// controllable Pi follow-up promise. No model, credentials, or user session.
import assert from "node:assert/strict";
import { readFileSync, appendFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

import { extension, env, required, type LifecycleName, type LifecycleHandler, type Notice, type FixtureContext } from "./notification_fixture.mts";
const status = env("RIDDIM_STATUS_PATH");
const first = env("RIDDIM_FIRST_ID");
const second = first.replace(/\.1$/, ".2");
const notices: Notice[] = [];
const messages: string[] = [];
// Scenario-specific observable projection, named after NotificationHandoff labels.
// RejectA marks injection plus the existing assertions, not an internal hook.
const trace: string[] = [];
let rejectOld: ((reason: Error) => void) | undefined;
let oldOffered = false;

function fakePi() {
  const events = new Map<LifecycleName, LifecycleHandler>();
  const pi: import("./notification_fixture.mts").FixtureAPI = {
    on(name, handler) { events.set(name, handler); },
    sendUserMessage(text, options) {
      assert.equal(options.deliverAs, "followUp");
      messages.push(text);
      if (text.includes(first) && !oldOffered) {
        oldOffered = true;
        trace.push("OfferA");
        return new Promise<void>((_resolve, reject) => { rejectOld = reject; });
      }
      trace.push(text.includes(second) ? "OfferB2" : "OfferB1");
    },
  };
  const ctx: FixtureContext = { ui: { notify(text, kind) { notices.push({ text, kind }); } } };
  extension(pi);
  return {
    start: () => required(events.get("session_start"), "session_start handler")({}, ctx),
    shutdown: () => required(events.get("session_shutdown"), "session_shutdown handler")({}, ctx),
  };
}

async function until(predicate: () => boolean) {
  for (let attempt = 0; attempt < 200; attempt++) {
    if (predicate()) return;
    await delay(50);
  }
  throw new Error(`timed out waiting for notification: ${JSON.stringify({ messages, notices })}`);
}

const old = fakePi();
try {
  old.start();
  appendFileSync(status, "blocked [at=1]: first claim\n");
  await until(() => oldOffered);
  // Exercise the stricter synthetic same-factory lifecycle: the pending
  // continuation closes over the old epoch when start reuses this factory.
  // Real Pi /reload instead loads a replacement extension runtime.
  await old.shutdown();
  trace.push("ShutdownA");
  const successor = old;
  trace.push("StartB");
  successor.start();
  await until(() => messages.filter((text) => text.includes(first)).length === 2);
  required(rejectOld, "old follow-up rejection")(new Error("late old-session rejection"));
  await delay(100);
  assert.equal(messages.length, 2, "old callback must not notify the new session");
  assert.equal(notices.length, 0, "old callback must not claim a failure in the new session");
  assert.equal(notices.length, 0);
  trace.push("RejectA");
  appendFileSync(status, "done [at=2]: second claim\n");
  trace.push("Publish2");
  await until(() => messages.some((text) => text.includes(second)));
  assert.equal(notices.length, 0);
  await delay(700); // The verified owner has had time to reconcile its exclusions.
  assert.equal(messages.filter((text) => text.includes(first)).length, 2,
    "old callback must not remove the successor's accepted identity");
  assert.equal(readFileSync(status, "utf8").split("\n").filter(Boolean).length, 2);
} finally {
  // Also retire the fixture's own watcher when a negative-copy assertion fails.
  await old.shutdown();
}
trace.push("ShutdownB");
console.log(JSON.stringify({ trace }));
