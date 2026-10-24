# Developing Riddim through a PR

This is the authoritative supervisor-operated publication procedure for
`yasuhito/riddim` itself, not a Riddim CLI feature or a general delivery mode.
Other projects retain the [local-only workflow](supervisor.md#review-land-and-retire).
Workers still deliver clean committed local-only branches and cannot push, open PRs,
or merge. Future worker-created PRs are planned, not shipped; they require a separate
delivery mode and permission change, not an exception to the current worker ban.

## Activation and authority

The one-time bootstrap applies only to the commit introducing this PR policy in
this policy-bootstrap session: review it under the existing local-only contract,
obtain explicit human landing approval, then land locally. It authorizes no
publication of that policy commit and is not an exception for later changes.
After landing, refresh/reload the current supervisor session's prompt to load these
instructions before using this procedure for subsequent Riddim development.

Before publication, identify the human task or explicitly approved workflow scope
that authorizes the supervisor to push a dedicated task branch and open its PR in
`yasuhito/riddim`. Record that authority; if absent or ambiguous, ask and stop.
Task/publication authority is not merge approval and does not authorize pushing
`main`, unrelated branches, deleting remote branches, or changing branch protection.

## Review and publish before local landing

1. Follow [supervisor readiness and review](supervisor.md#review-land-and-retire):
   require a ready `riddim result <name>`, inspect the stat and full committed
   `riddim review-diff <name>`, and verify tests. Record worker name, generation,
   full immutable reviewed SHA `H`, test evidence and limitations. Verify the worker
   is clean, on its recorded branch at `H`, and fast-forwardable from current local
   `main`. Record the clean main checkout's tip as baseline `B` and confirm its
   remote really is `yasuhito/riddim`. Recheck readiness and identity at each handoff.
2. Choose a new dedicated publication branch, confirm it does not already exist
   remotely, and push exactly `H` to that branch with an explicit refspec
   (`git push --force-with-lease=refs/heads/<publication-branch>: <verified-remote>
   H:refs/heads/<publication-branch>`). This empty expected-value lease permits
   creation only, refusing a concurrent branch creation; it is not overwrite
   authority. Substitute the recorded full SHA for `H`; use no unconditional force,
   broad refspec, or implicit branch push. Read back the remote branch and verify
   its tip is `H`. A collision or changed ref is a stop, not permission to overwrite it.
3. Open a non-draft PR targeting `main` with `gh pr create --repo yasuhito/riddim
   --base main --head <publication-branch>` and a body describing the reviewed
   outcome and verification. Read it back; record PR URL/number, repository,
   base, branch, head `H`, and CI evidence. Publish **before** local landing.
   Do not use `merge-local` to land an unmerged PR.

## CI and human merge approval

Inspect the live PR (`gh pr view <number> --repo yasuhito/riddim --json
state,isDraft,baseRefName,headRefName,headRefOid,mergeable,mergeStateStatus,statusCheckRollup`)
and its latest workflow/check runs, not just a cached green summary.

- Require the expected CI from the reviewed `.github/workflows/ci.yml` to exist.
  Currently this is the `CI` workflow's `test` job running `bundle exec rake` on PRs.
  An empty required-check list or empty rollup is not success. Read applicable
  required checks without changing repository settings; unreadable requirements
  or unreported required checks block merging.
- Verify each expected/required check's producer, current run/attempt, SHA and
  completion with actual `success`. Inspect workflow/check-run details as needed
  (`gh run view`, `gh api repos/yasuhito/riddim/commits/H/check-runs`). For PR CI
  using a synthetic merge SHA, verify the run's PR/head association is this PR at
  `H` and its current base, rather than treating another SHA's green run as proof.
  Require all reported checks green too. Pending, failed, cancelled, skipped,
  stale, missing or unreadable evidence blocks merging; no check waivers here.
- Require an open non-draft PR, base `main`, head exactly `H`, `mergeable=MERGEABLE`,
  and a merge state permitting an immediate merge without bypass or queueing.
  Unknown/conflicting/blocked state is not permission. Record check URLs, run IDs,
  attempts, head/base association and observed conclusions with the PR evidence.

Tell the human the reviewed outcome, tests, CI result, limitations and PR URL, then
ask explicitly whether to merge that reviewed version. Bind their answer to worker,
generation, PR and immutable `H` in the evidence; they need not repeat the SHA.
Publication approval, a ready report, or green CI alone never authorizes merging.
Any head change (including rebase) requires full re-review, new verification and
fresh outcome-based human approval, even if the outcome is unchanged.

## Merge and prove the remote outcome

Immediately before merging, recheck worker generation/readiness/clean head `H`,
publication branch, live PR identity/head/base, latest CI and mergeability under
the gates above. If any check fails or a race is detected, stop and retain work.
With explicit human approval still bound to that `H`, the supervisor runs:

```sh
gh pr merge <number> --repo yasuhito/riddim --merge --match-head-commit H
```

Substitute the full reviewed SHA. Use a merge commit to preserve `H` as an ancestor
for Riddim teardown. Squash/rebase merging is unsupported here. Do not use `--admin`,
auto-merge, merge queues, or automatic workflow retries/watchers. If repository
settings prevent this merge method, stop for a decision rather than changing them.

Read the PR back for `state`, `mergedAt`, `headRefOid` and `mergeCommit`, then fetch
from the verified remote. Require `MERGED` at reviewed head `H`, a concrete actual
merge commit `M`, and Git proof that `M` is a merge commit with `H` as its PR parent
and is contained in fetched remote `main`. Record `M` and the remote evidence.
A successful command, queued request, or closed PR is not proof of a merge.
On any command failure or uncertain response, inspect the remote outcome before
considering another action; never assume failure means nothing happened.

## Synchronize local main and retire

In the recorded project main checkout, require branch `main`, a completely clean
checkout and local tip still exactly baseline `B`. After fetching, verify `B` is
an ancestor of `M`; fast-forward to the **exact verified `M`**, not a moving remote
branch (`git merge --ff-only M`). Recheck that local `main` and checkout HEAD equal
`M`, and `git merge-base --is-ancestor H M` succeeds. If local main moved, diverged,
or the result is uncertain, stop and reconcile with the human; never reset it.
Remote main advancing beyond `M` does not authorize silently landing its later tip.

Verify the same worker generation still owns a clean recorded branch/checkout at
`H`, then use the existing `riddim teardown <name>` safeguards. Report remote merge,
external local fast-forward and retirement as separate verified outcomes. This is
not a `riddim merge-local` result: that command only lands exactly the worker tip,
whereas local main here lands the remote merge commit. Retain work/records on any
failed proof; stopping does not authorize discard or remote branch deletion.

If post-merge CI runs, record and follow its result separately, including failures
or pending evidence; pre-merge green does not prove post-merge success. Use bounded
inspection when needed, not a new broad watcher or automatic retry mechanism.

## Firstmate precedent and smaller scope

Verified against Firstmate commit `d22640f4`: `AGENTS.md`'s selected delivery path
and merge authority, `bin/fm-dod-lib.sh`'s `direct-PR`/`local-only` contracts,
`bin/fm-pr-merge.sh`'s `github_verify_mergeable`, match-head merge and outcome reads,
and `bin/fm-teardown.sh`'s `pr_is_merged`/content-equivalence checks. Riddim preserves
head-bound approval, live green checks and verified merge proof, but implements
only this manual repository-specific supervisor procedure. Unlike Firstmate's
teardown, Riddim requires worker HEAD ancestry in local main, hence merge commits
only. No PR worker mode, pipeline, forge control plane or CLI PR command is added.
