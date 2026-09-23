# frozen_string_literal: true

require 'open3'
require_relative 'ownership'
require_relative 'herdr'

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
    GIT_ENV = { 'GIT_DIR' => nil, 'GIT_WORK_TREE' => nil, 'GIT_COMMON_DIR' => nil,
                'GIT_INDEX_FILE' => nil }.freeze

    module_function

    def create(name, cwd:)
      project = project_root(cwd)
      branch = "riddim/#{name}"
      path = File.join(File.dirname(project), "#{File.basename(project)}-riddim-#{name}")
      [project, path, branch].each { |value| Ownership.validate_value('worktree', value) }
      raise Error, "worktree destination already exists: #{path}" if File.exist?(path) || File.symlink?(path)

      add_worktree!(project, path, branch)

      created = Created.new(project, path, branch)
      verify_created!(created)
      created
    end

    def add_worktree!(project, path, branch)
      output, status = git(project, 'worktree', 'add', '-b', branch, path, 'HEAD')
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

    def verify_created!(created)
      return if isolated_link?(created) && git_value(created.path, 'status', '--porcelain',
                                                     '--untracked-files=all').empty?

      raise Error, 'isolation or clean-check failed'
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

    # The workspace create request is not proof that its shell actually moved
    # into the new checkout. Require two consecutive exact-pane foreground cwd
    # reads, as Firstmate does, before launching an agent that can edit files.
    def confirm_pane!(workspace, created)
      expected = created.path
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
      matching = 0
      while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        path = Herdr.current_path(workspace.root_pane_id, session: Herdr.session)
        matching = path == expected ? matching + 1 : 0
        return if matching == 2

        sleep 0.2
      end
      raise Error, "pane #{workspace.root_pane_id} never confirmed its worktree cwd #{expected}"
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
