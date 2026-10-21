# frozen_string_literal: true

module Riddim
  # The locked transaction from private task publication through the exact
  # pane's launch. Any ambiguous task submission leaves its assets untouched.
  module Start
    module_function

    def start_locked(name, profile, options)
      reserve_record_path(name)
      task_plan = prepare_task(options)
      worktree = prepare_worktree(name, config_dir: options.config_dir) if options.create_worktree
      PiTrust.ensure_worktree_trusted!(worktree.path) if worktree
      task_launch = publish_task(name, options, task_plan)
      InstructionInbox.prepare(InstructionInbox.path(name, task_launch.spawn_gen)) if task_launch.mode
      launch_in_workspace(name, profile, worktree, task_launch)
      succeeded = true
    ensure
      report_failed_launch_assets(worktree, task_launch) unless succeeded
    end

    def launch_in_workspace(name, profile, worktree, task_launch)
      workspace = create_endpoint(name, cwd: worktree ? worktree.path : Dir.pwd, worktree: worktree)
      complete_launch(name, profile, workspace, worktree, task_launch)
      report_successful_launch(worktree, task_launch)
    end

    def prepare_task(options)
      Worktree.require_main!(Dir.pwd) if options.mode
      TaskPlan.new(task: read_task_file(options), spawn_gen: Ownership.fresh_spawn_gen, mode: options.mode)
    end

    def publish_task(name, options, task_plan)
      status_path = Result.publish(name, task_plan.spawn_gen) if task_plan.mode
      brief = publish_task_brief(name, options, task_plan, status_path)
      build_task_launch(options, task_plan, status_path, brief)
    rescue Ownership::Error
      warn "riddim: result file retained at #{status_path}; inspect before retrying" if status_path
      raise
    end

    def publish_task_brief(name, options, task_plan, status_path)
      return unless options.task_file

      TaskBrief.publish(name, task_plan.task, status_path: status_path, spawn_gen: task_plan.spawn_gen)
    end

    def build_task_launch(options, task_plan, status_path, brief)
      TaskLaunch.new(
        brief: brief,
        spawn_gen: task_plan.spawn_gen,
        mode: task_plan.mode,
        status_path: status_path,
        runtime_paths: task_runtime_paths(options)
      )
    end

    def task_runtime_paths(options)
      { config_dir: options.config_dir, state_dir: Ownership.state_dir }
    end

    def read_task_file(options)
      return unless options.task_file

      task = TaskBrief.read(options.task_file)
      TaskBrief.validate_delivery_contract!(task, options.mode) if options.mode
      task
    end

    def report_successful_launch(worktree, task_launch)
      report_started_assets(worktree, task_launch.brief)
      puts "result #{task_launch.status_path}" if task_launch.status_path
    end

    def report_failed_launch_assets(worktree, task_launch)
      report_retained_assets(worktree, task_launch&.brief)
      return unless task_launch&.status_path

      warn "riddim: result file retained at #{task_launch.status_path}; inspect before retrying"
    end

    # The record is the ownership authority; the same generation binds its
    # task launch file, result file, and exact response-derived endpoint.
    def publish_record(name, profile, workspace, task_launch, worktree:)
      fields = record_fields(name, profile, workspace, task_launch, worktree)
      Ownership.publish(Ownership.record_path(name), Ownership.serialize(fields))
      task_launch.spawn_gen
    rescue Ownership::Error => e
      rollback_after_failed_publication(workspace, e)
    end

    def record_fields(name, profile, workspace, task_launch, worktree)
      fields = Ownership::Endpoint.fields(
        name: name, profile: profile, spawn_gen: task_launch.spawn_gen,
        session: Riddim::Herdr.session, workspace: workspace
      )
      fields.merge!(worktree.record_fields) if worktree
      if task_launch.mode
        fields.merge!('task_mode' => task_launch.mode, 'base_head' => worktree.base_head,
                      'status_protocol' => Result::STATUS_PROTOCOL)
      end
      fields
    end
  end
end
