# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'open3'
require 'tmpdir'

# The documented Ruby-only CI boundary is observable, not blanket CI skipping.
# These subprocess tests need no Pi installation and exercise skipped teardown.
class ScheduledPromptsAvailabilityTest < Minitest::Test
  SUITE = File.expand_path('scheduled_prompts_e2e_test.rb', __dir__)

  def run_suite(path, *)
    temporary = File.join(path, 'fixtures')
    Dir.mkdir(temporary)
    output, status = Bundler.with_unbundled_env do
      Open3.capture2e({ 'PATH' => path, 'TMPDIR' => temporary, 'RIDDIM_TEST_EVIDENCE_DIR' => nil },
                      RbConfig.ruby, '-rbundler/setup', SUITE, '--verbose', *)
    end
    [output, status, Dir.children(temporary)]
  end

  def assert_unavailable(path)
    output, status, leftovers = run_suite(path)

    assert_predicate status, :success?, output
    assert_includes output, 'Pi executable unavailable on PATH'
    assert_includes output, '16 runs, 0 assertions, 0 failures, 0 errors, 16 skips'
    assert_empty leftovers, 'unavailable Pi must leave no allocated E2E fixtures behind'
  end

  def test_scheduled_integration_reports_explicit_skips_with_pi_absent
    Dir.mktmpdir('riddim-schedules-no-pi-') { |path| assert_unavailable(path) }
  end

  def test_directory_and_nonexecutable_file_are_not_pi_installations
    %w[directory nonexecutable].each do |kind|
      Dir.mktmpdir('riddim-schedules-no-pi-') do |path|
        candidate = File.join(path, 'pi')
        kind == 'directory' ? Dir.mkdir(candidate) : File.write(candidate, 'not an executable', perm: 0o600)

        assert_unavailable(path)
      end
    end
  end

  # An installed but broken executable must fail, not become an optional skip.
  # rubocop:disable-next Metrics/MethodLength, Minitest/MultipleAssertions
  def test_present_but_broken_pi_is_not_silently_skipped
    Dir.mktmpdir('riddim-schedules-broken-pi-') do |path|
      File.write(File.join(path, 'pi'), <<~SH, perm: 0o700)
        #!/bin/sh
        IFS= read -r request
        echo 'intentional broken Pi fixture' >&2
        exit 23
      SH
      output, status, leftovers = run_suite(path, '--name',
                                            'test_one_shot_reaches_only_explicit_session_and_requires_handling_ack')

      refute_predicate status, :success?, output
      assert_includes output, 'intentional broken Pi fixture'
      assert_includes output, '0 failures, 1 errors, 0 skips'
      refute_includes output, 'Pi executable unavailable on PATH'
      assert_empty leftovers, 'failed startup must clean up its owned fixture'
    end
  end
end
