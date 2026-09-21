# frozen_string_literal: true

require 'minitest/autorun'
require_relative '../lib/riddim/herdr'

class HerdrAgentParsingTest < Minitest::Test
  def test_parses_a_valid_agent
    json = '{"id":"cli:agent:get","result":{"type":"agent_info","agent":{"agent":"pi","agent_status":"working"}}}'

    assert_equal({ 'agent' => 'pi', 'agent_status' => 'working' }, Riddim::Herdr.parse_agent(json))
  end

  def test_parses_the_done_status
    json = '{"result":{"agent":{"agent_status":"done"}}}'

    assert_equal({ 'agent_status' => 'done' }, Riddim::Herdr.parse_agent(json))
  end

  def test_rejects_malformed_json
    assert_raises(Riddim::Herdr::InvalidResponse) { Riddim::Herdr.parse_agent('not JSON') }
  end

  def test_rejects_an_agent_without_a_status
    json = '{"result":{"agent":{"agent":"pi"}}}'

    assert_raises(Riddim::Herdr::InvalidResponse) { Riddim::Herdr.parse_agent(json) }
  end

  def test_rejects_an_unknown_status
    json = '{"result":{"agent":{"agent":"pi","agent_status":"sleeping"}}}'

    assert_raises(Riddim::Herdr::InvalidResponse) { Riddim::Herdr.parse_agent(json) }
  end
end
