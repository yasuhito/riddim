# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/riddim/teardown'

class TeardownTest < Minitest::Test
  def test_cwd_scan_refuses_a_pid_without_a_cwd_field
    assert_raises(Riddim::Teardown::Refused) do
      Riddim::Teardown.parse_cwd_scan!("p42\nfcwd\np43\nfcwd\nn/\n")
    end
  end

  def test_cwd_scan_parses_root_and_unreadable_proc_entries
    output = "p42\nn/\np43\nn/proc/43/cwd (readlink: Permission denied)\np44\nn/home/example/project\n"

    assert_equal ['/', '/proc/43/cwd (readlink: Permission denied)', '/home/example/project'],
                 Riddim::Teardown.parse_cwd_scan!(output)
  end
end
