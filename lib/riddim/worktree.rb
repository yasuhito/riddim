# frozen_string_literal: true

require 'open3'
require_relative 'ownership'
require_relative 'runtime_paths'

module Riddim
  # Fresh, unpooled Git worktrees for isolated Pi workers. Unlike Firstmate's
  # Treehouse pool, this owner never resets, returns, or removes a worktree.
  module Worktree
    Created = Struct.new(:project, :path, :branch) do
      def record_fields
        { 'project' => project, 'worktree' => path, 'branch' => branch }
      end

      def to_s
        "#{path} (branch #{branch})"
      end
    end

    class Error < StandardError; end

    # Do not let a caller's Git plumbing variables silently redirect -C away
    # from the project or the newly allocated worktree.
    GIT_ENV = RuntimePaths::GIT_ENV

    module_function

    def create(name, cwd:, config_dir:, state_dir:)
      project = project_root(cwd)
      branch = "riddim/#{name}"
      base_head = git_value(project, 'rev-parse', 'HEAD')
      path = destination(project, name, branch)
      add_worktree!(project, path, branch, base_head)

      created = Created.new(project, path, branch)
      verify_created!(created, base_head)
      publish_runtime_paths!(created, config_dir: config_dir, state_dir: state_dir)
      created
    end

    def destination(project, name, branch)
      path = File.join(File.dirname(project), "#{File.basename(project)}-riddim-#{name}")
      [project, path, branch].each { |value| Ownership.validate_value('worktree', value) }
      raise Error, "worktree destination already exists: #{path}" if File.exist?(path) || File.symlink?(path)

      path
    end

    def add_worktree!(project, path, branch, base_head)
      output, status = git(project, 'worktree', 'add', '-b', branch, path, base_head)
      return if status.success?

      raise Error, "git worktree add failed for #{path} (branch #{branch}): #{output.strip}; inspect before retrying"
    end

    def project_root(cwd)
      output, status = git(cwd, 'rev-parse', '--show-toplevel')
      raise Error, "not a Git worktree: #{cwd}: #{output.strip}" unless status.success?

      project = File.realpath(output.strip)
      head, status = git(project, 'rev-parse', '--verify', 'HEAD')
      raise Error, "project has no committed HEAD: #{project}: #{head.strip}" unless status.success?

      project
    rescue Errno::ENOENT => e
      raise Error, "project directory is unavailable: #{e.message}"
    end

    def verify_created!(created, base_head)
      return if isolated_link?(created) && expected_head?(created, base_head) &&
                git_value(created.path, 'status', '--porcelain', '--untracked-files=all').empty?

      raise Error, 'isolation, branch, HEAD, or clean-check failed'
    rescue Error, SystemCallError => e
      raise Error, "created worktree #{created.path} (branch #{created.branch}) retained for inspection: #{e.message}"
    end

    def isolated_link?(created)
      project = created.project
      path = created.path
      top = File.realpath(git_value(path, 'rev-parse', '--show-toplevel'))
      common = File.realpath(git_value(project, 'rev-parse', '--path-format=absolute', '--git-common-dir'))
      linked_common = File.realpath(git_value(path, 'rev-parse', '--path-format=absolute', '--git-common-dir'))
      git_dir = File.realpath(git_value(path, 'rev-parse', '--absolute-git-dir'))
      top == path && path != project && common == linked_common && git_dir != common
    end

    def publish_runtime_paths!(created, config_dir:, state_dir:)
      fields = runtime_fields(created, config_dir, state_dir)
      fields.each_value { |value| Ownership.validate_value('runtime path', value) }
      admin = File.realpath(git_value(created.path, 'rev-parse', '--absolute-git-dir'))
      Ownership.publish(File.join(admin, 'riddim-home'), RuntimePaths.serialize(fields))
    rescue Ownership::Error, SystemCallError => e
      raise Error, "created worktree #{created} retained; cannot publish runtime paths: #{e.message}"
    end

    def runtime_fields(created, config_dir, state_dir)
      { 'project' => created.project, 'worktree' => created.path,
        'config_dir' => File.expand_path(config_dir), 'state_dir' => File.expand_path(state_dir) }
    end

    def expected_head?(created, base_head)
      git_value(created.path, 'symbolic-ref', '--short', 'HEAD') == created.branch &&
        git_value(created.path, 'rev-parse', 'HEAD') == base_head
    end

    def git_value(dir, *args)
      output, status = git(dir, *args)
      raise Error, "git #{args.join(' ')} failed in #{dir}: #{output.strip}" unless status.success?

      output.strip
    end

    def git(dir, *)
      stdout, stderr, status = Open3.capture3(GIT_ENV, 'git', '-C', dir, *)
      [status.success? ? stdout : stderr + stdout, status]
    end
  end
end
