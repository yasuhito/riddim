// Pi accepts no answer at this boundary; recovery must be bounded.
import assert from "node:assert/strict";
import { appendFileSync } from "node:fs";
import { setTimeout as delay } from "node:timers/promises";

const extension = (await import(process.env.RIDDIM_EXTENSION)).default;
const messages = [];
const notices = [];
const events = new Map();
let offerCount = 0;
extension({
  on(name, handler) { events.set(name, handler); },
  sendUserMessage(text, options) {
    assert.equal(options.deliverAs, "followUp");
    messages.push(text);
    if (text.includes(process.env.RIDDIM_FIRST_ID) && ++offerCount === 1) {
      return new Promise(() => {});
    }
  },
});
const ctx = { ui: { notify(text, kind) { notices.push({ text, kind }); } } };
async function until(predicate) {
  for (let attempt = 0; attempt < 180; attempt++) {
    if (await predicate()) return;
    await delay(50);
  }
  throw new Error(`timed out: ${JSON.stringify({ messages, notices })}`);
}

events.get("session_start")({}, ctx);
appendFileSync(process.env.RIDDIM_STATUS_PATH, "blocked [at=1]: held claim\n");
await until(() => notices.some((row) => row.text.includes("follow-up acceptance timed out")));
assert.equal(offerCount, 1);
await until(() => messages.some((text) => text.includes("Riddim watcher FAILED")));
// Boundary-only lifecycle check; actual /reload is covered by the TUI E2E.
await events.get("session_shutdown")({}, ctx);
await events.get("session_start")({}, ctx);
await until(() => offerCount === 2);
assert.equal(messages.filter((text) => text.includes(process.env.RIDDIM_FIRST_ID)).length, 2);
await events.get("session_shutdown")({}, ctx);
