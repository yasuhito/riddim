# frozen_string_literal: true

module Riddim
  # The locked transaction from private task publication through the exact
  # pane's launch. Any ambiguous task submission leaves its assets untouched.
  module Start
    module_function

    def start_locked(name, profile, options)
      reserve_record_path(name)
      task_launch = prepare_task(name, options)
      worktree = prepare_worktree(name, config_dir: options.config_dir) if options.create_worktree
      workspace = create_endpoint(name, cwd: worktree ? worktree.path : Dir.pwd, worktree: worktree)
      complete_launch(name, profile, workspace, worktree, task_launch)
      report_successful_launch(worktree, task_launch)
      succeeded = true
    ensure
      report_failed_launch_assets(worktree, task_launch) unless succeeded
    end

    def prepare_task(name, options)
      Worktree.require_main!(Dir.pwd) if options.mode
      task = read_task_file(options)
      spawn_gen = Ownership.fresh_spawn_gen
      status_path = Result.publish(name, spawn_gen) if options.mode
      brief = TaskBrief.publish(name, task, status_path: status_path) if options.task_file
      TaskLaunch.new(brief: brief, spawn_gen: spawn_gen, mode: options.mode, status_path: status_path)
    rescue Ownership::Error
      warn "riddim: result file retained at #{status_path}; inspect before retrying" if status_path
      raise
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
      fields.merge!('task_mode' => task_launch.mode, 'base_head' => worktree.base_head) if task_launch.mode
      fields
    end
  end
end
