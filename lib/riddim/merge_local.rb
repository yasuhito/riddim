# frozen_string_literal: true

require_relative 'actor'
require_relative 'result'
require_relative 'worktree'

module Riddim
  # The operator's local-only landing action: one strict fast-forward of the
  # project checkout's local main to the exact reviewed worker branch tip.
  # Firstmate's fm-merge-local.sh, reduced to what Riddim owns: no PR, pool,
  # remote fetch, backlog, captain-hold lifecycle, or automatic approval; a
  # ready result is not approval, and this command never claims one happened.
  module MergeLocal
    # A full object id in either Git hash length Riddim accepts for base heads.
    REVIEWED_SHA = /\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z/

    class Refused < Ownership::Error; end

    module_function

    # One locked local merge. The role partition precedes reading the task
    # record, so the wrong actor is refused for its role whatever it says.
    def run(name, reviewed)
      Actor.refuse_landing!
      verify_reviewed_shape!(reviewed)
      Result.task_record(name) # Unlocked preflight refuses missing/non-local records without creating a lock.
      Ownership.with_lock(name) { merge_locked(name, reviewed) }
    end

    def verify_reviewed_shape!(reviewed)
      return if reviewed.is_a?(String) && reviewed.match?(REVIEWED_SHA)

      raise Refused, 'the reviewed head must be a full commit id'
    end

    def merge_locked(name, reviewed)
      snapshot, fields, bytes = Result.task_record(name)
      verify_done_report!(name, snapshot.last)
      main, head = Result.verified_tips(name, fields)
      verify_landing!(name, fields, main, head)
      verify_owner!(name, snapshot, bytes, 'before the merge; refusing')
      verify_reviewed_head!(reviewed, head)
      land(name, fields, reviewed, snapshot, bytes)
    rescue KeyError, SystemCallError, Worktree::Error => e
      raise Refused, "local merge unavailable: #{e.message}"
    end

    # Every gate that must hold before the fast-forward may move main.
    def verify_landing!(name, fields, main, head)
      verify_protocol!(fields)
      project = fields.fetch('project')
      verify_invocation_checkout!(project)
      unless Result.committed_branch?(name, fields)
        raise Refused, 'worker branch is not a committed ready handoff; refusing the merge'
      end

      verify_clean!(project, fields.fetch('worktree'))
      verify_main_checkout!(project, main)
      verify_fast_forward!(project, "riddim/#{name}", main, head)
    end

    def verify_reviewed_head!(reviewed, head)
      return if reviewed == head

      raise Refused,
            "the reviewed head does not match the worker branch tip #{head}; re-review and approve the current tip"
    end

    # Holds the lock through Git's fast-forward, then verifies the result:
    # the ownership record unchanged and local main at the approved tip.
    def land(name, fields, reviewed, snapshot, bytes)
      project = fields.fetch('project')
      previous = Worktree.git_value(project, 'rev-parse', 'refs/heads/main')
      verify_done_report!(name, snapshot.last) # A decision can arrive during the Git preflight.
      merge!(project, reviewed, previous)
      landed = Worktree.git_value(project, 'rev-parse', 'refs/heads/main')
      verify_owner!(name, snapshot, bytes, "during the merge; local main may have moved to #{landed}")
      verify_post_merge_report!(name, snapshot.last, landed)
      verify_landed_tip!(landed, reviewed)
      "merged riddim/#{name} into local main (#{previous} -> #{landed}) in #{project}"
    end

    def verify_landed_tip!(landed, reviewed)
      return if landed == reviewed

      raise Refused, "the fast-forward did not land the reviewed tip; local main is at #{landed}"
    end

    # The command must run from the recorded project's main checkout, so
    # another checkout cannot land the work.
    def verify_invocation_checkout!(project)
      refusal = "merge-local must run from the recorded project's main checkout: #{project}"
      current = File.realpath(Dir.pwd)
      return if current == project

      raise Refused, refusal
    rescue Errno::ENOENT, Errno::EACCES
      raise Refused, refusal
    end

    def verify_clean!(project, worktree)
      raise Refused, 'project has uncommitted work; refusing the merge' unless clean?(project)
      raise Refused, 'worker has uncommitted work; refusing the merge' unless clean?(worktree)
    end

    def clean?(directory)
      Worktree.git_value(directory, 'status', '--porcelain', '--untracked-files=all').empty?
    end

    # The checkout must be on local main at its tip, so the fast-forward
    # lands predictably (Firstmate's own checkout rules).
    def verify_main_checkout!(project, main)
      branch = Worktree.git_value(project, 'symbolic-ref', '--quiet', '--short', 'HEAD')
      raise Refused, 'project checkout is not on main; refusing the merge' unless branch == 'main'
      raise Refused, 'project checkout is not at local main; refusing the merge' unless
        Worktree.git_value(project, 'rev-parse', 'HEAD') == main
    end

    # Clean fast-forward only: local main must be a proper ancestor of the
    # branch tip; an already-contained branch is nothing to land and a
    # diverged branch refuses with Firstmate's rebase guidance.
    def verify_fast_forward!(project, branch, main, head)
      diverged = "#{branch} is not a fast-forward of local main (it has diverged); " \
                 'have the worker rebase onto main, then re-review and approve the new tip'
      if Worktree.git(project, 'merge-base', '--is-ancestor', head, main).last.success?
        raise Refused, 'worker branch tip is already in local main; nothing to land'
      end
      raise Refused, diverged unless Worktree.git(project, 'merge-base', '--is-ancestor', main, head).last.success?
    end

    # The record read at the start must still be current. Cooperating
    # writers cannot change it (the lock is held); a writer ignoring the
    # lock is caught, before and after the merge, not attributed to this spawn.
    def verify_owner!(name, snapshot, bytes, detail)
      current = Ownership::Endpoint.read_bytes(Ownership.record_path(name))
      return if Ownership::Endpoint.unchanged?(name, snapshot) && current == bytes

      raise Refused, "ownership changed #{detail}"
    end

    # Fast-forwards to the exact approved commit id, not the branch name,
    # so a branch that moves during the merge window cannot land an
    # unapproved tip. Git re-checks the fast-forward itself.
    def merge!(project, reviewed, previous)
      output, status = Worktree.git(project, 'merge', '--ff-only', reviewed)
      return if status.success?

      landed = Worktree.git_value(project, 'rev-parse', 'refs/heads/main')
      detail = landed == previous ? 'local main is unchanged' : "local main is at #{landed}"
      raise Refused, "git merge --ff-only failed (#{detail}): #{output.strip}"
    end
  end
end

require_relative 'merge_local/status_gate'
