# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative 'support/notification_worker_fixture'
require_relative '../lib/riddim/notifications'
require_relative '../lib/riddim/herdr'

class UnreportedStopTest < Minitest::Test
  include NotificationWorkerFixture

  GEN = 's1767200000.4242.7'

  def setup
    @root = Dir.mktmpdir('riddim-stop-')
    @previous = ENV.fetch('RIDDIM_STATE_DIR', nil)
    ENV['RIDDIM_STATE_DIR'] = @root
    write_notification_worker(@root, GEN)
    @status = File.join(@root, "worker.#{GEN}.status")
    File.write(@status, '', perm: 0o600)
  end

  def teardown
    ENV['RIDDIM_STATE_DIR'] = @previous
    FileUtils.remove_entry(@root)
  end

  def scan(state)
    original = Riddim::Herdr.method(:observe_pi_agent)
    Riddim::Herdr.singleton_class.remove_method(:observe_pi_agent)
    Riddim::Herdr.define_singleton_method(:observe_pi_agent) do |*, **|
      [state.respond_to?(:call) ? state.call : state, nil]
    end
    Riddim::Notifications.scan
  ensure
    Riddim::Herdr.singleton_class.remove_method(:observe_pi_agent)
    Riddim::Herdr.define_singleton_method(:observe_pi_agent, original)
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_stop_is_one_generation_bound_observation_not_a_worker_report
    assert_empty scan(:alive)
    rows = scan(:dead)

    assert_equal ["worker.#{GEN}.0"], rows.map(&:id)
    assert_equal ['unreported-stop'], rows.map(&:event)
    assert_equal rows, scan(:dead)
    assert_empty File.read(@status)
    Riddim::Notifications.acknowledge(rows.first.id)

    assert_empty scan(:missing)
  end

  def test_launching_or_unverifiable_worker_is_not_stopped
    %i[dead missing unreadable].each { |state| assert_empty scan(state) }
  end

  def test_live_and_unverifiable_states_do_not_prove_completion
    scan(:alive)

    %i[alive unreadable].each { |state| assert_empty scan(state) }
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_replacement_during_probe_cannot_publish_liveness_for_either_generation
    probe = lambda do
      write_notification_worker(@root, 's1767200001.4242.8')
      :alive
    end
    assert_raises(Riddim::Notifications::Error) { scan(probe) }
    assert_empty Dir.glob(File.join(@root, '.notifications/.alive-*'))
  end

  def test_actionable_report_prevents_unreported_stop
    scan(:alive)
    File.write(@status, "blocked [at=1]: waiting\n")

    assert_equal ['blocked'], scan(:dead).map(&:event)
  end

  def test_routine_progress_does_not_hide_a_stop
    scan(:alive)
    File.write(@status, "working [at=1]: still investigating\n")

    assert_equal ['unreported-stop'], scan(:dead).map(&:event)
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_replacement_requires_its_own_liveness_and_gets_its_own_alert
    scan(:alive)
    first = scan(:dead).first
    Riddim::Notifications.acknowledge(first.id)
    generation = 's1767200001.4242.8'
    write_notification_worker(@root, generation)
    File.write(File.join(@root, "worker.#{generation}.status"), '', perm: 0o600)

    assert_empty scan(:dead)
    scan(:alive)

    assert_equal ["worker.#{generation}.0"], scan(:missing).map(&:id)
  end
end
