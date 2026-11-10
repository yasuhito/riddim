import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';
import { extension, env, required, type LifecycleName, type LifecycleHandler } from './notification_fixture.mts';

const events = new Map<LifecycleName, LifecycleHandler>();
const notices: string[] = [];
const messages: string[] = [];
extension({
  on(name, callback) { events.set(name, callback); },
  sendUserMessage(text) { messages.push(text); },
});
const ctx = { ui: { notify(text: string) { notices.push(text); } } };
const start = performance.now();
const controller = new AbortController();
try {
  const startup = Promise.resolve(required(events.get('session_start'), 'start')({}, ctx)).then(() => true);
  const settled = await Promise.race([startup, delay(65_000, false, { signal: controller.signal })]);
  assert.equal(settled, true, 'continuing progress must not renew startup forever');
  const elapsed = performance.now() - start;
  assert.ok(elapsed >= 59_000 && elapsed < 65_000, `absolute deadline must allow the chosen 60-second budget: ${elapsed}`);
  assert.ok(notices.some(text => text.includes('60-second absolute deadline')), JSON.stringify(notices));
  assert.equal(messages.filter(text => text.includes('Supervisor notification')).length, 0, 'no readiness, no report delivery');
  assert.ok(readFileSync(env('RIDDIM_PHASE_TRACE'), 'utf8').trim().split('\n').length > 100, 'observer must really validate records throughout startup');
  console.log(JSON.stringify({ absoluteStartupElapsed: elapsed }));
} finally {
  controller.abort();
  await required(events.get('session_shutdown'), 'shutdown')({}, ctx);
}
