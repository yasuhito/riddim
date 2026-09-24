# frozen_string_literal: true

require 'json'
require 'open3'
require_relative '../../lib/riddim/ownership'
require_relative '../../lib/riddim/ownership/record'
require_relative '../../lib/riddim/result'

# Builds a complete local-only task record with its status protocol fields, as
# `riddim start --mode local-only` publishes, without running a start.
def local_only_record_fields(name, session:, pane_id: 'w9:p1', worktree: '/tmp/project-riddim-worker')
  ownership_record_fields(name, session: session, pane_id: pane_id).merge(
    'project' => '/tmp/project', 'worktree' => worktree, 'branch' => "riddim/#{name}",
    'task_mode' => 'local-only', 'base_head' => '0' * 40, 'status_protocol' => Riddim::Result::STATUS_PROTOCOL
  )
end

Given('a published local-only record for {string} with status events:') do |name, events|
  FileUtils.mkdir_p(scenario_state_dir)
  fields = local_only_record_fields(name, session: 'riddim')
  File.write(scenario_record_path(name), Riddim::Ownership.serialize(fields))
  status = File.join(scenario_state_dir, "#{name}.#{fields.fetch('spawn_gen')}.status")
  File.write(status, "#{events.chomp}\n")
  File.chmod(0o600, status)
end

Then('the snapshot pairs the git-verified report with the Pi process evidence') do
  record = JSON.parse(@stdout).fetch('records').fetch(0)
  assert_equal [true, true, true, true, true, false],
               [record.fetch('name') == 'worker', record.fetch('session') == scenario_session,
                record.fetch('pane_id') == 'w9:p1', record.fetch('report') == 'ready: done [at=17]: tests passed',
                record.fetch('pi_process') == 'pi', record.key?('agent_status')], @stdout
end

Given("the worker's tracked file has stale index metadata") do
  index, status = Open3.capture2('git', '-C', @worktree, 'rev-parse', '--git-path', 'index')
  raise 'worker index path unavailable' unless status.success?

  @worker_index = File.expand_path(index.strip, @worktree)
  File.utime(Time.at(1), Time.at(1), File.join(@worktree, 'tracked.txt'))
  @index_before = [File.binread(@worker_index), File.stat(@worker_index).mtime]
end

Then('the worker Git index bytes and mtime are unchanged') do
  unchanged = @index_before == [File.binread(@worker_index), File.stat(@worker_index).mtime]
  report = JSON.parse(@stdout).fetch('records').fetch(0).fetch('report')
  assert_equal [true, true], [unchanged, report.start_with?('ready:')]
end

Then('standard output is the empty fleet snapshot') do
  expected = { 'schema' => 'riddim.fleet.v1', 'state_dir' => scenario_state_dir, 'records' => [] }
  assert_equal expected, JSON.parse(@stdout)
end

Then('the rows are in record name order') do
  names = JSON.parse(@stdout).fetch('records').map { |row| row.fetch('name') }
  assert_equal %w[alpha zeta], names
end

Then('the row observes the pane without a report surface') do
  record = JSON.parse(@stdout).fetch('records').fetch(0)
  assert_equal [true, true, false],
               [record.fetch('pi_process') == 'pi', record.fetch('session') == 'riddim',
                record.key?('report')], @stdout
end

Then('the unreadable process observation is not a positive claim') do
  record = JSON.parse(@stdout).fetch('records').fetch(0)
  assert_equal 'unreadable', record.fetch('pi_process')
end

Then('the ready-looking done stays gated by the earlier decision') do
  record = JSON.parse(@stdout).fetch('records').fetch(0)
  assert_equal 'reported (not ready): done [at=17]: tests passed', record.fetch('report')
end

Then('the row keeps the captured identity without mutable evidence') do
  record = JSON.parse(@stdout).fetch('records').fetch(0)
  assert_equal [true, false, false, false],
               [record.fetch('name') == 'worker', record.key?('task_mode'), record.key?('report'),
                record.key?('pi_process')], @stdout
end

Given('the worker reports a pipe-containing event') do
  status = Dir.glob(File.join(scenario_state_dir, 'worker.*.status')).fetch(0)
  File.write(status, "working [at=18]: first | second\n")
end

Then('the human view keeps the pipe inside its report cell') do
  row = @stdout.lines.find { |line| line.start_with?('| worker |') }
  assert_equal [true, 7], [row&.include?('first \\| second'), row&.scan(/(?<!\\)\|/)&.length], @stdout
end

# A CLI subprocess with a one-shot filesystem race at the precise read seam.
# Only the test child loads this module; production still runs the real CLI.
def preload_fleet_race(source)
  file = File.join(new_temporary_directory, 'fleet-race.rb')
  File.write(file, "require #{File.expand_path('../../lib/riddim/list', __dir__).dump}\n#{source}")
  @environment = @environment.merge('RUBYOPT' => "-r#{file}")
end

Given('the recorded pane changes after endpoint capture') do
  preload_fleet_race(<<~RUBY)
    Riddim::Ownership::Endpoint.singleton_class.prepend(Module.new do
      def resolve_snapshot(name)
        snapshot = super
        marker = File.join(Riddim::Ownership.state_dir, 'replace-once')
        if File.exist?(marker)
          File.unlink(marker)
          path = Riddim::Ownership.record_path(name)
          fields = Riddim::Ownership.parse(read_bytes(path))
          fields['herdr_pane_id'] = 'w9:p2'
          fields['window'] = 'riddim:w9:p2'
          staging = "\#{path}.replacement"
          File.write(staging, Riddim::Ownership.serialize(fields))
          File.rename(staging, path)
        end
        snapshot
      end
    end)
  RUBY
  File.write(File.join(scenario_state_dir, 'replace-once'), '')
end

Then("the row retains its first pane without another pane's evidence") do
  row = JSON.parse(@stdout).fetch('records').fetch(0)
  assert_equal ['w9:p1', false, false, false],
               [row.fetch('pane_id'), row.key?('task_mode'), row.key?('report'),
                row.key?('pi_process')], @stdout
end

Given('the record disappears after enumeration') do
  preload_fleet_race(<<~RUBY)
    Riddim::List.singleton_class.prepend(Module.new do
      def record_names
        names = super
        File.unlink(Riddim::Ownership.record_path('worker')) if names.include?('worker')
        names
      end
    end)
  RUBY
end

Given('the record disappears while Herdr reads the process view') do
  File.write(File.join(@herdr_directory, 'remove-record'), '')
end

Then('the snapshot names the selected state directory') do
  assert_equal scenario_state_dir, JSON.parse(@stdout).fetch('state_dir')
end

Then('the human view reports no records') do
  assert_equal [true, true, true],
               [@status.success?, @stdout.include?('no recorded workers'), @stdout.include?(scenario_state_dir)],
               @stderr
end

Then("the human view renders the JSON record's facts") do
  json, json_stderr, json_status = run_riddim('fleet', '--json')
  human, human_stderr, human_status = run_fleet_human
  parsed = JSON.parse(json).fetch('records').fetch(0)
  assert_equal [true, true, true, true, true, true],
               [json_status.success? || (raise json_stderr), human_status.success? || (raise human_stderr),
                human.include?(parsed.fetch('name')), human.include?(parsed.fetch('session')),
                human.include?(parsed.fetch('pane_id')),
                human.include?('ready: done [at=17]: tests passed')], human
end

def run_fleet_human
  environment = { 'HERDR_SESSION' => nil }.merge(@environment || {})
  Bundler.with_unbundled_env do
    Open3.capture3(environment, RiddimWorld::RIDDIM, 'fleet')
  end
end
