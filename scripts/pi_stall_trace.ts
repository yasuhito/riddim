// Opt-in diagnostic for a single Pi process. Never serialize event payloads,
// messages, headers, model names, or credentials. The parent owns the trace path.
import { appendFileSync, constants, openSync } from "node:fs";

export default function (pi: any) {
  const path = process.env.RIDDIM_PI_TRACE_FILE;
  if (!path) return;

  // Pi can reload extensions for /new and /resume in the same process.
  const key = Symbol.for("riddim.pi-stall-trace");
  const previous = (globalThis as any)[key] as { path: string; fd: number } | undefined;
  if (previous && previous.path !== path) throw new Error("Pi trace path changed inside a process");
  const fd = previous?.fd ?? openSync(path, constants.O_WRONLY | constants.O_CREAT | constants.O_EXCL | constants.O_NOFOLLOW, 0o600);
  (globalThis as any)[key] = { path, fd };
  let request = 0;
  let firstUpdate = false;
  const mark = (event: string) => {
    appendFileSync(fd, JSON.stringify({ at: new Date().toISOString(), event, request }) + "\n");
  };

  pi.on("session_start", () => mark("session_start"));
  pi.on("agent_start", () => mark("agent_start"));
  pi.on("turn_start", () => mark("turn_start"));
  pi.on("before_provider_request", () => {
    request += 1;
    firstUpdate = false;
    mark("request_prepared");
    // No return value: never replace the provider payload.
  });
  pi.on("after_provider_response", () => mark("response_headers"));
  pi.on("message_update", () => {
    if (firstUpdate) return;
    firstUpdate = true;
    mark("first_update");
  });
  pi.on("turn_end", () => mark("turn_end"));
  pi.on("agent_settled", () => mark("agent_settled"));
}
