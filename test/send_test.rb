# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/riddim/send'

EventRecords = Struct.new(:events, :endpoints) do
  def resolve(name)
    events << [:resolve, name]
    endpoints.shift
  end
end

EventLocks = Struct.new(:events) do
  def with_lock(name, inherit_on_exec:)
    events << [:lock, name, inherit_on_exec]
    result = yield
    events << [:unlock, name]
    result
  end
end

EventHerdr = Struct.new(:events) do
  def prompt(pane, message, session:)
    events << [:prompt, pane, message, session]
    :process_status
  end
end

class OwnershipSafeSendTest < Minitest::Test
  OLD_ENDPOINT = Riddim::Ownership::Endpoint::Resolved.new('old', 'w1', 'w1:t1', 'w1:p1')
  RECORDED_ENDPOINT = Riddim::Ownership::Endpoint::Resolved.new('recorded', 'w9', 'w9:t1', 'w9:p1')
  EXPECTED_EVENTS = [
    [:resolve, 'worker'], [:lock, 'worker', true], [:resolve, 'worker'],
    [:prompt, 'w9:p1', 'Fix the tests', 'recorded'], [:unlock, 'worker']
  ].freeze

  def test_re_resolves_under_lock_and_holds_it_through_prompt_completion
    events = []
    collaborators = {
      endpoint_records: EventRecords.new(events, [OLD_ENDPOINT, RECORDED_ENDPOINT]),
      locks: EventLocks.new(events), herdr: EventHerdr.new(events)
    }
    result = Riddim::Send.run('worker', 'Fix the tests', **collaborators)

    assert_equal [EXPECTED_EVENTS, :process_status], [events, result]
  end
end
