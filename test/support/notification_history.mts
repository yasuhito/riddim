import assert from 'node:assert/strict';
import { appendFileSync, readFileSync, existsSync, writeFileSync, unlinkSync } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';
import { extension, env, required, type LifecycleName, type LifecycleHandler } from './notification_fixture.mts';

const events = new Map<LifecycleName, LifecycleHandler>();
const messages: string[] = [];
const notices: string[] = [];
extension({
  on(name, callback) { events.set(name, callback); },
  sendUserMessage(text) { messages.push(text); },
});
const ctx = { ui: { notify(text: string) { notices.push(text); } } };
const start = performance.now();
try {
  await required(events.get('session_start'), 'start')({}, ctx);
  assert.ok(!notices.some(text => text.includes('FAILED')), JSON.stringify(notices));
  if (env('RIDDIM_HISTORY_MODE') === 'slow') {
    assert.ok(performance.now() - start > 5000, 'fixture must exceed the startup deadline through real scan work');
  } else {
    writeFileSync(`${env('RIDDIM_STATE_DIR')}/slow-read`, '');
  }
  // Leave the observer processing another full retained-history scan. Pi's
  // responsive event loop must not spend its restart budget on advancing I/O.
  await delay(8500);
  assert.ok(!notices.some(text => text.includes('FAILED')), JSON.stringify(notices));
  const pids = new Set(readFileSync(env('RIDDIM_PHASE_TRACE'), 'utf8').trim().split('\n').map(line => line.split(' ')[0]));
  assert.equal(pids.size, 1, 'advancing scan must not restart a healthy observer');
  // The slow startup and ongoing scan have now been exercised. End the I/O
  // injection before testing delivery so successive rearm scans do not turn
  // the existing delivery deadline into a host-throughput benchmark.
  unlinkSync(`${env('RIDDIM_STATE_DIR')}/slow-read`);
  appendFileSync(env('RIDDIM_STATUS_PATH'), 'done [at=999]: new report after retained history\n');
  for (let i = 0; i < 600 && messages.length === 0; i++) await delay(50);
  assert.ok(required(messages[0], 'delivery').includes('.401'), JSON.stringify(messages));
  assert.ok(messages[0]?.includes('Watcher successor is ready'), JSON.stringify(messages));
  assert.ok(!notices.some(text => text.includes('FAILED')), JSON.stringify(notices));
  const trace = env('RIDDIM_PHASE_TRACE');
  assert.ok(existsSync(trace));
  const reads = readFileSync(trace, 'utf8').trim().split('\n').filter(line => !line.includes(' phase-')).length;
  console.log(JSON.stringify({ elapsed: performance.now() - start, reads }));
} finally {
  await required(events.get('session_shutdown'), 'shutdown')({}, ctx);
}
