# riddim

Riddim is a small command-line tool for working with coding agents in
[Herdr](https://github.com/herdrdev/herdr). It is being built incrementally from
the parts of [Firstmate](https://github.com/kunchenguid/firstmate) that are useful
in a smaller, Herdr-focused tool.

Riddim currently lets you inspect Herdr's agent registration status, read a
started agent's recent output from the exact pane its ownership record binds,
send a started agent a prompt, interrupt a started Pi agent with one Escape
and an honest post-delivery report, and start a background Pi agent whose
endpoint ownership it records, Firstmate-style, before the agent runs. It keeps its runtime small
and uses Ruby's standard library.

## Requirements

- Ruby
- Herdr client and running server version 0.8.0 or newer for `start`;
  Riddim intentionally requires Firstmate's focus-safe emptying-close release
  rather than supporting older versions with its more elaborate close plan
- Herdr with a running session; `status`, `peek`, `send`, and `interrupt`
  require an agent started with `riddim start`

Development uses Ruby 3.4.10, as configured in `mise.toml`.

## Usage

Run Riddim without arguments to see its commands:

```sh
bin/riddim
```

### Session targeting

Every Herdr subprocess Riddim launches targets one Herdr session: the
nonempty `HERDR_SESSION` value from Riddim's environment, otherwise Herdr's
`default` session. Each subprocess receives that session twice: as its
`HERDR_SESSION` environment variable and as an explicit `--session <session>`
global flag placed ahead of the subcommand. The explicit flag routes the call
exactly, even when another Herdr server is running on the same machine, and
stays valid ahead of commands such as `agent start`, whose `--` passthrough
tail must reach the agent's own arguments untouched.

`status`, `peek`, `send`, and `interrupt` are the exceptions: they target the
session recorded in the agent's endpoint ownership record, which overrides the ambient
`HERDR_SESSION` value on both routing surfaces, so an operation on one recorded
agent can never drift to another session's endpoint.

### List recorded agents

```sh
bin/riddim list [--json]
```

Lists validated `state/<name>.meta` records, sorted by name, as tab-separated
`name`, recorded Herdr session, and exact pane ID. An absent or empty state
directory produces no rows. A still-present malformed record fails the entire
read without printing a partial list; a record removed during enumeration is
omitted. The command does not invoke Herdr, read mutable labels, or modify
state. These are **owned endpoint records, not necessarily running agents**.
For example:

```text
worker\triddim\tw9:p1
```

`--json` prints a versioned `riddim.list.v1` object from the same validated
records, with a `records` array sorted by name. Its fields are `name`,
`session`, and `pane_id`; an empty inventory is `[]` within the object. JSON
is produced only after every record has been checked, so a failure prints no
partial object. For example:

```json
{"schema":"riddim.list.v1","records":[{"name":"worker","session":"riddim","pane_id":"w9:p1"}]}
```

This is only Firstmate's fleet snapshot ownership inventory. It does not
provide Firstmate's current crew state, endpoint presence, process liveness,
backlog, or full `fm-fleet-snapshot.v1` schema. Use `status <name>` for the
separate raw Herdr registration read, not as proof of process liveness.

### Read an agent's process state

```sh
bin/riddim agent-state <name>
```

Reports `alive`, `dead`, `missing`, or `unreadable` for the exact recorded
session and pane. Unlike `status`, this read corroborates Herdr registration
with pane presence and the OS process view: `alive` requires a registered Pi
process, and `dead` requires a present pane with no registered agent or a
shell-only process view behind a stale Pi registration. A confirmed missing
pane, or a recorded session whose server is positively stopped, reads
`missing`. **Missing does not prove the endpoint was destroyed:** a stopped
server can restore it. Unreadable and unfamiliar process states remain
`unreadable` rather than being guessed into `dead` or `alive`. If the ownership
record's `spawn_gen` or exact endpoint changes during observation, Riddim
returns `unreadable` rather than attributing the old observation to a new
incarnation.

This read-only feature is narrower than Firstmate's cross-harness recovery
classifier: another non-shell foreground process is `unreadable` here, not
`alive`; no server is started for an absence proof. None of these words
report turn completion or authorize removing a pane or an ownership record.

### Observe native Pi activity

```sh
bin/riddim busy-state <name>
```

Reports `busy`, `idle`, or `unknown` for the recorded session and pane.
Firstmate's Herdr busy classifier maps `working` to `busy`, and `idle`,
`done`, and `blocked` to `idle`. Riddim exposes a **smaller Pi-only subset**:
it reports either verdict only when a matching Pi registration and the real
Pi process corroborate the exact pane. Missing, stale, foreign, or unreadable
observations, and an ownership change during the read, return `unknown`.
Unlike Firstmate's watcher, Riddim does not fall back to a harness-specific
pane signature when native state is unknown.

`idle` is only the native activity observation. It does **not** mean a turn or
foreground tool finished, a reply was delivered, or the agent stopped. Use
`agent-state` to distinguish a dead agent from an unreadable one, not `idle`
to infer that a `send` completed.

### Read exact pane presence

```sh
bin/riddim pane-presence <name>
```

Reports `present`, `gone`, or `unknown` for the recorded session and exact
pane. This is the small, read-only Herdr subset of Firstmate's
`fm_backend_herdr_pane_presence_state`: a matching structured `pane get`
response establishes `present`; only a structured `pane_not_found` response
establishes `gone`. Exit status alone and an unreachable or stopped server
leave the result `unknown`. Unlike `agent-state`'s `missing`, `gone` is **not**
reported merely because the recorded server is stopped. Riddim checks that
ownership has not changed during the read and otherwise returns `unknown`.

Pane presence says nothing about whether Pi is running or a turn has finished.
It never closes a pane or removes an ownership record. Even `gone` is a
point-in-time observation, not permission to clean up a record without a
separate locked, exact-endpoint verification.

### Read the foreground working directory

```sh
bin/riddim current-path <name>
```

Prints the recorded exact pane's `foreground_cwd`, or `unknown` when it cannot
be verified. Firstmate's Herdr `current_path` probe reads that live field
instead of `cwd`, which can describe the pane shell rather than a foreground
subshell. On Herdr 0.9.0, a live subshell in `/` left the pane's `cwd` at
`/tmp` while `foreground_cwd` and `current-path` both read `/`. This is a
smaller read-only subset: Riddim
requires a successful, matching structured pane response and a legible
absolute path; it does not start a stopped Herdr server, substitute the pane's
`cwd` field, or claim the path owns a worktree. A changed
ownership record also makes the observation `unknown`.

### Inspect pane process evidence

```sh
bin/riddim process-state <name>
```

Reports `pi`, `shell`, or `unreadable` from the recorded pane's
`process-info` and the OS process table, independently of Herdr's agent
registration. This is a **Pi-only subset** of Firstmate's
`fm_backend_herdr_pane_process_state`: `pi` requires a verified Pi foreground
process or Pi descendant; `shell` requires a shell-only foreground with no Pi
descendant. Unfamiliar foreground processes, missing or mismatched pane
information, unreadable OS process data, and an ownership change during the
read all produce `unreadable`. Firstmate additionally distinguishes `other`
and settles transient foreground helpers; Riddim does not yet claim that state.

This read explains why a registration may be stale, but `shell` **alone never**
authorizes closing a pane. Firstmate refuses to close a stale-registration
pane as a disposable husk during recovery because it may hold a nested
worktree shell. Explicit `teardown` instead requires landed work, an ungated
report, exact pane ownership, and confirmed disappearance. Neither this output
nor `agent-state` proves turn completion.

### Read the recorded session's server state

```sh
bin/riddim server-state <name>
```

Reports `running`, `stopped`, or `unknown` from the recorded session's
`status --json` alone, without touching any pane. This is a smaller subset of
Firstmate's `fm_backend_herdr_server_running_state`; it tells you whether a
`missing` from `agent-state` is explained by a server that is not running.
Herdr preserves pane, tab, and workspace ids across a server restart while
harness processes and registrations die, so `stopped` means unreachable right
now: it is **not** evidence an endpoint was destroyed and licenses no
recovery by itself. Malformed status output and an ownership change during
the read both stay `unknown`.

### Classify a pane's composer

```sh
bin/riddim composer-state <name>
```

Classifies the recorded pane's input composer as `empty`, `pending`, or
`unknown` from a styled viewport capture and Herdr's native identity probe -
the pi separated-pair shape of Firstmate's shared composer classifier,
reduced to what a Pi-only pane can draw. Any non-empty row inside the
bottom-most separator pair is proven input; only a live Pi registration
reporting idle/done proves `empty`, so a working pi stays `unknown` and a
blocked pi (parked on its own prompt) refuses too. A missing or foreign
identity, a pair wider than eight inner rows, another shape below the pair,
failed reads, and an ownership change during the read all refuse.

This read authorizes nothing by itself. It exists as the gate Firstmate's
`exit` consumes: a composer that is not proven `empty` must never receive a
submitted command, and `pending` means visibly unsubmitted text is sitting
in the pane. Unlike Firstmate, Riddim classifies only the pi shape and never
emits `pending-unproven`.

### Stop a started Pi agent

```sh
bin/riddim exit <name>
```

Stops the recorded Pi agent and reports one of Firstmate's exit verdicts:
`stopped` (the exit command was submitted and the agent is proven stopped),
`already-stopped` (idempotent: the recovery-grade state already reads dead),
or `endpoint-gone` (a positively running recorded server proves the pane
itself is gone). The pane and the ownership record are preserved in every
outcome; record cleanup is a separate decision, never part of exit.

A busy agent is interrupted first, with `interrupt`'s own verification. The
composer must then be proven `empty` by `composer-state` before the pi exit
command (`/quit`) is typed once and submitted with Enter - pending text
refuses, and Enter is retried without retyping. The postcondition is the
recovered agent state within a bounded wait (`RIDDIM_EXIT_WAIT`, default 30
seconds); a timeout refuses with `exit=unconfirmed`. A `missing` endpoint is
absence-proven only by the recorded session's positively running server:
exit does not start servers, so a stopped server refuses unproven. Every
refusal names what exit would have done and why it stopped.

This is a smaller subset of Firstmate's `exit`: Riddim is pi-only, has no
relaunch, and does not start servers on recheck; an interrupt that actually
stops the agent reports interrupt's own refusal instead of exit success.

### Read agent status

```sh
bin/riddim status <name>
```

`name` is the name of an agent started with `riddim start`. Riddim validates its
endpoint ownership record with the same fail-closed rules as `peek`, then asks
Herdr for the registration attached to the exact recorded pane in the exact
recorded session. It prints Herdr's raw `agent_status` as one line.

This is deliberately a smaller subset than Firstmate's current crew-state
reader. It does not check pane presence, process liveness, task activity, or
status logs, and it does not return Firstmate's canonical `working`, `parked`,
`done`, `blocked`, `paused`, `failed`, or `unknown` crew state. It also omits
Firstmate's lower-level recovery classifier, which distinguishes `alive`,
`dead`, `missing`, and `unreadable` endpoints. Herdr can retain a registration
and its last `agent_status` after the registered process exits, so the printed
value must not be treated as proof that the process is alive or that the agent
is currently doing the named work.

```sh
bin/riddim status worker
# working
```

### Read a started agent's output

```sh
bin/riddim peek <name> [lines]
```

`name` is the name of an agent started with `riddim start`. Riddim resolves
the endpoint ownership record `state/<name>.meta` - in the directory named by
a nonempty `RIDDIM_STATE_DIR`, otherwise the repository's own `state/` - and
captures the exact Herdr pane the record binds, in the session the record
names, with Firstmate's Herdr capture: it reads
`herdr pane read <pane-id> --source recent --lines <fetch>`, where the fetch
is the requested count never below 200 lines, and trims the capture locally
to the final requested lines. The most recent 40 lines are printed by
default.

```sh
bin/riddim peek worker
bin/riddim peek worker 100
```

`peek <name> --visible` reads the exact pane's visible viewport instead,
from Firstmate's `fm_backend_herdr_visible_capture`: one
`herdr pane read <pane-id> --source visible` with no line count, because the
viewport itself is the bound and a line count is what triggers Herdr's
empty-read quirk. The capture is passed through whole, untrimmed.

```sh
bin/riddim peek worker --visible
```

The record is the routing authority, and it fails closed before Herdr is
touched at all: it must be a regular file at `state/<name>.meta` - never a
symbolic link - it must contain each required ownership field exactly once
(additional well-formed metadata fields are permitted), it must bind
`endpoint_task_id`
equal to the requested name on the `pi` harness
and the `herdr` backend, and its `window` must be exactly
`<herdr_session>:<herdr_pane_id>`. A missing, symlinked, malformed, or
inconsistent record is refused with Riddim's own status 1, and no Herdr
command is ever constructed from labels or inference. If the pane read
fails, Herdr's stdout, stderr, and exit status pass through unchanged.

### Interrupt a started Pi agent

```sh
bin/riddim interrupt <name>
```

`name` is the name of an agent started with `riddim start`; explicit pane IDs,
Herdr agent names without Riddim ownership, and mutable labels are refused.
Riddim validates the endpoint ownership record, acquires the per-name lock,
validates the record again, and keeps the lock through delivery and its
postcondition. Each Herdr subprocess inherits the lock descriptor, so even an
abrupt Riddim exit cannot release the name while that subprocess is still
finishing. Riddim requires Herdr to register Pi at the exact recorded pane
and checks `pane process-info` against the OS process table: a Pi process
must be in the foreground or descend from the pane shell. An unreadable,
stale, or shell-only process view refuses before delivery. It then sends one
Escape to that pane in the recorded session with
`herdr pane send-keys <pane-id> escape`. Pi cancels its running turn on a
single Escape and needs no composer-clear key afterwards. Interrupt is a
lifecycle control command, separate from `riddim send`, which sends
conversational text; there is deliberately no way to send arbitrary keys
through Riddim.

Delivery is reported honestly. After Herdr accepts the key, Riddim re-reads
Herdr's agent registration and process view for that exact pane, then prints
one line naming the pane only when both still corroborate the Pi process:

```sh
interrupt delivered to pane w9:p1 (Pi process checked before and after; cancellation unconfirmed)
```

The line claims the checked process view, not that cancellation was observed.
A registration alone is never liveness evidence.

If the record is invalid, the registration does not identify Pi at the exact
recorded pane, or a response is malformed, Riddim refuses before delivering
anything. If Herdr fails to deliver the key, Herdr's output and exit status
pass through unchanged. If the registration re-read after delivery fails, or
no longer registers Pi at the same pane, Riddim reports that the key may have
been delivered and says not to retry blindly; inspect the agent with
`riddim status` or `riddim peek` first.

This is deliberately smaller than Firstmate's interrupt control plane.
Firstmate's cross-harness recovery classifier also treats a non-shell
foreground process as live after a bounded settle, checks pane presence, and
reports the strongest adapter-owned cancellation acknowledgement. Riddim's
Pi-only check requires a positively identifiable Pi process instead and
refuses an unfamiliar foreground. It does not prove turn cancellation or a
task-state transition, and never rewrites status as proof of interruption.

### Send a prompt

```sh
bin/riddim send <name> <message...>
```

`name` is the name of an agent started with `riddim start`. The remaining
arguments are joined into one prompt. Riddim validates the endpoint ownership
record, acquires the per-name lock, validates the record again, and lets the
Herdr child process inherit that lock descriptor across `exec`, keeping the
lock until Herdr exits even if the Riddim controller dies. It submits the
prompt to the exact recorded pane in the exact recorded session, so a
cooperating lifecycle writer cannot rebind
the name during delivery.

```sh
bin/riddim send worker Fix the failing tests
```

This remains deliberately smaller than Firstmate's send. It is a direct Herdr
native prompt (`herdr agent prompt`), not a durable steering inbox: Riddim
records no sequenced inbox entry, rings no retryable doorbell, tracks no reply,
and provides no acknowledgement or idempotent retry contract. A successful
command proves only that Herdr accepted the prompt. A failed Herdr prompt
returns status 3 and a delivery-unconfirmed warning rather than
claiming no delivery; a child killed by a signal retains signal termination
with the same warning. No retry is automatically safe because an instruction
might already have reached the pane. Read what the agent answered separately
with `bin/riddim peek worker`, and inspect the pane before any retry.

### Start a background Pi agent

```sh
bin/riddim start <name>
```

Riddim creates a Herdr workspace labeled `riddim-<name>` for the current
directory without focusing it, then starts a background Pi agent named `name`
in the workspace's root pane. It never splits a pane or steals focus. `name`
must match Herdr's agent-name rule `[a-z][a-z0-9_-]{0,31}`.

The launch profile is read from `config/agent-profile`, one line in the
`<harness> <model> <effort>` token order of Firstmate's
`config/secondmate-harness`. It is a Pi-only profile: this first version
supports exactly the `pi` harness, and unlike Firstmate's secondmate-harness,
which allows omitting the model and effort tokens, Riddim requires all three
tokens:

```sh
pi openrouter/z-ai/glm-5.3-flash max
```

Copy `config/agent-profile.example` to create your own; the real
`config/agent-profile` is gitignored. Set `RIDDIM_CONFIG_DIR` to read the
profile from another directory.

The agent is started with `--model <model> --thinking <effort>`.

#### Start in a fresh Git worktree

```sh
bin/riddim start <name> --worktree
```

From a Git checkout (or a directory inside one), this creates a **new linked
worktree** beside the checkout's root, named `<project>-riddim-<name>`, on a
new `riddim/<name>` branch at the checkout's **local HEAD**. It never fetches,
resets, reuses a worktree or branch, or copies uncommitted changes. An existing
record, destination, or branch refuses rather than overwrites. The worktree
must be clean and must resolve to a different root of the same Git repository,
not to the primary checkout. Before starting Pi, Riddim also requires two
consecutive exact-pane foreground cwd reads to match that worktree. A failed
placement closes only the exact created pane and verifies the close.

For an assigned task, give `start` a UTF-8 file (at most 64 KiB):

```sh
bin/riddim start <name> --worktree --task-file <path>
```

Riddim reads and validates the file before allocating a worktree or endpoint,
then atomically publishes a 0600 `state/<name>.brief` outside the worktree.
The brief starts with a Pi worker role that distinguishes project coding
instructions from supervisor instructions in `AGENTS.md`, followed by the
file's exact task text. Herdr's native `agent start` refuses multi-line
arguments. For a task, Riddim instead stages a private 0600 shell launch file
outside the worktree, publishes the ownership record, then submits the launch
file to the exact new pane. Its filename carries the record's `spawn_gen`, so
a delayed source line cannot execute a replacement launch after a name is
reused. Its quoted command substitution supplies the full brief as Pi's
initial positional prompt, as Firstmate's Pi launch does. Riddim
confirms that Herdr detects Pi on the exact pane, names that detected agent,
and confirms the name, incarnation and Pi process before reporting `started`.
This **does not** confirm Pi read or completed the task, or delivered a reply.

An existing brief refuses any new start under the same name. Once the record
is published, any failed or ambiguous submission, registration, or naming
retains the pane, record, brief, launch file, and worktree for inspection:
Riddim cannot prove the task did not already run and never automatically
retries it. A symlinked, non-regular, empty, invalid UTF-8, or NUL-containing
task file refuses before allocation. This remains a Pi-only subset of Firstmate's launch brief: there is no typed
Firstmate operational-input marker, durable inbox, acknowledgement, reply
tracking, or PR delivery. Without `--task-file`, `start --worktree` retains
its previous native `agent start` behavior.

#### Local-only result handoff

```sh
bin/riddim start <name> --worktree --task-file <path> --mode local-only
bin/riddim report <name> --generation <spawn-gen> '<status-event>'
bin/riddim result <name>
```

This explicit mode starts only from a checkout on its local `main` branch. It
adds a local-only delivery contract to the private brief: the worker commits
on `riddim/<name>`, never pushes or opens a PR, and uses `report` to append a
short, timestamped `done`, `blocked`, `failed`, or `needs-decision` event to a
private status file outside the worktree. `report` requires the ownership
record's `spawn_gen` and holds the same per-name lock as `merge-local` through
the append, so a cooperating worker cannot open a decision during the
fast-forward. Direct writes to the status file are outside this contract. The
status filename also includes `spawn_gen`, so an old report cannot become the
new worker's report. Every
explicit `Delivery contract: mode=...` line in the task file must agree with
`local-only`, or the start refuses before allocating a worktree, pane, brief,
or result file. For free-text conflicts (such as an instruction to push), the
launch contract takes precedence and tells the worker to report a decision
instead of carrying out the conflicting delivery; this is an instruction, not
a guarantee of model compliance. The result file is created before launch with
owner-only permissions; ambiguous launch failures leave it and other assets
available for inspection. If `report` refuses, the worker must stop and
explain the refusal, not write the file directly. Work launched before the
locked reporting protocol remains readable by `result` but is not eligible
for `merge-local` and needs a separately approved manual landing.

`result` requires the exact current ownership record. `unreported` means its
status file is empty; `reported` is the worker's last event, not proof of
current activity. A `done` event becomes `ready` **only** if the recorded
linked worktree is still in the same repository, its branch has a commit past
the recorded start HEAD, that commit is the branch tip, its worktree has no
tracked or untracked changes, and `main` is an ancestor of that tip. Otherwise
it remains `reported (not ready)`. An earlier `blocked`, `failed`, or
`needs-decision` event cannot be cleared by a later `done` in this subset;
resolve it explicitly and start a new task. Missing, symlinked, unreadable, or malformed
status evidence fails closed instead of yielding `ready`. This is a snapshot,
not permission to merge: independently review code and tests and recheck Git
before merging. It does not infer completion from Herdr idle, validate test
claims, automatically merge, clean up, or implement Firstmate's reconciled
current crew-state, inbox, or watcher. Existing starts without `--mode` retain
their previous briefs and delivery behavior.

#### Review a local-only worker's committed diff

```sh
bin/riddim review-diff <name> [--stat]
```

Compares the recorded `riddim/<name>` branch with the project's **local
`main`**, using Git's three-dot diff (changes since their merge base). It
prints a stat and patch, or only the stat with `--stat`; an uncommitted edit
is not included. Both outputs begin with the exact worker branch tip SHA on
a `head:` line, the reviewed version the operator can approve for
`merge-local`. This is read-only: no fetch, PR lookup, merge, or cleanup.
It requires the current local-only ownership record, the same linked Git
repository and checked-out named branch. It holds the per-name lock from the
authoritative record read through printing, and rechecks the record and Git
tips before printing. A detected change or an unreadable checkout refuses
without printing a partial diff. Cooperating Riddim lifecycle writers wait
for the display to finish; Git writers and processes that ignore the lock do
not. This is a point-in-time read, not a merge authorization. Reviewing a
diff does not make a task `ready`; `result` separately checks the worker's
report and Git handoff evidence.

This is only the local-branch subset of Firstmate's `fm-review-diff.sh`, which
can also refresh a remote-backed base and review a recorded PR's fetched head.
Riddim deliberately neither fetches nor substitutes a PR or remote head.
Firstmate's review-diff does not hold a task lock or recheck its record; the
Riddim read adds that guard, while Firstmate's state-changing local merge has
its own generation and control-lock gate.

#### Land an approved local-only worker branch

```sh
bin/riddim review-diff <name>                          # review, then approve the printed head
bin/riddim merge-local <name> --head <reviewed-commit>
```

`merge-local` is the operator's landing action for a local-only task: it moves
the project checkout's local `main` to the exact reviewed worker branch tip
with one strict fast-forward. It is a smaller counterpart of Firstmate's
`fm-merge-local.sh`: no PR, pool, yolo, remote fetch, backlog, captain-hold
lifecycle, or automatic approval of any kind. Firstmate's worker status log
is a best-effort direct append, while its separate captain-hold record shares
the local merge's control lock. Riddim lacks that hold, so new task workers
report through the shared name lock instead; this is a stricter local-only
subset, not a claim to implement Firstmate's full hold lifecycle.

The operating rule is explicit human approval: run `review-diff`, review the
patch, and approve the exact `head:` SHA it prints. That approval is the
operator's own decision, recorded outside this CLI; a `ready` result, a `done`
report, or a printed diff is **not** approval, and this brief is not one
either. `merge-local` never claims that a human approved anything in the CLI.
It reports only what it did, with the exact resulting local main tip:

```text
merged riddim/<name> into local main (<old main tip> -> <new main tip>) in <project>
```

The command must be invoked from the recorded project's main checkout. Under
the per-name lock it validates, in order, and refuses without moving `main`
when a pre-merge check fails:

- the current local-only ownership record bytes and generation; missing,
  symlinked, malformed, rebound, or non-local records refuse
- a generation record using the locked report protocol and an ungated
  generation-local `done` report: any open `blocked`, `failed`, or
  `needs-decision` event refuses, and a later `done` cannot clear one (the
  sticky status rule)
- the same linked worktree and checked-out named branch, the branch tip
  matching its name, and the recorded base/ready relationship
- clean worker and project checkouts, and the project checkout on local
  `main`
- a strict fast-forward: local `main` must be a proper ancestor of the branch
  tip. A diverged branch refuses with Firstmate's rebase guidance; a branch
  local `main` already contains is refused as nothing to land
- the given `--head` must be a full commit id equal to the verified branch
  tip: a stale or changed reviewed SHA refuses, so the merge lands exactly
  the reviewed version

The lock stays held through Git's `merge --ff-only` and the result
verification. The merge fast-forwards to the approved commit id itself, not
to the branch name, so a branch that moves during the merge window cannot
land an unapproved tip; Git re-checks the fast-forward on its own. After the
fast-forward, Riddim re-verifies the ownership record, the ungated `done`
report, and the resulting `main` tip, and refuses to claim a verified merge
when a change is detected (the merge may already have landed; inspect before
continuing). A `report` call waits on the shared name lock; a decision reported
during landing therefore cannot be written until the fast-forward finishes.
Riddim also rechecks status immediately before and after Git's merge. A direct
file append ignores that lock and is outside the cooperative guarantee; if
noticed afterward, Riddim reports that `main` may have moved rather than
claiming success.
`merge-local` never pushes, fetches, auto-reviews, tears down, retries, or
forces, and it never closes a pane or removes a worktree, branch, brief, or
record: those remain for `teardown`. Cooperative Riddim writers share the
name lock; external Git writers ignoring it remain outside that guarantee.

##### Role boundary: the task worker never lands

The task launch exports `RIDDIM_ACTOR=branch` for the Pi process started by
the generation-bound private task shell, and every shell tool it spawns
inherits the marker, mirroring Firstmate's supervision role partition where
the supervision branch never lands local-only work. `merge-local` refuses a
`branch` actor and any unknown `RIDDIM_ACTOR` value before reading the task
record or touching Git; an unmarked caller is the operator, and the refusal
of a wrong actor precedes reading the record, so the role applies whatever
the record says. The variable is an operational actor boundary, not
cryptographic proof of the human's approval, and it deliberately covers only
this subset: native non-task `start --worktree` and `start` launch Pi through
Herdr's own `agent start`, which offers no environment-injection surface, so
marking those workers would change Herdr-native semantics. This first subset
therefore enforces the role partition for task workers only and does not
claim universal enforcement.

#### Retire an already-landed local-only worker

```sh
bin/riddim teardown <name>
```

This is a **destructive, explicit** local-only subset of Firstmate's
`fm-teardown.sh`, not an approval or merge command. Firstmate also manages
Treehouse pool slots, remote/PR tasks, backlog transitions, and forced discard;
Riddim does none of those. First merge the reviewed worker branch into local
`main` with separate human approval. `teardown` then requires an ungated `done`
report, the current ownership generation, a clean linked worker checkout on its
recorded branch, a clean project checkout on `main`, and proof that the worker
branch tip is already in local `main`. No `--force` is available.

Under the name lock it closes **only** the recorded exact pane (or confirms it
was already gone). It refuses to close its own calling pane or a pane occupied
by a different agent, and requires a structured read proving the pane gone.
Before removing the linked worktree without force, it runs Firstmate's
non-recursive process-cwd scan (`lsof -a -d cwd -Fpn`) and refuses if the scan
fails, returns empty or malformed records, or finds a process in the worker
checkout. Git
checks are repeated after pane closure. Only then does it remove the worktree,
delete the merged branch with `git branch -d`, archive the private brief at
`state/<name>.<spawn_gen>.brief`, and remove the generation-matched ownership
record. Generation-local status, opt-in trace, and the immutable launch file
remain private for diagnosis. Archiving frees the name for a later start.

On ambiguous reads or partial failures, it does not force-delete, retry a close,
or infer success: the record and any unremoved assets stay for inspection. In
particular, if Git removal succeeded but a later stage failed, do **not** run
another teardown blindly. Verify exactly what remains. Cooperative Riddim
writers share the name lock; an external process ignoring it or concurrently
changing Git is outside this guarantee. The command does not attest that a
human reviewed the patch; the operator must make that decision before landing.

The ownership record also stores `project`, `worktree`, and `branch` for this
mode. These are inventory, **not authority by themselves to remove files**:
`exit` leaves the pane, record, worktree, and branch intact, while `teardown`
requires the independent gates above. If creation or launch fails, inspect
the reported path and branch; Riddim never deletes or resets the worktree or
branch automatically. This is a smaller subset of Firstmate's Treehouse spawn:
there is no pool, lease, fresh remote fetch, reply tracking, or Firstmate's full teardown. The original `start <name>` still starts in the current directory.

The ignored `config/agent-profile` and `state/` are **not copied into a Git
worktree**. Before launching Pi, Riddim atomically writes the original config
and state directory paths into that worktree's private Git admin directory
(`riddim-home`), outside the checkout. A Riddim CLI invoked from the linked
worktree reads that marker and defaults to the original profile and records;
there is no environment setup for the worker. Explicit `RIDDIM_CONFIG_DIR` and
`RIDDIM_STATE_DIR` overrides still win. A malformed or symlinked marker refuses
rather than silently using a different state directory. The marker is not
endpoint authority and does not authorize worktree deletion.

#### Endpoint ownership record

Before the agent starts, `start` publishes an endpoint ownership record for
the name, shaped like Firstmate's `state/<id>.meta` task records: plain
`key=value` lines, not JSON, in Firstmate's field order:

```text
window=<session>:<pane-id>
endpoint_task_id=<name>
harness=pi
model=<model>
effort=<effort>
spawn_gen=<spawn-generation>
backend=herdr
herdr_session=<session>
herdr_workspace_id=<workspace-id>
herdr_tab_id=<tab-id>
herdr_pane_id=<pane-id>
```

`window` and the four `herdr_` fields carry Herdr's exact response-derived
ids for the created endpoint; a Herdr pane id contains a colon, so
`window=` splits on the first colon only. The records live in `state/`
inside the repository, or in the directory named by a nonempty
`RIDDIM_STATE_DIR`. Riddim creates that directory with owner-only
permissions and keeps every record the same way: the complete record is
fully written to a `0600` temp file in the same directory and then linked
into place - an atomic no-replace operation, so a reader never sees a
partial record and an existing record is never overwritten, even by a
writer that ignores the lock. Riddim records only the fields it owns: ordinary `start` has no `kind`,
`worktree`, or `project`, while `start --worktree` adds the created `project`,
`worktree`, and `branch` as inventory without changing endpoint routing.

The record makes the name owned. `start` holds one per-name lock
(`.meta-<name>.lock` in the state directory) from a duplicate preflight
through the launch result, and refuses any existing record - even a
malformed or unreadable one - before it invokes Herdr at all. Two concurrent
starts of the same name serialize on the lock, and the loser refuses.

Like Firstmate, Riddim uses this lock as a cooperative lifecycle-writer
contract, not as security isolation from other processes running as the same
Unix user. Every Riddim lifecycle writer for a name must hold its per-name lock
while it publishes, replaces, or removes that name's record; read-only routing
uses a validated descriptor snapshot instead. The state directory's `0700`
mode excludes other users, but a same-user process that deliberately ignores
the lock is outside this contract. Ruby's pathname-based unlink does not offer
an atomic compare-and-delete primitive that could make a stronger claim.

#### Confirmed pane cleanup

`start` follows Firstmate's spawn order: create the exact Herdr endpoint,
publish the authoritative record, then start the agent. `Herdr.start_agent`
performs no rollback of its own; the start flow owns every cleanup decision:

- If the record cannot be published after the workspace was created, Riddim
  issues one close of the exact root pane and then a `pane get` of the same
  pane, and reports the exact session, workspace, tab, and pane ids. Cleanup
  is claimed only when Herdr's structured `pane_not_found` response confirms
  the pane is gone.
- If the agent start fails, Riddim issues the same one close and one `pane
  get`, preserves Herdr's output and exit status unchanged, and removes the
  record only after the pane is confirmed gone and only while the record
  still carries the spawn generation this start minted. Under the same
  per-name lock, Riddim opens no symbolic links and immediately before the
  pathname unlink re-checks that a regular file's device and inode still match
  the descriptor whose bytes it verified. The lock, not that final check,
  prevents cooperating lifecycle writers from changing the pathname between
  the check and unlink.
- If the close fails, the pane's absence cannot be confirmed, or the Herdr
  executable itself becomes unavailable, the record is retained and Riddim
  reports that exactly, naming the record path and the endpoint ids,
  instead of claiming a cleanup it did not verify.

The cleanup is pane-scoped by construction: Riddim never calls `workspace close`.
Its dedicated workspace can become empty when that pane closes. Before creating
one, `start` checks the client and any running server are at least Herdr 0.8.0,
where Firstmate verifies an emptying close no longer steals focus. This is a
smaller supported-release subset than Firstmate, which also supports older
Herdr versions using session-level focus-safe cleanup.

## Development

Install the configured Ruby and development dependencies:

```sh
mise install
bundle install
```

Run the unit tests, Cucumber scenarios, Gherkin conventions, and RuboCop:

```sh
bundle exec rake
```
