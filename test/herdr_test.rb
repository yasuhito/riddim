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

class HerdrPanePresenceTest < Minitest::Test
  PANE_ID = 'w9:p1'

  def test_reads_gone_from_the_structured_pane_not_found_error
    assert_equal :gone, Riddim::Herdr.pane_presence(PANE_ID, '{"error":{"code":"pane_not_found"}}', '')
  end

  def test_reads_gone_from_stderr_when_stdout_is_unparseable
    assert_equal :gone, Riddim::Herdr.pane_presence(PANE_ID, 'noise', '{"error":{"code":"pane_not_found"}}')
  end

  def test_reads_present_from_a_response_naming_the_pane
    assert_equal :present, Riddim::Herdr.pane_presence(PANE_ID, '{"result":{"pane":{"pane_id":"w9:p1"}}}', '')
  end

  def test_reads_unknown_from_another_error_code
    assert_equal :unknown, Riddim::Herdr.pane_presence(PANE_ID, '{"error":{"code":"server_unavailable"}}', '')
  end

  def test_reads_unknown_from_a_response_naming_another_pane
    assert_equal :unknown, Riddim::Herdr.pane_presence(PANE_ID, '{"result":{"pane":{"pane_id":"w8:p2"}}}', '')
  end

  def test_reads_unknown_when_neither_stream_is_json
    assert_equal :unknown, Riddim::Herdr.pane_presence(PANE_ID, 'no', 'also no')
  end

  def test_reports_unparseable_for_a_non_json_body
    assert_equal :unparseable, Riddim::Herdr.classify_pane_body(PANE_ID, 'not JSON')
  end
end

class HerdrInterruptParsingTest < Minitest::Test
  def test_returns_the_exact_pane_of_a_pi_agent
    agent = { 'agent' => 'pi', 'agent_status' => 'working', 'pane_id' => 'w9:p1' }

    assert_equal 'w9:p1', Riddim::Herdr.interrupt_pane(agent)
  end

  def test_rejects_a_non_pi_agent
    agent = { 'agent' => 'codex', 'agent_status' => 'idle', 'pane_id' => 'w9:p1' }

    assert_raises(Riddim::Herdr::InvalidResponse) { Riddim::Herdr.interrupt_pane(agent) }
  end

  def test_rejects_an_agent_without_a_kind
    agent = { 'agent_status' => 'idle', 'pane_id' => 'w9:p1' }

    assert_raises(Riddim::Herdr::InvalidResponse) { Riddim::Herdr.interrupt_pane(agent) }
  end

  def test_rejects_a_response_without_a_pane_id
    agent = { 'agent' => 'pi', 'agent_status' => 'idle' }

    assert_raises(Riddim::Herdr::InvalidResponse) { Riddim::Herdr.interrupt_pane(agent) }
  end

  def test_rejects_an_empty_pane_id
    agent = { 'agent' => 'pi', 'agent_status' => 'idle', 'pane_id' => '' }

    assert_raises(Riddim::Herdr::InvalidResponse) { Riddim::Herdr.interrupt_pane(agent) }
  end

  def test_rejects_a_non_string_pane_id
    agent = { 'agent' => 'pi', 'agent_status' => 'idle', 'pane_id' => 42 }

    assert_raises(Riddim::Herdr::InvalidResponse) { Riddim::Herdr.interrupt_pane(agent) }
  end

  def test_names_the_pane_it_cannot_reverify
    error = Riddim::Herdr::InterruptUnverified.new('w9:p1', 'reason')

    assert_equal 'w9:p1', error.pane_id
  end
end

class HerdrCommandFailureReasonTest < Minitest::Test
  def test_appends_herdr_error_to_the_exit_status
    failure = Riddim::Herdr::CommandFailed.new('', "herdr: pane not found\n", 7)

    assert_equal 'Herdr exited with status 7: herdr: pane not found', Riddim::Herdr.command_failure_reason(failure)
  end

  def test_stands_alone_without_herdr_error
    failure = Riddim::Herdr::CommandFailed.new('', '', 7)

    assert_equal 'Herdr exited with status 7', Riddim::Herdr.command_failure_reason(failure)
  end
end

class HerdrPaneTailTest < Minitest::Test
  def test_fetches_the_requested_tail_above_the_minimum
    assert_equal 250, Riddim::Herdr.fetch_lines(250)
  end

  def test_fetches_the_minimum_for_a_smaller_tail
    assert_equal 200, Riddim::Herdr.fetch_lines(5)
  end

  def test_trims_a_capture_to_its_final_requested_lines
    assert_equal "pane-248\npane-249\npane-250\n", Riddim::Herdr.tail("pane-001\npane-248\npane-249\npane-250\n", 3)
  end

  def test_passes_a_capture_shorter_than_the_tail_through_whole
    assert_equal "only line\n", Riddim::Herdr.tail("only line\n", 40)
  end

  def test_keeps_a_final_line_that_has_no_newline
    assert_equal 'final', Riddim::Herdr.tail("earlier\nfinal", 1)
  end
end
