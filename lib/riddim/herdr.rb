# frozen_string_literal: true

require 'json'
require 'open3'

require_relative 'herdr/interrupt'

module Riddim
  # Reads and validates Herdr's concrete command-line state representation.
  module Herdr
    AGENT_STATUSES = %w[blocked done idle unknown working].freeze

    # Preserves a failed Herdr process's observable result for the caller.
    class CommandFailed < StandardError
      attr_reader :stdout, :stderr, :exitstatus

      def initialize(stdout, stderr, exitstatus)
        super("Herdr exited with status #{exitstatus}")
        @stdout = stdout
        @stderr = stderr
        @exitstatus = exitstatus
      end
    end

    class InvalidResponse < StandardError; end

    # The ids of a freshly created workspace, exactly as Herdr reported them.
    CreatedWorkspace = Struct.new(:workspace_id, :tab_id, :root_pane_id)

    module_function

    def agent(target)
      stdout, stderr, status = Open3.capture3('herdr', 'agent', 'get', target)
      raise CommandFailed.new(stdout, stderr, status.exitstatus) unless status.success?

      parse_agent(stdout)
    end

    def parse_agent(json)
      document = JSON.parse(json)
      result = document['result'] if document.is_a?(Hash)
      agent = result['agent'] if result.is_a?(Hash)
      status = agent['agent_status'] if agent.is_a?(Hash)
      return agent if AGENT_STATUSES.include?(status)

      raise InvalidResponse, 'expected result.agent.agent_status to be idle, working, blocked, done, or unknown'
    rescue JSON::ParserError
      raise InvalidResponse, 'malformed JSON'
    end

    def create_workspace(cwd:, label:)
      stdout, stderr, status = Open3.capture3(
        'herdr', 'workspace', 'create', '--cwd', cwd, '--label', label, '--no-focus'
      )
      raise CommandFailed.new(stdout, stderr, status.exitstatus) unless status.success?

      parse_workspace(stdout)
    end

    def parse_workspace(json)
      document = JSON.parse(json)
      result = document['result'] if document.is_a?(Hash)
      raise InvalidResponse, 'expected result.type to be workspace_created' unless created_result?(result)

      build_workspace(result)
    rescue JSON::ParserError
      raise InvalidResponse, 'malformed JSON'
    end

    def created_result?(result)
      result.is_a?(Hash) && result['type'] == 'workspace_created'
    end

    def build_workspace(result)
      workspace_id = response_id(result['workspace'], 'workspace_id')
      tab_id = response_id(result['tab'], 'tab_id')
      root_pane_id = response_id(result['root_pane'], 'pane_id')
      ids = [workspace_id, tab_id, root_pane_id]
      message = 'expected workspace, tab, and root_pane ids in the create response'
      raise InvalidResponse, message unless ids.all?

      validate_relationships(result, workspace_id, tab_id)
      CreatedWorkspace.new(workspace_id, tab_id, root_pane_id)
    end

    def validate_relationships(result, workspace_id, tab_id)
      return if related?(result, workspace_id, tab_id)

      message = 'contradictory create response: tab and root pane do not belong to the returned workspace and tab'
      raise InvalidResponse, message
    end

    def related?(result, workspace_id, tab_id)
      tab = Hash.try_convert(result['tab']) || {}
      pane = Hash.try_convert(result['root_pane']) || {}
      tab['workspace_id'] == workspace_id && pane['workspace_id'] == workspace_id && pane['tab_id'] == tab_id
    end

    def start_agent(name:, pane_id:, model:, effort:)
      stdout, stderr, status = Open3.capture3(
        'herdr', 'agent', 'start', name, '--kind', 'pi', '--pane', pane_id,
        '--', '--model', model, '--thinking', effort
      )
      return if status.success?

      close_pane(pane_id)
      raise CommandFailed.new(stdout, stderr, status.exitstatus)
    end

    # Best-effort rollback: never raises, so it cannot mask the start failure.
    def close_pane(pane_id)
      Open3.capture3('herdr', 'pane', 'close', pane_id)
    rescue StandardError
      nil
    end

    # The non-empty string value of one Herdr response field, or nil.
    def response_id(value, key)
      id = value[key] if value.is_a?(Hash)
      id if id.is_a?(String) && !id.empty?
    end
  end
end
