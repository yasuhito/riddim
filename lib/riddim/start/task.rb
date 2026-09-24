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

    def complete_launch(name, profile, workspace, worktree, task_launch)
      if task_launch.brief
        launch_file = stage_task_launch(workspace, task_launch.brief, profile, task_launch.spawn_gen,
                                        task_launch.runtime_paths)
        publish_record(name, profile, workspace, task_launch, worktree: worktree)
        launch_task(name, workspace, worktree, launch_file)
      else
        spawn_gen = publish_record(name, profile, workspace, task_launch, worktree: worktree)
        launch(name, profile, workspace, spawn_gen)
      end
    end

    def stage_task_launch(workspace, brief, profile, spawn_gen, runtime_paths)
      TaskBrief.publish_launch(brief, profile, spawn_gen, runtime_paths: runtime_paths)
    rescue TaskBrief::Error => e
      rollback_after_failed_publication(workspace, e)
    end

    # The record is already published when the shell command is submitted.
    # Submission can be ambiguous and the task may have executed before any
    # response, so no failure here ever closes the pane or removes the record.
    def launch_task(name, workspace, worktree, launch_file)
      pane = workspace.root_pane_id
      submit_task_shell(workspace, worktree, launch_file)
      observed = wait_for_task_pi(workspace)
      renamed = Riddim::Herdr.rename_agent(pane, name)
      confirm_named_task_pi(name, workspace, observed, renamed)
      puts "started #{name} in #{pane}"
    rescue Riddim::Herdr::CommandFailed, Riddim::Herdr::InvalidResponse, TaskBrief::Error, SystemCallError => e
      report_unconfirmed_task(e, pane)
    end

    def report_unconfirmed_task(error, pane)
      report_failed_start(error)
      warn "riddim: launch unconfirmed; retained session #{Riddim::Herdr.session} pane #{pane} " \
           'and its ownership record; inspect before retrying'
      exit 1
    end

    def submit_task_shell(workspace, worktree, launch_file)
      pane = workspace.root_pane_id
      raise TaskBrief::Error, 'exact worktree pane cwd changed before launch' unless
        Riddim::Herdr.worktree_cwd_confirmed?(pane, worktree.path, session: Riddim::Herdr.session)

      Riddim::Herdr.run_pane(pane, ". #{Shellwords.escape(launch_file)}")
    end

    def wait_for_task_pi(workspace)
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 30
      loop do
        agent = observe_task_pi(workspace)
        return agent if agent
        raise TaskBrief::Error, 'Pi registration could not be confirmed' if timed_out?(deadline)

        sleep 0.25
      end
    end

    def timed_out?(deadline) = Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

    def observe_task_pi(workspace)
      agent = Riddim::Herdr.agent(workspace.root_pane_id)
      raise TaskBrief::Error, 'another agent occupies the task pane' if agent['agent'] != 'pi'

      agent if exact_task_pi?(agent, workspace) && task_session(agent)
    rescue Riddim::Herdr::CommandFailed, Riddim::Herdr::InvalidResponse
      nil
    end

    def exact_task_pi?(agent, workspace)
      agent['agent'] == 'pi' && agent['pane_id'] == workspace.root_pane_id &&
        agent['workspace_id'] == workspace.workspace_id && agent['tab_id'] == workspace.tab_id
    end

    def task_session(agent)
      session = agent['agent_session']
      session['value'] if session.is_a?(Hash) && session['source'] == 'herdr:pi' && session['kind'] == 'path'
    end

    def confirm_named_task_pi(name, workspace, observed, renamed)
      named = Riddim::Herdr.agent(name)
      unless [renamed, named].all? { |agent| same_task_pi?(agent, workspace, name, observed) }
        raise TaskBrief::Error, 'named Pi does not match the observed task pane and incarnation'
      end
      raise TaskBrief::Error, 'Pi process is not confirmed alive' unless
        Riddim::Herdr.pi_process_alive?(workspace.root_pane_id, session: Riddim::Herdr.session)
    end

    def same_task_pi?(agent, workspace, name, observed)
      exact_task_pi?(agent, workspace) && agent['name'] == name && task_session(agent) == task_session(observed)
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
