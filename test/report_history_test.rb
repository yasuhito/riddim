# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'open3'
require 'tmpdir'
require 'json'
require_relative 'support/notification_worker_fixture'
require_relative '../lib/riddim/result'

class ReportHistoryTest < Minitest::Test
  include NotificationWorkerFixture

  CLI = File.expand_path('../bin/riddim', __dir__)
  GEN = 's1767200000.4242.7'

  def setup
    @root = Dir.mktmpdir('riddim-history-')
    File.chmod(0o700, @root)
    write_notification_worker(@root, GEN)
    @path = File.join(@root, "worker.#{GEN}.status")
    File.write(@path, '', perm: 0o600)
    bin = File.join(@root, 'bin')
    Dir.mkdir(bin)
    File.write(File.join(bin, 'herdr'), "#!/bin/sh\nexit 1\n", perm: 0o700)
    @env = { 'RIDDIM_STATE_DIR' => @root, 'RIDDIM_ACTOR' => nil, 'PATH' => "#{bin}:#{ENV.fetch('PATH')}" }
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def cli(*args)
    out, err, status = Bundler.with_unbundled_env { Open3.capture3(@env, CLI, *args) }

    assert_predicate status, :success?, "#{args.first}: #{out} #{err}"
    out
  end

  def report(event)
    cli('report', 'worker', '--generation', GEN, event)
  end

  def rejected(*)
    out, err, status = Bundler.with_unbundled_env { Open3.capture3(@env, CLI, *) }

    refute_predicate status, :success?, "#{out} #{err}"
    err
  end

  def long_history
    "working [at=1]: #{'x' * 950}\n" * 80
  end

  # Even a malformed suffix beyond the old whole-file cap must fail closed.
  # rubocop:disable-next Minitest/MultipleAssertions
  def test_malformed_history_is_rejected_without_appending_or_presenting
    ['done [at=2]: no newline', "bogus\n", "done [at=2]: bad\xFF\n".b,
     "done [at=2]: #{'x' * 65_536}\n"].each do |suffix|
      bytes = long_history + suffix
      File.binwrite(@path, bytes)
      rejected('report', 'worker', '--generation', GEN, 'done [at=3]: refused')
      rejected('notifications', 'scan')

      assert_equal bytes, File.binread(@path)
      assert_empty Dir[File.join(@root, '.notifications', '*.json')]
    end
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_per_record_limit_does_not_limit_whole_history
    record = "working [at=1]: #{'x' * (65_536 - 17)}\n"

    assert_equal 65_536, record.bytesize
    assert_equal 2, Riddim::Result.parse_events(record * 2).events.size
    error = assert_raises(Riddim::Result::Error) { Riddim::Result.parse_events(record.sub("\n", "x\n")) }

    assert_includes error.message, 'status event is oversized'
  end

  # A lost cursor replays the same ID, never an invented sequence. Mutating
  # even the old prefix beyond 64 KiB must be detected on a subsequent scan.
  # rubocop:disable-next Metrics/AbcSize, Minitest/MultipleAssertions
  def test_long_history_cursor_replay_and_prefix_verification
    File.write(@path, long_history)
    report('done [at=2]: finished')
    rows = JSON.parse(cli('notifications', 'scan'))

    assert_equal(["worker.#{GEN}.81"], rows.map { |row| row.fetch('id') })
    cursor = File.join(@root, '.notifications', ".cursor-worker-#{GEN}")
    File.unlink(cursor)

    assert_equal rows, JSON.parse(cli('notifications', 'scan'))
    File.open(@path, 'r+b') { |file| file.write('working [at=2]') }

    assert_includes rejected('notifications', 'scan'), 'status changed before classified position'
  end

  # Exercise actual appends, not just an oversized reader fixture. An answer
  # must preserve every byte and close only its own key, even past 64 KiB.
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  def test_long_history_report_answer_result_scan_and_ack
    report('needs-decision [at=1] [key=one]: choose one')
    report('blocked [at=2] [key=two]: choose two')
    report('failed [at=3]: retained failure')
    75.times { |index| report("working [at=#{index + 4}]: #{'x' * 950}") }
    original = File.binread(@path)

    assert_operator original.bytesize, :>, 65_536
    cli('send', 'worker', '--resolve-key', 'one', 'the answer')

    assert_equal original, File.binread(@path).byteslice(0, original.bytesize)
    assert_equal 1, Dir[File.join(@root, "worker.#{GEN}.inbox", '*.msg')].size
    report('done [at=100]: finished')
    result = cli('result', 'worker')

    assert_includes result, 'two (blocked)'
    refute_includes result, 'one (needs-decision)'
    assert_includes result, 'failed history remains a gate'
    ids = JSON.parse(cli('notifications', 'scan')).map { |row| row.fetch('id') }

    assert_includes ids, "worker.#{GEN}.80"
    ids.each { |id| cli('notifications', 'ack', id) }

    assert_empty JSON.parse(cli('notifications', 'scan'))
    assert_empty JSON.parse(cli('notifications', 'scan'))
  end
end
