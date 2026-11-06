import assert from 'node:assert/strict';
import type { ChildProcess } from 'node:child_process';
import { createRequire, syncBuiltinESMExports } from 'node:module';
import { appendFileSync, writeFileSync, unlinkSync, renameSync } from 'node:fs';
import { setTimeout as delay } from 'node:timers/promises';
import type { LifecycleName, LifecycleHandler } from './notification_fixture.mts';

const watchers: ChildProcess[] = [];
const childProcess: { spawn: (...args: unknown[]) => ChildProcess } = createRequire(import.meta.url)('node:child_process');
const spawn = childProcess.spawn;
childProcess.spawn = (...args) => {
  const proc = Reflect.apply(spawn, childProcess, args);
  watchers.push(proc);
  return proc;
};
syncBuiltinESMExports();
const { extension, env, required } = await import('./notification_fixture.mts');
const events = new Map<LifecycleName, LifecycleHandler>();
const notices: string[] = [];
const messages: string[] = [];
extension({
  on(name, handler) { events.set(name, handler); },
  sendUserMessage(text) { messages.push(text); },
});
const ctx = { ui: { notify(text: string) { notices.push(text); } } };
const state = env('RIDDIM_STATE_DIR');
const mode = env('RIDDIM_HISTORY_MODE');
async function until(predicate: () => boolean) {
  for (let i = 0; i < 600; i++) {
    if (predicate()) return;
    await delay(50);
  }
  assert.fail(JSON.stringify({ notices, messages }));
}
try {
  await required(events.get('session_start'), 'start')({}, ctx);
  const watcher = required(watchers[0], 'watcher');
  if (mode === 'hung') {
    writeFileSync(`${state}/hung-read`, '');
    const start = performance.now();
    await until(() => watcher.signalCode !== null);
    assert.equal(watcher.signalCode, 'SIGKILL', 'alive but blocked observer must trip the watchdog');
    assert.ok(performance.now() - start < 7500, 'no extra grace for a blocked read');
    unlinkSync(`${state}/hung-read`);
    await until(() => watchers.length >= 2);
    appendFileSync(env('RIDDIM_STATUS_PATH'), 'done [at=999]: recovered report\n');
    await until(() => messages.length > 0);
    assert.ok(required(messages[0], 'delivery').includes('.401'));
    assert.ok(messages[0]?.includes('Watcher successor is ready'));
    assert.ok(!notices.some(text => text.includes('FAILED')), JSON.stringify(notices));
  } else {
    writeFileSync(`${state}/slow-read`, '');
    if (mode === 'error') writeFileSync(`${state}/read-error`, '');
    else {
      // Allow a real scan checkpoint first, then replace only our own marker.
      await delay(1500);
      renameSync(`${state}/.notification-watcher.lock`, `${state}/old-lock`);
      writeFileSync(`${state}/.notification-watcher.lock`, '', { mode: 0o600 });
    }
    await until(() => notices.some(text => text.includes('FAILED')));
    assert.equal(messages.filter(text => text.includes('Supervisor notification')).length, 0);
    assert.ok(watcher.exitCode !== null || watcher.signalCode !== null, 'failed processing must stop');
    if (mode === 'error') assert.ok(notices.some(text => text.includes('injected record read failure')), JSON.stringify(notices));
    else assert.equal(watchers.length, 1, 'a replacement lock must not authorize recovery');
  }
} finally {
  await required(events.get('session_shutdown'), 'shutdown')({}, ctx);
}
