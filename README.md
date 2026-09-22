# riddim

Riddim is a small command-line tool for working with coding agents in
[Herdr](https://github.com/herdrdev/herdr). It is being built incrementally from
the parts of [Firstmate](https://github.com/kunchenguid/firstmate) that are useful
in a smaller, Herdr-focused tool.

Riddim currently lets you inspect agent status, read recent agent output, send
an agent a prompt, and start a background Pi agent. It keeps its runtime small
and uses Ruby's standard library.

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

### Send a prompt

```sh
bin/riddim send <target> <message...>
```

The remaining arguments are joined into one prompt and submitted to the Herdr
agent.

```sh
bin/riddim send pi Fix the failing tests
```

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
