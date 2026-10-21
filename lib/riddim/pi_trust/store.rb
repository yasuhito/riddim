# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'securerandom'

module Riddim
  module PiTrust
    # Safe, Pi-compatible trust.json read-modify-write transaction.
    module Store
      LIMIT = 1_048_576

      module_function

      def record_true!(directory, worktree)
        prepare_directory(directory)
        path = File.join(directory, 'trust.json')
        with_lock(path) { update(path, worktree) }
      end

      def prepare_directory(path)
        FileUtils.mkdir_p(path, mode: 0o700)
        return if safe_directory?(File.lstat(path))

        raise PiTrust::Error, "Pi agent directory is not safely writable: #{path}"
      end

      def safe_directory?(stat)
        stat.directory? && !stat.symlink? && stat.uid == Process.euid && stat.mode.nobits?(0o022)
      end

      def update(path, worktree)
        trust = read(path)
        return if trust[worktree] == true

        trust[worktree] = true
        write(path, trust)
      end

      def with_lock(path)
        lock = "#{path}.lock"
        lock_stat = acquire_lock(lock)
        yield
      ensure
        release_lock(lock, lock_stat) if lock_stat
      end

      def acquire_lock(path)
        Dir.mkdir(path, 0o700)
        File.lstat(path)
      rescue Errno::EEXIST
        raise PiTrust::Error, "Pi trust store is locked at #{path}; refusing to launch"
      end

      def release_lock(path, lock_stat)
        current = File.lstat(path)
        unless current.directory? && current.dev == lock_stat.dev && current.ino == lock_stat.ino
          raise PiTrust::Error, "Pi trust lock changed during update: #{path}"
        end

        Dir.rmdir(path)
      end

      def read(path)
        stat = existing_file_stat(path)
        return {} unless stat

        verify_trust_file!(stat, path)
        parse_store(read_file(path, stat), path)
      end

      def existing_file_stat(path)
        File.lstat(path)
      rescue Errno::ENOENT
        nil
      end

      def read_file(path, expected_stat)
        File.open(path, File::RDONLY | File::NOFOLLOW | File::NONBLOCK) do |file|
          stat = file.stat
          verify_trust_file!(stat, path)
          unless stat.dev == expected_stat.dev && stat.ino == expected_stat.ino
            raise PiTrust::Error, "Pi trust store changed while being read: #{path}"
          end

          file.read(LIMIT + 1)
        end
      end

      def verify_trust_file!(stat, path)
        return if stat.file? && stat.uid == Process.euid && stat.mode.nobits?(0o022)

        raise PiTrust::Error, "Pi trust store is not a safe regular file: #{path}"
      end

      def parse_store(bytes, path)
        raise PiTrust::Error, "Pi trust store is too large: #{path}" if bytes.bytesize > LIMIT

        bytes.force_encoding(Encoding::UTF_8)
        raise PiTrust::Error, "Pi trust store is not valid UTF-8: #{path}" unless bytes.valid_encoding?

        data = JSON.parse(bytes.delete_prefix("\uFEFF"))
        raise PiTrust::Error, "Pi trust store has an unsupported format: #{path}" unless valid_store?(data)

        data
      rescue JSON::ParserError => e
        raise PiTrust::Error, "Pi trust store is invalid at #{path}: #{e.message}"
      end

      def valid_store?(data)
        data.is_a?(Hash) && data.values.all? { |value| value == true || value == false || value.nil? }
      end

      def write(path, trust)
        temporary = "#{path}.#{Process.pid}.#{SecureRandom.hex(8)}.tmp"
        write_temporary(temporary, "#{JSON.pretty_generate(trust.sort.to_h)}\n")
        File.rename(temporary, path)
        File.open(File.dirname(path), &:fsync)
      ensure
        discard_temporary(temporary)
      end

      def write_temporary(path, content)
        File.open(path, File::WRONLY | File::CREAT | File::EXCL | File::NOFOLLOW, 0o600) do |file|
          file.chmod(0o600)
          file.write(content)
          file.flush
          file.fsync
        end
      end

      def discard_temporary(path)
        File.unlink(path) if path && (File.exist?(path) || File.symlink?(path))
      end
    end
  end
end
