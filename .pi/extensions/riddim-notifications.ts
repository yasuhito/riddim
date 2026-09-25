// Local-only Supervisor notifications. Opt in by selecting RIDDIM_STATE_DIR
// explicitly before starting Pi; this extension never guesses another home.
import { spawn, type ChildProcess } from "node:child_process";
import { randomBytes } from "node:crypto";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const cli = resolve(dirname(fileURLToPath(import.meta.url)), "../../bin/riddim");
const home = process.env.RIDDIM_STATE_DIR;
const identity = /^([a-z][a-z0-9_-]{0,31})\.(s\d+\.\d+\.\d+)\.([1-9]\d*)$/;
const READY_TIMEOUT = 5000;

type Frame = { type: string; nonce: string; ids?: string[] };

export default function (pi: ExtensionAPI) {
  let child: ChildProcess | null = null;
  let readyChild: ChildProcess | null = null;
  let arming: Promise<boolean> | null = null;
  let active = false;
  let serial = 0;
  let inFlight = false;
  const batches: string[][] = [];
  const accepted = new Set<string>();

  function failure(reason: string): void {
    console.error(`riddim watcher FAILED: ${reason}`);
    if (!active) return;
    // Failure is a Supervisor follow-up, never an acknowledgement.
    try {
      pi.sendUserMessage("Riddim watcher FAILED in selected home. " +
        "Inspect riddim notifications scan and repair with /riddim-watch-arm.",
      { deliverAs: "followUp" });
    } catch (error) {
      console.error(`riddim failure follow-up rejected: ${String(error)}`);
    }
  }

  function arm(): Promise<boolean> {
    if (arming) return arming;
    const flight = startArm();
    const completion = flight.finally(() => { if (arming === completion) arming = null; });
    arming = completion;
    return completion;
  }

  async function startArm(): Promise<boolean> {
    if (!active || !home) return false;
    if (child) return readyChild === child && child.exitCode === null;
    const epoch = serial;
    const nonce = randomBytes(16).toString("hex");
    const proc = spawn("ruby", [cli, "watch-notifications", "--nonce", nonce, "--exclude-stdin"], {
      env: { ...process.env, RIDDIM_STATE_DIR: home },
      stdio: ["pipe", "pipe", "pipe"],
    });
    child = proc;
    proc.stdin?.on("error", () => { /* An early watcher refusal closes stdin. */ });
    proc.stdin?.end(JSON.stringify([...accepted]));
    let stdout = "";
    let stderr = "";
    let ready = false;
    let pending: string[] | null = null;
    let failureReported = false;
    let finishReady: (value: boolean) => void = () => {};
    const readiness = new Promise<boolean>((done) => { finishReady = done; });
    const timeout = setTimeout(() => finishReady(false), READY_TIMEOUT);
    proc.stderr?.on("data", (part: Buffer) => { stderr += part.toString(); });
    proc.stdout?.on("data", (part: Buffer) => {
      stdout += part.toString();
      if (stdout.length > 64 * 1024) { proc.kill(); return; }
      for (;;) {
        const newline = stdout.indexOf("\n");
        if (newline < 0) break;
        const line = stdout.slice(0, newline);
        stdout = stdout.slice(newline + 1);
        let frame: Frame;
        try { frame = JSON.parse(line) as Frame; } catch { proc.kill(); return; }
        if (frame.nonce !== nonce) { proc.kill(); return; }
        if (frame.type === "ready" && !ready) {
          ready = true;
          finishReady(true);
        } else if (frame.type === "pending" && ready && Array.isArray(frame.ids) &&
          frame.ids.length > 0 && frame.ids.every((id) => identity.test(id))) {
          pending = frame.ids;
        } else { proc.kill(); return; }
      }
    });
    proc.on("error", (error) => { stderr += error.message; finishReady(false); });
    proc.on("close", () => {
      finishReady(false);
      if (child === proc) child = null;
      if (readyChild === proc) readyChild = null;
      if (!active || serial !== epoch) return;
      if (pending) {
        batches.push(pending);
        void deliver();
      } else if (!failureReported) {
        failure(stderr.trim() || (ready ? "observer stopped without a report" : "observer failed before readiness"));
      }
    });
    const signaled = await readiness;
    clearTimeout(timeout);
    // A printed ready frame by itself is not evidence of a live watcher.
    await new Promise<void>((done) => setImmediate(done));
    if (!active || serial !== epoch) return false;
    const healthy = signaled && child === proc && proc.exitCode === null && Boolean(proc.pid);
    if (!healthy && child === proc) {
      failureReported = true;
      failure(stderr.trim() || "readiness or liveness unverified");
      proc.kill();
    }
    if (healthy) readyChild = proc;
    return healthy;
  }

  async function deliver(): Promise<void> {
    if (inFlight || !active) return;
    inFlight = true;
    try {
      while (active && batches.length > 0) {
        const ids = [...new Set(batches.splice(0).flat())];
        // Suppression is session-local; a restart replays all unhandled rows.
        ids.forEach((id) => accepted.add(id));
        const healthy = await arm();
        if (!active) return;
        const detail = healthy ? "Watcher successor is ready." :
          "Watcher FAILED: successor readiness/liveness unverified; repair supervision.";
        const content = `Riddim Supervisor notification in selected home. Pending IDs: ${ids.join(", ")}. ` +
          "Run riddim notifications scan to drain; handle the reports, then explicitly ack each presented ID. " +
          `This is a Worker claim, not Git readiness or Landing approval. ${detail}`;
        if (!healthy) ids.forEach((id) => accepted.delete(id));
        try {
          await Promise.resolve(pi.sendUserMessage(content, { deliverAs: "followUp" }));
        } catch (error) {
          ids.forEach((id) => accepted.delete(id));
          failure(`follow-up rejected: ${String(error)}`);
        }
      }
    } finally {
      inFlight = false;
      if (active && batches.length > 0) void deliver();
    }
  }

  pi.on("session_start", () => {
    if (!home) return;
    active = true;
    void arm();
  });
  pi.on("session_shutdown", async () => {
    active = false;
    serial += 1;
    const predecessor = child;
    predecessor?.kill();
    if (predecessor && predecessor.exitCode === null) {
      // Pi awaits shutdown before binding the next session's extension.
      await Promise.race([
        new Promise<void>((done) => predecessor.once("close", () => done())),
        new Promise<void>((done) => setTimeout(done, READY_TIMEOUT)),
      ]);
    }
    child = null;
    readyChild = null;
    arming = null;
    accepted.clear(); // Restart replays every unacknowledged report.
    batches.length = 0;
  });
  pi.registerCommand("riddim-watch-arm", {
    description: "Repair a failed Riddim Supervisor notification watcher in the selected home",
    handler: async (_args, ctx) => {
      if (!home) { ctx.ui.notify("Set RIDDIM_STATE_DIR before starting Pi", "error"); return; }
      const healthy = await arm();
      ctx.ui.notify(healthy ? "Riddim watcher ready" : "Riddim watcher FAILED; inspect pending notifications",
        healthy ? "info" : "error");
    },
  });
}
