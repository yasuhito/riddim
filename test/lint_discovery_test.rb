# frozen_string_literal: true

require 'minitest/autorun'
require 'fileutils'
require 'open3'
require 'tmpdir'

# Exercise the formatter's public discovery, preserving its vendor defaults.
class LintDiscoveryTest < Minitest::Test
  def fixture(root)
    FileUtils.cp(File.expand_path('../.rubocop.yml', __dir__), root)
    %w[lib vendor/bundle].each { |path| FileUtils.mkdir_p(File.join(root, path)) }
    %w[lib/app.rb vendor/bundle/a.rb].each { |path| File.write(File.join(root, path), '# fixture') }
  end

  def test_rubocop_keeps_default_vendor_exclusions
    Dir.mktmpdir('riddim-lint-') do |root|
      fixture(root)
      output, error, status = Open3.capture3(RbConfig.ruby, Gem.bin_path('rubocop', 'rubocop'),
                                             '--list-target-files', chdir: root)

      assert_equal [true, true, false],
                   [status.success?, output.include?('lib/app.rb'), output.include?('vendor/bundle/a.rb')], error
    end
  end
end
