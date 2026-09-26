// Local-only Supervisor notifications. Opt in by selecting RIDDIM_STATE_DIR
// explicitly before starting Pi; this extension never guesses another home.
import { spawn, type ChildProcess } from "node:child_process";
import { lstatSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { dirname, resolve } from "node:path";
import { performance } from "node:perf_hooks";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const cli = resolve(dirname(fileURLToPath(import.meta.url)), "../../bin/riddim");
const home = process.env.RIDDIM_STATE_DIR && resolve(process.env.RIDDIM_STATE_DIR);
const identity = /^([a-z][a-z0-9_-]{0,31})\.(s\d+\.\d+\.\d+)\.([1-9]\d*)$/;
const WATCHER_READY_TIMEOUT = 5000;
const FOLLOW_UP_TIMEOUT = 5000;
const SHUTDOWN_TIMEOUT = 5000;
const BEAT_TIMEOUT = 4000;

type Frame = { type: string; nonce: string; ids?: string[]; home?: string; lock?: string };
type Batch = { ids: string[]; home: string; lock: string };

function lockIdentity(): string | null {
  if (!home) return null;
  try {
    const stat = lstatSync(resolve(home, ".notification-watcher.lock"), { bigint: true });
    return stat.isFile() && !stat.isSymbolicLink() && typeof process.getuid === "function" &&
      stat.uid === BigInt(process.getuid()) &&
      stat.size === 0n && (stat.mode & 0o077n) === 0n ? `${stat.dev}:${stat.ino}` : null;
  } catch {
    return null;
  }
}

function homeIdentity(): string | null {
  if (!home) return null;
  try {
    const stat = lstatSync(home, { bigint: true });
    return stat.isDirectory() && !stat.isSymbolicLink() ? `${stat.dev}:${stat.ino}` : null;
  } catch {
    return null;
  }
}

export default function (pi: ExtensionAPI) {
  let child: ChildProcess | null = null;
  const closedChildren = new WeakSet<ChildProcess>();
  let readyChild: ChildProcess | null = null;
  let verifiedAt = 0;
  let boundHome: string | null = null;
  let boundLock: string | null = null;
  let arming: Promise<boolean> | null = null;
  let active = false;
  let serial = 0;
  let inFlight: number | null = null;
  const batches: Batch[] = [];
  const accepted = new Map<string, Set<string>>();
  let notifyFailure: ((message: string) => void) | null = null;

  function failure(reason: string, epoch = serial): void {
    if (!active || serial !== epoch) return;
    console.error(`riddim watcher FAILED: ${reason}`);
    try {
      notifyFailure?.(`Riddim watcher FAILED: ${reason}. Run riddim notifications scan.`);
    } catch (error) {
      console.error(`riddim failure UI notification rejected: ${String(error)}`);
    }
    // Failure is a Supervisor follow-up, never an acknowledgement.
    try {
      void Promise.resolve(pi.sendUserMessage("Riddim watcher FAILED in selected home. " +
        "Inspect riddim notifications scan and repair with /riddim-watch-arm.",
      { deliverAs: "followUp" })).catch((error: unknown) => {
        console.error(`riddim failure follow-up rejected: ${String(error)}`);
      });
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
    if (child) {
      const matchingBinding = boundHome !== null && boundHome === homeIdentity() &&
        boundLock !== null && boundLock === lockIdentity();
      if (!matchingBinding && readyChild === child) {
        readyChild = null;
        verifiedAt = 0;
        child.kill();
        failure("selected home or watcher lock changed; ownership unverified");
      }
      return matchingBinding && readyChild === child && child.exitCode === null && child.signalCode === null &&
        performance.now() - verifiedAt <= BEAT_TIMEOUT;
    }
    const epoch = serial;
    const binding = homeIdentity();
    if (!binding) { failure("selected home is unavailable", epoch); return false; }
    boundHome = binding;
    const nonce = randomBytes(16).toString("hex");
    const proc = spawn("ruby", [cli, "watch-notifications", "--nonce", nonce, "--exclude-stdin"], {
      env: { ...process.env, RIDDIM_STATE_DIR: home },
      stdio: ["pipe", "pipe", "pipe"],
    });
    child = proc;
    proc.stdin?.on("error", () => { /* An early watcher refusal closes stdin. */ });
    const currentLock = lockIdentity();
    proc.stdin?.end(JSON.stringify([...(accepted.get(`${binding}/${currentLock}`) ?? [])]));
    let stdout = "";
    let stderr = "";
    let ready = false;
    let pending: Batch | null = null;
    let failureReported = false;
    const watchdog = setInterval(() => {
      if (!active || serial !== epoch || !ready || failureReported || child !== proc ||
        performance.now() - verifiedAt <= BEAT_TIMEOUT) return;
      failureReported = true;
      failure("watcher heartbeat stale; ownership unverified", epoch);
      proc.kill("SIGKILL");
    }, 1000);
    let finishReady: (value: boolean) => void = () => {};
    const readiness = new Promise<boolean>((done) => { finishReady = done; });
    const timeout = setTimeout(() => finishReady(false), WATCHER_READY_TIMEOUT);
    proc.stderr?.on("data", (part: Buffer) => { stderr += part.toString(); });
    proc.stdout?.on("data", (part: Buffer) => {
      if (!active || serial !== epoch || child !== proc) return;
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
        if (frame.type === "ready" && !ready && typeof frame.lock === "string" &&
          /^\d+:\d+$/.test(frame.lock)) {
          ready = true;
          boundLock = frame.lock;
          verifiedAt = performance.now();
          finishReady(true);
        } else if (frame.type === "beat" && ready) {
          verifiedAt = performance.now();
        } else if (frame.type === "pending" && ready && Array.isArray(frame.ids) &&
          frame.ids.length > 0 && frame.ids.every((id) => identity.test(id)) &&
          frame.home === binding && frame.lock === boundLock) {
          pending = { ids: frame.ids, home: frame.home, lock: frame.lock };
        } else { proc.kill(); return; }
      }
    });
    proc.on("error", (error) => { stderr += error.message; finishReady(false); });
    proc.on("close", () => {
      closedChildren.add(proc);
      clearInterval(watchdog);
      finishReady(false);
      if (child === proc) child = null;
      if (readyChild === proc) { readyChild = null; verifiedAt = 0; boundHome = null; boundLock = null; }
      if (!active || serial !== epoch) return;
      if (pending) {
        batches.push(pending);
        void deliver(epoch);
      } else if (!failureReported) {
        failure(stderr.trim() || (ready ? "observer stopped without a report" : "observer failed before readiness"), epoch);
      }
    });
    const signaled = await readiness;
    clearTimeout(timeout);
    // A printed ready frame by itself is not evidence of a live watcher.
    await new Promise<void>((done) => setImmediate(done));
    if (!active || serial !== epoch) return false;
    const healthy = signaled && child === proc && proc.exitCode === null && proc.signalCode === null &&
      Boolean(proc.pid) && binding === homeIdentity() && boundLock !== null && boundLock === lockIdentity();
    if (!healthy && child === proc) {
      failureReported = true;
      failure(stderr.trim() || "readiness or liveness unverified", epoch);
      proc.kill();
    }
    if (healthy) readyChild = proc;
    return healthy;
  }

  async function deliver(epoch: number): Promise<void> {
    if (inFlight === epoch || !active || serial !== epoch) return;
    inFlight = epoch;
    try {
      while (active && serial === epoch && batches.length > 0) {
        const batch = batches.shift()!;
        const ids = [...new Set(batch.ids)];
        const source = `${batch.home}/${batch.lock}`;
        if (batch.home !== homeIdentity() || batch.lock !== lockIdentity()) {
          failure("selected home or watcher lock changed; report remains in its original home", epoch);
          continue;
        }
        // Suppression is session-local; a restart replays all unhandled rows.
        if (!accepted.has(source)) accepted.set(source, new Set());
        ids.forEach((id) => accepted.get(source)!.add(id));
        const healthy = await arm();
        if (!active || serial !== epoch) return;
        if (batch.home !== homeIdentity() || batch.lock !== lockIdentity()) {
          ids.forEach((id) => accepted.get(source)!.delete(id));
          failure("selected home or watcher lock changed; report remains in its original home", epoch);
          continue;
        }
        const successor = healthy ? readyChild : null;
        const detail = healthy ? "Watcher successor is ready." :
          "Watcher FAILED: successor readiness/liveness unverified; repair supervision.";
        const content = `Riddim Supervisor notification in selected home. Pending IDs: ${ids.join(", ")}. ` +
          "Run riddim notifications scan to drain; handle the reports, then explicitly ack each presented ID. " +
          `This is a Worker claim, not Git readiness or Landing approval. ${detail}`;
        if (!healthy) ids.forEach((id) => accepted.get(source)!.delete(id));
        let deliveryTimeout: ReturnType<typeof setTimeout> | undefined;
        try {
          await Promise.race([
            Promise.resolve(pi.sendUserMessage(content, { deliverAs: "followUp" })),
            new Promise<never>((_resolve, reject) => {
              deliveryTimeout = setTimeout(() => reject(new Error("follow-up acceptance timed out")), FOLLOW_UP_TIMEOUT);
            }),
          ]);
        } catch (error) {
          if (serial !== epoch) return;
          ids.forEach((id) => accepted.get(source)!.delete(id));
          // Stop only this delivery's successor, not a later operator rearm.
          // Withdraw readiness before signaling: close is asynchronous.
          if (successor && child === successor) {
            readyChild = null;
            verifiedAt = 0;
            successor.kill();
          }
          failure(`follow-up rejected: ${String(error)}`, epoch);
        } finally {
          clearTimeout(deliveryTimeout);
        }
      }
    } finally {
      if (inFlight === epoch) inFlight = null;
      if (active && serial === epoch && batches.length > 0) void deliver(epoch);
    }
  }

  function waitForClose(proc: ChildProcess): Promise<void> {
    if (closedChildren.has(proc)) return Promise.resolve();
    return new Promise((done) => {
      const timer = setTimeout(() => { proc.off("close", closed); done(); }, SHUTDOWN_TIMEOUT);
      const closed = () => { clearTimeout(timer); done(); };
      proc.once("close", closed);
    });
  }

  pi.on("session_start", (_event, ctx) => {
    if (!home) return;
    active = true;
    notifyFailure = (message) => ctx.ui.notify(message, "error");
    void arm();
  });
  pi.on("session_shutdown", async () => {
    active = false;
    notifyFailure = null;
    serial += 1;
    const predecessor = child;
    predecessor?.kill();
    if (predecessor && !closedChildren.has(predecessor)) {
      // Pi awaits shutdown before binding the next session's extension.
      await waitForClose(predecessor);
      if (predecessor.exitCode === null && predecessor.signalCode === null) {
        predecessor.kill("SIGKILL");
        await waitForClose(predecessor);
      }
    }
    child = null;
    readyChild = null;
    verifiedAt = 0;
    boundHome = null;
    boundLock = null;
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
