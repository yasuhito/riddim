# frozen_string_literal: true

require 'digest'
require 'json'
require_relative 'actor'
require_relative 'teardown'

module Riddim
  # Explicit operator-approved discard, deliberately limited to clean trees.
  # Normal teardown's done and landed gates are not changed or bypassed there.
  module Discard
    class Refused < Ownership::Error; end

    module_function

    def run(name, approval: nil)
      refuse_worker! if approval
      Result.task_record(name)
      Ownership.with_lock(name) do
        task = Teardown::Task.new(name, *Result.task_record(name))
        scope = scope!(task)
        next JSON.generate(scope) unless approval

        discard!(task, scope, approval)
      end
    rescue KeyError, SystemCallError, Worktree::Error => e
      raise Refused, "discard incomplete; inspect retained assets: #{e.message}"
    end

    def refuse_worker!
      actor = ENV.fetch(Actor::VARIABLE, nil)
      return if actor.nil? || actor.empty?

      raise Refused, 'discard is operator-only; a marked worker or unknown actor cannot discard work'
    end

    def confirm!(scope, approval)
      return if approval == scope.values_at(:generation, :head, :snapshot)

      raise Refused, 'discard confirmation does not match current generation/head/snapshot; inspect again'
    end

    def scope!(task)
      Teardown.location!(task)
      _, head = Result.verified_tips(task.name, task.fields)
      clean_tree!(task.worktree)
      Teardown.verify_owner!(task)
      scope = describe(task, head)
      scope.merge(snapshot: Digest::SHA256.hexdigest(JSON.generate(scope) + task.bytes))
    end

    def describe(task, head)
      { name: task.name, generation: task.generation, project: task.project,
        worktree: task.worktree, branch: task.branch, head: head, files: 'clean-only',
        endpoint: task.snapshot.first.to_h }
    end

    def clean_tree!(directory)
      status = Worktree.git_value(directory, 'status', '--porcelain', '--untracked-files=all', '--ignored',
                                  '--ignore-submodules=none')
      flags = Worktree.git_value(directory, 'ls-files', '-v').lines
      return if status.empty? && flags.none? { |line| line.match?(/\A[a-zS]/) }

      raise Refused,
            'discard supports clean trees only; edits, untracked/ignored files or hidden index entries retained'
    end

    def discard!(task, scope, approval)
      confirm!(scope, approval)
      brief, archived = Teardown.brief_paths!(task)
      audit = File.join(Ownership.state_dir, "#{task.name}.#{task.generation}.discard.#{SecureRandom.hex(8)}.jsonl")
      Ownership.publish(audit, "#{JSON.generate(event: 'authorized-attempt', at: Time.now.to_i, scope: scope,
                                                record: task.bytes)}\n")
      perform!(task, scope, brief, archived, audit)
      "discarded #{task.name} at #{scope.fetch(:head)}; evidence kept at #{audit}"
    end

    def perform!(task, scope, brief, archived, audit)
      recheck!(task, scope)
      Teardown.close_exact_pane!(task)
      note!(audit, 'pane-gone')
      Teardown.scan_cwds!(task)
      remove_git_assets!(task, scope, audit)
      finish!(task, brief, archived)
      note!(audit, 'complete')
    rescue Ownership::Error, SystemCallError => e
      raise Refused, "discard incomplete; some assets may already be removed; inspect #{audit}: #{e.message}"
    end

    def finish!(task, brief, archived)
      Teardown.verify_owner!(task)
      Teardown.archive_brief!(brief, archived)
      Teardown.retire_record!(task)
    end

    def remove_git_assets!(task, scope, audit)
      recheck!(task, scope)
      Teardown.git!(task.project, 'worktree', 'remove', task.worktree) # Never --force.
      note!(audit, 'worktree-removed')
      remove_branch!(task, scope.fetch(:head))
      note!(audit, 'branch-removed')
    end

    def recheck!(task, scope)
      return if scope!(task) == scope

      raise Refused, 'discard source changed since confirmation; retaining remaining assets'
    end

    def remove_branch!(task, head)
      Teardown.verify_owner!(task)
      trees = Worktree.git_value(task.project, 'worktree', 'list', '--porcelain')
      raise Refused, 'branch is checked out elsewhere; retaining branch and record' if
        trees.lines.include?("branch refs/heads/#{task.branch}\n")

      # Compare-and-delete refuses a newly moved branch instead of deleting it.
      Teardown.git!(task.project, 'update-ref', '-d', "refs/heads/#{task.branch}", head)
    end

    def note!(audit, event)
      File.open(audit, File::WRONLY | File::APPEND | File::NOFOLLOW) do |file|
        Result.verify_private_file!(file)
        file.puts(JSON.generate(event: event, at: Time.now.to_i))
        file.flush
        file.fsync
      end
    end
  end
end
