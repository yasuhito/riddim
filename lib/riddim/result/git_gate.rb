# frozen_string_literal: true

module Riddim
  # Independent local Git evidence for a worker's done claim. No operation
  # here changes a ref, checkout, pane, or ownership record.
  module Result
    module_function

    def ready?(name, fields)
      return false unless linked_checkout?(fields)
      return false unless committed_branch?(name, fields)

      worktree = fields.fetch('worktree')
      project = fields.fetch('project')
      return false unless Worktree.git_value(worktree, 'status', '--porcelain', '--untracked-files=all').empty?

      head = Worktree.git_value(worktree, 'rev-parse', 'HEAD')
      main = Worktree.git_value(project, 'rev-parse', 'refs/heads/main')
      Worktree.git(project, 'merge-base', '--is-ancestor', main, head).last.success?
    rescue KeyError, SystemCallError, Worktree::Error
      false
    end

    def linked_checkout?(fields)
      project = fields.fetch('project')
      worktree = fields.fetch('worktree')
      return false unless File.realpath(project) == project && File.realpath(worktree) == worktree
      return false unless Worktree.git_value(project, 'rev-parse', '--show-toplevel') == project &&
                          Worktree.git_value(worktree, 'rev-parse', '--show-toplevel') == worktree

      common, linked, admin = git_admin_paths(project, worktree)
      common == linked && common != admin
    end

    def git_admin_paths(project, worktree)
      common = File.realpath(Worktree.git_value(project, 'rev-parse', '--path-format=absolute', '--git-common-dir'))
      linked = File.realpath(Worktree.git_value(worktree, 'rev-parse', '--path-format=absolute', '--git-common-dir'))
      admin = File.realpath(Worktree.git_value(worktree, 'rev-parse', '--absolute-git-dir'))
      [common, linked, admin]
    end

    def committed_branch?(name, fields)
      project = fields.fetch('project')
      worktree = fields.fetch('worktree')
      branch = "riddim/#{name}"
      base = fields.fetch('base_head')
      return false unless fields['branch'] == branch && base.match?(/\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z/)

      head = Worktree.git_value(worktree, 'rev-parse', 'HEAD')
      return false if head == base || Worktree.git_value(worktree, 'symbolic-ref', '--short', 'HEAD') != branch
      return false unless Worktree.git_value(project, 'rev-parse', "refs/heads/#{branch}") == head

      Worktree.git(project, 'merge-base', '--is-ancestor', base, head).last.success?
    end

    # The local main tip and the verified worker branch tip of one local-only
    # record. Raises Result::Error, refusing instead of guessing, when the
    # branch is not bound to this name, the worktree is not the recorded
    # linked checkout, the named branch is not checked out there, or the
    # named branch tip no longer matches its checkout.
    def verified_tips(name, fields)
      branch = "riddim/#{name}"
      raise Error, 'worker branch is not bound to this name' unless fields.fetch('branch') == branch
      raise Error, 'worker worktree is not the recorded linked checkout' unless linked_checkout?(fields)

      worktree = fields.fetch('worktree')
      project = fields.fetch('project')
      verify_checked_out_branch!(worktree, branch)
      head = Worktree.git_value(worktree, 'rev-parse', 'HEAD')
      named_head = Worktree.git_value(project, 'rev-parse', "refs/heads/#{branch}")
      raise Error, 'worker branch no longer points to its checkout' unless named_head == head

      [Worktree.git_value(project, 'rev-parse', 'refs/heads/main'), head]
    end

    def verify_checked_out_branch!(worktree, branch)
      checkout_branch, status = Worktree.git(worktree, 'symbolic-ref', '--quiet', '--short', 'HEAD')
      raise Error, 'worker branch is not checked out' unless status.success? && checkout_branch.strip == branch
    end
  end
end
