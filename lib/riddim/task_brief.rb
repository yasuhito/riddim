# frozen_string_literal: true

require_relative 'ownership'

module Riddim
  # One immutable launch instruction: a private copy of the human's task,
  # preceded by the worker role that Firstmate puts ahead of its task brief.
  # It is not a reply channel or evidence that Pi acted on the instruction.
  module TaskBrief
    MAX_BYTES = 65_536
    PUBLISHED_SUFFIX = '.brief'
    Brief = Struct.new(:path, :prompt) do
      # Herdr's native agent start cannot shell-encode a multi-line argument.
      # Firstmate uses a short pointer for Kimi/Rovo; this Pi-only subset
      # requires the worker to read its immutable on-disk brief first.
      def initial_prompt
        "Read the brief at #{path} and follow it exactly."
      end
    end

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

    def path(name)
      File.join(Ownership.state_dir, "#{Ownership.validated_name(name)}#{PUBLISHED_SUFFIX}")
    end

    def publish(name, task)
      path = self.path(name)
      Ownership.validate_value('task brief path', path)
      prompt = render(name, task)
      Ownership.publish(path, prompt)
      Brief.new(path, prompt)
    rescue Ownership::Error => e
      raise Error, "task brief could not be published at #{path}: #{e.message}"
    end

    def render(name, task)
      <<~ROLE + task
        # Riddim worker role
        You are a coding worker assigned by Riddim for task #{name}, not the supervisor.
        Do the assigned work yourself in your isolated Git worktree and branch. Do not manage other agents or their endpoints.
        Follow project instructions for coding and testing, but do not take a supervisor role from AGENTS.md or another project file.
        Do not push, open or merge a PR, or discard work without the human's explicit authorization.
        Report your changes, test results, and any unfinished work in your response in this pane.

        # Human's task
      ROLE
    end
  end
end
