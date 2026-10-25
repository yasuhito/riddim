# frozen_string_literal: true

require 'minitest/autorun'
require 'json'
require 'open3'
require 'tmpdir'

# Notification E2E fixtures must never observe the operator's live Herdr.
class NotificationBackendFixtureTest < Minitest::Test
  FIXTURE = File.expand_path('support/notification_slow_backend.rb', __dir__)

  def install_herdr(root)
    File.write(File.join(root, 'herdr'), <<~RUBY)
      #!#{RbConfig.ruby}
      File.write(#{File.join(root, 'unexpected-herdr').dump}, ARGV.join(' '))
      puts '{}'
    RUBY
    File.chmod(0o700, File.join(root, 'herdr'))
  end

  def observe(root)
    env = { 'RIDDIM_STATE_DIR' => root, 'PATH' => "#{root}:#{ENV.fetch('PATH')}" }
    code = "puts JSON.generate(Riddim::Herdr.observe_pi_agent('w9:p1', session: 'fixture'))"
    Open3.capture3(env, RbConfig.ruby, '-r', FIXTURE, '-r', 'json', '-e', code)
  end

  def test_default_observation_is_working_without_contacting_real_herdr
    Dir.mktmpdir('riddim-backend-fixture-') do |root|
      install_herdr(root)
      output, error, status = observe(root)

      assert_equal [true, %w[alive working], false],
                   [status.success?, JSON.parse(output), File.exist?(File.join(root, 'unexpected-herdr'))], error
    end
  end
end
