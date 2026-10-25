# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'open3'
require 'tmpdir'

class GitFixtureIdentityTest < Minitest::Test
  # rubocop:disable-next Metrics/MethodLength
  def test_dirty_worktree_fixture_does_not_require_a_developer_git_identity
    Dir.mktmpdir('riddim-no-git-identity-') do |home|
      environment = {
        'HOME' => home, 'XDG_CONFIG_HOME' => File.join(home, 'config'),
        'GEM_PATH' => Gem.path.join(File::PATH_SEPARATOR),
        'GIT_CONFIG_GLOBAL' => File::NULL, 'GIT_CONFIG_NOSYSTEM' => '1', 'GIT_CONFIG_COUNT' => '0',
        'GIT_AUTHOR_NAME' => nil, 'GIT_AUTHOR_EMAIL' => nil,
        'GIT_COMMITTER_NAME' => nil, 'GIT_COMMITTER_EMAIL' => nil, 'EMAIL' => nil
      }
      # Keep Bundler's original environment so unbundled CLI subprocesses do not
      # inherit vendored native gems built for a different Ruby than their shebang.
      output, status = Open3.capture2e(
        environment, RbConfig.ruby, '-rbundler/setup', Gem.bin_path('cucumber', 'cucumber'),
        'features/discard.feature', '--name', '^Dirty inspection presents a reviewable exact inventory$',
        '--format', 'progress', chdir: File.expand_path('..', __dir__)
      )

      assert_equal [true, true], [status.success?, output.include?('1 scenario (1 passed)')], output
    end
  end
end
