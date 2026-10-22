import assert from 'node:assert/strict';
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
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
const alive = `${state}/.notifications/.alive-${id.slice(0, -2).replace('.', '-')}`;
async function until(predicate) {
  for (let i = 0; i < 200; i++) {
    if (predicate()) return;
    await delay(50);
  }
  throw new Error('timed out: ' + JSON.stringify(messages));
}
events.get('session_start')({}, { ui: { notify(text) { throw new Error(text); } } });
try {
  await until(() => existsSync(alive));
  writeFileSync(`${state}/stopped`, '');
  await until(() => messages.length > 0);
  assert.equal(messages.length, 1);
  assert.ok(messages[0].includes(id));
  assert.ok(messages[0].includes('not completion'));
  assert.ok(messages[0].includes('Watcher successor is ready'));
  await delay(1000);
  assert.equal(messages.length, 1, 'one generation must not spam');
  assert.equal(readFileSync(process.env.RIDDIM_STATUS_PATH, 'utf8'), '');
} finally {
  await events.get('session_shutdown')();
}
