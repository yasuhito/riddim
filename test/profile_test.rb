# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/riddim/profile'

class AgentProfileParsingTest < Minitest::Test
  def test_parses_a_pi_profile
    profile = Riddim::AgentProfile.parse("pi openrouter/z-ai/glm-5.3-flash max\n")

    assert_equal %w[pi openrouter/z-ai/glm-5.3-flash max], [profile.harness, profile.model, profile.effort]
  end

  def test_skips_comment_and_blank_lines
    profile = Riddim::AgentProfile.parse("# riddim agent profile\n\n  pi model max  \n")

    assert_equal 'max', profile.effort
  end

  def test_tolerates_extra_whitespace_between_tokens
    profile = Riddim::AgentProfile.parse("pi  openrouter/z-ai/glm-5.3-flash\tmax\n")

    assert_equal 'openrouter/z-ai/glm-5.3-flash', profile.model
  end

  def test_rejects_a_short_profile_line
    assert_raises(Riddim::AgentProfile::Error) { Riddim::AgentProfile.parse("pi openrouter/z-ai/glm-5.3-flash\n") }
  end

  def test_rejects_a_long_profile_line
    assert_raises(Riddim::AgentProfile::Error) { Riddim::AgentProfile.parse("pi model max extra\n") }
  end

  def test_rejects_an_unsupported_harness
    assert_raises(Riddim::AgentProfile::Error) { Riddim::AgentProfile.parse("claude opus high\n") }
  end

  def test_rejects_an_unsupported_effort
    assert_raises(Riddim::AgentProfile::Error) { Riddim::AgentProfile.parse("pi model ultra\n") }
  end

  def test_rejects_a_model_with_a_control_character
    assert_raises(Riddim::AgentProfile::Error) { Riddim::AgentProfile.parse("pi mo\x00del max\n") }
  end

  def test_rejects_a_second_profile_line
    assert_raises(Riddim::AgentProfile::Error) do
      Riddim::AgentProfile.parse("pi model max\npi other-model high\n")
    end
  end

  def test_rejects_a_file_without_a_profile_line
    assert_raises(Riddim::AgentProfile::Error) { Riddim::AgentProfile.parse("# comment only\n\n") }
  end
end

class AgentProfileLoadingTest < Minitest::Test
  def test_loads_the_profile_from_the_config_directory
    profile = Dir.mktmpdir do |directory|
      File.write(File.join(directory, 'agent-profile'), "pi m max\n")
      Riddim::AgentProfile.load(config_dir: directory)
    end

    assert_equal 'm', profile.model
  end

  def test_reports_a_missing_profile_file
    assert_raises(Riddim::AgentProfile::Error) do
      Dir.mktmpdir { |directory| Riddim::AgentProfile.load(config_dir: directory) }
    end
  end

  def test_reports_an_unreadable_profile_file
    assert_raises(Riddim::AgentProfile::Error) do
      Dir.mktmpdir do |directory|
        Dir.mkdir(File.join(directory, 'agent-profile'))
        Riddim::AgentProfile.load(config_dir: directory)
      end
    end
  end
end
