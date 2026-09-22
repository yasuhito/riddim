# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/riddim/interrupt'

InterruptRecords = Struct.new(:events, :endpoints) do
  def resolve(name)
    events << [:resolve, name]
    endpoints.shift
  end
end

InterruptLocks = Struct.new(:events) do
  def with_lock(name, inherit_on_exec:)
    events << [:lock, name, inherit_on_exec]
    result = yield
    events << [:unlock, name]
    result
  end
end

InterruptHerdr = Struct.new(:events) do
  def interrupt(pane, session:)
    events << [:interrupt, pane, session]
    :verified_pane
  end
end

class OwnershipSafeInterruptTest < Minitest::Test
  OLD_ENDPOINT = Riddim::Ownership::Endpoint::Resolved.new('old', 'w1', 'w1:t1', 'w1:p1')
  RECORDED_ENDPOINT = Riddim::Ownership::Endpoint::Resolved.new('recorded', 'w9', 'w9:t1', 'w9:p1')
  EXPECTED_EVENTS = [
    [:resolve, 'worker'], [:lock, 'worker', true], [:resolve, 'worker'],
    [:interrupt, 'w9:p1', 'recorded'], [:unlock, 'worker']
  ].freeze

  def test_re_resolves_under_lock_and_holds_it_through_verification
    events = []
    collaborators = {
      endpoint_records: InterruptRecords.new(events, [OLD_ENDPOINT, RECORDED_ENDPOINT]),
      locks: InterruptLocks.new(events), herdr: InterruptHerdr.new(events)
    }
    result = Riddim::Interrupt.run('worker', **collaborators)

    assert_equal [EXPECTED_EVENTS, :verified_pane], [events, result]
  end
end
