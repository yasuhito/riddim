# frozen_string_literal: true

require_relative '../../lib/riddim/ownership'

# A single locked local-only Worker record for notification boundary tests.
module NotificationWorkerFixture
  def write_notification_worker(state, generation)
    fields = { 'harness' => 'pi', 'model' => 'stall-lab/test', 'effort' => 'off', 'spawn_gen' => generation,
               'backend' => 'herdr', 'herdr_workspace_id' => 'w9', 'herdr_tab_id' => 'w9:t1',
               'window' => 'test:w9:p1', 'endpoint_task_id' => 'worker', 'herdr_session' => 'test',
               'herdr_pane_id' => 'w9:p1', 'task_mode' => 'local-only', 'status_protocol' => 'locked-v1' }
    File.write(File.join(state, 'worker.meta'), Riddim::Ownership.serialize(fields), perm: 0o600)
  end
end
