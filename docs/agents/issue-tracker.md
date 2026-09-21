# Issue tracker: GitHub

Issues and specs for this repo live as GitHub issues in `yasuhito/riddim`. Use the `gh` CLI for all operations.

## Conventions

- **Create an issue**: `gh issue create --repo yasuhito/riddim --title "..." --body "..."`. Use a heredoc for multi-line bodies.
- **Read an issue**: `gh issue view <number> --repo yasuhito/riddim --comments`, filtering comments by `jq` and also fetching labels.
- **List issues**: `gh issue list --repo yasuhito/riddim --state open --json number,title,body,labels,comments --jq '[.[] | {number, title, body, labels: [.labels[].name], comments: [.comments[].body]}]'` with appropriate `--label` and `--state` filters.
- **Comment on an issue**: `gh issue comment <number> --repo yasuhito/riddim --body "..."`
- **Apply or remove labels**: `gh issue edit <number> --repo yasuhito/riddim --add-label "..."` or `--remove-label "..."`
- **Close**: `gh issue close <number> --repo yasuhito/riddim --comment "..."`

Once the local repository has a GitHub remote, `gh` can infer the repository when run inside this clone. Keep `--repo yasuhito/riddim` when explicit routing is safer.

## Pull requests as a triage surface

**PRs as a request surface: no.** Set this to `yes` if this repo later treats external PRs as feature requests; `/triage` reads this flag.

When set to `yes`, PRs run through the same labels and states as issues, using the `gh pr` equivalents:

- **Read a PR**: `gh pr view <number> --comments` and `gh pr diff <number>` for the diff.
- **List external PRs for triage**: `gh pr list --state open --json number,title,body,labels,author,authorAssociation,comments`, then keep only `authorAssociation` of `CONTRIBUTOR`, `FIRST_TIME_CONTRIBUTOR`, or `NONE` and drop `OWNER`, `MEMBER`, and `COLLABORATOR`.
- **Comment, label, or close**: `gh pr comment`, `gh pr edit --add-label` or `--remove-label`, and `gh pr close`.

GitHub shares one number space across issues and PRs, so a bare `#42` may be either. Resolve it with `gh pr view 42` and fall back to `gh issue view 42`.

## When a skill says "publish to the issue tracker"

Create a GitHub issue in `yasuhito/riddim`.

## When a skill says "fetch the relevant ticket"

Run `gh issue view <number> --repo yasuhito/riddim --comments`.

## Wayfinding operations

Used by `/wayfinder`. The **map** is a single issue with **child** issues as tickets.

- **Map**: a single issue labelled `wayfinder:map`, holding the Notes, Decisions-so-far, and Fog body. Create it with `gh issue create --repo yasuhito/riddim --label wayfinder:map`.
- **Child ticket**: an issue linked to the map as a GitHub sub-issue using `gh api` on the sub-issues endpoint. Where sub-issues are unavailable, add the child to a task list in the map body and put `Part of #<map>` at the top of the child body. Labels are `wayfinder:<type>`, where type is `research`, `prototype`, `grilling`, or `task`. Once claimed, assign the ticket to the driving developer.
- **Blocking**: GitHub's native issue dependencies are the canonical, UI-visible representation. Add an edge with `gh api --method POST repos/yasuhito/riddim/issues/<child>/dependencies/blocked_by -F issue_id=<blocker-db-id>`, where `<blocker-db-id>` is the blocker's numeric database ID from `gh api repos/yasuhito/riddim/issues/<n> --jq .id`, not the issue number or `node_id`. GitHub reports open blockers in `issue_dependencies_summary.blocked_by`. Where dependencies are unavailable, fall back to a `Blocked by: #<n>, #<n>` line at the top of the child body. A ticket is unblocked when every blocker is closed.
- **Frontier query**: list the map's open children, drop any with an open blocker or an assignee, and take the first in map order.
- **Claim**: `gh issue edit <n> --repo yasuhito/riddim --add-assignee @me`. This is the session's first write.
- **Resolve**: comment with the answer, close the issue, then append a context pointer with its link to the map's Decisions-so-far.
