import assert from "node:assert/strict";
import { extension, type LifecycleName } from "./notification_fixture.mts";
const previous = process.env.RIDDIM_ACTOR;
try {
  for (const actor of ["branch", "crew", "supervisor", " "]) {
    process.env.RIDDIM_ACTOR = actor;
    extension({
      on() { assert.fail(`actor ${actor} registered a lifecycle callback`); },
      registerCommand() { assert.fail(`actor ${actor} registered watcher repair`); },
      sendUserMessage() { assert.fail(`actor ${actor} sent a notification`); },
    });
  }
  for (const actor of [undefined, ""]) {
    if (actor === undefined) delete process.env.RIDDIM_ACTOR;
    else process.env.RIDDIM_ACTOR = actor;
    const events: LifecycleName[] = [];
    const commands: string[] = [];
    extension({
      on(name) { events.push(name); },
      sendUserMessage() { assert.fail("registration must not send a notification"); },
      registerCommand(name) { commands.push(name); },
    });
    assert.deepEqual(events, ["session_start", "before_agent_start", "session_shutdown"]);
    assert.deepEqual(commands, []);
  }
} finally {
  if (previous === undefined) delete process.env.RIDDIM_ACTOR;
  else process.env.RIDDIM_ACTOR = previous;
}
