# frozen_string_literal: true

require 'minitest/autorun'
require_relative 'support/one_then_per_scenario'

class OneThenPerScenarioTest < Minitest::Test
  def test_accepts_one_then
    violations = lint(<<~GHERKIN)
      Feature: Example
        Scenario: One outcome
          When something happens
          Then one result is visible
    GHERKIN

    assert_empty violations
  end

  def test_rejects_a_scenario_without_a_then
    violations = lint(<<~GHERKIN)
      Feature: Example
        Scenario: No outcome
          When something happens
    GHERKIN

    assert_equal ['example.feature:2: Scenario "No outcome" must have exactly one Then step; found 0'], violations
  end

  def test_rejects_multiple_then_steps
    violations = lint(<<~GHERKIN)
      Feature: Example
        Scenario: Two outcomes
          Then one result is visible
          Then another result is visible
    GHERKIN

    assert_equal ['example.feature:2: Scenario "Two outcomes" must have exactly one Then step; found 2'], violations
  end

  def test_counts_and_after_then_as_another_outcome
    violations = lint(<<~GHERKIN)
      Feature: Example
        Scenario: Continued outcome
          Then one result is visible
          And another result is visible
    GHERKIN

    expected = ['example.feature:2: Scenario "Continued outcome" must have exactly one Then step; found 2']

    assert_equal expected, violations
  end

  def test_counts_a_wildcard_after_then_as_another_outcome
    violations = lint(<<~GHERKIN)
      Feature: Example
        Scenario: Wildcard outcome
          Then one result is visible
          * another result is visible
    GHERKIN
    expected = ['example.feature:2: Scenario "Wildcard outcome" must have exactly one Then step; found 2']

    assert_equal expected, violations
  end

  def test_rejects_an_outcome_in_a_background
    violations = lint(<<~GHERKIN)
      Feature: Example
        Background:
          Then one result is visible
        Scenario: One outcome
          Then another result is visible
    GHERKIN

    assert_equal ['example.feature:2: Background must not have Then steps; found 1'], violations
  end

  private

  def lint(source)
    OneThenPerScenario.call(source, path: 'example.feature')
  end
end
