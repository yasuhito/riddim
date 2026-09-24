# frozen_string_literal: true

require 'shellwords'

module Riddim
  # The private, generation-bound shell launch for a task brief.
  module TaskBrief
    module_function

    def publish_launch(brief, profile, spawn_gen, runtime_paths: nil)
      unless spawn_gen.is_a?(String) && spawn_gen.match?(/\As\d+\.\d+\.\d+\z/)
        raise Error, 'task launch requires a valid spawn generation'
      end

      path = "#{brief.path}.launch.#{spawn_gen}.sh"
      trace_file = "#{brief.path}.trace.#{spawn_gen}.jsonl" if ENV['RIDDIM_PI_TRACE'] == '1'
      publish_launch_file(path, brief, profile, trace_file, runtime_paths)
      path
    end

    def publish_launch_file(path, brief, profile, trace_file, runtime_paths)
      source = launch_source(brief, profile, trace_file: trace_file, runtime_paths: runtime_paths)
      Ownership.publish(path, source)
    rescue Ownership::Error => e
      raise Error, "task launch could not be published at #{path}: #{e.message}"
    end

    def launch_source(brief, profile, trace_file: nil, runtime_paths: nil)
      args = [pi_executable, '--model', profile.model, '--thinking', profile.effort]
      args.push('--extension', trace_extension) if trace_file
      command = args.map { |value| Shellwords.escape(value) }.join(' ')
      command = "RIDDIM_PI_TRACE_FILE=#{Shellwords.escape(trace_file)} #{command}" if trace_file
      # The marked task worker is a branch actor for role-partitioned actions
      # such as merge-local. This is an operational actor boundary the Pi
      # process and every shell tool it spawns inherit, not proof of the
      # human's approval.
      "export RIDDIM_ACTOR=branch\n" \
        "#{runtime_exports(runtime_paths)}" \
        "riddim_launch_brief=$(/usr/bin/cat -- #{Shellwords.escape(brief.path)}) || return 1\n" \
        "test -n \"$riddim_launch_brief\" || return 1\n" \
        "#{command} \"$riddim_launch_brief\"\n"
    end

    def runtime_exports(paths)
      return '' unless paths

      "export RIDDIM_CONFIG_DIR=#{Shellwords.escape(File.expand_path(paths.fetch(:config_dir)))}\n" \
        "export RIDDIM_STATE_DIR=#{Shellwords.escape(File.expand_path(paths.fetch(:state_dir)))}\n"
    end

    def trace_extension
      path = File.expand_path('../../../scripts/pi_stall_trace.ts', __dir__)
      raise Error, 'Pi trace extension is unavailable' unless File.file?(path)

      path
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
  end
end
