# frozen_string_literal: true

module Riddim
  # Task-side reporting for a Firstmate-shaped but deliberately smaller
  # worker launch: failures retain the private brief and the Git worktree.
  module Start
    module_function

    def reserve_record_path(name)
      path = Ownership.record_path(name)
      refuse_duplicate(name, path)
      brief = TaskBrief.path(name)
      if Ownership.record_present?(brief)
        raise TaskBrief::Error,
              "a task brief already exists at #{brief}; inspect before reusing #{name}"
      end

      path
    end

    def report_started_assets(worktree, brief)
      puts "worktree #{worktree}" if worktree
      puts "brief #{brief.path}" if brief
    end

    def report_retained_assets(worktree, brief)
      warn "riddim: retained #{worktree.path} (#{worktree.branch}); inspect before cleanup" if worktree
      warn "riddim: task brief retained at #{brief.path}; inspect before retrying" if brief
    end
  end
end
