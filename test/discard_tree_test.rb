# frozen_string_literal: true

require 'minitest/autorun'
require 'tmpdir'
require_relative '../lib/riddim/discard'

class DiscardTreeTest < Minitest::Test
  def test_replaced_file_with_identical_mtime_is_not_the_inspected_inode
    Dir.mktmpdir('riddim-discard-stat-') do |root|
      first, replacement = %w[first replacement].map { |name| File.join(root, name) }
      [first, replacement].each do |path|
        File.write(path, 'same size')
        File.utime(Time.at(1), Time.at(1), path)
      end
      inspected = File.lstat(first)
      File.rename(replacement, first)

      assert_raises(Riddim::Discard::Refused) { Riddim::Discard::Tree.fingerprint!(first, inspected) }
    end
  end

  def test_regular_file_fingerprint_binds_content_and_permissions_without_contents
    Dir.mktmpdir('riddim-discard-content-') do |root|
      path = File.join(root, 'file')
      File.write(path, 'reviewed bytes')
      File.chmod(0o755, path)

      assert_equal({ type: 'file', mode: 0o755, sha256: Digest::SHA256.hexdigest('reviewed bytes') },
                   Riddim::Discard::Tree.fingerprint!(path, File.lstat(path)))
    end
  end
end
