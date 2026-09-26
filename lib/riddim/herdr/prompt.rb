# frozen_string_literal: true

module Riddim
  # Streams native Herdr prompts while retaining a completion-unknown outcome.
  module Herdr
    module_function

    # Best-effort doorbell, retaining the ownership lock in Herdr if the
    # controller exits while the subprocess is still submitting.
    def notify?(target, text, session:)
      args = command('agent', 'prompt', target, text, session: session)
      pid = Process.spawn(environment(session), 'herdr', *args,
                          close_others: false, out: File::NULL, err: File::NULL)
      Process.wait2(pid).last.success?
    end

    # The Herdr child inherits the per-name lock across exec. A dead parent
    # cannot release ownership while Herdr still delivers the prompt.
    def prompt(target, message, session: nil)
      selected = targeted_session(session)
      arguments = command('agent', 'prompt', target, message, session: selected)
      delivery = { pid: nil, pending: [] }
      handlers = prompt_signal_handlers(delivery)
      delivery[:pid] = Process.spawn(environment(selected), 'herdr', *arguments, close_others: false)
      wait_prompt(delivery)
    ensure
      handlers&.each { |signal, previous| Signal.trap(signal, previous) }
    end

    def wait_prompt(delivery)
      delivery[:pending].each { |signal| forward_prompt_signal(delivery[:pid], signal) }
      Process.wait2(delivery[:pid]).last
    end

    def prompt_signal_handlers(delivery)
      %w[HUP INT QUIT TERM].to_h do |signal|
        previous = Signal.trap(signal) do
          delivery[:pid] ? forward_prompt_signal(delivery[:pid], signal) : delivery[:pending] << signal
        end
        [signal, previous]
      end
    end

    def forward_prompt_signal(pid, signal)
      Process.kill(signal, pid)
    rescue Errno::ESRCH
      nil
    end
  end
end
