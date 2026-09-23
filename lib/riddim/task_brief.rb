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

    def path(name)
      File.join(File.expand_path(Ownership.state_dir), "#{Ownership.validated_name(name)}#{PUBLISHED_SUFFIX}")
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

    # The script is sourced by an idle shell in the exact new pane. Keep the
    # multi-line argument out of Herdr's shell encoder, and never interpolate
    # human-supplied text into shell source. Both files are immutable, private,
    # outside the worktree, and published without replacement under the lock.
    def publish_launch(brief, profile, spawn_gen)
      unless spawn_gen.is_a?(String) && spawn_gen.match?(/\As\d+\.\d+\.\d+\z/)
        raise Error, 'task launch requires a valid spawn generation'
      end

      path = "#{brief.path}.launch.#{spawn_gen}.sh"
      Ownership.publish(path, launch_source(brief, profile))
      path
    rescue Ownership::Error => e
      raise Error, "task launch could not be published at #{path}: #{e.message}"
    end

    def launch_source(brief, profile)
      args = [pi_executable, '--model', profile.model, '--thinking', profile.effort]
      command = args.map { |value| Shellwords.escape(value) }.join(' ')
      "riddim_launch_brief=$(/usr/bin/cat -- #{Shellwords.escape(brief.path)}) || return 1\n" \
        "test -n \"$riddim_launch_brief\" || return 1\n" \
        "#{command} \"$riddim_launch_brief\"\n"
    end

    def pi_executable
      candidate = ENV.fetch('PATH').split(File::PATH_SEPARATOR).filter_map do |dir|
        next unless dir.start_with?('/')

        path = File.join(dir, 'pi')
        path if File.file?(path) && File.executable?(path)
      end.first
      raise Error, 'Pi executable is unavailable on PATH' unless candidate

      candidate
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
