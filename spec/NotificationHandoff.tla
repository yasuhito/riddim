---------------------- MODULE NotificationHandoff ----------------------
EXTENDS Naturals, Sequences, TLC

(* --algorithm NotificationHandoff
variables serial = "A", active = TRUE,
          child = "aInitial", readyChild = "aInitial", inFlight = "none",
          accepted = {}, rows = {1}, published = {1}, handled = {},
          failures = 0, oldPending = FALSE, trace = <<>>;

\* One same-factory shutdown/start, a stable source, two ordinary reports.
\* Each label is atomic; await/send boundaries are separate labels.
process lifecycle = "sessions"
begin
  OfferA:
    accepted := {1};
    child := "aSuccessor"; readyChild := "aSuccessor";
    inFlight := "A"; oldPending := TRUE;
    trace := Append(trace, "OfferA");
  ShutdownA:
    active := FALSE; serial := "B";
    child := "none"; readyChild := "none"; accepted := {};
    trace := Append(trace, "ShutdownA");
  StartB:
    active := TRUE;
    child := "bInitial"; readyChild := "bInitial";
    trace := Append(trace, "StartB");
  OfferB1:
    accepted := {1}; inFlight := "B";
    child := "bSuccessor1"; readyChild := "bSuccessor1";
    trace := Append(trace, "OfferB1");
  FinishB1:
    if inFlight = "B" then inFlight := "none"; end if;
  Publish2:
    published := published \cup {2}; rows := rows \cup {2};
    trace := Append(trace, "Publish2");
  OfferB2:
    accepted := accepted \cup {2}; inFlight := "B";
    child := "bSuccessor2"; readyChild := "bSuccessor2";
    trace := Append(trace, "OfferB2");
  FinishB2:
    if inFlight = "B" then inFlight := "none"; end if;
  ShutdownB:
    active := FALSE; serial := "retired";
    child := "none"; readyChild := "none"; accepted := {};
    trace := Append(trace, "ShutdownB");
end process;

process completion = "old"
variables outcome = "pending";
begin
  WaitA:
    await oldPending;
    either outcome := "resolve"; or outcome := "reject"; end either;
  SettleA:
    \* deliver catch: the selected stale-epoch guard. failure() independently
    \* checks active/serial, and killing independently checks process identity.
    if outcome = "reject" /\ serial = "A" then
      accepted := accepted \ {1};
      if child = "aSuccessor" then readyChild := "none"; end if;
      if active /\ serial = "A" then failures := failures + 1; end if;
    end if;
    \* deliver finally: shutdown intentionally does not clear an old inFlight.
    if inFlight = "A" then inFlight := "none"; end if;
    if outcome = "reject" then trace := Append(trace, "RejectA");
    else trace := Append(trace, "ResolveA"); end if;
end process;
end algorithm; *)
\* BEGIN TRANSLATION (chksum(pcal) = "82187e4" /\ chksum(tla) = "9f709a9c")
VARIABLES serial, active, child, readyChild, inFlight, accepted, rows, 
          published, handled, failures, oldPending, trace, pc, outcome

vars == << serial, active, child, readyChild, inFlight, accepted, rows, 
           published, handled, failures, oldPending, trace, pc, outcome >>

ProcSet == {"sessions"} \cup {"old"}

Init == (* Global variables *)
        /\ serial = "A"
        /\ active = TRUE
        /\ child = "aInitial"
        /\ readyChild = "aInitial"
        /\ inFlight = "none"
        /\ accepted = {}
        /\ rows = {1}
        /\ published = {1}
        /\ handled = {}
        /\ failures = 0
        /\ oldPending = FALSE
        /\ trace = <<>>
        (* Process completion *)
        /\ outcome = "pending"
        /\ pc = [self \in ProcSet |-> CASE self = "sessions" -> "OfferA"
                                        [] self = "old" -> "WaitA"]

OfferA == /\ pc["sessions"] = "OfferA"
          /\ accepted' = {1}
          /\ child' = "aSuccessor"
          /\ readyChild' = "aSuccessor"
          /\ inFlight' = "A"
          /\ oldPending' = TRUE
          /\ trace' = Append(trace, "OfferA")
          /\ pc' = [pc EXCEPT !["sessions"] = "ShutdownA"]
          /\ UNCHANGED << serial, active, rows, published, handled, failures, 
                          outcome >>

ShutdownA == /\ pc["sessions"] = "ShutdownA"
             /\ active' = FALSE
             /\ serial' = "B"
             /\ child' = "none"
             /\ readyChild' = "none"
             /\ accepted' = {}
             /\ trace' = Append(trace, "ShutdownA")
             /\ pc' = [pc EXCEPT !["sessions"] = "StartB"]
             /\ UNCHANGED << inFlight, rows, published, handled, failures, 
                             oldPending, outcome >>

StartB == /\ pc["sessions"] = "StartB"
          /\ active' = TRUE
          /\ child' = "bInitial"
          /\ readyChild' = "bInitial"
          /\ trace' = Append(trace, "StartB")
          /\ pc' = [pc EXCEPT !["sessions"] = "OfferB1"]
          /\ UNCHANGED << serial, inFlight, accepted, rows, published, handled, 
                          failures, oldPending, outcome >>

OfferB1 == /\ pc["sessions"] = "OfferB1"
           /\ accepted' = {1}
           /\ inFlight' = "B"
           /\ child' = "bSuccessor1"
           /\ readyChild' = "bSuccessor1"
           /\ trace' = Append(trace, "OfferB1")
           /\ pc' = [pc EXCEPT !["sessions"] = "FinishB1"]
           /\ UNCHANGED << serial, active, rows, published, handled, failures, 
                           oldPending, outcome >>

