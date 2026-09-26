# frozen_string_literal: true

Given('the project checkout is on main') do
  git = Open3.capture3('git', '-C', @project, 'branch', '-M', 'main').last
  raise 'project main branch could not be established' unless git.success?
end

Given('a regular task was started') do
  @stdout, @stderr, @status = run_riddim('start', 'worker', '--worktree', '--task-file', 'task.md')
  raise "task start failed: #{@stderr}" unless @status.success?
end

Given('a local-only task was started') do
  @stdout, @stderr, @status = run_riddim('start', 'worker', '--worktree', '--task-file', 'task.md',
                                         '--mode', 'local-only')
  raise "task start failed: #{@stderr}" unless @status.success?

  generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  @result_path = File.join(scenario_state_dir, "worker.#{generation}.status")
  @worker_tip = worker_branch_tip
end

Given('the worker reports {string}') do |event|
  generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  _output, errors, status = run_riddim('report', 'worker', '--generation', generation, event)
  raise "worker report failed: #{errors}" unless status.success?
end

Given('the worker status is nearly full with an open decision') do
  decision = "needs-decision [at=16]: choose A\n"
  filler = "working [at=1]: #{'x' * (Riddim::Result::MAX_BYTES - decision.bytesize - 17)}\n"
  File.write(@result_path, filler + decision)
end

Given('the worker status contains a malformed event') do
  File.open(@result_path, 'a') { |file| file.puts('done: trust me') }
end

Given('the worker commits a change in its own branch') do
  File.write(File.join(@worktree, 'tracked.txt'), "worker change\n")
  git = Open3.capture3('git', '-C', @worktree, 'add', 'tracked.txt').last
  raise 'worker could not stage its change' unless git.success?

  git = Open3.capture3('git', '-C', @worktree, '-c', 'user.name=Worker', '-c', 'user.email=test@example.invalid',
                       'commit', '-qm', 'worker change').last
  raise 'worker could not commit' unless git.success?

  @worker_tip = worker_branch_tip
end

Given('the worker commits another change in its own branch') do
  File.write(File.join(@worktree, 'tracked.txt'), "worker change two\n")
  git = Open3.capture3('git', '-C', @worktree, 'add', 'tracked.txt').last
  raise 'worker could not stage its second change' unless git.success?

  git = Open3.capture3('git', '-C', @worktree, '-c', 'user.name=Worker', '-c', 'user.email=test@example.invalid',
                       'commit', '-qm', 'worker change two').last
  raise 'worker could not commit a second change' unless git.success?

  @worker_tip = worker_branch_tip
end

# The full commit id of the recorded worker branch, read from the project.
def worker_branch_tip
  output, status = Open3.capture2('git', '-C', @project, 'rev-parse', 'refs/heads/riddim/worker')
  raise 'worker branch tip could not be read' unless status.success?

  output.strip
end

Given('the worker leaves an untracked file') do
  File.write(File.join(@worktree, 'unfinished.txt'), 'unfinished')
end

Given('main advances independently') do
  git = Open3.capture3('git', '-C', @project, '-c', 'user.name=Main', '-c', 'user.email=test@example.invalid',
                       'commit', '--allow-empty', '-qm', 'main advances').last
  raise 'main could not advance' unless git.success?
end

Given('the ownership record names a replacement generation') do
  record = scenario_record_path('worker')
  bytes = File.read(record)
  File.write(record, bytes.sub(/^spawn_gen=.+$/, 'spawn_gen=s9999.9999.9999'))
end

Given('the worker status file is replaced with a symlink') do
  File.delete(@result_path)
  File.symlink(File.join(@project, 'tracked.txt'), @result_path)
end

Then('the conflicting delivery contract is refused before publication') do
  brief = File.join(scenario_state_dir, 'worker.brief')
  assets = Dir.exist?(scenario_state_dir) ? Dir.children(scenario_state_dir) : []
  assert_equal [false, true, false, false, true, false],
               [@status.success?, @stderr.include?('delivery mismatch'), File.exist?(@worktree),
                File.exist?(brief), herdr_invocations.empty?, assets.any? { |file| file.end_with?('.status') }]
end

Then('the local-only brief puts the binding delivery contract before the task') do
  brief = File.read(File.join(scenario_state_dir, 'worker.brief'))
  assert_equal [true, true, true, true, true],
               [@status.success?, brief.include?('Delivery contract: mode=local-only'),
                brief.include?('supersedes conflicting project and task instructions'),
                brief.include?('report a needs-decision event and stop'),
                brief.index('# Local-only delivery contract') < brief.index('# Human\'s task')], @stderr
end

Then('the local-only result is {string}') do |outcome|
  assert_equal [true, "#{outcome}\n"], [@status.success?, @stdout], @stderr
end

Given('the supervisor answers key {string} with {string}') do |key, text|
  _output, errors, status = run_riddim('send', 'worker', '--resolve-key', key, text)
  raise "answer failed: #{errors}" unless status.success?
end

When('the worker reports a blocker while the supervisor answers key {string}') do |key|
  generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  results = [Thread.new { run_riddim('send', 'worker', '--resolve-key', key, 'Choose A') },
             Thread.new do
               run_riddim('report', 'worker', '--generation', generation,
                          'blocked [at=17] [key=beta]: wait for B')
             end].map(&:value)
  assert results.all? { |_out, _err, status| status.success? }, results.inspect
end

Then('the unrelated blocker remains open') do
  generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  _out, errors, status = run_riddim('report', 'worker', '--generation', generation, 'done [at=18]: tested')
  assert_predicate status, :success?, errors
  @stdout, @stderr, @status = run_riddim('result', 'worker')
  assert_equal "reported (not ready): done [at=18]: tested\n", @stdout
  @stdout, @stderr, @status = run_riddim('send', 'worker', '--resolve-key', 'beta', 'Proceed')
  assert_predicate @status, :success?, @stderr
  _out, errors, status = run_riddim('report', 'worker', '--generation', generation, 'done [at=19]: tested')
  assert_predicate status, :success?, errors
  @stdout, @stderr, @status = run_riddim('result', 'worker')
  assert_equal "ready: done [at=19]: tested\n", @stdout
end

Then('the wrong key is refused without storing another answer') do
  count = Dir.glob(File.join(scenario_state_dir, '*.inbox', '*.msg')).length
  assert_equal [1, true, 1], [@status.exitstatus, @stderr.include?('not open'), count]
end

Then('the wrong key is refused without storing an answer') do
  assert_equal [1, true, []], [@status.exitstatus, @stderr.include?('not open'),
                               Dir.glob(File.join(scenario_state_dir, '*.inbox', '*.msg'))]
end

Then('the answer is stored but its decision remains open for repair') do
  sent_status = @status.exitstatus
  warning = @stderr
  records = Dir.glob(File.join(scenario_state_dir, '*.inbox', '*.msg'))
  @stdout, @stderr, @status = run_riddim('result', 'worker')
  assert_equal [1, true, true, 0, "reported: needs-decision [at=16]: choose A\n"],
               [sent_status, warning.include?('do not resend; decision default close unconfirmed'),
                records.length == 1 && File.read(records.first).include?('Choose A'), @status.exitstatus, @stdout]
end

Then('the result command refuses a regular task') do
  assert_equal [false, true], [@status.success?, @stderr.include?('only for local-only tasks')]
end

Then('the result command refuses malformed status evidence') do
  assert_equal [false, true], [@status.success?, @stderr.include?('invalid event')]
end

Then('the local-only result begins with {string}') do |prefix|
  assert_equal [true, true], [@status.success?, @stdout.start_with?(prefix)], @stderr
end
