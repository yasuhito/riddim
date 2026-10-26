# frozen_string_literal: true

require 'minitest/autorun'
require 'open3'
require 'tmpdir'
require_relative '../lib/riddim/task_brief'
require_relative '../lib/riddim/profile'

class WorkerWaitingPromptTest < Minitest::Test
  RULES = ['# Bounded waiting', 'one foreground command', '900-second outer budget',
           'watcher/retry bans take precedence', 'timeout alone is neither test/CI failure nor a human decision',
           'preserve evidence outside the checkout', 'Never assume cancellation or duplicate a mutation',
           'Still-pending checks remain pending', 'end the turn and await the instruction notification',
           'Delivery contract: mode=local-only',
           'If you report a blocker or decision, stop until the supervisor answers it.'].freeze

  def test_staged_pi_receives_waiting_rules_with_local_only_gates_and_the_unchanged_task
    task = "Fix the build.\nKeep test deadlines unchanged.\n"
    prompt = Riddim::TaskBrief.render('worker', task, status_path: '/private/worker.status', spawn_gen: 's1.2.3')
    delivered, status = deliver(prompt)

    assert_equal [true, prompt.chomp, [], true],
                 [status.success?, delivered, RULES.reject { |rule| delivered.include?(rule) },
                  delivered.end_with?("# Human's task\n#{task.chomp}")]
  end

  def deliver(prompt)
    Dir.mktmpdir do |dir|
      brief = Riddim::TaskBrief::Brief.new(File.join(dir, 'worker.brief'), prompt)
      File.write(brief.path, prompt)
      pi = File.join(dir, 'pi')
      File.write(pi, "#!/bin/sh\nprintf '%s' \"$5\"\n")
      File.chmod(0o700, pi)
      run_launch(brief, pi)
    end
  end

  def run_launch(brief, executable)
    old_path = ENV.fetch('PATH')
    ENV['PATH'] = "#{File.dirname(executable)}:#{old_path}"
    source = Riddim::TaskBrief.launch_source(brief, Riddim::AgentProfile.parse('pi safe max'))
    output, error, status = Open3.capture3('/bin/sh', '-c', source)
    raise error unless status.success?

    [output, status]
  ensure
    ENV['PATH'] = old_path
  end
end
