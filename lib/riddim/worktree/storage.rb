# frozen_string_literal: true

module Riddim
  # Central, fresh destinations, without pool ownership or recursive cleanup.
  module Worktree
    module_function

    def repository_directory(project)
      common = File.realpath(git_value(project, 'rev-parse', '--path-format=absolute', '--git-common-dir'))
      identity = Digest::SHA256.hexdigest(common)
      label = File.basename(RuntimePaths.primary_checkout(project)).gsub(/[^a-zA-Z0-9_.-]/, '_')[0, 64]
      "#{label}-#{identity}"
    end

    # Reserve the destination, never adopting an existing directory. Rollback
    # only removes empty directories this attempt created with the same inode.
    # Git assets or a hook's files are always retained for inspection.
    def allocate!(project, path, branch, base_head)
      owned = []
      begin
        prepare_parents!(File.dirname(path), owned, File.dirname(path, 2))
        Dir.mkdir(path, 0o700)
        owned << [path, File.lstat(path)]
        add_worktree!(project, path, branch, base_head)
      rescue Error, SystemCallError => e
        remove_empty_owned(owned)
        raise Error, "#{e.message}; inspect before retrying"
      end
    end

    def prepare_parents!(path, owned, storage)
      parent = File.dirname(path)
      prepare_parents!(parent, owned, storage) unless parent == path
      stat = find_or_create_parent(path, owned)
      # lstat never treats a symlink as a directory.
      raise Error, "unsafe worktree parent: #{path}" unless stat.directory?
      return unless path == storage || path.start_with?("#{storage}/")
      return if stat.uid == Process.uid && stat.mode.nobits?(0o022)

      raise Error, "worktree storage must be owned and not writable by others: #{path}"
    end

    def find_or_create_parent(path, owned)
      File.lstat(path)
    rescue Errno::ENOENT
      begin
        Dir.mkdir(path, 0o700)
        owned << [path, File.lstat(path)]
      rescue Errno::EEXIST
        # Another cooperating start may have created a shared parent.
      end
      File.lstat(path)
    end

    def remove_empty_owned(owned)
      owned.reverse_each do |path, before|
        after = File.lstat(path)
        next unless after.directory? && before.dev == after.dev && before.ino == after.ino

        Dir.rmdir(path)
      rescue SystemCallError
        # Never recurse, force removal, or obscure the original failure.
        next
      end
    end
  end
end
