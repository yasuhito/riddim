// Local-only Supervisor notifications, with native primary-checkout startup.
// External projects retain the explicit supervise/selected-home entrypoint.
import { execFileSync, spawn, type ChildProcess } from "node:child_process";
import { lstatSync, readFileSync, realpathSync } from "node:fs";
import { randomBytes } from "node:crypto";
import { dirname, resolve } from "node:path";
import { performance } from "node:perf_hooks";
import { fileURLToPath } from "node:url";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";

const cli = resolve(dirname(fileURLToPath(import.meta.url)), "../../bin/riddim");
const root = resolve(dirname(cli), "..");
let home = process.env.RIDDIM_STATE_DIR && resolve(process.env.RIDDIM_STATE_DIR);
const identity = /^(?:[a-z][a-z0-9_-]{0,31}\.s\d+\.\d+\.\d+\.(?:0|[1-9]\d*)|scheduled\.[0-9a-f]{32}\.[1-9]\d{0,9})$/;
const scheduledIdentity = /^scheduled\.[0-9a-f]{32}\.[1-9]\d{0,9}$/;
const sessionIdentity = /^[A-Za-z0-9][A-Za-z0-9_-]{0,127}$/;
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
  // Task launches inherit this project extension and the shared state home.
  // Match Actor's operator boundary, including fail-closed unknown markers.
  if (process.env.RIDDIM_ACTOR) return;

  let child: ChildProcess | null = null;
  const closedChildren = new WeakSet<ChildProcess>();
  let readyChild: ChildProcess | null = null;
  let verifiedAt = 0;
  let boundHome: string | null = null;
  let boundLock: string | null = null;
  let arming: Promise<boolean> | null = null;
  let active = false;
  let recipient: string | null = null;
  let serial = 0;
  let inFlight: number | null = null;
  const batches: Batch[] = [];
  const accepted = new Map<string, Set<string>>();
  let notifyFailure: ((message: string) => void) | null = null;
  let retryTimer: ReturnType<typeof setTimeout> | null = null;
  let retryAttempts = 0;
  let recovering = false;
  let recoveryBlocked = false;

  function failure(reason: string, epoch = serial): void {
    if (!active || serial !== epoch) return;
    console.error(`riddim watcher FAILED: ${reason}`);
    if (recovering) return; // One alarm after the bounded recovery episode.
    try {
      notifyFailure?.(`Riddim watcher FAILED: ${reason}. Verify the original home before running riddim notifications scan.`);
    } catch (error) {
      console.error(`riddim failure UI notification rejected: ${String(error)}`);
    }
    // Failure is a Supervisor follow-up, never an acknowledgement.
    try {
      void Promise.resolve(pi.sendUserMessage(`Riddim watcher FAILED: ${reason}. ` +
        "Verify the ORIGINAL home and watcher-lock identities and pending reports before scanning or asking the human to use /reload while idle. " +
        "If either identity differs or is unknown, stop and recover the original source; never scan a replacement as the original. " +
        "Reload rebinds current paths; it does not repair ownership or prerequisites. Confirm watcher readiness before claiming recovery.",
      { deliverAs: "followUp" })).catch((error: unknown) => {
        console.error(`riddim failure follow-up rejected: ${String(error)}`);
      });
    } catch (error) {
      console.error(`riddim failure follow-up rejected: ${String(error)}`);
    }
  }

  // Retry only a previously verified observer, never a contested startup lock.
  // The budget is runtime-wide (Pi reload replaces it), so a crash loop cannot
  // turn successful readiness frames into an unbounded restart storm.
  function recover(reason: string, epoch: number, originalHome: string, originalLock: string | null): void {
    if (!active || serial !== epoch || retryTimer || recovering || recoveryBlocked) return;
    const unchanged = () => originalHome === homeIdentity() && originalLock !== null && originalLock === lockIdentity();
    if (!unchanged() || retryAttempts >= 3) {
      recoveryBlocked = true;
      failure(`${reason}; automatic recovery exhausted or ownership ambiguous`, epoch);
      return;
    }
    retryAttempts += 1;
    retryTimer = setTimeout(async () => {
      retryTimer = null;
      if (!active || serial !== epoch) return;
      if (!unchanged()) {
        recoveryBlocked = true;
        failure("automatic recovery refused changed ownership", epoch);
        return;
      }
      recovering = true;
      const healthy = await arm();
      if (!active || serial !== epoch) return;
      if (!unchanged()) {
        recoveryBlocked = true;
        readyChild = null;
        verifiedAt = 0;
        child?.kill();
        recovering = false;
        failure("automatic recovery refused changed ownership after readiness", epoch);
        return;
      }
      const retiring = child;
      if (!healthy && retiring) await waitForClose(retiring);
      if (!active || serial !== epoch) return;
      recovering = false;
      if (healthy) return;
      if (child) {
        recoveryBlocked = true;
        failure("automatic recovery could not verify observer retirement", epoch);
        return;
      }
      recover(reason, epoch, originalHome, originalLock);
    }, 250 * 2 ** (retryAttempts - 1));
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
    const args = [cli, "watch-notifications", "--nonce", nonce, "--exclude-stdin"];
    if (recipient) args.push("--session", recipient);
    const proc = spawn("ruby", args, {
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
    let verifiedLock: string | null = null;
    let pending: Batch | null = null;
    let failureReported = false;
    let recoveryReason: string | null = null;
    const watchdog = setInterval(() => {
      if (!active || serial !== epoch || !ready || failureReported || child !== proc ||
        performance.now() - verifiedAt <= BEAT_TIMEOUT) return;
      failureReported = true;
      recoveryReason = "watcher heartbeat stale; ownership unverified";
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
          verifiedLock = frame.lock;
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
      } else if (ready) {
        recover(recoveryReason || stderr.trim() || "observer stopped without a report", epoch, binding, verifiedLock);
      } else if (!failureReported) {
        failure(stderr.trim() || "observer failed before readiness", epoch);
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
        if (!healthy) ids.forEach((id) => accepted.get(source)!.delete(id));
        let deliveryTimeout: ReturnType<typeof setTimeout> | undefined;
        try {
          const content = notificationContent(batch, ids, healthy, detail);
          if (!content) continue; // Cancelled/handled before the durable offer.
          if (batch.home !== homeIdentity() || batch.lock !== lockIdentity()) {
            throw new Error("selected home or watcher lock changed before follow-up");
          }
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

  function notificationContent(batch: Batch, ids: string[], healthy: boolean, detail: string): string {
    const parts: string[] = [];
    const reports = ids.filter((id) => !scheduledIdentity.test(id));
    if (reports.length) {
      parts.push(`Riddim Supervisor notification from home ${batch.home}, watcher lock ${batch.lock}. ` +
        `Pending IDs: ${reports.join(", ")}. Verify both identities in the selected home before running ` +
        "riddim notifications scan; if changed, recover from the original home manually. " +
        "Handle the reports, then explicitly ack each presented ID. " +
        "Reports are Worker claims; sequence 0 is unreported idle/stop attention, not completion. " +
        `Neither is Git readiness or Landing approval. ${detail}`);
    }
    for (const id of ids.filter((id) => scheduledIdentity.test(id))) {
      if (!recipient || !healthy) throw new Error("scheduled recipient or watcher readiness unverified");
      // This atomic, durable offer is NOT an ACK or proof of sendUserMessage
      // consumption. Cancellation before it withholds content; after it cannot
      // retract a follow-up already in flight. No shell or terminal input.
      const offered = JSON.parse(execFileSync("ruby", [cli, "schedule", "offer", id,
        "--session", recipient, "--home", batch.home, "--lock", batch.lock],
      { env: { ...process.env, RIDDIM_STATE_DIR: home }, encoding: "utf8", timeout: 5000,
        maxBuffer: 128 * 1024 }));
      if (!offered) continue;
      if (offered.kind !== "scheduled-prompt" || offered.id !== id || offered.session !== recipient ||
          typeof offered.prompt !== "string") throw new Error("invalid scheduled prompt offer");
      parts.push(`Riddim scheduled prompt ${id} for Pi session ${recipient}, from home ${batch.home}, ` +
        `watcher lock ${batch.lock}. Scheduled prompts are not Worker reports, sequence 0, Git readiness, ` +
        "or human landing/publication/destruction approval. Act only within the human-authorized scope. " +
        "After handling, explicitly acknowledge this occurrence (not just receipt) with " +
        `riddim schedule ack ${id} --session ${recipient}. Delivery may replay until ACK; ` +
        "it does not promise exactly-once task side effects. Cancellation cannot retract an in-flight follow-up.\n\n" +
        offered.prompt);
    }
    return parts.join("\n\n");
  }

  function waitForClose(proc: ChildProcess): Promise<void> {
    if (closedChildren.has(proc)) return Promise.resolve();
    return new Promise((done) => {
      const timer = setTimeout(() => { proc.off("close", closed); done(); }, SHUTDOWN_TIMEOUT);
      const closed = () => { clearTimeout(timer); done(); };
      proc.once("close", closed);
    });
  }

  let supervisorInstructions: string | null = null;
  let startupFailure: string | null = null;
  let startup: Promise<void> = Promise.resolve();
  async function initialize(ctx: ExtensionContext): Promise<void> {
    supervisorInstructions = null;
    startupFailure = null;
    // Explicit supervise remains usable from external projects and linked
    // runtimes. Native discovery alone must never promote a linked worker.
    try {
      if (ctx.cwd && realpathSync(ctx.cwd) === realpathSync(root) &&
          process.env.RIDDIM_SUPERVISE !== root) {
        const prepared = JSON.parse(execFileSync("ruby", [resolve(root, "scripts/pi_supervisor_startup.rb"), ctx.cwd],
          { encoding: "utf8", timeout: 5000 }));
        if (!prepared) return;
        Object.assign(process.env, prepared);
        home = prepared.RIDDIM_STATE_DIR;
        supervisorInstructions = readFileSync(resolve(root, "docs/supervisor.md"), "utf8");
      }
    } catch (error) {
      startupFailure = `Riddim native startup FAILED: ${String(error)}. Do not supervise or start workers until repaired. ` +
        "Fix the reported prerequisite, then use /reload or restart Pi from this checkout.";
      ctx.ui.notify(startupFailure, "error");
      return;
    }
    if (!home) return;
    // Only Pi's actual durable session metadata can route scheduled content.
    // A missing/ephemeral/unknown identity never binds itself implicitly.
    const actualId = ctx.sessionManager?.getSessionId();
    recipient = actualId && sessionIdentity.test(actualId) && ctx.sessionManager?.getSessionFile() ? actualId : null;
    active = true;
    notifyFailure = (message) => ctx.ui.notify(message, "error");
    if (!await arm() && supervisorInstructions) {
      startupFailure = "Riddim native startup FAILED: watcher ownership/readiness was not established. " +
        "Do not supervise or start workers until ownership is unambiguous and the watcher is ready.";
    }
  }
  pi.on("session_start", (_event, ctx) => {
    // Publish the gate before even a synchronous initialization failure can
    // send a follow-up into before_agent_start.
    startup = Promise.resolve().then(() => initialize(ctx));
    return startup;
  });
  pi.on("before_agent_start", async (event) => {
    // Pi's sendUserMessage binding is fire-and-forget: a failure follow-up
    // can start a run before session_start completes. Never publish the role
    // until the startup prerequisite has settled and ownership is verified.
    await startup;
    if (startupFailure) event.systemPromptOptions.sections.riddim_startup = startupFailure;
    else if (supervisorInstructions &&
             !event.systemPromptOptions.appendSystemPrompt.includes(supervisorInstructions.trim())) {
      // A pre-native supervise process may already have appended this contract
      // without the newer launcher marker. Keep that legacy reload idempotent.
      event.systemPromptOptions.sections.riddim_supervisor = supervisorInstructions;
    }
  });
  pi.on("session_shutdown", async () => {
    active = false;
    recipient = null;
    if (retryTimer) clearTimeout(retryTimer);
    retryTimer = null;
    retryAttempts = 0;
    recovering = false;
    recoveryBlocked = false;
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
}
