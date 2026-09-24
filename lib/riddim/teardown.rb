# frozen_string_literal: true

require 'open3'
require_relative 'herdr'
require_relative 'result'
require_relative 'task_brief'

module Riddim
  # Retire one landed local-only worker. No force, remote, pool, backlog, or
  # workspace cleanup: uncertain operations retain the record and unremoved assets.
  module Teardown
    class Refused < Ownership::Error; end

    Task = Data.define(:name, :snapshot, :fields, :bytes) do
      def project = fields.fetch('project')
      def worktree = fields.fetch('worktree')
      def branch = fields.fetch('branch')
      def generation = snapshot.last
    end

    module_function

    def run(name)
      Result.task_record(name) # Refuse missing/non-local records without creating a lock.
      Ownership.with_lock(name) { retire_locked(name) }
    end

    def retire_locked(name)
      task = Task.new(name, *Result.task_record(name))
      head, brief, archived = prepare!(task)
      close_exact_pane!(task)
      scan_cwds!(task)
      finish!(task, head, brief, archived)
      "retired #{name} (pane gone; worktree and branch removed; brief archived; trace and status kept)"
    rescue KeyError, SystemCallError, Worktree::Error => e
      raise Refused, "teardown incomplete; inspect retained assets: #{e.message}"
    end

    def prepare!(task)
      verify_preflight!(task)
      head = landed_head!(task)
      brief, archived = brief_paths!(task)
      verify_owner!(task)
      [head, brief, archived]
    end

    def finish!(task, head, brief, archived)
      verify_owner!(task)
      verify_preflight!(task) # The worker could append a new gate before its pane closed.
      remove_git_assets!(task, head)
      verify_owner!(task)
      archive_brief!(brief, archived)
      retire_record!(task)
    end

    def verify_preflight!(task)
      location!(task)
      status = Result.read_status(Result.path(task.name, task.generation))
      return if status.last&.start_with?('done ') && !status.open_gate

      raise Refused, 'worker has no ungated done report; retaining assets'
    end

    def verify_owner!(task)
      return if Ownership::Endpoint.unchanged?(task.name, task.snapshot) &&
                Ownership::Endpoint.read_bytes(Ownership.record_path(task.name)) == task.bytes

      raise Refused, 'ownership changed during teardown; retaining assets'
    end

    def retire_record!(task)
      return if Ownership.remove_if_unchanged_under_lock(Ownership.record_path(task.name), task.generation)

      raise Refused, 'ownership record could not be removed; inspect before retrying'
    end
  end
end

require_relative 'teardown/git_gate'
require_relative 'teardown/brief'
require_relative 'teardown/endpoint_gate'
