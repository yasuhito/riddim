# frozen_string_literal: true

require 'minitest/autorun'
require 'bundler'
require 'open3'
require 'tmpdir'

class PiWorkerStartupAvailabilityTest < Minitest::Test
  # rubocop:disable-next Minitest/MultipleAssertions
  def test_startup_integration_reports_a_skip_without_pi_on_path
    Dir.mktmpdir('riddim-no-pi-') do |path|
      output, status = Bundler.with_unbundled_env do
        Open3.capture2e({ 'PATH' => path }, RbConfig.ruby, '-rbundler/setup',
                        File.expand_path('pi_worker_startup_test.rb', __dir__), '--verbose')
      end

      assert_predicate status, :success?, output
      assert_includes output, 'Pi executable unavailable on PATH'
      assert_includes output, '1 runs, 0 assertions, 0 failures, 0 errors, 1 skips'
    end
  end
end
