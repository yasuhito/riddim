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

  def test_prepends_a_supplied_session_as_the_explicit_flag
    argv = Riddim::Herdr.command('agent', 'get', 'pi', session: 'lab')

    assert_equal ['--session', 'lab', 'agent', 'get', 'pi'], argv
  end

  def test_prepends_the_ambient_session_when_none_is_supplied
    with_herdr_session('lab') do
      assert_equal ['--session', 'lab', 'agent', 'get', 'pi'], Riddim::Herdr.command('agent', 'get', 'pi')
    end
  end

  def test_leads_agent_start_with_the_supplied_session_and_keeps_the_pi_tail_intact
    argv = Riddim::Herdr.command(
      'agent', 'start', 'worker', '--kind', 'pi', '--pane', 'w9:p1',
      '--', '--model', 'openrouter/z-ai/glm-5.3-flash', '--thinking', 'max', session: 'lab'
    )

    assert_equal AGENT_START_ARGV, argv
  end

  def test_names_the_supplied_session_in_the_environment
    assert_equal({ 'HERDR_SESSION' => 'lab' }, Riddim::Herdr.environment('lab'))
  end

  def test_names_the_ambient_session_when_none_is_supplied
    with_herdr_session('lab') do
      assert_equal({ 'HERDR_SESSION' => 'lab' }, Riddim::Herdr.environment)
    end
  end
end

class TargetedSessionResolutionTest < Minitest::Test
  include HerdrSessionEnv

  def test_targets_the_supplied_session_over_the_ambient_one
    with_herdr_session('ambient') do
      assert_equal 'recorded', Riddim::Herdr.targeted_session('recorded')
    end
  end

  def test_falls_back_to_the_ambient_session_without_a_supplied_session
    with_herdr_session('ambient') do
      assert_equal 'ambient', Riddim::Herdr.targeted_session(nil)
    end
  end

  def test_falls_back_to_herdr_default_session_without_a_supplied_or_ambient_session
    with_herdr_session(nil) do
      assert_equal 'default', Riddim::Herdr.targeted_session(nil)
    end
  end
end
