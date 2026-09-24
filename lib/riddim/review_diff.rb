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
      base, head = Result.verified_tips(name, fields)
      output = render(fields.fetch('worktree'), base, head, stat_only: stat_only)
      raise Refused, 'Git refs changed during review' unless Result.verified_tips(name, fields) == [base, head]

      verify_record!(name, snapshot, bytes)

      output
    rescue KeyError, SystemCallError, Worktree::Error => e
      raise Refused, "review diff unavailable: #{e.message}"
    end

    def render(worktree, base, head, stat_only:)
      header = "diff base: main\nhead: #{head}\n"
      changes = diff(worktree, base, head, '--stat')
      return "#{header}no changes vs main\n" if changes.empty?
      return "#{header}#{changes}" if stat_only

      "#{header}#{changes}\n#{diff(worktree, base, head)}"
    end

    def verify_record!(name, snapshot, bytes)
      current = Ownership::Endpoint.read_bytes(Ownership.record_path(name))
      return if Ownership::Endpoint.unchanged?(name, snapshot) && current == bytes

      raise Refused, 'ownership changed during review'
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
