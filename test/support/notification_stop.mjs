import assert from 'node:assert/strict';
import { appendFileSync, existsSync, readFileSync, unlinkSync, writeFileSync } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';

const extension = (await import(process.env.RIDDIM_EXTENSION)).default;
for (const actor of ['branch', 'unknown']) {
  process.env.RIDDIM_ACTOR = actor;
  extension(new Proxy({}, { get() { throw new Error('marked actor registered supervisor behavior'); } }));
}
delete process.env.RIDDIM_ACTOR;
const events = new Map();
const messages = [];
extension({
  on(name, callback) { events.set(name, callback); },
  registerCommand() {},
  sendUserMessage(text, options) {
    assert.equal(options.deliverAs, 'followUp');
    messages.push(text);
  },
});
const state = process.env.RIDDIM_STATE_DIR;
const id = process.env.RIDDIM_FIRST_ID.replace(/\.1$/, '.0');
const suffix = id.slice(0, -2).replace('.', '-');
const alive = `${state}/.notifications/.alive-${suffix}`;
const idleCandidate = `${state}/.notifications/.idle-${suffix}`;
const idleMode = process.env.RIDDIM_TEST_IDLE === '1';
function samples() {
  return existsSync(idleCandidate) && JSON.parse(readFileSync(idleCandidate, 'utf8')).samples;
}
async function until(predicate) {
  for (let i = 0; i < 1200; i++) {
    if (predicate()) return;
    await delay(50);
  }
  throw new Error('timed out: ' + JSON.stringify(messages));
}
events.get('session_start')({}, { ui: { notify(text) { throw new Error(text); } } });
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
  assert.ok(messages[0].includes(id));
  assert.ok(messages[0].includes('not completion'));
  assert.ok(messages[0].includes('Watcher successor is ready'));
  await delay(1000);
  assert.equal(messages.length, 1, 'one generation must not spam');
  assert.equal(readFileSync(process.env.RIDDIM_STATUS_PATH, 'utf8'), '');
  const row = JSON.parse(readFileSync(`${state}/.notifications/${id}.json`, 'utf8'));
  assert.equal(row.event, idleMode ? 'unreported-idle' : 'unreported-stop');
  if (idleMode) {
    appendFileSync(process.env.RIDDIM_STATUS_PATH, 'done [at=1]: actual worker report\n');
    await until(() => messages.length === 2);
    assert.ok(messages[1].includes(process.env.RIDDIM_FIRST_ID), 'real report keeps its independent identity');
  }
} finally {
  await events.get('session_shutdown')();
}
