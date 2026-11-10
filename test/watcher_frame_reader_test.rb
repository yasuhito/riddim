# frozen_string_literal: true

require 'minitest/autorun'
require 'stringio'
require_relative 'support/watcher_frame_reader'

class WatcherFrameReaderTest < Minitest::Test
  NONCE = 'a' * 32

  def frame(type, nonce: NONCE, **extra)
    "#{JSON.generate({ type: type, nonce: nonce }.merge(extra))}\n"
  end

  def read(bytes, expected: 'ready')
    WatcherFrameReader.read(StringIO.new(bytes), nonce: NONCE, expected: expected)
  end

  def test_skips_matching_checkpoints_before_readiness
    ready = frame('ready', lock: '1:2')

    assert_equal JSON.parse(ready), read(frame('progress') + frame('beat') + ready)
  end

  def test_skips_matching_checkpoints_before_a_notification
    pending = frame('pending', ids: ['worker.s1.2.3.1'])

    assert_equal JSON.parse(pending), read(frame('beat') + frame('progress') + pending, expected: 'pending')
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_refuses_foreign_nonce_even_on_a_checkpoint
    %w[progress beat ready pending].each do |type|
      error = assert_raises(RuntimeError) { read(frame(type, nonce: 'b' * 32) + frame('ready')) }

      assert_equal 'watcher frame nonce mismatch', error.message
    end
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_first_non_checkpoint_must_be_the_expected_type
    { 'ready' => 'pending', 'pending' => 'ready' }.each do |expected, actual|
      error = assert_raises(RuntimeError) { read(frame('progress') + frame(actual), expected: expected) }

      assert_equal "expected watcher #{expected}, got #{actual.inspect}", error.message
    end
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_checkpoints_alone_do_not_establish_readiness
    error = assert_raises(RuntimeError) { read(frame('progress') + frame('beat')) }

    assert_equal 'watcher exited before frame', error.message
  end

  # Real pipe traffic continues past the deadline, then publishes ready. A
  # per-frame timeout reset would incorrectly return ready instead of timing out.
  # rubocop:disable-next Metrics/MethodLength
  def test_checkpoints_do_not_renew_the_overall_timeout
    input, output = IO.pipe
    output.write(frame('progress'))
    writer = Thread.new do
      20.times do
        output.write(frame('beat'))
        sleep 0.01
      end
      output.write(frame('ready'))
    end

    assert_raises(Timeout::Error) do
      WatcherFrameReader.read(input, nonce: NONCE, expected: 'ready', timeout: 0.05)
    end
  ensure
    writer&.kill&.join
    [input, output].compact.each(&:close)
  end
end
