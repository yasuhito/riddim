# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'endpoint_test'
require_relative '../lib/riddim/instruction_watcher'

# rubocop:disable-next Metrics/ClassLength
class InstructionWatcherTest < Minitest::Test
  include EndpointStateEnv

  class FakeHerdr
    attr_accessor :busy, :composer, :state, :held_line
    attr_reader :bells

    def initialize
      @busy = :idle
      @state = :alive
      @composer = :empty
      @bells = []
    end

    def busy_state(_pane, session:)
      raise 'wrong session' unless session == 'lab'

      busy
    end

    def agent_state(_pane, session:)
      raise 'wrong session' unless session == 'lab'

      state
    end

    def composer_state(_pane, session:)
      raise 'wrong session' unless session == 'lab'

      composer
    end

    def composer_holds_line?(_pane, _line, session:)
      raise 'wrong session' unless session == 'lab'

      held_line
    end

    def send_key(pane, key, session:)
      @bells << [pane, key, session]
      @held_line = false
    end

    def notify?(pane, bell, session:)
      @bells << [pane, bell, session]
      true
    end
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  def test_notification_child_keeps_ownership_lock_if_watcher_exits
    with_started_record('task_mode' => 'local-only') do
      herdr = FakeHerdr.new
      def herdr.notify?(_pane, _bell, session:)
        raise 'wrong session' unless session == 'lab'

        @child = Process.spawn(RbConfig.ruby, '-e', 'sleep 10', close_others: false)
        true
      end
      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.utime(Time.at(100), Time.at(100), record)
      poll(190, herdr)
      lock_path = Riddim::Ownership.lock_path('worker')

      File.open(lock_path, File::RDWR | File::NOFOLLOW) do |lock|
        refute lock.flock(File::LOCK_EX | File::LOCK_NB)
      end
    ensure
      if (child = herdr.instance_variable_get(:@child))
        Process.kill('TERM', child)
        Process.wait(child)
      end
    end
  end

  def test_grace_spacing_oldest_and_acknowledgement_survive_restart
    with_started_record('task_mode' => 'local-only') do
      herdr = FakeHerdr.new
      first = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      second = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'second')
      File.utime(Time.at(100), Time.at(100), first)
      File.utime(Time.at(101), Time.at(101), second)

      poll(189, herdr)

      assert_empty herdr.bells
      poll(190, herdr)

      assert_equal 1, herdr.bells.size
      poll(200, herdr)

      assert_equal 1, herdr.bells.size
      herdr.busy = :busy
      poll(280, herdr)

      assert_equal 1, herdr.bells.size
      herdr.busy = :idle
      poll(280, herdr)

      assert_equal 2, herdr.bells.size
      File.rename(first, File.join(File.dirname(first), 'handled', File.basename(first)))
      poll(281, herdr)

      assert_equal 3, herdr.bells.size
      File.rename(second, File.join(File.dirname(second), 'handled', File.basename(second)))
      poll(400, herdr)

      assert_equal 3, herdr.bells.size
    end
  end

  def test_pending_composer_is_never_submitted_and_replaced_generation_is_not_rung
    with_started_record('task_mode' => 'local-only') do |path|
      herdr = FakeHerdr.new
      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.utime(Time.at(100), Time.at(100), record)
      herdr.composer = :pending
      poll(200, herdr)

      assert_empty herdr.bells
      File.write(path, Riddim::Ownership.serialize(ENDPOINT_FIELDS.merge('task_mode' => 'local-only',
                                                                         'spawn_gen' => 's1767200001.4242.8')))
      herdr.composer = :empty
      poll(300, herdr)

      assert_empty herdr.bells
    end
  end

  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
  def test_only_one_observer_can_hold_the_home_lock
    with_started_record('task_mode' => 'local-only') do
      lock = File.join(Riddim::Ownership.state_dir, '.instruction-watcher.lock')
      File.open(lock, File::RDWR | File::CREAT, 0o600) do |owner|
        owner.flock(File::LOCK_EX)

        refute Riddim::InstructionWatcher.run(once: true)
      end
      assert Riddim::InstructionWatcher.run(once: true)
    end
  end

  def test_exhausted_budget_fails_instead_of_claiming_healthy_observation
    with_started_record('task_mode' => 'local-only') do
      herdr = FakeHerdr.new
      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.utime(Time.at(100), Time.at(100), record)
      [190, 280, 370].each { |time| poll(time, herdr) }

      assert_raises(Riddim::InstructionInbox::Error) { poll(460, herdr) }
    end
  end

  def test_own_pending_doorbell_is_submitted_without_retyping
    with_started_record('task_mode' => 'local-only') do
      herdr = FakeHerdr.new
      herdr.composer = :pending
      herdr.held_line = true
      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.utime(Time.at(100), Time.at(100), record)
      poll(190, herdr)

      assert_equal [['w9:p2', 'Enter', 'lab']], herdr.bells
    end
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def test_pending_doorbell_needs_verified_idle_before_each_enter
    endpoint = Riddim::Ownership::Endpoint::Resolved.new('lab', 'w9', 'w9:t1', 'w9:p2')
    herdr = FakeHerdr.new
    herdr.held_line = true
    herdr.busy = :unknown

    refute Riddim::Send.submit_existing_doorbell?(herdr, endpoint, 'bell')
    assert_empty herdr.bells

    def herdr.busy_state(_pane, session:)
      raise 'wrong session' unless session == 'lab'

      @busy_reads ||= 0
      @busy_reads += 1
      @busy_reads == 1 ? :idle : :unknown
    end

    def herdr.send_key(pane, key, session:)
      @bells << [pane, key, session]
    end

    refute Riddim::Send.submit_existing_doorbell?(herdr, endpoint, 'bell')
    assert_equal [['w9:p2', 'Enter', 'lab']], herdr.bells
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def test_invalid_retry_state_fails_without_resetting_attempts
    with_started_record('task_mode' => 'local-only') do
      herdr = FakeHerdr.new
      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.utime(Time.at(100), Time.at(100), record)
      poll(190, herdr)
      state = File.join(File.dirname(record), '.ring-state')

      ["bad\n", "#{File.basename(record)}\t1\t190\nextra\n"].each do |invalid|
        File.write(state, invalid)
        assert_raises(Riddim::InstructionInbox::Error) { poll(280, herdr) }
      end
      assert_equal 1, herdr.bells.size
    end
  end

  def test_missing_retry_state_fails_without_resetting_attempts
    with_started_record('task_mode' => 'local-only') do
      herdr = FakeHerdr.new
      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.utime(Time.at(100), Time.at(100), record)
      poll(190, herdr)
      File.delete(File.join(File.dirname(record), '.ring-state'))

      assert_raises(Riddim::InstructionInbox::Error) { poll(280, herdr) }
      assert_equal 1, herdr.bells.size
    end
  end

  def test_missing_unhandled_record_requires_a_receipt
    with_started_record('task_mode' => 'local-only') do
      herdr = FakeHerdr.new
      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.utime(Time.at(100), Time.at(100), record)
      poll(190, herdr)
      File.delete(record)

      assert_raises(Riddim::InstructionInbox::Error) { poll(280, herdr) }
      assert_equal 1, herdr.bells.size
    end
  end

  def test_record_lost_before_first_scan_requires_a_receipt
    with_started_record('task_mode' => 'local-only') do
      herdr = FakeHerdr.new
      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.delete(record)

      assert_raises(Riddim::InstructionInbox::Error) { poll(190, herdr) }
      assert_empty herdr.bells
    end
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def test_missing_oldest_record_does_not_advance_to_next_pending_instruction
    with_started_record('task_mode' => 'local-only') do
      herdr = FakeHerdr.new
      first = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      second = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'second')
      File.utime(Time.at(100), Time.at(100), first)
      File.utime(Time.at(101), Time.at(101), second)
      poll(190, herdr)
      File.delete(first)

      assert_raises(Riddim::InstructionInbox::Error) { poll(280, herdr) }
      assert_equal 1, herdr.bells.size
    end
  end

  # rubocop:disable-next Metrics/MethodLength
  def test_disappearance_during_backend_probe_requires_a_receipt
    with_started_record('task_mode' => 'local-only') do
      herdr = FakeHerdr.new
      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.utime(Time.at(100), Time.at(100), record)
      herdr.define_singleton_method(:busy_state) do |_pane, session:|
        raise 'wrong session' unless session == 'lab'

        File.delete(record)
        :idle
      end

      assert_raises(Riddim::InstructionInbox::Error) { poll(190, herdr) }
      assert_empty herdr.bells
    end
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def test_handling_during_backend_probe_stops_notification
    with_started_record('task_mode' => 'local-only') do
      herdr = FakeHerdr.new
      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.utime(Time.at(100), Time.at(100), record)
      herdr.define_singleton_method(:busy_state) do |_pane, session:|
        raise 'wrong session' unless session == 'lab'

        File.rename(record, File.join(File.dirname(record), 'handled', File.basename(record)))
        :idle
      end

      assert poll(190, herdr)
      assert_empty herdr.bells
    end
  end

  def test_pending_inbox_fails_when_owner_mode_is_lost
    with_started_record('task_mode' => 'local-only') do |path|
      herdr = FakeHerdr.new
      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.utime(Time.at(100), Time.at(100), record)
      File.write(path, Riddim::Ownership.serialize(ENDPOINT_FIELDS))

      assert_raises(Riddim::InstructionInbox::Error) { poll(190, herdr) }
      assert_empty herdr.bells
    end
  end

  def test_unverifiable_owner_with_pending_instruction_fails
    with_started_record('task_mode' => 'local-only') do |path|
      herdr = FakeHerdr.new
      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.utime(Time.at(100), Time.at(100), record)
      File.write(path, "invalid\n")

      assert_raises(Riddim::InstructionInbox::Error) { poll(190, herdr) }
      assert_empty herdr.bells
    end
  end

  def test_missing_owner_with_pending_instruction_fails
    with_started_record('task_mode' => 'local-only') do |path|
      herdr = FakeHerdr.new
      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.delete(path)

      assert_raises(Riddim::InstructionInbox::Error) { poll(190, herdr) }
      assert File.file?(record)
      assert_empty herdr.bells
    end
  end

  # rubocop:disable-next Metrics/MethodLength
  def test_unverifiable_pending_inbox_and_record_fail
    with_started_record('task_mode' => 'local-only') do
      herdr = FakeHerdr.new
      dir = Riddim::InstructionInbox.path('worker', ENDPOINT_FIELDS.fetch('spawn_gen'))
      File.symlink('missing', dir)
      assert_raises(Riddim::InstructionInbox::Error) { poll(190, herdr) }
      File.delete(dir)

      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.delete(record)
      File.symlink('missing', record)
      assert_raises(Riddim::InstructionInbox::Error) { poll(190, herdr) }
      assert_empty herdr.bells
    end
  end

  def test_unverifiable_activity_fails_instead_of_appearing_healthy
    with_started_record('task_mode' => 'local-only') do
      herdr = FakeHerdr.new
      herdr.busy = :unknown
      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.utime(Time.at(100), Time.at(100), record)

      assert_raises(Riddim::InstructionInbox::Error) { poll(190, herdr) }
    end
  end

  def test_dead_endpoint_fails_instead_of_claiming_healthy_observation
    with_started_record('task_mode' => 'local-only') do
      herdr = FakeHerdr.new
      herdr.state = :dead
      record = Riddim::InstructionInbox.enqueue('worker', ENDPOINT_FIELDS.fetch('spawn_gen'), 'first')
      File.utime(Time.at(100), Time.at(100), record)

      assert_raises(Riddim::InstructionInbox::Error) { poll(190, herdr) }
    end
  end

  # rubocop:enable Minitest/MultipleAssertions

  private

  def poll(time, herdr)
    Riddim::InstructionWatcher.run(once: true, now: -> { time }, herdr: herdr)
  end
end
