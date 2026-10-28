import assert from 'node:assert/strict';
import { appendFileSync, existsSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';

import { extension, env, required, type LifecycleName, type LifecycleHandler, parseRecord } from "./notification_fixture.mts";
for (const actor of ['branch', 'unknown']) {
  process.env.RIDDIM_ACTOR = actor;
  extension(new Proxy<import("./notification_fixture.mts").FixtureAPI>({ on() {}, sendUserMessage() {} }, { get() { throw new Error('marked actor registered supervisor behavior'); } }));
}
delete process.env.RIDDIM_ACTOR;
const events = new Map<LifecycleName, LifecycleHandler>();
const messages: string[] = [];
extension({
  on(name, callback) { events.set(name, callback); },
  registerCommand() {},
  sendUserMessage(text, options) {
    assert.equal(options.deliverAs, 'followUp');
    messages.push(text);
  },
});
const state = env("RIDDIM_STATE_DIR");
const id = env("RIDDIM_FIRST_ID").replace(/\.1$/, '.0');
const suffix = id.slice(0, -2).replace('.', '-');
const alive = `${state}/.notifications/.alive-${suffix}`;
const idleCandidate = `${state}/.notifications/.idle-${suffix}`;
const idleMode = process.env.RIDDIM_TEST_IDLE === '1';
function samples() {
  return existsSync(idleCandidate) && parseRecord(readFileSync(idleCandidate, 'utf8')).samples;
}
async function until(predicate: () => boolean) {
  for (let i = 0; i < 1200; i++) {
    if (predicate()) return;
    await delay(50);
  }
  throw new Error('timed out: ' + JSON.stringify(messages));
}
required(events.get('session_start'), 'session_start handler')({}, { ui: { notify(text) { throw new Error(text); } } });
try {
  await until(() => existsSync(alive));
  if (idleMode) {
    writeFileSync(`${state}/idle`, '');
    await until(() => samples() === 1);
    assert.equal(messages.length, 0, 'transient idle during launch must not wake the supervisor');
    unlinkSync(`${state}/idle`);
    await until(() => samples() === 0);
    assert.equal(messages.length, 0, 'busy transition must reset idle evidence');
    writeFileSync(`${state}/idle`, '');
  } else {
    writeFileSync(`${state}/stopped`, '');
  }
  await until(() => messages.length > 0);
  assert.equal(messages.length, 1);
  assert.ok(required(messages[0], 'message 0').includes(id));
  assert.ok(required(messages[0], 'message 0').includes('not completion'));
  assert.ok(required(messages[0], 'message 0').includes('Watcher successor is ready'));
  await delay(1000);
  assert.equal(messages.length, 1, 'one generation must not spam');
  assert.equal(readFileSync(env("RIDDIM_STATUS_PATH"), 'utf8'), '');
  const row = parseRecord(readFileSync(`${state}/.notifications/${id}.json`, 'utf8'));
  assert.equal(row.event, idleMode ? 'unreported-idle' : 'unreported-stop');
  if (idleMode) {
    appendFileSync(env("RIDDIM_STATUS_PATH"), 'done [at=1]: actual worker report\n');
    await until(() => messages.length === 2);
    assert.ok(required(messages[1], 'message 1').includes(env("RIDDIM_FIRST_ID")), 'real report keeps its independent identity');
  }
} finally {
  await required(events.get('session_shutdown'), 'session_shutdown handler')({}, { ui: { notify(text) { throw new Error(text); } } });
}
