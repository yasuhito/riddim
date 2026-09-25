# Riddim

Riddim lets a supervisor coordinate locally isolated coding workers without treating their reports or process observations as human approval.

## Language

**Worker report**:
A worker's generation-bound claim about its task. It is distinct from the worker's current activity, Git readiness, and human approval.

**Actionable report**:
A worker report that calls for the supervisor's attention, such as a completion claim or a request for a decision. A later routine report does not erase that obligation.

**Supervisor notification**:
An alert that an actionable report needs the supervisor's attention. Delivery or receipt is not evidence that the report was reviewed or approved.

**Landing approval**:
A human's authorization to incorporate the exact worker branch tip they reviewed. Neither a worker's completion claim nor Git readiness grants it.
