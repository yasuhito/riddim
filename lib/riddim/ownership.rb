# frozen_string_literal: true

module Riddim
  # The endpoint ownership record plane, shaped like Firstmate's
  # state/<id>.meta task records: one key=value record per started agent,
  # published after the exact Herdr endpoint exists and before the agent
  # starts, guarded by a per-name lock from duplicate preflight through
  # launch, and removable only while it still names the spawn that wrote it.
  # Riddim records only the fields it owns: there is no kind, worktree, or
  # project value, because Riddim manages none of those. This file owns where
  # the records live and how they are locked; ownership/record.rb owns the
  # record bytes themselves.
  module Ownership
    # The agent-name shape the CLI already enforces, re-checked here because
    # the name becomes part of a filesystem path.
    NAME_PATTERN = /\A[a-z][a-z0-9_-]{0,31}\z/

    # The repository's own state directory, used when RIDDIM_STATE_DIR is
    # unset or empty.
    DEFAULT_STATE_DIR = File.expand_path('../../state', __dir__)

    class Error < StandardError; end

    class InvalidValue < Error; end

    module_function

    # The state directory: a nonempty RIDDIM_STATE_DIR value, otherwise the
    # repository's own state/ directory.
    def state_dir
      value = ENV.fetch('RIDDIM_STATE_DIR', nil)
      return DEFAULT_STATE_DIR if value.nil? || value.empty?

      value
    end

    # The ownership record path for one agent name: state/<name>.meta.
    def record_path(name)
      File.join(state_dir, "#{validated_name(name)}.meta")
    end

    # The per-name lock path, shaped like Firstmate's fm_meta_lock_path.
    def lock_path(name)
      File.join(state_dir, ".meta-#{validated_name(name)}.lock")
    end

    def validated_name(name)
      raise InvalidValue, "invalid agent name #{name.inspect}" unless name.is_a?(String) && name.match?(NAME_PATTERN)

      name
    end

    # Creates the state directory with owner-only permissions when missing
    # and tightens an existing one to the same. A symlinked or non-directory
    # state path refuses instead of being followed.
    def ensure_state_dir
      dir = state_dir
      begin
        Dir.mkdir(dir, 0o700)
      rescue Errno::EEXIST
        verify_state_dir(dir)
      end
      File.chmod(0o700, dir)
      dir
    end

    def verify_state_dir(dir)
      raise Error, "the state directory is not a real directory: #{dir}" if File.symlink?(dir) || !File.directory?(dir)
    end

    # Runs the block holding the per-name exclusive flock. The lock is held
    # from duplicate preflight through launch result, so concurrent starts of
    # one name serialize and only the winner publishes its record. The lock
    # file is opened with O_NOFOLLOW - a symlinked lock path refuses instead
    # of being followed - and its owner-only permissions are forced after
    # creation, so a 0777 umask cannot leave the lock unusable.
    def with_lock(name)
      path = lock_path(name)
      File.open(path, File::RDWR | File::CREAT | File::NOFOLLOW, 0o600) do |file|
        file.chmod(0o600)
        file.flock(File::LOCK_EX)
        yield
      end
    rescue Errno::ELOOP
      raise Error, "the per-name lock is a symbolic link: #{path}"
    end
  end
end

require_relative 'ownership/record'
require_relative 'ownership/endpoint'
