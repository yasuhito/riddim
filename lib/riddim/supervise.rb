# frozen_string_literal: true

require_relative 'herdr'
require_relative 'ownership'
require_relative 'runtime_paths'

module Riddim
  # Starts the Riddim supervisor Pi in the current terminal process.
  module Supervise
    class Error < StandardError; end

    ROLE_CONTRACT = File.join(RuntimePaths::ROOT, 'docs/supervisor.md')
    NOTIFICATIONS_EXTENSION = File.join(RuntimePaths::ROOT, '.pi/extensions/riddim-notifications.ts')
    CLI_DIRECTORY = File.join(RuntimePaths::ROOT, 'bin')

    module_function

    def run(profile)
      validate_resources!
      verify_herdr!
      executable = resolve_pi_executable
      state_dir = File.expand_path(Ownership.state_dir)
      prepare_state_dir!(state_dir)
      environment = launch_environment(state_dir).merge('RIDDIM_SUPERVISE' => RuntimePaths::ROOT)
      Kernel.exec(environment, executable, *launch_arguments(profile))
    rescue SystemCallError => e
      raise Error, "could not start Pi: #{e.message}"
    end

    def validate_resources!
      raise Error, 'supervisor role contract is missing: docs/supervisor.md' unless File.file?(ROLE_CONTRACT)
      return if File.file?(NOTIFICATIONS_EXTENSION)

      raise Error, 'notifications extension is missing: .pi/extensions/riddim-notifications.ts'
    end

    def prepare_state_dir!(state_dir)
      ENV['RIDDIM_STATE_DIR'] = state_dir
      Ownership.ensure_state_dir
    rescue Ownership::Error, SystemCallError => e
      raise Error, "could not prepare Riddim state directory #{state_dir}: #{e.message}"
    end

    def verify_herdr!
      Herdr.verify_running_client!
    rescue Herdr::CommandFailed => e
      raise Error, unreachable_herdr_message(herdr_failure_detail(e))
    rescue Herdr::IncompatibleClient => e
      raise Error, "Herdr is not ready in session #{Herdr.session}: #{e.message}"
    rescue SystemCallError => e
      raise Error, unreachable_herdr_message(e.message)
    end

    def herdr_failure_detail(failure)
      [failure.stderr.strip, failure.stdout.strip, failure.message].find { |line| !line.empty? }
    end

    def unreachable_herdr_message(detail)
      "Herdr is not reachable in session #{Herdr.session}: #{detail}"
    end

    def resolve_pi_executable
      ENV.fetch('PATH', '').split(File::PATH_SEPARATOR, -1).each do |directory|
        candidate = File.expand_path(File.join(directory.empty? ? Dir.pwd : directory, 'pi'))
        return candidate if File.file?(candidate) && File.executable?(candidate)
      end

      raise Error, 'pi executable not found on PATH'
    end

    # Native discovery is confined to this runtime's genuine primary checkout,
    # never a task worktree or a caller-selected working directory.
    def native_environment(cwd)
      return if ENV.fetch('RIDDIM_ACTOR', '') != ''
      return unless File.realpath(cwd) == File.realpath(RuntimePaths::ROOT)

      root = File.realpath(RuntimePaths::ROOT)
      return unless RuntimePaths.git_path(root, '--show-toplevel') == root
      return unless RuntimePaths.git_path(root, '--absolute-git-dir') ==
                    RuntimePaths.git_path(root, '--path-format=absolute', '--git-common-dir')

      validate_resources!
      state_dir = File.expand_path(Ownership.state_dir)
      prepare_state_dir!(state_dir)
      launch_environment(state_dir)
    end

    def launch_environment(state_dir)
      directories = ENV.fetch('PATH', '').split(File::PATH_SEPARATOR, -1)
      directories.delete(CLI_DIRECTORY)
      path = [CLI_DIRECTORY, *directories].join(File::PATH_SEPARATOR)
      { 'RIDDIM_STATE_DIR' => state_dir, 'PATH' => path }
    end

    def launch_arguments(profile)
      [
        '--model', profile.model,
        '--thinking', profile.effort,
        '-e', NOTIFICATIONS_EXTENSION,
        '--append-system-prompt', ROLE_CONTRACT
      ]
    end

    private_class_method :validate_resources!, :prepare_state_dir!, :verify_herdr!, :herdr_failure_detail,
                         :unreachable_herdr_message, :resolve_pi_executable,
                         :launch_environment, :launch_arguments
  end
end
