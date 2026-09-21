# riddim

Riddim is a small command-line tool for working with coding agents in
[Herdr](https://github.com/herdrdev/herdr). It is being built incrementally from
the parts of [Firstmate](https://github.com/kunchenguid/firstmate) that are useful
in a smaller, Herdr-focused tool.

Riddim currently lets you read recent agent output and send an agent a prompt.
It keeps its runtime small and uses Ruby's standard library.

## Requirements

- Ruby
- Herdr with a running session and a named agent

Development uses Ruby 3.4.10, as configured in `mise.toml`.

## Usage

Run Riddim without arguments to see its commands:

```sh
bin/riddim
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
