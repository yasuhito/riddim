# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'fileutils'
require 'json'
require 'open3'
require 'timeout'
require 'tmpdir'
require_relative 'support/notification_worker_fixture'

# Real CLI acknowledgement and listing processes, paused at the interleaving
# where an unlocked reader listed an intent marker that acknowledgement then
# withdrew. The watcher scan uses the same pending listing.
class NotificationAckRaceTest < Minitest::Test
  include NotificationWorkerFixture

  CLI = File.expand_path('../bin/riddim', __dir__)
  GEN = 's1767200000.4242.7'
  ID = "worker.#{GEN}.1".freeze

  def setup
    @root = Dir.mktmpdir('riddim-ack-race-')
    @state = File.join(@root, 'state')
    @pauses = File.join(@root, 'pauses')
    FileUtils.mkdir_p([@state, @pauses])
    write_notification_worker(@state, GEN)
    File.write(File.join(@state, "worker.#{GEN}.status"), "done [at=1]: claim\n", perm: 0o600)
    _out, error, status = riddim('notifications', 'scan', backend: 'notification_stop_backend')
    raise "presentation failed: #{error}" unless status.success?
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def riddim(*, backend: nil, role: nil, spawn: false)
    env = { 'RIDDIM_STATE_DIR' => @state, 'RIDDIM_ACTOR' => nil, 'RIDDIM_TEST_INTERLEAVE' => @pauses }
    if backend || role
      env['RUBYOPT'] = "-r#{File.expand_path("support/#{backend || 'notification_ack_interleave'}", __dir__)}"
    end
    env['RIDDIM_TEST_INTERLEAVE_ROLE'] = role if role
    Bundler.with_unbundled_env do
      spawn ? Open3.popen3(env, CLI, *) : Open3.capture3(env, CLI, *)
    end
  end

  def await(*names)
    Timeout.timeout(10) do
      loop do
        found = names.find { |name| File.exist?(File.join(@pauses, name)) }
        return found if found

        sleep 0.01
      end
    end
  end

  def release(name)
    File.write(File.join(@pauses, "release-#{name}"), '')
  end

  def finish(process)
    input, output, error, wait = process
    input.close
    [output.read, error.read, wait.value].tap { [output, error].each(&:close) }
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  def test_listing_during_acknowledgement_never_reads_a_withdrawn_intent
    acknowledger = riddim('notifications', 'ack', ID, role: 'acknowledger', spawn: true)
    await('acknowledger')

    assert_path_exists File.join(@state, '.notifications', ".ack-pending-#{ID}.json")
    reader = riddim('notifications', role: 'reader', spawn: true)
    await('reader', 'reader-locking')
    release('acknowledger')
    ack_out, ack_error, ack_status = finish(acknowledger)

    assert_predicate ack_status, :success?, ack_error
    assert_equal ID, JSON.parse(ack_out).fetch('id')
    release('reader')
    out, error, status = finish(reader)

    assert_predicate status, :success?, error
    assert_empty JSON.parse(out)
  end
end
