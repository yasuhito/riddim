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
writer that ignores the lock. Riddim records only the fields it owns -
there is no `kind`, `worktree`, or `project` value, because Riddim manages
none of those.

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
