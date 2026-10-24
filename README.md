# Riddim

Riddim lets you ask a [Pi](https://pi.dev) supervisor to delegate coding work
in [Herdr](https://github.com/herdrdev/herdr). Workers edit and commit in
separate Git worktrees. The supervisor coordinates them, reviews their work,
and asks you before landing an exact reviewed commit on local `main`.

Riddim is Pi-only and local-only. It does not push, open pull requests, or
merge remotely. It implements a smaller subset of
[Firstmate](https://github.com/kunchenguid/firstmate), without its PR pipelines,
secondmates, remote homes, quota routing or other harnesses.

## 1. Prepare your tools

You need:

- Ruby. Development and tests use **3.4.10** (`mise.toml`); other Ruby versions
  are not verified here. The CLI uses Ruby's standard library.
- Git and a target project with at least one commit and a local `main` branch.
- A Herdr client and running server, both **0.8.0 or newer**, with an open
  terminal pane. This is the launcher's minimum version check, not a claim
  that every later Herdr release has been tested.
- Pi installed as an executable named `pi` on PATH, with working model access.
  Follow [Pi's setup guide](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/quickstart.md).
- The system `ps` command for process checks and `lsof` for safe worker retirement.

In the shell you will use to launch Riddim, check the tools:

```sh
ruby --version
git --version
pi --version
command -v herdr ps lsof
```

Before delegating, run Pi interactively in a directory you trust. Use `/login`
to authenticate a supported provider, then `/model` to choose an available
coding model. Ask a small read-only question to confirm it responds, then exit
with `/quit`. If your provider needs a custom endpoint, configure it in Pi
first; Riddim does not configure providers or credentials.

Credentials supplied through environment variables must also be available to
Pi in the Herdr worker panes. A working login in an unrelated shell is not
proof workers can authenticate. Riddim does not forward arbitrary shell
variables into new panes.

## 2. Configure the launch profile

Riddim runs directly from its source checkout. In a shell, clone it to a new
directory, or use your existing checkout:

```sh
git clone https://github.com/yasuhito/riddim.git
cd riddim
```

From the **Riddim checkout**, create the ignored profile only if it does not
already exist (including a symlink):

```sh
if [ ! -e config/agent-profile ] && [ ! -L config/agent-profile ]; then
  cp config/agent-profile.example config/agent-profile
fi
```

Open `config/agent-profile` in your editor. It must contain one non-comment
line with three space-separated tokens:

```text
pi <provider/model> <effort>
```

Replace the placeholders with a model available in your Pi installation and
one of `low`, `medium`, `high`, `xhigh`, `max`. For example, the supplied sample
uses `pi openrouter/z-ai/glm-5.3-flash max`; it requires access to that model,
not just a Pi installation. Choose an effort your model supports.

The profile supplies `--model` and `--thinking` to new workers and to a
supervisor launched by `riddim supervise`. Native `pi` uses Pi's own model
selection. No Bundler install is needed to run the CLI.

## 3. Launch Pi

To supervise Riddim itself, open a shell pane in your running Herdr session:

```sh
cd /path/to/riddim
pi
```

Review and approve Pi's project trust prompt on first launch. The tracked
extension initializes the private `state/` directory, puts `riddim` on Pi's
PATH, supplies the supervisor instructions, and starts the notification watcher.
No `supervise` command or manual watcher arm is needed. A nonempty
`RIDDIM_STATE_DIR` override is preserved. This native entrypoint requires the
plain Riddim checkout root; linked worker worktrees and sessions with any
nonempty `RIDDIM_ACTOR` do not become supervisors. Ruby, Git, configured Pi
model access, Herdr and the worker launch profile are still required as above.
A competing watcher owner is refused, not replaced.

### Supervise another project

Open a shell pane in your running Herdr session. Change to the **target
project's checkout root**, not the Riddim checkout. Use a checkout on local
`main`, and commit or set aside your own edits before starting:

```sh
cd /path/to/your-project
git branch --show-current
git status --short
/path/to/riddim/bin/riddim supervise
```

Replace both paths with real absolute paths. The branch command should print
`main`; status should print nothing. Riddim starts workers from local HEAD,
without fetching or copying your uncommitted changes.

`supervise` checks the profile and running Herdr session, then starts Pi in
this same pane. It loads the supervisor instructions and notification extension
and puts `riddim` on the supervisor's PATH. You do not need to install an
extension in the target project or manually start a watcher.

If Pi asks whether to trust the target project, review its configuration before
accepting. When starting workers with project resources, Riddim persistently
trusts each exact new worktree path in Pi's trust store, not its parent.
Worktrees isolate Git edits, **not** filesystem access or credentials; workers
run as your user. Delegate only in projects whose code and Pi resources you trust.

Herdr calls use `HERDR_SESSION`, or `default` when unset. Select the intended
session before launching if you use more than one. By default, this Riddim
checkout keeps its configuration in `config/` and private runtime records in
`state/`. For separate homes, see the [CLI reference](docs/cli-reference.md).

## 4. Ask for your first task

Type a bounded request into the supervisor's Pi conversation, for example:

> Start one local-only worker named docs-example to add a short example of
> running this project's tests to its README. Have it verify the command,
> change documentation only, and commit its work. Review the diff and tell me
> what you checked. Ask me to approve this reviewed version before landing it.
> Do not push or open a PR.

The supervisor prepares the task and launches the worker in a background
Herdr workspace without changing focus. For a project named `my-app`, that
worker uses a sibling checkout `my-app-riddim-docs-example` and branch
`riddim/docs-example`. Existing names, worktrees and branches are not overwritten.
You stay in the supervisor conversation; you do not need to write task files
or run worker reporting commands yourself.

Ask the supervisor for progress or a change in direction in ordinary language.
It can inspect output and send instructions. Sending an instruction is not
proof the worker has read it. A worker becoming idle is not completion.
If a worker asks for a decision, answer through the supervisor before expecting
it to continue.

## 5. Review and approve local landing

When the worker reports completion, the supervisor checks its committed diff,
tests and handoff state. It should show you what changed, what was actually
verified, and any limitations, then ask whether to land this reviewed version.
A `done` report or `ready` result alone does not establish correctness or approval.

Review that evidence. Request changes if needed. For example, you can answer
the supervisor's specific landing proposal with:

> I approve landing this reviewed version of docs-example on local main.

You need not read or repeat a commit hash. The supervisor records the full
reviewed commit ID with its proposal and your answer; it remains available
in review evidence. General permission to do the task is not landing approval.
Every landing requires your explicit approval. If the candidate commit changes,
including by rebasing after `main` moves, the supervisor must review it again,
explain any changes to the outcome and verification, and ask for fresh approval,
even if the outcome is unchanged.

After your approval, the supervisor can fast-forward local `main` to exactly
that recorded commit. Both checkouts must be clean; diverged work must be rebased and
reviewed again. The supervisor reports whether landing actually succeeded.
Only after landing may it retire the worker, closing its pane and removing
its clean worktree and merged branch. Nothing is automatically pushed or
turned into a PR. Any later publication is outside this workflow.

Stopping a worker does not discard its work. Abandoning unlanded work requires
**separate explicit approval of irreversible loss**, tied to the inspected
worker, generation, commit and file snapshot. Landing approval never grants
that permission. See [discard safeguards](docs/cli-reference.md#discard-abandoned-local-only-work-with-separate-approval).

## Reference and troubleshooting

- [CLI reference](docs/cli-reference.md): command syntax, configuration/state
  selection, reports, notifications, diagnostic probes and cleanup limits.
- [Supervisor contract](docs/supervisor.md): authoritative supervisor obligations.
- [Operational backlog](docs/operational-backlog.md): known limitations and
  historical incidents, not additional setup steps.

If launch or delivery is unconfirmed, ask the supervisor to inspect the retained
assets before retrying. Do not delete worktrees or records to bypass a refusal.
If notification supervision reports failure, ask the supervisor to follow its
recovery instructions; a running observer is not proof every worker is readable.

## Development

From the **Riddim checkout**, install the configured Ruby and test dependencies,
then run unit tests, disposable CLI scenarios, Gherkin checks and RuboCop:

```sh
mise install
bundle install
bundle exec rake
```

The real-Pi notification and worker-startup tests run automatically when `pi`
is available on PATH, using isolated Pi configuration and a loopback model
without credentials. They report skips when Pi is absent, including in the
Ruby-only CI job; the remaining tests still run. To verify the startup
lock-collision regression with Pi installed, run:

```sh
bundle exec ruby -Itest test/pi_worker_startup_test.rb --verbose
```

Expect 1 test, 11 assertions and no skips. A skipped test does not verify real
Pi startup.
