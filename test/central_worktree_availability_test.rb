# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'open3'
require 'tmpdir'

# Both modified Pi suites must skip only when no executable is installed.
class CentralWorktreeAvailabilityTest < Minitest::Test
  SUITES = {
    'central_worktree_context_test.rb' => 'test_real_pi_keeps_target_and_global_context_without_riddim_context',
    'pi_native_startup_test.rb' => 'test_fresh_clone_initializes_default_home_and_injects_supervisor_contract'
  }.freeze

  def run_suite(path, suite, name)
    temporary = File.join(path, 'fixtures')
    Dir.mkdir(temporary)
    output, status = Bundler.with_unbundled_env do
      Open3.capture2e({ 'PATH' => path, 'TMPDIR' => temporary }, RbConfig.ruby, '-rbundler/setup',
                      File.expand_path(suite, __dir__), '--verbose', '--name', name)
    end
    [output, status, Dir.children(temporary)]
  end

  def install_broken_pi(path)
    %w[ruby git which node bash sh].each do |command|
      executable = ENV.fetch('PATH').split(File::PATH_SEPARATOR).map { |dir| File.join(dir, command) }
                      .find { |candidate| File.file?(candidate) && File.executable?(candidate) }
      File.symlink(executable, File.join(path, command)) if executable
    end
    File.write(File.join(path, 'pi'), "#!/bin/sh\necho 'broken Pi fixture' >&2\nexit 23\n", perm: 0o700)
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_absent_pi_skips_before_creating_resources
    SUITES.each do |suite, name|
      Dir.mktmpdir('riddim-central-no-pi-') do |path|
        output, status, leftovers = run_suite(path, suite, name)

        assert_predicate status, :success?, output
        assert_includes output, 'Pi executable unavailable on PATH'
        assert_includes output, '1 runs, 0 assertions, 0 failures, 0 errors, 1 skips'
        assert_empty leftovers
      end
    end
  end

  # rubocop:disable-next Minitest/MultipleAssertions
  def test_present_but_broken_pi_fails_instead_of_skipping
    SUITES.each do |suite, name|
      Dir.mktmpdir('riddim-central-broken-pi-') do |path|
        install_broken_pi(path)
        output, status, leftovers = run_suite(path, suite, name)

        refute_predicate status, :success?, output
        refute_includes output, 'Pi executable unavailable on PATH'
        assert_includes output, '0 skips'
        assert_empty leftovers
      end
    end
  end
end
