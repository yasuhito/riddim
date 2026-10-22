## Agent skills

### Issue tracker

Issues are tracked in GitHub repository `yasuhito/riddim`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the five canonical triage labels. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. See `docs/agents/domain.md`.

### Development direction

Keep Riddim a compact Ruby implementation, using the standard library where practical: Pi-only workers supervised from one session. Add necessary features one at a time when actual use exposes a need. Keep unrelated PR, remote, quota and multi-harness machinery out of this scope.

Before proposing or implementing a user-facing feature, find and read its working implementation in `/home/yasuhito/Work/oss/firstmate`. Propose only features that Firstmate already implements. State when Riddim implements a smaller subset, and preserve Firstmate's safety contract rather than substituting a Herdr-native behavior with different semantics.

### Roles and delivery

Project edits belong to Riddim workers in their assigned isolated worktrees; workers follow the project's coding and testing instructions there. The supervisor coordinates rather than editing the project. See `docs/supervisor.md` for external task-file/local-only launch, review, exact-SHA human landing approval and the CLI reference's separately approved irreversible discard procedure.
