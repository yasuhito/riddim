# frozen_string_literal: true

module Riddim
  # Exact-pane close and the process-cwd proof before removing a worktree.
  module Teardown
    module_function

    def close_exact_pane!(task)
      endpoint = task.snapshot.first
      raise Refused, 'teardown cannot close its own pane; retaining assets' if self_pane?(endpoint)

      case Herdr.pane_presence_state(endpoint.pane_id, session: endpoint.session)
      when :gone then return
      when :present then verify_agent!(task.name, endpoint)
      else raise Refused, 'exact pane presence is unknown; retaining assets'
      end
      return if Herdr.close_pane_confirmed(endpoint.pane_id, session: endpoint.session)

      raise Refused, 'exact pane disappearance unconfirmed; retaining record and Git assets'
    end

    def self_pane?(endpoint)
      ENV['HERDR_ENV'] == '1' && Herdr.session == endpoint.session &&
        ENV['HERDR_PANE_ID'] == endpoint.pane_id
    end

    def verify_agent!(name, endpoint)
      agent = Herdr.agent(endpoint.pane_id, session: endpoint.session)
      identity = agent.values_at('name', 'agent', 'pane_id', 'workspace_id', 'tab_id')
      expected = [name, 'pi', endpoint.pane_id, endpoint.workspace_id, endpoint.tab_id]
      return if identity == expected

      raise Refused, 'a different agent occupies the exact pane; retaining assets'
    rescue Herdr::CommandFailed, Herdr::InvalidResponse
      return if Herdr.agent_state(endpoint.pane_id, session: endpoint.session) == :dead

      raise Refused, 'pane agent identity cannot be verified; retaining assets'
    end

    # Firstmate's cwd sweep uses this non-recursive, process-bounded lsof form.
    # Unrelated mounts can warn; failure or a warning about this worktree refuses.
    def scan_cwds!(task)
      output, errors, status = Open3.capture3('lsof', '-a', '-d', 'cwd', '-Fpn')
      raise Refused, 'cwd scan failed; retaining assets' unless status.success?

      paths = parse_cwd_scan!(output)
      raise Refused, 'empty cwd scan; retaining assets' if paths.empty?
      raise Refused, 'cwd scan cannot inspect the worker; retaining assets' if errors.include?(task.worktree)
      raise Refused, 'a process still uses the worker worktree; retaining assets' if cwd_listed?(paths, task.worktree)
    end

    def parse_cwd_scan!(output)
      output.split(/(?=^p[1-9]\d*\n)/).flat_map { |row| parse_cwd_row!(row) }
    end

    def parse_cwd_row!(row)
      lines = row.lines
      raise Refused, 'malformed cwd scan; retaining assets' unless lines.shift&.match?(/\Ap[1-9]\d*\n\z/)

      paths = lines.reject { |line| line == "fcwd\n" }.map { |line| cwd_field!(line) }
      raise Refused, 'incomplete cwd scan; retaining assets' if paths.empty?

      paths
    end

    def cwd_field!(line)
      raise Refused, 'malformed cwd scan; retaining assets' unless line.match?(%r{\An/[^\n]*\n\z})

      line[1..].delete_suffix("\n")
    end

    def cwd_listed?(paths, directory)
      paths.any? { |path| path == directory || path.start_with?("#{directory}/", "#{directory} ") }
    end
  end
end
