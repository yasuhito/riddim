# frozen_string_literal: true

module Riddim
  # Pi-specific, recovery-grade process check for one Herdr pane.
  module Herdr
    module_function

    # A positive Pi, shell-only, or unreadable process verdict. Registration
    # alone is not process liveness; an unfamiliar foreground is never called
    # shell-only or assumed to be Pi in this narrower adapter.
    def pi_process_state(pane, session: nil)
      info = pane_process_info(pane, session: session)
      return :unreadable unless valid_process_info?(info, pane)

      rows = process_rows
      return :unreadable unless rows&.key?(info['shell_pid'])

      classify_pi_processes(info, rows)
    rescue JSON::ParserError, TypeError, ArgumentError, SystemCallError
      :unreadable
    end

    def pi_process_alive?(pane, session: nil)
      pi_process_state(pane, session: session) == :pi
    end

    def classify_pi_processes(info, rows)
      foreground = info.fetch('foreground_processes')
      return :pi if foreground.any? { |process| pi_foreground?(process, rows) }
      return :unreadable unless foreground.all? { |process| shell_foreground?(process, rows) }

      descendant_pi?(rows, info.fetch('shell_pid')) ? :pi : :shell
    end

    def pane_process_info(pane, session:)
      stdout, _stderr, status = capture('pane', 'process-info', '--pane', pane, session: session)
      return unless status.success?

      document = JSON.parse(stdout)
      return unless document.is_a?(Hash)

      result = document['result']
      result['process_info'] if result.is_a?(Hash) && result['type'] == 'pane_process_info'
    end

    def valid_process_info?(info, pane)
      info.is_a?(Hash) && info['pane_id'] == pane && info['shell_pid'].is_a?(Integer) &&
        info['shell_pid'] > 1 && info['foreground_processes'].is_a?(Array)
    end

    def pi_name?(value)
      %w[pi pi-signed pi-launcher Pi].include?(File.basename(value.to_s.sub(/\A-/, '')))
    end

    def pi_foreground?(process, rows)
      return false unless process.is_a?(Hash) && rows.key?(process['pid'])

      args = process['argv']
      argv0 = args.is_a?(Array) ? args.first : process['argv0']
      pi_name?(process['name']) || pi_name?(argv0)
    end

    def shell_foreground?(process, rows)
      return false unless process.is_a?(Hash) && rows.key?(process['pid'])

      args = process['argv']
      argv0 = args.is_a?(Array) ? args.first : process['argv0']
      %w[zsh bash sh dash ash ksh mksh tcsh csh fish].include?(File.basename(process['name'].to_s)) &&
        (argv0.nil? || %w[zsh bash sh dash ash ksh mksh tcsh csh fish].include?(File.basename(argv0.to_s)))
    end

    def process_rows
      stdout, _stderr, status = Open3.capture3('ps', '-axo', 'pid=,ppid=,comm=,args=')
      return unless status.success?

      rows = {}
      stdout.each_line do |line|
        match = line.match(/\A\s*(\d+)\s+(\d+)\s+(\S+)\s*(.*)/)
        raise ArgumentError, 'unreadable process table' unless match

        rows[match[1].to_i] = { parent: match[2].to_i, name: match[3], args: match[4] }
      end
      rows
    end

    def descendant_pi?(rows, shell_pid)
      descendants = [shell_pid]
      index = 0
      while index < descendants.length
        parent = descendants[index]
        children = rows.filter_map { |pid, entry| pid if entry[:parent] == parent && !descendants.include?(pid) }
        descendants.concat(children)
        index += 1
      end
      descendants.drop(1).any? { |pid| process_pi?(rows.fetch(pid)) }
    end

    def process_pi?(entry)
      pi_name?(entry[:name]) || pi_name?(entry[:args].split.first)
    end
  end
end