FinishB1 == /\ pc["sessions"] = "FinishB1"
            /\ IF inFlight = "B"
                  THEN /\ inFlight' = "none"
                  ELSE /\ TRUE
                       /\ UNCHANGED inFlight
            /\ pc' = [pc EXCEPT !["sessions"] = "Publish2"]
            /\ UNCHANGED << serial, active, child, readyChild, accepted, rows, 
                            published, handled, failures, oldPending, trace, 
                            outcome >>

Publish2 == /\ pc["sessions"] = "Publish2"
            /\ published' = (published \cup {2})
            /\ rows' = (rows \cup {2})
            /\ trace' = Append(trace, "Publish2")
            /\ pc' = [pc EXCEPT !["sessions"] = "OfferB2"]
            /\ UNCHANGED << serial, active, child, readyChild, inFlight, 
                            accepted, handled, failures, oldPending, outcome >>

OfferB2 == /\ pc["sessions"] = "OfferB2"
           /\ accepted' = (accepted \cup {2})
           /\ inFlight' = "B"
           /\ child' = "bSuccessor2"
           /\ readyChild' = "bSuccessor2"
           /\ trace' = Append(trace, "OfferB2")
           /\ pc' = [pc EXCEPT !["sessions"] = "FinishB2"]
           /\ UNCHANGED << serial, active, rows, published, handled, failures, 
                           oldPending, outcome >>

FinishB2 == /\ pc["sessions"] = "FinishB2"
            /\ IF inFlight = "B"
                  THEN /\ inFlight' = "none"
                  ELSE /\ TRUE
                       /\ UNCHANGED inFlight
            /\ pc' = [pc EXCEPT !["sessions"] = "ShutdownB"]
            /\ UNCHANGED << serial, active, child, readyChild, accepted, rows, 
                            published, handled, failures, oldPending, trace, 
                            outcome >>

ShutdownB == /\ pc["sessions"] = "ShutdownB"
             /\ active' = FALSE
             /\ serial' = "retired"
             /\ child' = "none"
             /\ readyChild' = "none"
             /\ accepted' = {}
             /\ trace' = Append(trace, "ShutdownB")
             /\ pc' = [pc EXCEPT !["sessions"] = "Done"]
             /\ UNCHANGED << inFlight, rows, published, handled, failures, 
                             oldPending, outcome >>

lifecycle == OfferA \/ ShutdownA \/ StartB \/ OfferB1 \/ FinishB1
                \/ Publish2 \/ OfferB2 \/ FinishB2 \/ ShutdownB

WaitA == /\ pc["old"] = "WaitA"
         /\ oldPending
         /\ \/ /\ outcome' = "resolve"
            \/ /\ outcome' = "reject"
         /\ pc' = [pc EXCEPT !["old"] = "SettleA"]
         /\ UNCHANGED << serial, active, child, readyChild, inFlight, accepted, 
                         rows, published, handled, failures, oldPending, trace >>

SettleA == /\ pc["old"] = "SettleA"
           /\ IF outcome = "reject" /\ serial = "A"
                 THEN /\ accepted' = accepted \ {1}
                      /\ IF child = "aSuccessor"
                            THEN /\ readyChild' = "none"
                            ELSE /\ TRUE
                                 /\ UNCHANGED readyChild
                      /\ IF active /\ serial = "A"
                            THEN /\ failures' = failures + 1
                            ELSE /\ TRUE
                                 /\ UNCHANGED failures
                 ELSE /\ TRUE
                      /\ UNCHANGED << readyChild, accepted, failures >>
           /\ IF inFlight = "A"
                 THEN /\ inFlight' = "none"
                 ELSE /\ TRUE
                      /\ UNCHANGED inFlight
           /\ IF outcome = "reject"
                 THEN /\ trace' = Append(trace, "RejectA")
                 ELSE /\ trace' = Append(trace, "ResolveA")
           /\ pc' = [pc EXCEPT !["old"] = "Done"]
           /\ UNCHANGED << serial, active, child, rows, published, handled, 
                           oldPending, outcome >>

completion == WaitA \/ SettleA

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == lifecycle \/ completion
           \/ Terminating

Spec == Init /\ [][Next]_vars

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION 

\* Translation is generated by pcal.trans, never edited by hand.

TypeOK == /\ serial \in {"A", "B", "retired"}
          /\ active \in BOOLEAN
          /\ child \in {"none", "aInitial", "aSuccessor", "bInitial",
                         "bSuccessor1", "bSuccessor2"}
          /\ readyChild \in {"none", child}
          /\ inFlight \in {"none", "A", "B"}
          /\ accepted \subseteq {1, 2}
          /\ rows \subseteq {1, 2} /\ published \subseteq {1, 2}
          /\ handled \subseteq rows /\ failures \in 0..1

\* No human handling/ACK is in this bounded scenario. Pi acceptance never ACKs.
UnhandledRecoverable == published \subseteq (rows \ handled) /\ handled = {}

\* Check the actual transition, not just a final-state/no-error assertion.
\* A stale finally may release its own A flight, but never B's flight.
LatePredecessorIsolated ==
  [][(SettleA /\ serial # "A") =>
       (UNCHANGED <<accepted, child, readyChild, failures>> /\
        (inFlight # "A" => UNCHANGED inFlight))]_vars
=============================================================================
