# frozen_string_literal: true

require 'bundler'
require 'minitest/autorun'
require 'open3'
require 'tmpdir'

class RiddimTest < Minitest::Test
  RIDDIM = File.expand_path('../bin/riddim', __dir__)

  private

  def run_riddim(*, env: {})
    Bundler.with_unbundled_env { Open3.capture3(env, RIDDIM, *) }
  end

  def run_with_fake_herdr(*)
    with_fake_herdr do |path|
      return run_riddim(*, env: { 'PATH' => path })
    end
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

class SendTest < RiddimTest
  def test_send_prompts_the_requested_agent_through_herdr
    stdout, = run_with_fake_herdr('send', 'pi', 'Fix', 'the tests')

    assert_equal "agent prompt pi Fix the tests\n", stdout
  end

  def test_send_exits_successfully_after_prompting_herdr
    _, _, status = run_with_fake_herdr('send', 'pi', 'Fix', 'the tests')

    assert_predicate status, :success?
  end

  def test_send_writes_no_error_after_prompting_herdr
    _, stderr = run_with_fake_herdr('send', 'pi', 'Fix', 'the tests')

    assert_empty stderr
  end

  def test_send_without_a_target_exits_with_usage_status
    _, _, status = run_riddim('send')

    assert_equal 2, status.exitstatus
  end

  def test_send_without_a_target_writes_nothing_to_standard_output
    stdout, = run_riddim('send')

    assert_empty stdout
  end

  def test_send_without_a_target_prints_usage
    _, stderr = run_riddim('send')

    assert_equal "Usage: riddim send <target> <message...>\n", stderr
  end

  def test_send_without_a_message_exits_with_usage_status
    _, _, status = run_riddim('send', 'pi')

    assert_equal 2, status.exitstatus
  end

  def test_send_without_a_message_writes_nothing_to_standard_output
    stdout, = run_riddim('send', 'pi')

    assert_empty stdout
  end

  def test_send_without_a_message_prints_usage
    _, stderr = run_riddim('send', 'pi')

    assert_equal "Usage: riddim send <target> <message...>\n", stderr
  end

  def test_send_with_a_blank_message_exits_with_usage_status
    _, _, status = run_riddim('send', 'pi', " \t ")

    assert_equal 2, status.exitstatus
  end

  def test_send_with_a_blank_message_writes_nothing_to_standard_output
    stdout, = run_riddim('send', 'pi', " \t ")

    assert_empty stdout
  end

  def test_send_with_a_blank_message_prints_an_error
    _, stderr = run_riddim('send', 'pi', " \t ")

    assert_equal "riddim: message must not be blank\n", stderr
  end
end

class PeekTest < RiddimTest
  def test_peek_reads_the_requested_agent_from_herdr
    stdout, = run_with_fake_herdr('peek', 'pi', '5')

    assert_equal "agent read pi --source recent-unwrapped --lines 5\n", stdout
  end

  def test_peek_exits_successfully_after_reading_herdr
    _, _, status = run_with_fake_herdr('peek', 'pi', '5')

    assert_predicate status, :success?
  end

  def test_peek_writes_no_error_after_reading_herdr
    _, stderr = run_with_fake_herdr('peek', 'pi', '5')

    assert_empty stderr
  end

  def test_peek_reads_forty_lines_by_default
    stdout, = run_with_fake_herdr('peek', 'pi')

    assert_equal "agent read pi --source recent-unwrapped --lines 40\n", stdout
  end

  def test_default_peek_exits_successfully
    _, _, status = run_with_fake_herdr('peek', 'pi')

    assert_predicate status, :success?
  end

  def test_default_peek_writes_no_error
    _, stderr = run_with_fake_herdr('peek', 'pi')

    assert_empty stderr
  end

  def test_peek_with_a_non_positive_line_count_exits_with_usage_status
    _, _, status = run_riddim('peek', 'pi', '0')

    assert_equal 2, status.exitstatus
  end

  def test_peek_with_a_non_positive_line_count_writes_nothing_to_standard_output
    stdout, = run_riddim('peek', 'pi', '0')

    assert_empty stdout
  end

  def test_peek_with_a_non_positive_line_count_prints_an_error
    _, stderr = run_riddim('peek', 'pi', '0')

    assert_equal "riddim: lines must be a positive integer\n", stderr
  end

  def test_peek_without_a_target_exits_with_usage_status
    _, _, status = run_riddim('peek')

    assert_equal 2, status.exitstatus
  end

  def test_peek_without_a_target_writes_nothing_to_standard_output
    stdout, = run_riddim('peek')

    assert_empty stdout
  end

  def test_peek_without_a_target_prints_usage
    _, stderr = run_riddim('peek')

    assert_equal "Usage: riddim peek <target> [lines]\n", stderr
  end

  def test_peek_with_extra_arguments_exits_with_usage_status
    _, _, status = run_riddim('peek', 'pi', '5', 'extra')

    assert_equal 2, status.exitstatus
  end

  def test_peek_with_extra_arguments_writes_nothing_to_standard_output
    stdout, = run_riddim('peek', 'pi', '5', 'extra')

    assert_empty stdout
  end

  def test_peek_with_extra_arguments_prints_usage
    _, stderr = run_riddim('peek', 'pi', '5', 'extra')

    assert_equal "Usage: riddim peek <target> [lines]\n", stderr
  end
end

class HelpTest < RiddimTest
  def test_help_lists_send
    stdout, = run_riddim

    assert_includes stdout, 'send <target> <message...>'
  end

  def test_help_for_send_exits_successfully
    _, _, status = run_riddim

    assert_predicate status, :success?
  end

  def test_help_for_send_writes_no_error
    _, stderr = run_riddim

    assert_empty stderr
  end

  def test_help_lists_peek
    stdout, = run_riddim

    assert_includes stdout, 'peek <target> [lines]'
  end

  def test_help_for_peek_exits_successfully
    _, _, status = run_riddim

    assert_predicate status, :success?
  end

  def test_help_for_peek_writes_no_error
    _, stderr = run_riddim

    assert_empty stderr
  end
end
