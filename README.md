# riddim

Riddim is a small command-line tool for working with coding agents in
[Herdr](https://github.com/herdrdev/herdr). It is being built incrementally from
the parts of [Firstmate](https://github.com/kunchenguid/firstmate) that are useful
in a smaller, Herdr-focused tool.

Riddim currently lets you inspect agent status, read recent agent output, send
an agent a prompt (optionally waiting until the agent is idle, done, or
blocked), interrupt a Pi agent with one verified Escape, and start a background
Pi agent. It keeps its runtime small and uses Ruby's standard library.

## Requirements

- Ruby
- Herdr with a running session; status, peek, and send also need a named agent

Development uses Ruby 3.4.10, as configured in `mise.toml`.

## Usage

Run Riddim without arguments to see its commands:

```sh
bin/riddim
```

### Read agent status

```sh
bin/riddim status <target>
```

Riddim reads the agent from Herdr and prints its status as one line.

```sh
bin/riddim status pi
# working
```

### Read agent output

```sh
bin/riddim peek <target> [lines]
```

`target` is a Herdr agent name or pane ID. Riddim prints the most recent 40
unwrapped lines by default.

```sh
bin/riddim peek pi
bin/riddim peek pi 100
```

### Interrupt a Pi agent

```sh
bin/riddim interrupt <target>
```

`target` is a Herdr agent name or pane ID. Riddim resolves the target once,
requires the pane to hold a Pi agent, and delivers exactly one Escape with
`herdr agent send-keys <pane-id> esc`: Pi cancels its running turn on a single
Escape and needs no composer-clear key afterwards. Interrupt is a lifecycle
control command, separate from `riddim send`, which sends conversational text;
there is deliberately no way to send arbitrary keys through Riddim.

Delivery is verified honestly. After Herdr accepts the key, Riddim re-reads
that exact pane and requires it to still identify a Pi endpoint, then prints
one line naming the pane:

```sh
interrupt delivered to pane w9:p1 (endpoint verified; cancellation unconfirmed)
```

The line never claims cancellation was observed.

If the target does not resolve to a Pi agent, or a response is malformed,
Riddim refuses before delivering anything. If Herdr fails to deliver the key,
Herdr's output and exit status pass through unchanged. If the pane cannot be
re-read after delivery, or no longer proves the same Pi endpoint, Riddim
reports that the key may have been delivered and says not to retry blindly;
inspect the agent with `riddim status` or `riddim peek` first.

### Send a prompt

```sh
bin/riddim send <target> <message...>
```

The remaining arguments are joined into one prompt and submitted to the Herdr
agent.

```sh
bin/riddim send pi Fix the failing tests
```

### Send a prompt and wait

```sh
bin/riddim send --wait <target> <message...>
```

`--wait` is recognized only as the first argument after `send`; a later literal
`--wait` stays message text. In wait mode Riddim delegates atomically to
`herdr agent prompt <target> <message> --wait` rather than polling the agent
itself. A confirmed submit alone proves only that Herdr accepted the text -
the agent needs a beat to enter activity before its busy state shows, so an
immediate status poll would race the idle-to-working transition. Delegating
lets Herdr submit the prompt and observe the agent's state in one process.

The wait follows Herdr's contract exactly: when submission starts from a
non-working state, Herdr requires an observed `working` or `blocked` state
after the submission (otherwise it fails with `agent_prompt_stalled`) and then
finishes on its default terminal match: `idle`, `done`, or `blocked`. Herdr
does not track turns: if the agent is already `working` when the prompt is
submitted, the pre-existing active turn's completion may satisfy the wait, so
`--wait` is not a per-turn completion guarantee.

This keeps Firstmate's distinction between confirmed delivery and reply
completion: `--wait` confirms delivery plus the agent's next settled state.
It never confirms a reply - a successful `--wait` does not mean the agent
produced a semantically valid answer. Read what the agent answered separately,
for example with `bin/riddim peek`.

Herdr's output and exit status pass through unchanged, including its wait
failures, such as a submission rejected for an already blocked agent or a
prompt that stalled before activity was observed.

### Start a background Pi agent

```sh
bin/riddim start <name>
```

Riddim creates a Herdr workspace labeled `riddim-<name>` for the current
directory without focusing it, then starts a background Pi agent named `name`
in the workspace's root pane. It never splits a pane or steals focus. `name`
must match Herdr's agent-name rule `[a-z][a-z0-9_-]{0,31}`.

The launch profile is read from `config/agent-profile`, one line in the
Firstmate-compatible `<harness> <model> <effort>` format. This first version
supports exactly the `pi` harness:

```sh
pi openrouter/z-ai/glm-5.3-flash max
```

Copy `config/agent-profile.example` to create your own; the real
`config/agent-profile` is gitignored. Set `RIDDIM_CONFIG_DIR` to read the
profile from another directory.

The agent is started with `--model <model> --thinking <effort>`. If the start
fails, Riddim closes the created root pane again and preserves Herdr's failure
output and exit status.

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
