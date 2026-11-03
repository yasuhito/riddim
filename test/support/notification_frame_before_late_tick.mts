// A Pi stall can end with a watcher frame read before the late watchdog
// tick. That stall must neither kill a healthy watcher nor postpone noticing
// a watcher that falls silent right after the frame. Ruby and the extension
// are real; the fixture only sees the watcher pipe first and stalls Pi there.
import assert from "node:assert/strict";
import type { ChildProcess } from "node:child_process";
import { createRequire, syncBuiltinESMExports } from "node:module";
import { setTimeout as delay } from "node:timers/promises";

import type { LifecycleName, LifecycleHandler, FixtureContext } from "./notification_fixture.mts";

const STALL = 8000;
const DETECTION_LIMIT = 7500; // Four-second grace, one tick, exit latency.
const watchers: ChildProcess[] = [];
const childProcess: { spawn: (...args: unknown[]) => ChildProcess } = createRequire(import.meta.url)("node:child_process");
const spawn = childProcess.spawn;
childProcess.spawn = (...args) => {
  const proc = Reflect.apply(spawn, childProcess, args);
  watchers.push(proc);
  return proc;
};
syncBuiltinESMExports();
const { extension, required } = await import("./notification_fixture.mts");

const events = new Map<LifecycleName, LifecycleHandler>();
const messages: string[] = [];
const notices: string[] = [];
extension({
  on(name, handler) { events.set(name, handler); },
  sendUserMessage(text) { messages.push(text); },
});
const ctx: FixtureContext = { ui: { notify(text) { notices.push(text); } } };

// Block Pi inside the pipe's I/O callback, ahead of the extension's frame
// handler, so this frame is handled after the stall but before the late tick.
function stallBeforeFrame(proc: ChildProcess, silenceWatcher: boolean): Promise<number> {
  return new Promise((done) => {
    required(proc.stdout ?? undefined, "watcher stdout").prependOnceListener("data", () => {
      if (silenceWatcher) proc.kill("SIGSTOP");
      const end = performance.now() + STALL;
      while (performance.now() < end) { /* Pi is not running. */ }
      done(performance.now());
    });
  });
}

function exited(proc: ChildProcess): Promise<number> {
  return new Promise((done) => proc.once("exit", () => done(performance.now())));
}

await required(events.get("session_start"), "session_start handler")({}, ctx);
const watcher = required(watchers[0], "armed watcher");
try {
  await stallBeforeFrame(watcher, false);
  await delay(3000);
  assert.equal(watcher.exitCode, null, "a healthy watcher must survive the stall");
  assert.equal(watchers.length, 1);

  const exit = exited(watcher);
  const frame = await stallBeforeFrame(watcher, true);
  const detection = await Promise.race([exit, delay(20_000, Infinity)]) - frame;
  assert.ok(detection >= 3500 && detection <= DETECTION_LIMIT,
    `a watcher silent after the frame must be replaced after the usual grace, not ${detection} ms`);
  assert.deepEqual({ messages, notices }, { messages: [], notices: [] });
} finally {
  if (watcher.exitCode === null && watcher.signalCode === null) watcher.kill("SIGCONT");
  await required(events.get("session_shutdown"), "session_shutdown handler")({}, ctx);
}
