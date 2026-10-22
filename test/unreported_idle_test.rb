# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative 'support/notification_worker_fixture'
require_relative '../lib/riddim/notifications'

# rubocop:disable-next Metrics/ClassLength
class UnreportedIdleTest < Minitest::Test
  include NotificationWorkerFixture

  GEN = 's1767200000.4242.7'

  def setup
    @root = Dir.mktmpdir('riddim-idle-')
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

  def override(target, method, value)
    original = target.method(method)
    target.singleton_class.remove_method(method)
    target.define_singleton_method(method) { |*, **| value.respond_to?(:call) ? value.call : value }
    yield
  ensure
    target.singleton_class.remove_method(method)
    target.define_singleton_method(method, original)
  end

  def scan(status, at:, pane: 'Stable Pi prompt', wait: true)
    state = if status.respond_to?(:call)
              status
            else
              status == :unknown ? [:unreadable, nil] : [:alive, status]
            end
    override(Riddim::Herdr, :observe_pi_agent, state) do
      override(Riddim::Herdr, :pane_tail, pane) do
        override(Time, :now, Time.at(at)) { Riddim::Notifications.scan(wait: wait) }
      end
    end
  end

  def warm_up
    (100..125).step(5) { |at| scan('idle', at: at) }
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_original_live_idle_without_report_calls_for_attention_not_completion
    warm_up
    rows = scan('idle', at: 130)

    assert_equal ['unreported-idle'], rows.map(&:event)
    assert_equal ["worker.#{GEN}.0"], rows.map(&:id)
    assert_empty File.read(@status)
    assert_equal rows, scan('idle', at: 135)
    Riddim::Notifications.acknowledge(rows.first.id)

    assert_empty scan('idle', at: 140)
  end

  def test_scan_start_and_per_worker_clock_jitter_does_not_prevent_attention
    rows = nil
    [100, 105.1, 110.0, 115.2, 120.1, 125.3, 130.2].each do |at|
      rows = scan('idle', at: at)
    end

    assert_equal ['unreported-idle'], rows.map(&:event)
  end

  def test_existing_counted_only_candidate_remains_readable_after_upgrade
    warm_up
    path = File.join(@root, '.notifications', ".idle-worker-#{GEN}")
    row = JSON.parse(File.read(path))
    row.delete('last_observed')
    File.write(path, JSON.generate(row))

    assert_equal ['unreported-idle'], scan('idle', at: 130).map(&:event)
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_timed_out_backend_resets_stability_without_claiming_a_stop
    warm_up
    failure = -> { raise Riddim::Herdr::CaptureTimeout }
    scan(failure, at: 130)
    scan('idle', at: 135)

    assert_empty scan('idle', at: 140)
    assert_equal ['unreported-idle'], scan('idle', at: 145).map(&:event)
  end

  def test_launch_grace_and_rapid_manual_scans_do_not_create_an_idle_alert
    (100..129).each { |at| assert_empty scan('idle', at: at) }
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_busy_transition_resets_stability_before_a_later_idle_alert
    warm_up
    scan('working', at: 130)
    scan('idle', at: 135)

    assert_empty scan('idle', at: 140)
    assert_equal ['unreported-idle'], scan('idle', at: 145).map(&:event)
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_changed_pane_resets_stability
    warm_up
    scan('idle', at: 130, pane: 'Changed Pi prompt')

    assert_empty scan('idle', at: 135, pane: 'Changed Pi prompt')
    assert_equal ['unreported-idle'], scan('idle', at: 140, pane: 'Changed Pi prompt').map(&:event)
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_unverifiable_observation_resets_stability
    warm_up
    scan(:unknown, at: 130)
    scan('idle', at: 135)

    assert_empty scan('idle', at: 140)
    assert_equal ['unreported-idle'], scan('idle', at: 145).map(&:event)
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_empty_capture_and_sampling_gap_do_not_prove_stable_idle
    warm_up
    scan('idle', at: 130, pane: '')
    scan('idle', at: 135)

    assert_empty scan('idle', at: 140)
    assert_empty scan('idle', at: 200)
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_failed_capture_resets_idle_evidence_without_claiming_attention
    warm_up
    failure = -> { raise Errno::EIO }
    scan('idle', at: 130, pane: failure)
    scan('idle', at: 135)

    assert_empty scan('idle', at: 140)
    assert_equal ['unreported-idle'], scan('idle', at: 145).map(&:event)
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_clock_rollback_and_a_long_gap_require_fresh_observations
    warm_up

    assert_empty scan('idle', at: 90)
    assert_empty scan('idle', at: 200)
  end

  def test_acknowledged_idle_does_not_repeat_after_busy_or_unknown_transitions
    warm_up
    id = scan('idle', at: 130).first.id
    Riddim::Notifications.acknowledge(id)
    scan('working', at: 135)
    scan(:unknown, at: 140)

    (145..190).step(5) { |at| assert_empty scan('idle', at: at) }
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_launch_lock_cannot_accumulate_idle_evidence_or_bypass_grace
    File.open(Riddim::Ownership.lock_path('worker'), File::RDWR | File::CREAT, 0o600) do |lock|
      lock.flock(File::LOCK_EX)

      assert_empty scan('idle', at: 100, wait: false)
      assert_empty scan('idle', at: 135, wait: false)
    end
    (140..165).step(5) { |at| assert_empty scan('idle', at: at) }
    assert_equal ['unreported-idle'], scan('idle', at: 170).map(&:event)
  end

  def test_corrupt_candidate_fails_closed_instead_of_claiming_idle_attention
    warm_up
    File.write(File.join(@root, '.notifications', ".idle-worker-#{GEN}"), '{invalid')

    assert_raises(Riddim::Notifications::Error) { scan('idle', at: 130) }
  end

  def test_actionable_report_suppresses_idle_attention
    warm_up
    File.write(@status, "blocked [at=1]: waiting\n")

    assert_equal ['blocked'], scan('idle', at: 130).map(&:event)
  end

  def test_progress_report_does_not_suppress_idle_attention
    warm_up
    File.write(@status, "working [at=1]: investigating\n")

    assert_equal ['unreported-idle'], scan('idle', at: 130).map(&:event)
  end

  def test_replacement_generation_cannot_borrow_idle_evidence
    warm_up
    generation = 's1767200001.4242.8'
    write_notification_worker(@root, generation)
    File.write(File.join(@root, "worker.#{generation}.status"), '', perm: 0o600)

    assert_empty scan('idle', at: 130)
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_replacement_during_pane_read_cannot_publish_an_idle_candidate
    pane = lambda do
      write_notification_worker(@root, 's1767200001.4242.8')
      'Stable Pi prompt'
    end
    assert_raises(Riddim::Notifications::Error) { scan('idle', at: 100, pane: pane) }
    assert_empty Dir.glob(File.join(@root, '.notifications/.idle-*'))
  end
end
