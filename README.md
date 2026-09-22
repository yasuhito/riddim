# riddim

Riddim is a small command-line tool for working with coding agents in
[Herdr](https://github.com/herdrdev/herdr). It is being built incrementally from
the parts of [Firstmate](https://github.com/kunchenguid/firstmate) that are useful
in a smaller, Herdr-focused tool.

Riddim currently lets you inspect Herdr's agent registration status, read recent
agent output, send an agent a prompt, interrupt a Pi agent with one Escape and
an honest post-delivery report, and start a background Pi agent. It keeps its
runtime small and uses Ruby's standard library.

## Requirements

- Ruby
- Herdr with a running session; status, peek, and send also need a named agent

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

### Read agent status

```sh
bin/riddim status <target>
```

Riddim reads the agent from Herdr and prints its status as one line. The value
is Herdr's own agent registration status, passed through raw. It does not prove
the agent's process is alive or what the agent is doing right now: Herdr keeps
a registration, with its last `agent_status`, even after the registered process
has exited.

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
requires Herdr to register the pane as a Pi agent, and delivers exactly one
Escape with
`herdr agent send-keys <pane-id> esc`: Pi cancels its running turn on a single
Escape and needs no composer-clear key afterwards. Interrupt is a lifecycle
control command, separate from `riddim send`, which sends conversational text;
there is deliberately no way to send arbitrary keys through Riddim.

Delivery is reported honestly. After Herdr accepts the key, Riddim re-reads
Herdr's agent registration for that exact pane and requires it to still
register a Pi agent, then prints one line naming the pane:

```sh
interrupt delivered to pane w9:p1 (Pi registration re-read; process liveness and cancellation unconfirmed)
```

The line claims only the registration re-read: it never claims the agent's
process is alive - a Herdr registration can outlive the process it names - and
it never claims cancellation was observed.

If the target does not resolve to a Pi agent, or a response is malformed,
Riddim refuses before delivering anything. If Herdr fails to deliver the key,
Herdr's output and exit status pass through unchanged. If the registration
re-read after delivery fails, or no longer registers that pane as a Pi agent,
Riddim reports that the key may have been delivered and says not to retry
blindly; inspect the agent with `riddim status` or `riddim peek` first.

### Send a prompt

```sh
bin/riddim send <target> <message...>
```

The remaining arguments are joined into one prompt and submitted to the Herdr
agent.

```sh
bin/riddim send pi Fix the failing tests
```

Ordinary send is a direct Herdr native prompt (`herdr agent prompt`), not
Firstmate's send: it records no durable inbox entry and tracks no reply, so a
confirmed submit proves only that Herdr accepted the text. Read what the agent
answered separately, for example with `bin/riddim peek`.

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
