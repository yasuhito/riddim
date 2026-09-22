# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/riddim/herdr'

class ComposerGhostStripTest < Minitest::Test
  def test_strips_a_dim_run
    assert_equal 'tail', Riddim::Herdr.strip_ghost("\e[2mplaceholder\e[0mtail")
  end

  def test_keeps_bright_text
    assert_equal 'typed draft', Riddim::Herdr.strip_ghost("typed \e[1;32mdraft\e[0m")
  end

  def test_strips_a_dark_truecolor_foreground_run
    assert_equal '', Riddim::Herdr.strip_ghost("\e[38;2;40;40;40mhint\e[0m")
  end

  def test_keeps_a_bright_truecolor_foreground
    assert_equal 'hint', Riddim::Herdr.strip_ghost("\e[38;2;200;200;40mhint\e[0m")
  end

  def test_keeps_a_256_colour_foreground
    assert_equal 'hint', Riddim::Herdr.strip_ghost("\e[38;5;236mhint\e[0m")
  end

  def test_ends_a_dark_run_on_a_base_foreground
    assert_equal 'shown', Riddim::Herdr.strip_ghost("\e[38;2;10;10;10m\e[37mshown\e[0m")
  end

  def test_reads_a_colon_form_truecolor_payload
    assert_equal '', Riddim::Herdr.strip_ghost("\e[38:2::20:20:20mhint\e[0m")
  end
end

class ComposerNormalizeTrimTest < Minitest::Test
  def test_maps_unicode_whitespace_onto_plain_spaces
    assert_equal 'a b', Riddim::Herdr.normalize_trim("a\u00A0b\u2003")
  end

  def test_trims_leading_and_trailing_whitespace
    assert_equal 'a', Riddim::Herdr.normalize_trim("\t\u00A0a\n ")
  end
end

class ComposerSeparatorTest < Minitest::Test
  def test_accepts_a_solid_rule_of_at_least_eight_columns
    assert Riddim::Herdr.pi_separator_row?('────────────')
  end

  def test_rejects_a_separator_below_the_width_floor
    refute Riddim::Herdr.pi_separator_row?('───────')
  end

  def test_rejects_a_row_with_any_other_byte
    refute Riddim::Herdr.pi_separator_row?('──────── x')
  end
end

class ComposerPairScanTest < Minitest::Test
  SCREEN = "────────────\n\n────────────\n"

  def test_selects_the_bottom_most_closed_pair
    screen = "#{SCREEN}transcript\n────────────\n\n────────────\n"

    pair = Riddim::Herdr.bottom_most_pi_pair(screen)

    assert_equal({ open: 4, close: 6, valid: true }, pair)
  end

  def test_marks_a_pair_wider_than_the_inner_bound_invalid
    screen = "────────────\n#{"row of typed input\n" * 9}────────────\n"

    assert_equal({ open: 0, close: 10, valid: false }, Riddim::Herdr.bottom_most_pi_pair(screen))
  end

  def test_refuses_when_no_pair_closes
    assert_nil Riddim::Herdr.bottom_most_pi_pair("────────────\nopen region\n")
  end

  def test_refuses_a_shell_glyph_row_below_the_pair
    screen = "#{SCREEN}$ prompt\n"

    refute Riddim::Herdr.bottom_most_pi_pair(screen)
  end

  def test_refuses_a_bare_agent_glyph_row_below_the_pair
    screen = "#{SCREEN}❯ stray\n"

    refute Riddim::Herdr.bottom_most_pi_pair(screen)
  end
end

class ComposerVerdictTest < Minitest::Test
  def with_screen(identity)
    Riddim::Herdr.singleton_class.send(:define_method, :composer_capture) { |*| [ComposerPairScanTest::SCREEN, true] }
    Riddim::Herdr.singleton_class.send(:define_method, :composer_identity) { |*| identity }
    yield
  ensure
    Riddim::Herdr.singleton_class.send(:remove_method, :composer_capture)
    Riddim::Herdr.singleton_class.send(:remove_method, :composer_identity)
  end

  def test_proves_empty_for_an_idle_live_pi
    with_screen("pi\tidle") do
      assert_equal :empty, Riddim::Herdr.composer_state('w9:p1', session: 'riddim')
    end
  end

  def test_needs_identity_before_any_verdict
    with_screen(nil) do
      assert_equal :unknown, Riddim::Herdr.composer_state('w9:p1', session: 'riddim')
    end
  end

  def test_refuses_an_absent_probe
    with_screen('probe-absent') do
      assert_equal :unknown, Riddim::Herdr.composer_state('w9:p1', session: 'riddim')
    end
  end
end
