# frozen_string_literal: true

require 'json'

Given('notifications were scanned') do
  _out, error, status = run_riddim('notifications', 'scan')
  raise "scan failed: #{error}" unless status.success?
end

Given('another valid plain task record is present') do
  original = File.read(scenario_record_path('worker'))
  plain = original.sub('endpoint_task_id=worker', 'endpoint_task_id=peer')
                  .lines.reject { |line| line.start_with?('task_mode=', 'status_protocol=') }.join
  File.write(scenario_record_path('peer'), plain)
  File.chmod(0o600, scenario_record_path('peer'))
end

Given('the ownership record is invalid for notification scanning') do
  path = scenario_record_path('worker')
  File.write(path, File.read(path).sub('endpoint_task_id=worker', 'endpoint_task_id=other'))
end

Given('a new generation status file is published') do
  generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  File.write(File.join(scenario_state_dir, "worker.#{generation}.status"), '')
  File.chmod(0o600, File.join(scenario_state_dir, "worker.#{generation}.status"))
end

Given('the worker status is world-readable') do
  File.chmod(0o644, @result_path)
end

Given('the status ends in an incomplete event') do
  File.open(@result_path, 'a') { |file| file.write('done [at=1]: partial') }
end

Given('the notification directory is unavailable') do
  File.symlink(@project, File.join(scenario_state_dir, '.notifications'))
end

Given('ownership changes during status classification') do
  fixture = File.join(new_temporary_directory, 'change_owner.rb')
  File.write(fixture, <<~RUBY)
    require #{File.expand_path('../../lib/riddim/notifications', __dir__).dump}
    module Riddim::Result
      class << self
        alias_method :original_parse_events, :parse_events
        def parse_events(bytes)
          status = original_parse_events(bytes)
          path = Riddim::Ownership.record_path('worker')
          File.write(path, File.read(path).sub(/^spawn_gen=.+$/, 'spawn_gen=s9999.9999.9999'))
          status
        end
      end
    end
  RUBY
  @environment['RUBYOPT'] = "-r#{fixture}"
end

Given('the notification cursor cannot be replaced') do
  fixture = File.join(new_temporary_directory, 'break_cursor.rb')
  File.write(fixture, <<~RUBY)
    require #{File.expand_path('../../lib/riddim/notifications', __dir__).dump}
    module Riddim::Notifications
      def self.replace(*)
        raise IOError, 'injected crash before cursor replacement'
      end
    end
  RUBY
  @environment['RUBYOPT'] = "-r#{fixture}"
end

When('I scan pending notifications twice') do
  @first_scan = run_riddim('notifications', 'scan')
  @second_scan = run_riddim('notifications', 'scan')
end

Then('pending notifications retain three separate report identities without changing the worker') do
  first, second = [@first_scan, @second_scan].map { |out, _err, status| status.success? ? JSON.parse(out) : nil }
  inspected, error, status = run_riddim('notifications')
  generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  expected = [1, 3, 4].zip(%w[needs-decision blocked done]).map do |sequence, event|
    { 'id' => "worker.#{generation}.#{sequence}", 'task' => 'worker',
      'generation' => generation, 'sequence' => sequence, 'event' => event }
  end
  assert_equal [expected, expected, expected, true, 4, true],
               [first, second, JSON.parse(inspected), status.success?, File.readlines(@result_path).size,
                herdr_invocations.none? do |invocation|
                  invocation.include?('key') || invocation.include?('send')
                end], error
end

Then('the appended decision stays pending with its own sequence') do
  generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  expected = [{ 'id' => "worker.#{generation}.2", 'task' => 'worker', 'generation' => generation,
                'sequence' => 2, 'event' => 'needs-decision' }]
  assert_equal [expected, expected], [JSON.parse(@first_scan[0]), JSON.parse(@second_scan[0])]
end

Then('only the worker report is pending') do
  generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  expected = [{ 'id' => "worker.#{generation}.1", 'task' => 'worker', 'generation' => generation,
                'sequence' => 1, 'event' => 'blocked' }]
  assert_equal [true, expected], [@status.success?, JSON.parse(@stdout)], @stderr
end

Then('only the replacement generation report is pending') do
  generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  expected = [{ 'id' => "worker.#{generation}.1", 'task' => 'worker', 'generation' => generation,
                'sequence' => 1, 'event' => 'failed' }]
  assert_equal [true, expected], [@status.success?, JSON.parse(@stdout)], @stderr
end

Then('no notifications were published') do
  assert_equal [true, "[]\n", true, "[]\n"],
               [@first_scan[2].success?, @first_scan[0], @second_scan[2].success?, @second_scan[0]]
end

Then('the old notification remains historical and the successor has no claim') do
  generation = File.basename(@result_path)[/worker\.(s\d+\.\d+\.\d+)\.status/, 1]
  inspected, = run_riddim('notifications')
  assert_equal [false, false, [{ 'id' => "worker.#{generation}.1", 'task' => 'worker',
                                 'generation' => generation, 'sequence' => 1, 'event' => 'failed' }]],
               [@first_scan[2].success?, @second_scan[2].success?, JSON.parse(inspected)]
end

Then('scanning fails without publishing a notification') do
  inspected, = run_riddim('notifications')
  assert_equal [false, true, "[]\n"], [@status.success?, !@stderr.empty?, inspected]
end

Then('reporting succeeds even though observation cannot publish') do
  _output, error, status = run_riddim('notifications', 'scan')
  assert_equal [true, true, false, true],
               [@report_status.success?, File.readlines(@result_path).size == 1,
                status.success?, error.include?('notification directory')], @report_stderr
end

Then('the failed scan leaves the same pending identity recoverable') do
  @environment.delete('RUBYOPT')
  before, = run_riddim('notifications')
  later, error, status = run_riddim('notifications', 'scan')
  generation = File.read(scenario_record_path('worker'))[/^spawn_gen=(.+)$/, 1]
  expected = [{ 'id' => "worker.#{generation}.1", 'task' => 'worker',
                'generation' => generation, 'sequence' => 1, 'event' => 'blocked' }]
  assert_equal [false, expected, true, expected],
               [@status.success?, JSON.parse(before), status.success?, JSON.parse(later)], error
end
