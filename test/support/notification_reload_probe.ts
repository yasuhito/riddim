// Observation only: no commands, reload adapters, or fake session events.
import { appendFileSync, readFileSync } from "node:fs";
import { randomUUID } from "node:crypto";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

export default function (pi: ExtensionAPI) {
  const runtime = randomUUID();
  const record = (event: object) => appendFileSync(process.env.RIDDIM_RELOAD_TRACE!,
    JSON.stringify({ runtime, ...event }) + "\n");
  pi.on("session_start", (event) => record({ type: "start", reason: event.reason,
    commands: pi.getCommands(),
    children: readFileSync(`/proc/${process.pid}/task/${process.pid}/children`, "utf8").trim().split(/\s+/),
  }));
  pi.on("session_shutdown", (event) => record({ type: "shutdown", reason: event.reason }));
  pi.on("message_start", (event) => {
    if (event.message.role === "user") record({ type: "user", content: event.message.content });
  });
  pi.on("agent_settled", () => record({ type: "settled" }));
}
