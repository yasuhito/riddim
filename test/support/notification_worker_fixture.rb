# frozen_string_literal: true

require 'json'
require_relative '../../lib/riddim/ownership'

# A single locked local-only Worker record for notification boundary tests.
module NotificationWorkerFixture
  # Prepare historical evidence before any observer exists. These scenarios
  # test reading retained records, not 400 durable ACK transactions during setup.
  # The real observer still validates every private queue/marker row itself.
  def write_handled_notification_history(state, generation, count:)
    directory = File.join(state, '.notifications')
    Dir.mkdir(directory, 0o700)
    count.times do |index|
      id = "worker.#{generation}.#{index + 1}"
      row = { id: id, task: 'worker', generation: generation, sequence: index + 1, event: 'done' }
      ["#{id}.json", ".presented-#{id}.json", ".handled-#{id}.json"].each do |filename|
        File.write(File.join(directory, filename), "#{JSON.generate(row)}\n", perm: 0o600)
      end
    end
  end

  def write_notification_worker(state, generation, name: 'worker')
    fields = { 'harness' => 'pi', 'model' => 'stall-lab/test', 'effort' => 'off', 'spawn_gen' => generation,
               'backend' => 'herdr', 'herdr_workspace_id' => 'w9', 'herdr_tab_id' => 'w9:t1',
               'window' => 'test:w9:p1', 'endpoint_task_id' => name, 'herdr_session' => 'test',
               'herdr_pane_id' => 'w9:p1', 'task_mode' => 'local-only', 'status_protocol' => 'locked-v1' }
    File.write(File.join(state, "#{name}.meta"), Riddim::Ownership.serialize(fields), perm: 0o600)
  end
end
