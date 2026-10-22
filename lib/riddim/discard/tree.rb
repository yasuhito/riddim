# frozen_string_literal: true

require 'find'
require_relative 'tree/sensitive'

module Riddim
  module Discard
    # A content inventory, not a backup. No recursive clean or forced removal.
    module Tree
      module_function

      def inspect!(directory)
        verify_unlocked!(directory)
        index = records!(directory, 'ls-files', '--stage', '-z')
        head = records!(directory, 'ls-tree', '-r', '-z', 'HEAD')
        verify_index!(directory, index, head)
        status = statuses!(directory)
        disk = disk!(directory)
        { files: inventory!(directory, disk, index + head, status), index: index }
      end

      def verify_unlocked!(directory)
        lock = Result.git_value(directory, 'rev-parse', '--git-path', 'index.lock')
        return unless File.exist?(lock) || File.symlink?(lock)

        raise Refused, 'Git index is locked; retaining assets'
      end

      def inventory!(directory, disk, entries, status)
        paths = (disk.keys + entries.map { |line| line.split("\t", 2).last }).uniq.sort
        paths.map do |path|
          verify_path!(path, File.join(directory, path))
          state = status.fetch(path, '  ')
          verify_sensitive!(directory, path, state, disk[path])
          { path: path, status: state, content: disk[path] }
        end
      end

      def records!(directory, *)
        output, result = Result.git(directory, *)
        raise Refused, 'cannot read discard file inventory; retaining assets' unless result.success?

        output.split("\0")
      end

      def verify_index!(directory, index, head)
        flags = records!(directory, 'ls-files', '-v', '-z')
        unsupported = unsupported_entries?(flags, index, head)
        visible = records!(directory, 'diff', '--cached', '--raw', '-z', '--ita-visible-in-index')
        invisible = records!(directory, 'diff', '--cached', '--raw', '-z', '--ita-invisible-in-index')
        raise Refused, 'unsupported hidden, conflicted, intent-to-add, symlink or submodule index; retaining assets' if
          unsupported || visible != invisible
      end

      def unsupported_entries?(flags, index, head)
        flags.any? { |line| line.match?(/\A[a-zS]/) } ||
          index.any? { |line| !line.match?(/\A100(?:644|755) [0-9a-f]+ 0\t/) } ||
          head.any? { |line| !line.match?(/\A100(?:644|755) blob /) }
      end

      def statuses!(directory)
        records!(directory, 'status', '--porcelain=v1', '-z', '--no-renames', '--untracked-files=all',
                 '--ignored', '--ignore-submodules=none').each_with_object({}) do |line, paths|
          raise Refused, 'ignored files are not discardable; retaining assets' if line.start_with?('!!')
          raise Refused, 'duplicate Git status paths are unsupported; retaining assets' if paths.key?(line[3..])

          paths[line[3..]] = line[0, 2]
        end
      end

      def disk!(directory)
        files = {}
        Find.find(directory) do |absolute|
          next if absolute == directory

          path = absolute.delete_prefix("#{directory}/")
          Find.prune if path == '.git'
          verify_path!(path, absolute)
          stat = File.lstat(absolute)
          files[path] = stat.directory? ? { type: 'directory' } : fingerprint!(absolute, stat)
        end
        files
      end

      def verify_path!(path, absolute)
        raise Refused, 'unsupported filename encoding; retaining assets' unless path.valid_encoding?

        parts = path.split('/')
        return unless path.match?(/[[:cntrl:]]/) || nested?(parts, absolute)

        raise Refused, 'unsupported paths or nested repositories are not discardable; retaining assets'
      end

      def nested?(parts, absolute)
        parts.include?('.git') || (File.directory?(absolute) &&
          %w[HEAD objects refs].all? { |name| File.exist?(File.join(absolute, name)) })
      end

      def fingerprint!(path, stat)
        raise Refused, 'only regular files and directories are discardable; retaining assets' unless
          stat.file? && stat.nlink == 1

        File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
          verify_stat!(stat, file.stat)
          digest = checksum(file)
          verify_stat!(stat, file.stat)
          verify_stat!(stat, File.lstat(path))
          { type: 'file', mode: stat.mode & 0o7777, sha256: digest }
        end
      end

      def checksum(file)
        digest = Digest::SHA256.new
        digest << file.read(65_536) until file.eof?
        digest.hexdigest
      end

      def verify_stat!(before, after)
        return if signature(before) == signature(after)

        raise Refused, 'file changed during inspection; inspect again'
      end

      def signature(stat)
        [stat.dev, stat.ino, stat.mode, stat.nlink, stat.size, stat.mtime, stat.ctime]
      end
    end
  end
end
