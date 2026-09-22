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

class HerdrWorkspaceParsingTest < Minitest::Test
  WORKSPACE_JSON = <<~JSON
    {"id":"cli:workspace:create","result":{"type":"workspace_created","workspace":{"workspace_id":"w9"},"tab":{"tab_id":"w9:t1","workspace_id":"w9"},"root_pane":{"pane_id":"w9:p1","workspace_id":"w9","tab_id":"w9:t1"}}}
  JSON

  def test_parses_a_created_workspace
    workspace = Riddim::Herdr.parse_workspace(WORKSPACE_JSON)

    assert_equal %w[w9 w9:t1 w9:p1], [workspace.workspace_id, workspace.tab_id, workspace.root_pane_id]
  end

  def test_rejects_malformed_json
    assert_raises(Riddim::Herdr::InvalidResponse) { Riddim::Herdr.parse_workspace('not JSON') }
  end

  def test_rejects_an_unexpected_result_type
    json = '{"result":{"type":"pane_list"}}'

    assert_raises(Riddim::Herdr::InvalidResponse) { Riddim::Herdr.parse_workspace(json) }
  end

  def test_rejects_a_response_without_a_root_pane
    json = '{"result":{"type":"workspace_created","workspace":{"workspace_id":"w9"},"tab":{"tab_id":"w9:t1"}}}'

    assert_raises(Riddim::Herdr::InvalidResponse) { Riddim::Herdr.parse_workspace(json) }
  end

  def test_rejects_a_response_without_a_workspace_id
    json = <<~JSON
      {"result":{"type":"workspace_created","workspace":{},"tab":{"tab_id":"w9:t1"},"root_pane":{"pane_id":"w9:p1"}}}
    JSON

    assert_raises(Riddim::Herdr::InvalidResponse) { Riddim::Herdr.parse_workspace(json) }
  end

  def test_rejects_a_tab_outside_the_returned_workspace
    json = <<~JSON
      {"result":{"type":"workspace_created","workspace":{"workspace_id":"w9"},"tab":{"tab_id":"w9:t1","workspace_id":"w8"},"root_pane":{"pane_id":"w9:p1","workspace_id":"w9","tab_id":"w9:t1"}}}
    JSON

    assert_raises(Riddim::Herdr::InvalidResponse) { Riddim::Herdr.parse_workspace(json) }
  end

  def test_rejects_a_root_pane_outside_the_returned_tab
    json = <<~JSON
      {"result":{"type":"workspace_created","workspace":{"workspace_id":"w9"},"tab":{"tab_id":"w9:t1","workspace_id":"w9"},"root_pane":{"pane_id":"w9:p1","workspace_id":"w9","tab_id":"w8:t1"}}}
    JSON

    assert_raises(Riddim::Herdr::InvalidResponse) { Riddim::Herdr.parse_workspace(json) }
  end
end
