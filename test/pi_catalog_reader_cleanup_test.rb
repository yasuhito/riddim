# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/riddim/pi_catalog'

class PiCatalogReaderCleanupTest < Minitest::Test
  # A timeout must cancel readers before Open3 closes their streams. Delaying
  # their read simulates a reader not scheduled promptly after process-group
  # termination, without depending on host load to expose the close race.
  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength, Minitest/MultipleAssertions
  def test_timeout_retires_reader_threads_before_closing_their_streams
    readers = []
    original = Open3.method(:popen3)
    delayed = lambda do |*args, **options, &block|
      original.call(*args, **options) do |input, output, error, waiter|
        [output, error].each do |stream|
          read = stream.method(:read)
          stream.define_singleton_method(:read) do
            readers << Thread.current
            sleep 60
            read.call
          end
        end
        block.call(input, output, error, waiter)
      end
    end
    singleton = Open3.singleton_class
    singleton.send(:remove_method, :popen3)
    singleton.send(:define_method, :popen3, delayed)
    Dir.mktmpdir('riddim-catalog-readers-') do |root|
      executable = File.join(root, 'pi')
      File.write(executable, "#!/bin/sh\nsleep 30\n", perm: 0o700)
      error = assert_raises(Riddim::PiCatalog::Error) do
        Riddim::PiCatalog.verify!('provider/model', executable: executable, timeout: 1)
      end

      assert_includes error.message, 'did not finish within 1 seconds'
    end

    assert_equal 2, readers.size
    assert readers.none?(&:alive?), 'timed-out catalog readers outlived their owned streams'
  ensure
    readers&.each { |reader| reader.kill.join }
    if singleton
      singleton.send(:remove_method, :popen3)
      singleton.send(:define_method, :popen3, original)
    end
  end
end
