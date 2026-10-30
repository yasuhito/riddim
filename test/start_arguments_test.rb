# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/riddim/start/arguments'
require_relative '../lib/riddim/profile'

class StartArgumentsTest < Minitest::Test
  def test_refuses_nul_before_a_subprocess_can_receive_it
    assert_raises(Riddim::Start::Arguments::Error) do
      Riddim::Start::Arguments.parse(['--model', "provider/a\0model"])
    end
  end

  def test_does_not_consume_or_mutate_callers_arguments
    arguments = ['--effort=high', '--model', 'provider/a'].map(&:freeze).freeze
    parsed = Riddim::Start::Arguments.parse(arguments)

    assert_equal({ '--effort' => 'high', '--model' => 'provider/a' }, parsed)
  end
end

class EffectiveAgentProfileTest < Minitest::Test
  def with_profile
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, 'agent-profile'), "pi provider/configured max\n")
      yield directory
    end
  end

  def test_each_resolution_is_fresh_and_leaves_the_configured_profile_intact
    with_profile do |directory|
      configured = Riddim::AgentProfile.load(config_dir: directory)
      custom = Riddim::AgentProfile.resolve(config_dir: directory, model: 'provider/custom', effort: 'low')
      default = Riddim::AgentProfile.resolve(config_dir: directory)

      assert_equal ['provider/configured', 'max', 'provider/custom', 'low', 'provider/configured', 'max', false],
                   [configured.model, configured.effort, custom.model, custom.effort, default.model, default.effort,
                    custom.equal?(default)]
    end
  end

  def test_refuses_an_empty_explicit_model_instead_of_inheriting
    with_profile do |directory|
      assert_raises(Riddim::AgentProfile::Error) do
        Riddim::AgentProfile.resolve(config_dir: directory, model: '')
      end
    end
  end

  def test_refuses_an_empty_explicit_effort_instead_of_inheriting
    with_profile do |directory|
      assert_raises(Riddim::AgentProfile::Error) do
        Riddim::AgentProfile.resolve(config_dir: directory, effort: '')
      end
    end
  end
end
