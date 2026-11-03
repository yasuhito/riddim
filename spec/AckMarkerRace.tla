---------------------------- MODULE AckMarkerRace ----------------------------
EXTENDS TLC

(* --algorithm AckMarkerRace
variables files = {"queue", "presented"}, lock = "free", outcome = "running";

define
  Markers == {"presented", "intent", "handled"}
  TypeOK == files \subseteq {"queue"} \cup Markers /\ lock \in {"free", "ack", "reader"} /\
            outcome \in {"running", "pending", "handled", "deferred", "error"}
  \* A legitimate concurrent ACK never makes the observer fail.
  NoObserverError == outcome # "error"
  \* Omitting the row as handled needs the durable receipt with its intent
  \* withdrawn; reporting it pending again (replay) or deferring is allowed.
  NoInventedHandling == outcome = "handled" => "handled" \in files /\ "intent" \notin files
  QueueRetained == "queue" \in files
  ReaderFinishes == <>(outcome # "running")
end define;

\* Notifications.acknowledge: each file operation is its own step, all inside
\* Ownership.with_lock(task).
fair process acknowledger = "ack"
begin
  AckLock:
    await lock = "free"; lock := "ack";
  PublishIntent:
    files := files \cup {"intent"};
  PublishHandled:
    files := files \cup {"handled"};
  UnlinkIntent:
    files := files \ {"intent"};
  AckUnlock:
    lock := "free";
end process;

\* One watcher poll of Notifications.pending/pending_for (wait: false). The
\* listing, each verify_marker_queue read and each marker? exists/read probe of
\* handled? are separate steps; the scan as a whole is not atomic.
fair process reader = "pending"
variables toRead = {}, handled = FALSE, intent = FALSE;
begin
  ReaderLock:
    either
      await lock = "free"; lock := "reader";
    or
      await lock = "ack"; outcome := "deferred"; goto Done;
    end either;
  List:
    toRead := files \cap Markers;
  VerifyMarkers:
    while toRead # {} do
      with marker \in toRead do
        toRead := toRead \ {marker};
        if marker \notin files then outcome := "error"; lock := "free"; end if;
      end with;
      if outcome = "error" then goto Done; end if;
    end while;
  HandledExists:
    handled := "handled" \in files;
  HandledRead:
    if handled /\ "handled" \notin files then outcome := "error"; lock := "free"; goto Done; end if;
  IntentExists:
    if handled then intent := "intent" \in files; end if;
  IntentRead:
    if intent /\ "intent" \notin files then outcome := "error"; lock := "free"; goto Done; end if;
  Decide:
    if handled /\ ~intent then outcome := "handled"; else outcome := "pending"; end if;
    lock := "free";
end process;
end algorithm; *)
\* BEGIN TRANSLATION (chksum(pcal) = "a423e37a" /\ chksum(tla) = "1b485340")
VARIABLES files, lock, outcome, pc

(* define statement *)
Markers == {"presented", "intent", "handled"}
TypeOK == files \subseteq {"queue"} \cup Markers /\ lock \in {"free", "ack", "reader"} /\
          outcome \in {"running", "pending", "handled", "deferred", "error"}

NoObserverError == outcome # "error"


NoInventedHandling == outcome = "handled" => "handled" \in files /\ "intent" \notin files
QueueRetained == "queue" \in files
ReaderFinishes == <>(outcome # "running")

VARIABLES toRead, handled, intent

vars == << files, lock, outcome, pc, toRead, handled, intent >>

ProcSet == {"ack"} \cup {"pending"}

Init == (* Global variables *)
        /\ files = {"queue", "presented"}
        /\ lock = "free"
        /\ outcome = "running"
        (* Process reader *)
        /\ toRead = {}
        /\ handled = FALSE
        /\ intent = FALSE
        /\ pc = [self \in ProcSet |-> CASE self = "ack" -> "AckLock"
                                        [] self = "pending" -> "ReaderLock"]

AckLock == /\ pc["ack"] = "AckLock"
           /\ lock = "free"
           /\ lock' = "ack"
           /\ pc' = [pc EXCEPT !["ack"] = "PublishIntent"]
           /\ UNCHANGED << files, outcome, toRead, handled, intent >>

PublishIntent == /\ pc["ack"] = "PublishIntent"
                 /\ files' = (files \cup {"intent"})
                 /\ pc' = [pc EXCEPT !["ack"] = "PublishHandled"]
                 /\ UNCHANGED << lock, outcome, toRead, handled, intent >>

PublishHandled == /\ pc["ack"] = "PublishHandled"
                  /\ files' = (files \cup {"handled"})
                  /\ pc' = [pc EXCEPT !["ack"] = "UnlinkIntent"]
                  /\ UNCHANGED << lock, outcome, toRead, handled, intent >>

UnlinkIntent == /\ pc["ack"] = "UnlinkIntent"
                /\ files' = files \ {"intent"}
                /\ pc' = [pc EXCEPT !["ack"] = "AckUnlock"]
                /\ UNCHANGED << lock, outcome, toRead, handled, intent >>

AckUnlock == /\ pc["ack"] = "AckUnlock"
             /\ lock' = "free"
             /\ pc' = [pc EXCEPT !["ack"] = "Done"]
             /\ UNCHANGED << files, outcome, toRead, handled, intent >>

acknowledger == AckLock \/ PublishIntent \/ PublishHandled \/ UnlinkIntent
                   \/ AckUnlock

ReaderLock == /\ pc["pending"] = "ReaderLock"
              /\ \/ /\ lock = "free"
                    /\ lock' = "reader"
                    /\ pc' = [pc EXCEPT !["pending"] = "List"]
                    /\ UNCHANGED outcome
                 \/ /\ lock = "ack"
                    /\ outcome' = "deferred"
                    /\ pc' = [pc EXCEPT !["pending"] = "Done"]
                    /\ lock' = lock
              /\ UNCHANGED << files, toRead, handled, intent >>

List == /\ pc["pending"] = "List"
        /\ toRead' = (files \cap Markers)
        /\ pc' = [pc EXCEPT !["pending"] = "VerifyMarkers"]
        /\ UNCHANGED << files, lock, outcome, handled, intent >>

VerifyMarkers == /\ pc["pending"] = "VerifyMarkers"
                 /\ IF toRead # {}
                       THEN /\ \E marker \in toRead:
                                 /\ toRead' = toRead \ {marker}
                                 /\ IF marker \notin files
                                       THEN /\ outcome' = "error"
                                            /\ lock' = "free"
                                       ELSE /\ TRUE
                                            /\ UNCHANGED << lock, outcome >>
                            /\ IF outcome' = "error"
                                  THEN /\ pc' = [pc EXCEPT !["pending"] = "Done"]
                                  ELSE /\ pc' = [pc EXCEPT !["pending"] = "VerifyMarkers"]
                       ELSE /\ pc' = [pc EXCEPT !["pending"] = "HandledExists"]
                            /\ UNCHANGED << lock, outcome, toRead >>
                 /\ UNCHANGED << files, handled, intent >>

HandledExists == /\ pc["pending"] = "HandledExists"
                 /\ handled' = ("handled" \in files)
                 /\ pc' = [pc EXCEPT !["pending"] = "HandledRead"]
                 /\ UNCHANGED << files, lock, outcome, toRead, intent >>

HandledRead == /\ pc["pending"] = "HandledRead"
               /\ IF handled /\ "handled" \notin files
                     THEN /\ outcome' = "error"
                          /\ lock' = "free"
                          /\ pc' = [pc EXCEPT !["pending"] = "Done"]
                     ELSE /\ pc' = [pc EXCEPT !["pending"] = "IntentExists"]
                          /\ UNCHANGED << lock, outcome >>
               /\ UNCHANGED << files, toRead, handled, intent >>

IntentExists == /\ pc["pending"] = "IntentExists"
                /\ IF handled
                      THEN /\ intent' = ("intent" \in files)
                      ELSE /\ TRUE
                           /\ UNCHANGED intent
                /\ pc' = [pc EXCEPT !["pending"] = "IntentRead"]
                /\ UNCHANGED << files, lock, outcome, toRead, handled >>

IntentRead == /\ pc["pending"] = "IntentRead"
              /\ IF intent /\ "intent" \notin files
                    THEN /\ outcome' = "error"
                         /\ lock' = "free"
                         /\ pc' = [pc EXCEPT !["pending"] = "Done"]
                    ELSE /\ pc' = [pc EXCEPT !["pending"] = "Decide"]
                         /\ UNCHANGED << lock, outcome >>
              /\ UNCHANGED << files, toRead, handled, intent >>

Decide == /\ pc["pending"] = "Decide"
          /\ IF handled /\ ~intent
                THEN /\ outcome' = "handled"
                ELSE /\ outcome' = "pending"
          /\ lock' = "free"
          /\ pc' = [pc EXCEPT !["pending"] = "Done"]
          /\ UNCHANGED << files, toRead, handled, intent >>

reader == ReaderLock \/ List \/ VerifyMarkers \/ HandledExists
             \/ HandledRead \/ IntentExists \/ IntentRead \/ Decide

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == acknowledger \/ reader
           \/ Terminating

Spec == /\ Init /\ [][Next]_vars
        /\ WF_vars(acknowledger)
        /\ WF_vars(reader)

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION 
=============================================================================
