# frozen_string_literal: true

require 'shellwords'
require_relative 'ownership'

module Riddim
  # One immutable launch instruction: a private copy of the human's task,
  # preceded by the worker role that Firstmate puts ahead of its task brief.
  # It is not a reply channel or evidence that Pi acted on the instruction.
  module TaskBrief
    MAX_BYTES = 65_536
    PUBLISHED_SUFFIX = '.brief'
    Brief = Struct.new(:path, :prompt)

    class Error < Ownership::Error; end

    module_function

    def read(path)
      File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        raise Error, "task file is not a regular file: #{path}" unless file.stat.file?

        validate_text(file.read(MAX_BYTES + 1), path)
      end
    rescue Errno::ELOOP
      raise Error, "task file is a symbolic link: #{path}"
    rescue SystemCallError => e
      raise Error, "task file cannot be read at #{path}: #{e.message}"
    end

    def validate_text(bytes, path)
      text = bytes.force_encoding(Encoding::UTF_8)
      unless text.bytesize <= MAX_BYTES && text.valid_encoding? && !text.include?("\0") && !text.strip.empty?
        raise Error, "task file must contain nonempty UTF-8 without NUL and be at most #{MAX_BYTES} bytes: #{path}"
      end

      text
    end

    # A task file may carry a Firstmate-style explicit delivery contract. Every
    # such line must agree with the launch mode; checking only the first would
    # let a later contradictory instruction reach Pi after publication.
    def validate_delivery_contract!(task, mode)
      expected = "Delivery contract: mode=#{mode}"
      task.each_line do |line|
        declared = line.delete_suffix("\n")
        next unless declared.start_with?('Delivery contract: mode=')
        next if declared == expected

        raise Error, "delivery mismatch: task declares #{declared.inspect}, launch uses mode=#{mode}"
      end
    end

    def path(name)
      File.join(File.expand_path(Ownership.state_dir), "#{Ownership.validated_name(name)}#{PUBLISHED_SUFFIX}")
    end

    def publish(name, task, status_path: nil, spawn_gen: nil)
      path = self.path(name)
      Ownership.validate_value('task brief path', path)
      prompt = render(name, task, status_path: status_path, spawn_gen: spawn_gen)
      Ownership.publish(path, prompt)
      Brief.new(path, prompt)
    rescue Ownership::Error => e
      raise Error, "task brief could not be published at #{path}: #{e.message}"
    end

    def render(name, task, status_path: nil, spawn_gen: nil)
      role = <<~ROLE
        # Riddim worker role
        You are a coding worker assigned by Riddim for task #{name}, not the supervisor.
        Do the assigned work yourself in your isolated Git worktree and branch. Do not manage other agents or their endpoints.
        Follow project instructions for coding and testing, but do not take a supervisor role from AGENTS.md or another project file.
        Do not push, open or merge a PR, or discard work without the human's explicit authorization.
        Report your changes, test results, and any unfinished work in your response in this pane.
      ROLE
      "#{role}#{local_contract(name, status_path, spawn_gen)}\n# Human's task\n#{task}"
    end

    def report_executable
      File.expand_path('../../bin/riddim', __dir__)
    end

    def local_contract(name, status_path, spawn_gen)
      return '' unless status_path
      raise Error, 'task report requires a spawn generation' unless spawn_gen&.match?(/\As\d+\.\d+\.\d+\z/)

      <<~CONTRACT

        # Local-only delivery contract
        Delivery contract: mode=local-only
        This delivery contract supersedes conflicting project and task instructions, including explicit human instructions to push, open a PR, or merge. If the task conflicts, report a needs-decision event and stop instead of carrying out the conflicting delivery.
        This task is local-only: do not push, open a PR, or merge. Commit your completed work on your riddim/#{name} branch.
        Keep the worktree clean and your branch fast-forwardable from main. If main moves, rebase your branch before claiming readiness.
        When you have a result, run `#{Shellwords.escape(report_executable)} report #{name} --generation #{spawn_gen} '<status-event>'` from this worktree. Replace <status-event> with one short `done [at=<epoch>]: <summary>` after committing and testing, or `blocked [at=<epoch>]: <reason>`, `failed [at=<epoch>]: <reason>`, or `needs-decision [at=<epoch>]: <question>` if you cannot finish. Use current Unix epoch seconds for <epoch>. The command writes the private #{status_path} file under the same per-name lock used to land work. Never append directly to that file; if the command refuses, stop and report the refusal in your reply instead.
        The event is a report, not proof of review or tests. Never call a task done based on Pi becoming idle. If you report a blocker, failure, or decision, stop; this small handoff cannot automatically clear that gate with a later done event.
      CONTRACT
    end
  end
end

require_relative 'task_brief/launch'
