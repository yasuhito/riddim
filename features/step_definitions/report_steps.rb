# frozen_string_literal: true

require 'timeout'

When('the worker tries to report done while the operator holds the name lock') do
  generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  lock = File.join(scenario_state_dir, '.meta-worker.lock')
  File.open(lock, File::RDWR | File::NOFOLLOW) do |file|
    file.flock(File::LOCK_EX)
    Bundler.with_unbundled_env do
      environment = { 'HERDR_SESSION' => nil }.merge(@environment || {})
      Open3.popen3(environment, RiddimWorld::RIDDIM, 'report', 'worker', '--generation', generation,
                   'done [at=123]: work committed', chdir: @project) do |input, output, error, process|
        input.close
        sleep 0.5
        @report_waited = process.alive? && File.empty?(@result_path)
        file.flock(File::LOCK_UN)
        @report_stdout = output.read
        @report_stderr = error.read
        @report_status = Timeout.timeout(8) { process.value }
      end
    end
  end
end

When('an older generation reports {string} through riddim') do |event|
  @report_stdout, @report_stderr, @report_status =
    run_riddim('report', 'worker', '--generation', 's9999.9999.9999', event)
end

When('the current worker reports {string} through riddim') do |event|
  generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  @report_stdout, @report_stderr, @report_status = run_riddim('report', 'worker', '--generation', generation, event)
end

Then('the report waits until the lock is released and result becomes ready') do
  stdout, stderr, status = run_riddim('result', 'worker')
  assert_equal [true, true, true],
               [@report_waited, @report_status.success?, status.success? && stdout.start_with?('ready: done ')],
               "#{@report_stderr} #{stderr}"
end

Then('the worker has a usable absolute report command and inherited private state') do
  generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  brief = File.read(File.join(scenario_state_dir, 'worker.brief'))
  launch = File.read(File.join(@herdr_directory, 'staged-launch'))
  assert_equal [true, false, true, true, true],
               [@status.success?, File.exist?(File.join(@worktree, 'bin', 'riddim')),
                brief.include?("#{RiddimWorld::RIDDIM} report worker --generation #{generation}"),
                launch.include?("export RIDDIM_STATE_DIR=#{scenario_state_dir}"),
                launch.include?("export RIDDIM_CONFIG_DIR=#{@environment.fetch('RIDDIM_CONFIG_DIR')}")], @stderr
end

Then('the task brief instructs the worker to use its generation-locked report command') do
  record = File.read(scenario_record_path('worker'))
  generation = record[/^spawn_gen=(.+)$/, 1]
  brief = File.read(File.join(scenario_state_dir, 'worker.brief'))
  assert_equal [true, true, true],
               [@status.success?, record.include?('status_protocol=locked-v1'),
                brief.include?("#{RiddimWorld::RIDDIM} report worker --generation #{generation}")], @stderr
end

Then('reporting refuses the stale generation and keeps the status empty') do
  assert_equal [false, true, true],
               [@report_status.success?, @report_stderr.include?('another worker generation'),
                File.empty?(@result_path)], @report_stderr
end

Then('reporting refuses an uncoordinated legacy worker and keeps the status empty') do
  assert_equal [false, true, true],
               [@report_status.success?, @report_stderr.include?('locked report protocol'),
                File.empty?(@result_path)], @report_stderr
end

Then('reporting refuses the symlink and does not change its target') do
  assert_equal [false, true, "base\n"],
               [@report_status.success?, File.symlink?(@result_path), File.read(File.join(@project, 'tracked.txt'))],
               @report_stderr
end

Then('the report is accepted and result shows the worker ready') do
  result_stdout, result_stderr, result_status = run_riddim('result', 'worker')
  assert_equal [true, true, true, true],
               [@report_status.success?, @report_stdout.include?('reported'), result_status.success?,
                result_stdout.start_with?('ready: done ')], "#{@report_stderr} #{result_stderr}"
end
