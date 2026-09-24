# frozen_string_literal: true

module Riddim
  # Local Git proof of landed work and non-forced cleanup of its linked tree.
  module Teardown
    module_function

    def location!(task)
      raise Refused, 'worker branch is not bound to this name' unless task.branch == "riddim/#{task.name}"
      raise Refused, 'worker worktree is not a linked checkout' unless Result.linked_checkout?(task.fields)
      raise Refused, 'project main is not checked out' unless
        Worktree.git_value(task.project, 'symbolic-ref', '--short', 'HEAD') == 'main'
    end

    def landed_head!(task)
      raise Refused, 'project has uncommitted work; retaining assets' unless clean?(task.project)
      raise Refused, 'worker has uncommitted work; retaining assets' unless clean?(task.worktree)
      raise Refused, 'worker is not on its named branch; retaining assets' unless
        Worktree.git_value(task.worktree, 'symbolic-ref', '--short', 'HEAD') == task.branch
      raise Refused, 'worker branch is not its checkout tip; retaining assets' unless
        Result.committed_branch?(task.name, task.fields)

      verify_landed_head!(task)
    end

    def verify_landed_head!(task)
      head = Worktree.git_value(task.worktree, 'rev-parse', 'HEAD')
      main = Worktree.git_value(task.project, 'rev-parse', 'refs/heads/main')
      raise Refused, 'project checkout is not at local main; retaining assets' unless
        Worktree.git_value(task.project, 'rev-parse', 'HEAD') == main
      raise Refused, 'worker work is not landed in local main; retaining assets' unless
        Worktree.git(task.project, 'merge-base', '--is-ancestor', head, main).last.success?

      head
    end

    def clean?(directory)
      Worktree.git_value(directory, 'status', '--porcelain', '--untracked-files=all').empty?
    end

    def remove_git_assets!(task, head)
      raise Refused, 'Git changed after pane close; retaining assets' unless landed_head!(task) == head

      git!(task.project, 'worktree', 'remove', task.worktree)
      unless Worktree.git_value(task.project, 'rev-parse', "refs/heads/#{task.branch}") == head
        raise Refused, 'worker branch changed after worktree removal; retaining record'
      end

      git!(task.project, 'branch', '-d', task.branch)
    end

    def git!(project, *args)
      output, status = Worktree.git(project, *args)
      return if status.success?

      raise Refused, "git #{args.first} failed; retaining remaining assets: #{output.strip}"
    end
  end
end
