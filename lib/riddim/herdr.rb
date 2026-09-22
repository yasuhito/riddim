# frozen_string_literal: true

require 'json'
require 'open3'

require_relative 'herdr/agent_state'
require_relative 'herdr/cleanup'
require_relative 'herdr/command_failed'
require_relative 'herdr/interrupt'
require_relative 'herdr/pane_tail'
require_relative 'herdr/preflight'
require_relative 'herdr/process_state'
require_relative 'herdr/prompt'

module Riddim
  # Owns Riddim's concrete Herdr command-line surface: it resolves the one
  # targeted session, constructs and runs every session-targeted subprocess,
  # and reads and validates Herdr's responses.
  module Herdr
    AGENT_STATUSES = %w[blocked done idle unknown working].freeze

    # The session Herdr targets when HERDR_SESSION is unset or empty.
    DEFAULT_SESSION = 'default'

    class InvalidResponse < StandardError; end

    # The ids of a freshly created workspace, exactly as Herdr reported them.
    CreatedWorkspace = Struct.new(:workspace_id, :tab_id, :root_pane_id)

    module_function

    # The Herdr session this process targets when the caller supplies none: a
    # nonempty HERDR_SESSION value, otherwise Herdr's own default session.
    def session
      value = ENV.fetch('HERDR_SESSION', nil)
      return DEFAULT_SESSION if value.nil? || value.empty?

      value
    end

    # The session one Herdr subprocess targets: the session its caller
    # supplies - such as the session recorded in an endpoint ownership
    # record - or, without one, the ambient resolution above. Supplying a
    # session overrides the ambient one on both routing surfaces: the
    # subprocess environment and the leading --session flag name it.
    def targeted_session(supplied = nil)
      supplied || session
    end

    # The environment of one Herdr subprocess targeting the supplied session,
    # or the ambient/default session when its caller supplies none.
    def environment(target = session)
      { 'HERDR_SESSION' => target }
    end

    # The argv of one Herdr subprocess targeting <session>: Herdr's explicit
    # --session global flag first, then the operation. The flag routes the
    # call exactly even when another Herdr server is already running, where
    # HERDR_SESSION alone is not honored reliably by every client, and it
    # stays globally valid ahead of subcommands with an inner -- separator,
    # such as agent start, whose passthrough tail must reach the agent
    # untouched.
    def command(*arguments, session: self.session)
      ['--session', session, *arguments]
    end

    # One captured Herdr invocation targeting <session>, or the ambient
    # session when the caller supplies none, so every existing call keeps its
    # ambient or default routing.
    def capture(*, session: nil)
      target = targeted_session(session)
      Open3.capture3(environment(target), 'herdr', *command(*, session: target))
    end

    # Replaces this process with one Herdr invocation targeting <session>, or
    # the ambient session when the caller supplies none, preserving Herdr's
    # streaming output and exit status.
    def exec(*, session: nil)
      target = targeted_session(session)
      Kernel.exec(environment(target), 'herdr', *command(*, session: target))
    end

    def agent(target, session: nil)
      stdout, stderr, status = capture('agent', 'get', target, session: session)
      raise CommandFailed.new(stdout, stderr, status) unless status.success?

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
      stdout, stderr, status = capture('workspace', 'create', '--cwd', cwd, '--label', label, '--no-focus')
      raise CommandFailed.new(stdout, stderr, status) unless status.success?

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

    # Starts the agent in the exact pane and raises CommandFailed on failure.
    # Performs no rollback of its own: the caller owns the published endpoint
    # record and the cleanup decisions, so a hidden best-effort close can
    # never race the record's retention rules.
    def start_agent(name:, pane_id:, model:, effort:)
      stdout, stderr, status = capture(
        'agent', 'start', name, '--kind', 'pi', '--pane', pane_id,
        '--', '--model', model, '--thinking', effort
      )
      raise CommandFailed.new(stdout, stderr, status) unless status.success?
    end

    # The non-empty string value of one Herdr response field, or nil.
    def response_id(value, key)
      id = value[key] if value.is_a?(Hash)
      id if id.is_a?(String) && !id.empty?
    end
  end
end
