## Agent skills

### Issue tracker

Issues are tracked in GitHub repository `yasuhito/riddim`. See `docs/agents/issue-tracker.md`.

### Triage labels

Use the five canonical triage labels. See `docs/agents/triage-labels.md`.

### Domain docs

This is a single-context repository. See `docs/agents/domain.md`.

### Development direction

Keep Riddim a compact Ruby implementation, using the standard library where practical: Pi-only workers supervised from one session. Add necessary features one at a time when actual use exposes a need. Keep unrelated PR, remote, quota and multi-harness machinery out of this scope. For Riddim's own development publication and merge, read `docs/repository-development.md`: the supervisor uses an explicitly authorized external PR workflow; workers remain local-only.

The sole approved exception to the Firstmate-only policy is Riddim-owned scheduled prompts to the supervisor: one-shot at a chosen datetime or fixed intervals, with saved schedules and existing watcher/Pi delivery, using only Ruby's standard library with no added runtime or external scheduler dependencies. This permits future implementation, not new landing, publication or destruction authority. Before proposing or implementing any other user-facing feature, find and read its working implementation in `/home/yasuhito/Work/oss/firstmate`. Propose only features that Firstmate already implements. State when Riddim implements a smaller subset, and preserve Firstmate's safety contract rather than substituting a Herdr-native behavior with different semantics.

### Roles and delivery

Project edits belong to Riddim workers in their assigned isolated worktrees; workers follow the project's coding and testing instructions there. The supervisor coordinates rather than editing the project. See `docs/supervisor.md` for external task-file/local-only launch, review, head-bound human approval, the Riddim-own-repository PR procedure and the CLI reference's separately approved irreversible discard procedure.
