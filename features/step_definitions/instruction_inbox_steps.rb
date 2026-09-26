# frozen_string_literal: true

require_relative '../../lib/riddim/instruction_inbox'

Given('a published local-only inbox owner {string}') do |name|
  @inbox_name = name
  publish_record(name, session: 'riddim', overrides: { 'task_mode' => 'local-only' })
end

def current_inbox
  fields = Riddim::Ownership.parse(File.read(scenario_record_path(@inbox_name)))
  File.join(scenario_state_dir, "#{@inbox_name}.#{fields.fetch('spawn_gen')}.inbox")
end

def inbox_bodies(dir)
  Dir.glob(File.join(dir, '*.msg')).map { |file| File.read(file).split("\n--\n", 2).last }
end

Given('the notification probe sees a running server') do
  File.write(File.join(@herdr_directory, 'client-status.json'), '{"server":{"running":true}}')
end

Given('Herdr checks that the instruction already exists') do
  install_fake_herdr(<<~RUBY)
    inbox = Dir.glob(File.join(ENV.fetch('RIDDIM_STATE_DIR'), 'worker.*.inbox')).fetch(0)
    abort 'notification preceded storage' unless Dir.glob(File.join(inbox, '*.msg')).size == 1
    puts 'saved before notification'
  RUBY
  File.write(File.join(@herdr_directory, 'client-status.json'), '{"server":{"running":true}}')
end

Then('the notification observed the stored instruction') do
  assert @status.success?
  assert_equal ['First instruction'], inbox_bodies(current_inbox)
  assert_includes herdr_invocations.last, current_inbox
end

Given('the local-only inbox owner has an inconsistent window') do
  publish_record(@inbox_name, session: 'riddim', overrides: { 'task_mode' => 'local-only', 'window' => 'riddim:w9:p2' })
end

Given('the notification fails') do
  install_fake_herdr("warn 'failed to notify'; exit 17")
end

When('I send two instructions to {string}') do |name|
  @first_send = run_riddim('send', name, 'First instruction')
  @stdout, @stderr, @status = run_riddim('send', name, 'Second instruction')
end

Then('{string} and {string} are ordered and individually acknowledged') do |first, second|
  assert @first_send[2].success?
  assert_equal [first, second], inbox_bodies(current_inbox)
  pending, other = Dir.glob(File.join(current_inbox, '*.msg'))
  handled = File.join(current_inbox, 'handled', File.basename(pending))
  File.rename(pending, handled)
  assert File.file?(handled)
  assert File.file?(other)
  invocation = herdr_invocations.last
  assert_includes invocation, current_inbox
  refute_includes invocation, first
  refute_includes invocation, second
end

Then('the instruction {string} is stored despite notification failure') do |text|
  assert @status.success?
  assert_includes @stderr, 'do not resend'
  assert_equal [text], inbox_bodies(current_inbox)
end

When('I run the instruction watcher after the grace period') do
  # A second home simulates a restarted watcher without racing the daemon
  # that the send command started in the original home.
  restarted = File.join(new_temporary_directory, 'state')
  FileUtils.cp_r(scenario_state_dir, restarted)
  copy = Dir.glob(File.join(restarted, '*.inbox', '*.msg')).fetch(0)
  File.utime(Time.at(100), Time.at(100), copy)
  @environment['RIDDIM_STATE_DIR'] = restarted
  install_fake_herdr(<<~RUBY)
    require 'json'
    if ARGV[0, 2] == %w[pane get]
      puts JSON.generate(result: { type: 'pane', pane: { pane_id: 'w9:p1' } })
    elsif ARGV[0, 2] == %w[agent get]
      puts JSON.generate(result: { agent: { agent: 'pi', pane_id: 'w9:p1', agent_status: 'idle' } })
    elsif ARGV[0, 2] == %w[pane read]
      puts "╭─╮\\n│ │\\n╰─╯"
    else
      puts [*session_argv, *ARGV].join(' ')
    end
  RUBY
  @stdout, @stderr, @status = run_riddim('watch-instructions', '--once')
end

Then('the watcher has retried the stored instruction') do
  assert @status.success?, @stderr
  assert herdr_invocations.any? { |call| call.include?('agent prompt') }, herdr_invocations.inspect
end

Then('the native command reaches Herdr without an inbox') do
  assert_equal "--session riddim agent prompt w9:p1 /help\n", @stdout
  refute File.exist?(current_inbox)
end

Given('the local-only inbox owner is retired') do
  @retired_inbox = current_inbox
  File.delete(scenario_record_path(@inbox_name))
end

Then('the retired owner is refused without an inbox') do
  assert_equal 1, @status.exitstatus
  refute File.exist?(@retired_inbox)
  assert_empty herdr_invocations
end

When('the local-only inbox owner is replaced by a new generation') do
  @old_inbox = current_inbox
  publish_record(@inbox_name, session: 'riddim',
                              overrides: { 'task_mode' => 'local-only', 'spawn_gen' => 's1767200001.4242.8' })
end

Then('the current inbox contains {string} and the old inbox contains {string}') do |fresh, old|
  assert_equal [fresh], inbox_bodies(current_inbox)
  assert_equal [old], inbox_bodies(@old_inbox)
end

Given('the generation inbox is a symlink') do
  File.symlink(new_temporary_directory, current_inbox)
end

Then('the unsafe inbox is refused before Herdr') do
  assert_equal 1, @status.exitstatus
  assert_empty herdr_invocations
end
