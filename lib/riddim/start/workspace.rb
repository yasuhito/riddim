# frozen_string_literal: true

module Riddim
  # Endpoint allocation for Start. A new worktree's pane is checked before
  # publication or agent launch; failed placement uses Start's exact-pane
  # rollback, which never removes the linked worktree or its branch.
  module Start
    module_function

    def preflight!
      Riddim::Herdr.verify_client!
    rescue Riddim::Herdr::CommandFailed => e
      report_failed_start(e)
      Riddim::Herdr.terminate_like(e)
    end

    def create_endpoint(name, cwd:, worktree: nil)
      preflight!
      workspace = create_workspace(name, cwd)
      confirm_worktree_workspace(workspace, worktree) if worktree
      workspace
    end

    def create_workspace(name, cwd)
      Riddim::Herdr.create_workspace(cwd: cwd, label: "riddim-#{name}")
    rescue Riddim::Herdr::CommandFailed => e
      [[$stdout, e.stdout], [$stderr, e.stderr]].each { |stream, text| stream.write(text) }
      Riddim::Herdr.terminate_like(e)
    rescue Riddim::Herdr::InvalidResponse => e
      warn "riddim: invalid Herdr workspace JSON: #{e.message}"
      exit 1
    end

    def confirm_worktree_workspace(workspace, worktree)
      pane = workspace.root_pane_id
      return if Riddim::Herdr.worktree_cwd_confirmed?(pane, worktree.path, session: Riddim::Herdr.session)

      error = Worktree::Error.new("pane #{pane} never confirmed its worktree cwd #{worktree.path}")
      rollback_after_failed_publication(workspace, error)
    end
  end
end
