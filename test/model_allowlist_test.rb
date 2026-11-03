# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/riddim/profile'

# Exact, fail-closed membership of the local allowed-models policy.
class ModelAllowlistTest < Minitest::Test
  BRIDGE = 'claude-bridge/claude-opus-5-5'

  def with_allowlist(content)
    Dir.mktmpdir do |directory|
      File.binwrite(File.join(directory, 'allowed-models'), content) if content
      yield directory
    end
  end

  def refusal(model, content)
    with_allowlist(content) { |directory| refusal_in(directory, model) }
  end

  def refusal_in(directory, model)
    Riddim::ModelAllowlist.verify!(model, config_dir: directory)

    flunk "#{model} was admitted"
  rescue Riddim::ModelAllowlist::Error => e
    e.message
  end

  def allowed?(model, content)
    with_allowlist(content) do |directory|
      Riddim::ModelAllowlist.verify!(model, config_dir: directory)
      true
    rescue Riddim::ModelAllowlist::Error
      false
    end
  end

  def test_admits_an_exactly_listed_model
    assert allowed?(BRIDGE, "openai-codex/gpt-6.1-sol\n#{BRIDGE}\n")
  end

  def test_refuses_openrouter_and_other_look_alikes_of_a_listed_bridge_model
    look_alikes = ['openrouter/anthropic/claude-opus-5.5', 'openrouter/anthropic/claude-opus-5-5',
                   "openrouter/#{BRIDGE}", 'claude-bridge/claude-opus-5.5', 'Claude-Bridge/claude-opus-5-5',
                   'claude-opus-5-5', 'claude-bridge/claude-opus', "#{BRIDGE}-extra", "#{BRIDGE}/", " #{BRIDGE}"]

    assert_equal([false] * look_alikes.length, look_alikes.map { |model| allowed?(model, "#{BRIDGE}\n") })
  end

  def test_names_the_provider_and_model_of_a_refused_model
    message = refusal('openrouter/anthropic/claude-opus-5.5', "#{BRIDGE}\n")

    assert_includes message, 'provider "openrouter" model "anthropic/claude-opus-5.5" is not listed in'
  end

  def test_explains_an_unqualified_model_has_no_provider
    assert_includes refusal('claude-opus-5-5', "#{BRIDGE}\n"), 'it names no provider'
  end

  def test_treats_glob_and_regexp_characters_literally
    results = [allowed?(BRIDGE, "claude-bridge/*\n"), allowed?(BRIDGE, "claude-bridge/.*\n"),
               allowed?('claude-bridge/*', "claude-bridge/*\n")]

    assert_equal [false, false, true], results
  end

  def test_skips_comments_blank_lines_and_surrounding_whitespace
    content = "# approved by a human\n\n   \n  #{BRIDGE}  \r\n\t# openrouter/anthropic/claude-opus-5.5\n"

    assert_equal [true, false], [allowed?(BRIDGE, content), allowed?('openrouter/anthropic/claude-opus-5.5', content)]
  end

  def test_accepts_duplicate_entries
    assert allowed?(BRIDGE, "#{BRIDGE}\n#{BRIDGE}\n")
  end

  def test_matches_non_ascii_utf8_ids_whatever_the_argv_encoding
    results = ['provider/モデル', 'provider/モデル'.b].map { |model| allowed?(model, "provider/モデル\n") }

    assert_equal [true, true], results
  end

  def test_refuses_a_missing_allowlist_with_setup_guidance
    assert_match %r{missing model allowlist .*/allowed-models: list one approved provider/model ID per line},
                 refusal(BRIDGE, nil)
  end

  def test_refuses_an_unreadable_allowlist
    message = Dir.mktmpdir do |directory|
      Dir.mkdir(File.join(directory, 'allowed-models'))
      refusal_in(directory, BRIDGE)
    end

    assert_match %r{\Aunreadable model allowlist .*/allowed-models: }, message
  end

  def test_refuses_an_allowlist_without_entries
    messages = ['', "\n\n", "# only a comment\n   \n"].map { |content| refusal(BRIDGE, content) }

    assert_equal([true] * 3, messages.map { |message| message.start_with?('empty model allowlist ') })
  end

  def test_refuses_invalid_utf8
    assert_includes refusal(BRIDGE, "#{BRIDGE}\nprovider/\xff\n".b), 'valid UTF-8 is required'
  end

  def test_reports_the_line_of_each_malformed_entry
    entries = ["#{BRIDGE} xhigh", "#{BRIDGE} # inline comment", 'claude-opus-5-5', '/claude-opus-5-5',
               'claude-bridge/', "claude-bridge/claude\topus", "claude-bridge/claude\u00A0opus",
               "claude-bridge/claude-opus-5-5\u3000", "claude-bridge/claude\u200Bopus", "\uFEFF#{BRIDGE}"]
    messages = entries.map { |entry| refusal(BRIDGE, "# header\n#{BRIDGE}\n#{entry}\n") }

    assert_equal([true] * entries.length, messages.map { |message| message.include?(' line 3: expected one ') })
  end
end

# The effective model is checked after profile defaults and overrides resolve.
class AgentProfileAllowlistTest < Minitest::Test
  def with_config(allowed)
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, 'agent-profile'), "pi openai-codex/gpt-6.1-sol high\n")
      File.write(File.join(directory, 'allowed-models'), allowed) if allowed
      yield directory
    end
  end

  def resolved_model(allowed, **overrides)
    with_config(allowed) { |directory| Riddim::AgentProfile.resolve(config_dir: directory, **overrides).model }
  rescue Riddim::ModelAllowlist::Error
    :refused
  end

  def test_admits_a_listed_default_and_a_listed_override
    allowed = "openai-codex/gpt-6.1-sol\nclaude-bridge/claude-opus-5-5\n"

    assert_equal ['openai-codex/gpt-6.1-sol', 'claude-bridge/claude-opus-5-5'],
                 [resolved_model(allowed), resolved_model(allowed, model: 'claude-bridge/claude-opus-5-5')]
  end

  def test_refuses_an_unlisted_default_even_when_overriding_only_effort
    assert_equal %i[refused refused],
                 [resolved_model("claude-bridge/claude-opus-5-5\n"),
                  resolved_model("claude-bridge/claude-opus-5-5\n", effort: 'low')]
  end

  def test_refuses_an_unlisted_override_even_when_the_default_is_listed
    assert_equal :refused, resolved_model("openai-codex/gpt-6.1-sol\n", model: 'openrouter/anthropic/claude-opus-5.5',
                                                                        effort: 'max')
  end

  def test_admits_a_listed_override_when_the_default_is_unlisted
    assert_equal 'claude-bridge/claude-opus-5-5',
                 resolved_model("claude-bridge/claude-opus-5-5\n", model: 'claude-bridge/claude-opus-5-5')
  end

  def test_refuses_every_selection_without_an_allowlist
    assert_equal %i[refused refused], [resolved_model(nil), resolved_model(nil, model: 'openai-codex/gpt-6.1-sol')]
  end

  def test_reports_profile_errors_before_consulting_the_allowlist
    error = with_config(nil) do |directory|
      Riddim::AgentProfile.resolve(config_dir: directory, effort: 'ultra')
    rescue Riddim::AgentProfile::Error, Riddim::ModelAllowlist::Error => e
      e
    end

    assert_equal [Riddim::AgentProfile::Error, true], [error.class, error.message.include?('unsupported effort')]
  end
end
