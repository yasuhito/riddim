# frozen_string_literal: true

require 'open3'
require_relative 'result'

module Riddim
  # Read-only local-only review against the project's local main. The recorded
  # worktree must still be the named branch in the same repository. Snapshot
  # both Git tips and ownership before producing output. The per-name lock
  # stays held through display so cooperating lifecycle writers cannot rebind
  # the record between its final check and the displayed diff.
  module ReviewDiff
    class Refused < Result::Error; end

    module_function

    def emit(name, stat_only: false)
      Result.task_record(name) # Unlocked preflight refuses missing/non-local records without creating a lock.
      Ownership.with_lock(name) { yield read_under_lock(name, stat_only: stat_only) }
    end

    def read_under_lock(name, stat_only:)
      snapshot, fields, bytes = Result.task_record(name)
      base, head = tips(name, fields)
      output = render(fields.fetch('worktree'), base, head, stat_only: stat_only)
      raise Refused, 'Git refs changed during review' unless tips(name, fields) == [base, head]

      verify_record!(name, snapshot, bytes)

      output
    rescue KeyError, SystemCallError, Worktree::Error => e
      raise Refused, "review diff unavailable: #{e.message}"
    end

    def render(worktree, base, head, stat_only:)
      changes = diff(worktree, base, head, '--stat')
      return "diff base: main\nno changes vs main\n" if changes.empty?
      return "diff base: main\n#{changes}" if stat_only

      "diff base: main\n#{changes}\n#{diff(worktree, base, head)}"
    end

    def verify_record!(name, snapshot, bytes)
      current = Ownership::Endpoint.read_bytes(Ownership.record_path(name))
      return if Ownership::Endpoint.unchanged?(name, snapshot) && current == bytes

      raise Refused, 'ownership changed during review'
    end

    def tips(name, fields)
      branch = "riddim/#{name}"
      raise Refused, 'worker branch is not bound to this name' unless fields.fetch('branch') == branch
      raise Refused, 'worker worktree is not the recorded linked checkout' unless Result.linked_checkout?(fields)

      worktree = fields.fetch('worktree')
      project = fields.fetch('project')
      verify_branch!(worktree, branch)
      head = Worktree.git_value(worktree, 'rev-parse', 'HEAD')
      named_head = Worktree.git_value(project, 'rev-parse', "refs/heads/#{branch}")
      raise Refused, 'worker branch no longer points to its checkout' unless named_head == head

      [Worktree.git_value(project, 'rev-parse', 'refs/heads/main'), head]
    end

    def verify_branch!(worktree, branch)
      checkout_branch, status = Worktree.git(worktree, 'symbolic-ref', '--quiet', '--short', 'HEAD')
      raise Refused, 'worker branch is not checked out' unless status.success? && checkout_branch.strip == branch
    end

    def diff(worktree, base, head, flag = nil)
      args = ['git', '--no-pager', '-C', worktree, 'diff', '--no-ext-diff', '--no-textconv']
      args << flag if flag
      stdout, stderr, status = Open3.capture3(
        Worktree::GIT_ENV.merge('GIT_OPTIONAL_LOCKS' => '0'), *args, "#{base}...#{head}", '--'
      )
      raise Refused, "git diff failed: #{stderr.strip}" unless status.success?
      raise Refused, "git diff produced diagnostics: #{stderr.strip}" unless stderr.empty?

      stdout
    end
  end
end
