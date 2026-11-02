# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/riddim/pi_catalog'

# Exact membership in the table `pi --list-models` prints, via a fake Pi.
class PiCatalogTest < Minitest::Test
  def setup
    @bin = Dir.mktmpdir('riddim-pi-catalog-test-')
  end

  def teardown
    FileUtils.remove_entry(@bin)
  end

  # Pi pads each column to its widest cell, as `pi --list-models` does.
  def table(*models)
    rows = [%w[provider model context max-out]] + models.map { |model| [*model.split('/', 2), '1M', '128K'] }
    widths = rows.transpose.map { |column| column.map(&:length).max }
    "#{rows.map { |row| row.zip(widths).map { |cell, width| cell.ljust(width) }.join('  ') }.join("\n")}\n"
  end

  def fake_pi(script)
    File.write(File.join(@bin, 'pi'), "#!/bin/sh\n#{script}\n", perm: 0o700)
  end

  def listing(*models)
    File.write(File.join(@bin, 'table'), table(*models))
    fake_pi("[ \"$*\" = --list-models ] || exit 9\ncat #{File.join(@bin, 'table')}")
  end

  def verdict(model, timeout: 30)
    old_path = ENV.fetch('PATH')
    ENV['PATH'] = "#{@bin}:#{old_path}"
    Riddim::PiCatalog.verify!(model, timeout: timeout)
    :listed
  rescue Riddim::PiCatalog::Error => e
    e.message
  ensure
    ENV['PATH'] = old_path
  end

  def test_admits_an_exactly_listed_model
    listing('anthropic/claude-opus-5-5', 'claude-bridge/claude-opus-5-5', 'claude-bridge/claude-opus-5-5-pro')

    assert_equal :listed, verdict('claude-bridge/claude-opus-5-5')
  end

  def test_refuses_an_id_pi_would_fuzzy_match_to_a_costlier_model
    listing('claude-bridge/claude-opus-5-5-pro', 'openrouter/claude-bridge/claude-opus-5-5')

    assert_includes verdict('claude-bridge/claude-opus-5-5'),
                    'is not listed by `pi --list-models`; Pi would substitute or guess another "claude-bridge" model'
  end

  def test_refuses_a_case_variant_pi_would_select_instead
    listing('openai/gpt-5.5')

    assert_includes verdict('openai/GPT-5.5'),
                    'is not listed exactly by `pi --list-models`, which lists "openai/gpt-5.5"'
  end

  def test_refuses_an_exact_id_pi_could_confuse_with_a_case_variant
    listing('custom/Model', 'custom/model')

    assert_includes verdict('custom/model'), 'is ambiguous in `pi --list-models`'
  end

  # Pi reads --provider openrouter --model openrouter/free as the ID "free" when that exists.
  def test_refuses_an_id_repeating_its_provider_when_pi_would_read_the_shorter_id
    listing('openrouter/free', 'openrouter/openrouter/free')

    assert_includes verdict('openrouter/openrouter/free'), 'is ambiguous in `pi --list-models`'
  end

  def test_admits_an_id_repeating_its_provider_without_a_shorter_rival
    listing('openrouter/openrouter/free')

    assert_equal :listed, verdict('openrouter/openrouter/free')
  end

  def test_admits_slashed_and_non_ascii_ids_by_their_columns
    listing('openrouter/openai/gpt-5.5', 'provider/モデル', 'provider/モデル-pro')

    verdicts = ['openrouter/openai/gpt-5.5', 'provider/モデル'.b].map { |model| verdict(model) }

    assert_equal %i[listed listed], verdicts
  end

  def test_refuses_when_pi_lists_nothing_or_prints_something_else
    fake_pi("echo 'No models available. Use /login or set an API key environment variable.'")

    assert_includes verdict('openai/gpt-5.5'), 'unexpected `pi --list-models` output: "No models available.'
  end

  def test_refuses_when_pi_fails
    fake_pi("echo 'catalog broke' >&2\nexit 3")

    assert_includes verdict('openai/gpt-5.5'), '`pi --list-models` failed: "catalog broke"'
  end

  def test_refuses_when_pi_is_missing
    old_path = ENV.fetch('PATH')
    ENV['PATH'] = @bin
    message = verdict('openai/gpt-5.5')

    assert_includes message, 'could not run `pi --list-models`'
  ensure
    ENV['PATH'] = old_path
  end

  def test_stops_a_hanging_pi_and_its_children_within_the_bound
    fake_pi("sleep 30 &\nsleep 30")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    message = verdict('openai/gpt-5.5', timeout: 1)

    assert_equal [true, true],
                 [message.include?('did not finish within 1 seconds'),
                  Process.clock_gettime(Process::CLOCK_MONOTONIC) - started < 10]
  end
end
