# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/riddim/herdr'

# Sets HERDR_SESSION for the duration of one test; a nil value removes it.
module HerdrSessionEnv
  def with_herdr_session(value)
    original = ENV.fetch('HERDR_SESSION', nil)
    ENV['HERDR_SESSION'] = value
    yield
  ensure
    ENV['HERDR_SESSION'] = original
  end
end

class SessionResolutionTest < Minitest::Test
  include HerdrSessionEnv

  def test_targets_herdr_default_session_without_the_environment_variable
    with_herdr_session(nil) do
      assert_equal 'default', Riddim::Herdr.session
    end
  end

  def test_targets_herdr_default_session_for_an_empty_environment_value
    with_herdr_session('') do
      assert_equal 'default', Riddim::Herdr.session
    end
  end

  def test_targets_the_nonempty_environment_value
    with_herdr_session('lab') do
      assert_equal 'lab', Riddim::Herdr.session
    end
  end
end

class SessionCommandConstructionTest < Minitest::Test
  include HerdrSessionEnv

  # The session flag leads; the Pi passthrough tail ends at --thinking.
  AGENT_START_ARGV = [
    '--session', 'lab', 'agent', 'start', 'worker', '--kind', 'pi', '--pane', 'w9:p1',
    '--', '--model', 'openrouter/z-ai/glm-5.3-flash', '--thinking', 'max'
  ].freeze

  def test_prepends_the_resolved_session_as_the_explicit_flag
    with_herdr_session('lab') do
      assert_equal ['--session', 'lab', 'agent', 'get', 'pi'], Riddim::Herdr.command('agent', 'get', 'pi')
    end
  end

  def test_prepends_the_default_session_without_the_environment_variable
    with_herdr_session(nil) do
      assert_equal ['--session', 'default', 'agent', 'get', 'pi'], Riddim::Herdr.command('agent', 'get', 'pi')
    end
  end

  def test_keeps_the_session_ahead_of_agent_start_and_the_pi_passthrough_tail_intact
    argv = with_herdr_session('lab') do
      Riddim::Herdr.command(
        'agent', 'start', 'worker', '--kind', 'pi', '--pane', 'w9:p1',
        '--', '--model', 'openrouter/z-ai/glm-5.3-flash', '--thinking', 'max'
      )
    end

    assert_equal AGENT_START_ARGV, argv
  end

  def test_names_the_resolved_session_in_the_environment
    with_herdr_session('lab') do
      assert_equal({ 'HERDR_SESSION' => 'lab' }, Riddim::Herdr.environment)
    end
  end

  def test_names_the_default_session_in_the_environment
    with_herdr_session(nil) do
      assert_equal({ 'HERDR_SESSION' => 'default' }, Riddim::Herdr.environment)
    end
  end
end
