# frozen_string_literal: true

require 'bundler'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class RiddimTest < Minitest::Test
  RIDDIM = File.expand_path('../bin/riddim', __dir__)

  def test_peek_reads_the_requested_agent_from_herdr
    with_fake_herdr do |path|
      stdout, stderr, status = run_riddim('peek', 'pi', '5', env: { 'PATH' => path })

      assert_predicate status, :success?
      assert_equal "agent read pi --source recent-unwrapped --lines 5\n", stdout
      assert_empty stderr
    end
  end

  def test_peek_reads_forty_lines_by_default
    with_fake_herdr do |path|
      stdout, stderr, status = run_riddim('peek', 'pi', env: { 'PATH' => path })

      assert_predicate status, :success?
      assert_equal "agent read pi --source recent-unwrapped --lines 40\n", stdout
      assert_empty stderr
    end
  end

  def test_peek_rejects_a_non_positive_line_count
    stdout, stderr, status = run_riddim('peek', 'pi', '0')

    assert_equal 2, status.exitstatus
    assert_empty stdout
    assert_equal "riddim: lines must be a positive integer\n", stderr
  end

  def test_help_lists_peek
    stdout, stderr, status = run_riddim

    assert_predicate status, :success?
    assert_includes stdout, 'peek <target> [lines]'
    assert_empty stderr
  end

  def test_peek_requires_a_target
    stdout, stderr, status = run_riddim('peek')

    assert_equal 2, status.exitstatus
    assert_empty stdout
    assert_equal "Usage: riddim peek <target> [lines]\n", stderr
  end

  def test_peek_rejects_extra_arguments
    stdout, stderr, status = run_riddim('peek', 'pi', '5', 'extra')

    assert_equal 2, status.exitstatus
    assert_empty stdout
    assert_equal "Usage: riddim peek <target> [lines]\n", stderr
  end

  private

  def run_riddim(*, env: {})
    Bundler.with_unbundled_env { Open3.capture3(env, RIDDIM, *) }
  end

  def with_fake_herdr
    Dir.mktmpdir do |dir|
      herdr = File.join(dir, 'herdr')
      File.write(herdr, <<~RUBY)
        #!/usr/bin/ruby
        puts ARGV.join(" ")
      RUBY
      File.chmod(0o755, herdr)
      yield "#{dir}:#{ENV.fetch('PATH')}"
    end
  end
end
