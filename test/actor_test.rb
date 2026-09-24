# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/riddim/actor'

class ActorTest < Minitest::Test
  def with_actor(value)
    previous = ENV.fetch('RIDDIM_ACTOR', nil)
    value ? ENV['RIDDIM_ACTOR'] = value : ENV.delete('RIDDIM_ACTOR')
    yield
  ensure
    previous ? ENV['RIDDIM_ACTOR'] = previous : ENV.delete('RIDDIM_ACTOR')
  end

  def landing_refusal(value)
    with_actor(value) do
      Riddim::Actor.refuse_landing!
      nil
    end
  rescue Riddim::Actor::Refused => e
    e
  end

  def test_branch_actor_is_refused_as_the_wrong_role
    refusal = landing_refusal('branch')

    assert_equal [Riddim::Actor::Refused,
                  'the marked task worker never lands local-only work; leave the merge to the operator'],
                 [refusal&.class, refusal&.message]
  end

  def test_unknown_actor_is_refused_as_a_wiring_bug
    refusal = landing_refusal('crew')

    assert_equal [Riddim::Actor::Refused, 'unknown RIDDIM_ACTOR value "crew"; an unmarked caller is the operator'],
                 [refusal&.class, refusal&.message]
  end

  def test_unmarked_caller_is_the_operator
    assert_nil landing_refusal(nil)
  end
end
