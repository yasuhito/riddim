# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../lib/riddim/schedules/cli'
require_relative '../lib/riddim/notifications'

# Clock seams are Ruby arguments, never production environment overrides.
# rubocop:disable-next Metrics/ClassLength, Minitest/MultipleAssertions
class SchedulesTest < Minitest::Test
  S = Riddim::Schedules
  START = 1_800_000_000
  SESSION = 'explicit-pi-session'

  def setup
    @root = Dir.mktmpdir('riddim-schedules-')
    @previous = ENV.to_h.slice('RIDDIM_STATE_DIR', 'RIDDIM_ACTOR')
    ENV['RIDDIM_STATE_DIR'] = @root
    ENV.delete('RIDDIM_ACTOR')
    File.write(File.join(@root, S::Store::WATCHER), '', perm: 0o600)
    @prompt = File.join(@root, 'prompt.txt')
    File.write(@prompt, 'authorized prompt')
  end

  def teardown
    %w[RIDDIM_STATE_DIR RIDDIM_ACTOR].each { |key| ENV.delete(key) }
    ENV.update(@previous)
    FileUtils.remove_entry(@root)
  end

  def create(every: nil, at: START)
    S.create(session: SESSION, prompt_file: @prompt, at: Time.at(at).utc.iso8601.gsub('Z', '+00:00'), every: every)
  end

  def stored
    JSON.parse(File.read(File.join(@root, S::Store::FILE)))
  end

  def corrupt
    value = stored
    yield value
    File.write(File.join(@root, S::Store::FILE), JSON.generate(value))
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def test_one_shot_has_durable_pending_before_completion_and_no_implicit_ack
    row = create

    assert_empty S.pending(session: SESSION, now: START - 1)
    ids = S.pending(session: SESSION, now: START)

    assert_equal ["scheduled.#{row['id']}.1"], ids
    assert_nil S.list.first['next_at']
    assert_equal ids, S.pending(session: SESSION, now: START + 10_000)
    assert_raises(S::Error) { S.acknowledge(ids.first, session: SESSION) }
    S.offer(ids.first, session: SESSION)

    assert_equal 'pending', S.list.first['occurrence']['status']
    2.times { assert_equal({ id: ids.first, status: 'handled' }, S.acknowledge(ids.first, session: SESSION)) }
    assert_empty S.pending(session: SESSION, now: START + 10_001)
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def test_fixed_cadence_catches_up_once_and_coalesces_with_stable_identity
    create(every: '30m')
    ids = S.pending(session: SESSION, now: START + 10_800)

    assert_equal START + 12_600, S.list.first['next_at']
    assert_equal ids, S.pending(session: SESSION, now: START + 12_601)
    assert_equal START, S.list.first['occurrence']['due_at']
    assert_equal START + 14_400, S.list.first['next_at']
    S.offer(ids.first, session: SESSION)
    S.acknowledge(ids.first, session: SESSION)

    assert_empty S.pending(session: SESSION, now: START + 12_602)
    later = S.pending(session: SESSION, now: START + 14_400).first

    assert_equal ids.first.sub(/\.1$/, '.2'), later
    assert_equal({ id: ids.first, status: 'handled' }, S.acknowledge(ids.first, session: SESSION))
  end

  # rubocop:disable-next Metrics/AbcSize
  def test_unmatched_and_unknown_sessions_never_offer_or_ack
    create

    assert_empty S.pending(session: nil, now: START)
    assert_empty S.pending(session: 'unrelated', now: START)
    id = S.list.first['occurrence']['id']

    assert_raises(S::Error) { S.offer(id, session: 'unrelated') }
    assert_raises(S::Error) { S.acknowledge(id, session: 'unrelated') }
    assert_raises(S::Error) { S.offer(id, session: nil) }
    assert_equal [id], S.pending(session: SESSION, now: START + 1)
  end

  # rubocop:disable-next Metrics/AbcSize
  def test_cancel_before_due_or_before_offer_prevents_any_future_dispatch
    first = create(every: '1s')
    S.cancel(first['id'])

    assert_empty S.pending(session: SESSION, now: START + 10)
    second = create
    id = S.pending(session: SESSION, now: START).first
    S.cancel(second['id'])

    assert_nil S.offer(id, session: SESSION)
    assert_raises(S::Error) { S.acknowledge(id, session: SESSION) }
    assert_empty S.pending(session: SESSION, now: START + 100)
  end

  # rubocop:disable-next Metrics/AbcSize
  def test_cancel_after_offer_is_not_retraction_and_still_allows_explicit_handling_ack
    row = create(every: '1s')
    id = S.pending(session: SESSION, now: START).first
    offer = S.offer(id, session: SESSION)
    S.cancel(row['id'])

    assert_equal 'authorized prompt', offer[:prompt]
    assert_nil S.offer(id, session: SESSION)
    assert_equal 'cancelled', S.list.first['occurrence']['status']
    S.acknowledge(id, session: SESSION)

    assert_equal 'handled', S.list.first['occurrence']['status']
    assert_empty S.pending(session: SESSION, now: START + 100)
  end

  # rubocop:disable-next Metrics/AbcSize
  def test_worker_and_unknown_actors_cannot_read_create_scan_cancel_or_ack
    row = create
    %w[branch unknown].each do |actor|
      ENV['RIDDIM_ACTOR'] = actor

      [-> { create }, -> { S.list }, -> { S.cancel(row['id']) }, -> { S.scan(session: SESSION) },
       -> { S.pending(session: SESSION) }, -> { S.acknowledge('bad', session: SESSION) }].each do |operation|
        assert_raises(S::Error, &operation)
      end
    end
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def test_rejects_invalid_datetime_interval_prompt_and_duplicate_options
    invalid_dates = ['2027-02-30T00:00:00+00:00', '2027-01-01T24:00:00+00:00',
                     '2027-01-01T00:00:60+00:00', '2027-01-01T00:00:00', '2027-01-01T00:00:00Z',
                     '2027-01-01T00:00:00+14:01', '2101-01-01T00:00:00+00:00']

    invalid_dates.each { |value| assert_raises(S::Error) { S::Validation.datetime(value) } }
    %w[0m -1s 1.5h 366d 999999999999999999h daily 30m;id].each do |value|
      assert_raises(S::Error) { S::Validation.interval(value) }
    end
    ["\0", '', ' ', "\xFF".dup.force_encoding(Encoding::UTF_8), 'x' * 16_385].each do |value|
      File.binwrite(@prompt, value)

      assert_raises(S::Error) { create }
    end
    assert_raises(S::CLI::Usage) { S::CLI.run(%w[create --session a --session b --prompt-file path --every 1s]) }
    assert_raises(S::Error) { S::CLI.run(%w[create --session a --prompt-file path]) }
  end

  def test_bounds_overflow_sequence_and_interval_only_creation
    row = S.create(session: SESSION, prompt_file: @prompt, every: '30m', now: START)

    assert_equal START + 1800, row['at']
    assert_raises(S::Error) do
      S.create(session: SESSION, prompt_file: @prompt, every: '1s', now: S::Validation::MAX_TIME)
    end
    create(every: '1d', at: S::Validation::MAX_TIME)
    before = File.read(File.join(@root, S::Store::FILE))

    assert_raises(S::Error) { S.pending(session: SESSION, now: S::Validation::MAX_TIME) }
    assert_equal before, File.read(File.join(@root, S::Store::FILE))
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def test_corrupt_state_duplicate_keys_symlinks_and_binding_changes_fail_closed
    create
    original = File.read(File.join(@root, S::Store::FILE))
    [->(data) { data['schedules'][0]['every'] = -1 },
     ->(data) { data['schedules'][0]['next_at'] = 'tomorrow' },
     ->(data) { data['schedules'][0]['occurrence'] = {} },
     ->(data) { data['schema'] = 'other' },
     ->(data) { data['home'] = '0:0' }].each do |mutation|
      corrupt(&mutation)

      assert_raises(S::Error) { S.list }
      File.write(File.join(@root, S::Store::FILE), original)
    end
    File.write(File.join(@root, S::Store::FILE), original.sub('"schema":', '"schema":"duplicate","schema":'))

    assert_raises(S::Error) { S.list }
    File.write(File.join(@root, S::Store::FILE), original)
    lock = File.join(@root, S::Store::WATCHER)
    File.rename(lock, "#{lock}.old")
    File.write(lock, '', perm: 0o600)

    assert_raises(S::Error) { S.list }
  end

  # rubocop:disable-next Metrics/AbcSize
  def test_wrong_original_source_never_offers_and_replaced_home_cannot_read_copied_store
    create
    id = S.pending(session: SESSION, now: START).first

    assert_raises(S::Error) { S.offer(id, session: SESSION, expected: %w[0:0 0:0]) }
    original = "#{@root}.old"
    File.rename(@root, original)
    Dir.mkdir(@root, 0o700)
    FileUtils.cp_r(Dir.glob(File.join(original, '.*')).reject { |path| %w[. ..].include?(File.basename(path)) }, @root)

    assert_raises(S::Error) { S.list }
  ensure
    FileUtils.remove_entry(original) if original && File.exist?(original)
  end

  def test_schedule_and_worker_notification_ids_and_acknowledgements_are_disjoint
    create
    id = S.pending(session: SESSION, now: START).first

    assert_empty Riddim::Notifications.scan(observe_activity: false)
    assert_raises(Riddim::Notifications::Error) { Riddim::Notifications.acknowledge(id) }
    assert_raises(S::Error) { S.acknowledge('worker.s1800000000.1.1.0', session: SESSION) }
    assert_equal 'pending', S.list.first['occurrence']['status']
  end

  def test_missing_previously_created_store_is_not_silently_empty_or_reinitialized
    create
    file = File.join(@root, S::Store::FILE)
    File.unlink(file)

    assert_raises(S::Error) { S.list }
    assert_raises(S::Error) { S.pending(session: SESSION, now: START) }
    assert_raises(S::Error) { create }
    refute_path_exists file
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def test_interrupted_atomic_publication_preserves_due_one_shot_for_replay
    row = create
    before = File.read(File.join(@root, S::Store::FILE))

    pid = fork do
      interruption = Module.new do
        def replace(*)
          Process.exit!(42) # Simulate process loss immediately before atomic publication.
        end
      end
      S::Store.singleton_class.prepend(interruption)
      S.pending(session: SESSION, now: START)
      exit! 1
    end

    assert_equal 42, Process.wait2(pid).last.exitstatus

    assert_equal before, File.read(File.join(@root, S::Store::FILE))
    assert_equal ["scheduled.#{row['id']}.1"], S.pending(session: SESSION, now: START)
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def test_symbolic_or_nonregular_state_and_prompt_files_are_refused
    row = create
    file = File.join(@root, S::Store::FILE)
    File.rename(file, "#{file}.saved")
    File.symlink("#{file}.saved", file)

    assert_raises(Errno::ELOOP) { S.list }
    File.unlink(file)
    File.mkfifo(file, 0o600)

    assert_raises(Riddim::Result::Error) { S.list }
    File.unlink(file)
    File.rename("#{file}.saved", file)
    File.rename(@prompt, "#{@prompt}.saved")
    File.symlink("#{@prompt}.saved", @prompt)

    assert_raises(Errno::ELOOP) { create }
    assert_equal row['id'], S.list.first['id']
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Metrics/CyclomaticComplexity
  def test_concurrent_create_scan_offer_and_ack_preserve_all_updates_and_single_identity
    children = 6.times.map do
      fork do
        3.times { create(every: '1m') }
        S.pending(session: SESSION, now: START + 100)
        exit! 0
      end
    end

    children.each { |pid| assert_predicate Process.wait2(pid).last, :success? }
    rows = S.list

    assert_equal 18, rows.size
    assert_equal 18, rows.map { |row| row['id'] }.uniq.size
    ids = S.pending(session: SESSION, now: START + 100)
    children = 4.times.map do
      fork do
        S.pending(session: SESSION, now: START + 200).each do |id|
          S.offer(id, session: SESSION)
          S.acknowledge(id, session: SESSION)
        end
        exit! 0
      end
    end

    children.each { |pid| assert_predicate Process.wait2(pid).last, :success? }

    assert_empty S.pending(session: SESSION, now: START + 200)
    assert_equal ids.sort, S.list.map { |row| row['occurrence']['id'] }.sort
  end
end
