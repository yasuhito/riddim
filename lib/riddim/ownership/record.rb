# frozen_string_literal: true

require 'securerandom'

module Riddim
  # The record-byte surface of Riddim::Ownership, kept apart from the state
  # directory and lock surface in ownership.rb: how a record's exact bytes are
  # rendered, read back, published atomically, and removed only while they
  # still name the spawn that wrote them.
  module Ownership
    # The record fields, in Firstmate's relative order. window= and the four
    # herdr_ fields carry Herdr's exact response-derived endpoint identities.
    FIELD_ORDER = %w[
      window endpoint_task_id harness model effort spawn_gen backend
      herdr_session herdr_workspace_id herdr_tab_id herdr_pane_id
    ].freeze
    WORKTREE_FIELDS = %w[project worktree branch task_mode base_head status_protocol].freeze

    class InvalidRecord < Error; end

    module_function

    # Whether any endpoint record exists at <path>, including a malformed or
    # unreadable one: existence alone refuses a duplicate start.
    def record_present?(path) = File.exist?(path) || File.symlink?(path)

    # A fresh Firstmate-shaped incarnation token: s<epoch>.<pid>.<random>.
    # Every start mints a new one, so durable consumers can tell a replacement
    # worker that reuses the same name from the worker it replaced.
    def fresh_spawn_gen
      "s#{Time.now.to_i}.#{Process.pid}.#{SecureRandom.random_number(32_768)}"
    end

    # Renders one record's exact bytes: Firstmate-style key=value lines in
    # Firstmate's field order. Every value must be one nonempty line, so no
    # value can inject or forge another record line.
    def serialize(fields)
      keys = FIELD_ORDER + WORKTREE_FIELDS.select { |key| fields.key?(key) }
      "#{keys.map { |key| serialize_field(key, fields) }.join("\n")}\n"
    end

    def serialize_field(key, fields)
      value = fields.fetch(key) { raise InvalidValue, "missing record field #{key.inspect}" }
      "#{key}=#{validate_value(key, value)}"
    end

    def validate_value(key, value)
      return value if value.is_a?(String) && !value.empty? && !value.match?(/[[:cntrl:]]/)

      raise InvalidValue, "record field #{key.inspect} must be one nonempty line: got #{value.inspect}"
    end

    # Parses record bytes back into fields. Required ownership keys must be
    # present exactly once. Other well-formed keys are retained so later
    # Firstmate-style metadata extensions do not invalidate older readers.
    def parse(bytes)
      text = record_text(bytes)
      raise InvalidRecord, 'an endpoint record must not be empty' if text.empty?
      raise InvalidRecord, 'an endpoint record must end with one newline' unless text.end_with?("\n")

      fields = {}
      text.split("\n").each { |line| add_field(fields, line) }
      missing = FIELD_ORDER - fields.keys
      raise InvalidRecord, "the endpoint record is missing #{missing.join(', ')}" unless missing.empty?

      fields
    end

    def record_text(bytes)
      text = bytes.to_s.dup.force_encoding(Encoding::UTF_8)
      raise InvalidRecord, 'an endpoint record must use valid UTF-8' unless text.valid_encoding?

      text
    end

    def add_field(fields, line)
      key, _, value = line.partition('=')
      raise InvalidRecord, "unreadable endpoint record line #{line.inspect}" unless readable_field?(key, value)
      raise InvalidRecord, "duplicate endpoint record field #{key.inspect}" if fields.key?(key)

      fields[key] = value
    end

    def readable_field?(key, value)
      key.match?(/\A[a-z][a-z0-9_]*\z/) && !value.empty? && !value.match?(/[[:cntrl:]]/)
    end

    # Publishes the complete record bytes at <path>: the bytes are fully
    # written, flushed, and fsynced to a 0600 temp file in the same directory,
    # then hard-linked into place - an atomic no-replace operation that fails
    # with EEXIST instead of replacing, so an existing record is never
    # overwritten and a reader never sees a partial record. The temp file is
    # unlinked once the record is in place. The caller must hold the per-name
    # lock, which serializes cooperating writers.
    def publish(path, bytes)
      temp = temp_path(path)
      begin
        stage_record(temp, bytes)
        link_no_replace(temp, path)
      ensure
        discard_temp(temp)
      end
    rescue SystemCallError => e
      raise Error, "the endpoint record could not be published at #{path}: #{e.message}"
    end

    # Writes the complete record bytes to the staging file in one pass.
    # Owner-only permissions are forced after creation, so a 0777 umask cannot
    # leave the staged bytes closed to their owner, and the bytes are flushed
    # and fsynced before they are linked into place.
    def stage_record(temp, bytes)
      File.open(temp, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(bytes)
        file.chmod(0o600)
        file.flush
        file.fsync
      end
    end

    # Hard-links the staged bytes into place. link(2) never replaces an
    # existing destination: a record that appears between staging and
    # publication refuses the start instead of being overwritten, even when
    # the writer does not hold the per-name lock.
    def link_no_replace(temp, path)
      File.link(temp, path)
    rescue Errno::EEXIST
      raise Error, "an endpoint record already exists at #{path}"
    end

    # The staging path of one publication, in the record's own directory and
    # named like Firstmate's spawn temp file.
    def temp_path(path)
      File.join(File.dirname(path), ".#{File.basename(path)}.spawn.#{Process.pid}")
    end

    def discard_temp(temp)
      File.delete(temp)
    rescue StandardError
      nil
    end

    # Removes this spawn's record while the caller holds its per-name lock.
    # That lock is the concurrency contract, matching Firstmate: every Riddim
    # lifecycle writer for the name must cooperate with it. Open never follows
    # a symlink, the bytes must parse and name this spawn, and an immediate
    # pre-unlink lstat must still identify the opened regular file. The lstat
    # is defense in depth, not an atomic compare-and-delete: a same-user process
    # that ignores the lock is outside this coordination contract because Ruby
    # ultimately unlinks by pathname. Returns true when the record was absent
    # at the initial check or this verified pathname unlink completed; false
    # when the record was retained.
    def remove_if_unchanged_under_lock(path, spawn_gen)
      return true unless record_present?(path)

      File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
        return false unless removable_record?(path, spawn_gen, file)

        File.delete(path)
      end
      true
    rescue SystemCallError, InvalidRecord
      false
    end

    def removable_record?(path, spawn_gen, file)
      before = file.stat
      before.file? &&
        parse(file.read)['spawn_gen'] == spawn_gen &&
        same_regular_file?(before, File.lstat(path))
    end

    # At the final pre-unlink check, the pathname must still identify the
    # opened regular file. The caller's per-name lock keeps cooperating writers
    # from changing it after this check.
    def same_regular_file?(before, after)
      before.dev == after.dev && before.ino == after.ino && after.file?
    end
  end
end
