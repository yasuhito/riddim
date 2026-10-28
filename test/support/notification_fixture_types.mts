// Compile-only regressions. An unused @ts-expect-error fails typecheck if this
// boundary becomes permissive; these deliberately invalid calls never execute.
import type { FixtureAPI, FixtureContext, LifecycleHandler } from "./notification_fixture.mts";

export function rejectsInvalidFixtureUse(pi: FixtureAPI, ctx: FixtureContext, handler: LifecycleHandler): void {
  // @ts-expect-error Misspelled lifecycle events must not register silently.
  pi.on("session_strat", handler);
  // @ts-expect-error Follow-ups must use Pi's followUp delivery mode.
  pi.sendUserMessage("pending report", { deliverAs: "followup" });
  // @ts-expect-error A message cannot omit its delivery mode.
  pi.sendUserMessage("pending report");
  // @ts-expect-error Notice kinds are checked even in fake lifecycle contexts.
  ctx.ui.notify("failure", "fatal");
  // @ts-expect-error A dispatched lifecycle callback requires a context.
  handler({});
  // @ts-expect-error Fixture implementations must accept string messages.
  const invalid: FixtureAPI = { on() {}, sendUserMessage(_text: number) {} };
  void invalid;
}
