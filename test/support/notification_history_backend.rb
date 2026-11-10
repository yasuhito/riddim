# frozen_string_literal: true

require_relative '../../lib/riddim/notifications'

# Controlled per-record I/O cost in an owned subprocess only. Phase records
# contain timings, never Worker content. A single hung read must still fail.
module NotificationHistoryBackend
  def scan(**options)
    return super unless ENV['RIDDIM_HISTORY_MODE'] == 'forever'

    # Real record validation keeps advancing, but this injected scan never
    # returns. Progress alone must not grant unlimited startup time or ready.
    filename = Dir.children(directory).find { |name| name.start_with?('worker.') }
    loop do
      Riddim::Ownership.with_lock('worker', wait: false) do
        read_entry(File.join(directory, filename), filename)
        options[:progress]&.call
      end
      sleep 0.05
    end
  end

  def classify(...)
    timed_phase('classify') { super }
  end

  def pending_for(...)
    timed_phase('pending') { super }
  end

  def present(...)
    timed_phase('present') { super }
  end

  def timed_phase(name)
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
  ensure
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    File.open(ENV.fetch('RIDDIM_PHASE_TRACE'), 'a') { |file| file.puts "#{Process.pid} phase-#{name} #{elapsed}" }
  end

  # rubocop:disable-next Metrics/AbcSize, Metrics/MethodLength
  def private_read(path)
    if path.end_with?('.json')
      File.open(ENV.fetch('RIDDIM_PHASE_TRACE'), 'a') do |file|
        file.puts "#{Process.pid} #{File.basename(path)} #{Process.clock_gettime(Process::CLOCK_MONOTONIC)}"
      end
      state = Riddim::Ownership.state_dir
      sleep 10 if File.exist?(File.join(state, 'hung-read'))
      sleep 0.003 if File.exist?(File.join(state, 'slow-read'))
      if File.exist?(File.join(state, 'read-error'))
        @error_reads = (@error_reads || 0) + 1
        raise Riddim::Notifications::Error, 'injected record read failure' if @error_reads >= 400
      end
    end
    super
  end
end

Riddim::Notifications.singleton_class.prepend(NotificationHistoryBackend)
