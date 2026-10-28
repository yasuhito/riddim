# Riddim

Riddim lets a supervisor coordinate locally isolated coding workers without treating their reports or process observations as human approval.

## Language

**Riddimセッション (Riddim session)**:
The supervisor Pi session (conversation) in which the human coordinates Workers. It can continue through reload while the extension runtime is replaced.
_Avoid_: bare session, extension runtime

**ワーカー (Worker)**:
An agent carrying out assigned work in an isolated workspace.
_Avoid_: notification watcher process, monitor

**通知監視プロセス (Notification watcher process)**:
A process that watches Worker reports and other pending notifications and alerts a Riddim session.
_Avoid_: Worker, monitor, bare watcher

**拡張ランタイム (Extension runtime)**:
The execution context in which Pi extensions operate. Reload replaces the pre-reload extension runtime with a post-reload extension runtime without requiring a new Riddim session.
_Avoid_: notification processing generation, Riddim session, software version

**Riddimの通知拡張 (Riddim notification extension)**:
The Pi extension that connects notification watcher processes to supervisor notifications in a Riddim session.
_Avoid_: notification watcher process, monitor, extension runtime

**Worker report**:
A worker's generation-bound claim about its task. It is distinct from the worker's current activity, Git readiness, and human approval.

**Actionable report**:
A worker report that calls for the supervisor's attention, such as a completion claim or a request for a decision. A later routine report does not erase that obligation.

**Supervisor notification**:
An alert that an actionable report needs the supervisor's attention. Delivery or receipt is not evidence that the report was reviewed or approved.

**Landing approval**:
A human's authorization to incorporate the exact worker branch tip they reviewed. Neither a worker's completion claim nor Git readiness grants it.
