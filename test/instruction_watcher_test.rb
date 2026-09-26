# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'endpoint_test'
require_relative '../lib/riddim/instruction_watcher'

class InstructionWatcherTest < Minitest::Test
  include EndpointStateEnv

  class FakeHerdr
    attr_accessor :busy, :composer, :state
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

    def notify?(pane, bell, session:)
      @bells << [pane, bell, session]
      true
    end
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
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
