---------------------- MODULE RetainRecordUntilGone ----------------------
(* --algorithm RetainRecordUntilGone
variables recordPresent = TRUE, closeSucceeded = FALSE, panePresence = "unread";
begin
  CloseExactPane:
    with outcome \in {"succeeded", "failed"} do
      closeSucceeded := (outcome = "succeeded");
    end with;
  ReadExactPane:
    if closeSucceeded then
      with answer \in {"gone", "present", "unknown"} do
        panePresence := answer;
      end with;
    end if;
  RemoveOwnRecord:
    \* Only a successful close followed by an exact pane_not_found proof
    \* permits deleting this start's own record under the name lock.
    if closeSucceeded /\ panePresence = "gone" then
      recordPresent := FALSE;
    end if;
end algorithm; *)
\* BEGIN TRANSLATION (chksum(pcal) = "88687c8" /\ chksum(tla) = "78043ef1")
VARIABLES recordPresent, closeSucceeded, panePresence, pc

vars == << recordPresent, closeSucceeded, panePresence, pc >>

Init == (* Global variables *)
        /\ recordPresent = TRUE
        /\ closeSucceeded = FALSE
        /\ panePresence = "unread"
        /\ pc = "CloseExactPane"

CloseExactPane == /\ pc = "CloseExactPane"
                  /\ \E outcome \in {"succeeded", "failed"}:
                       closeSucceeded' = (outcome = "succeeded")
                  /\ pc' = "ReadExactPane"
                  /\ UNCHANGED << recordPresent, panePresence >>

ReadExactPane == /\ pc = "ReadExactPane"
                 /\ IF closeSucceeded
                       THEN /\ \E answer \in {"gone", "present", "unknown"}:
                                 panePresence' = answer
                       ELSE /\ TRUE
                            /\ UNCHANGED panePresence
                 /\ pc' = "RemoveOwnRecord"
                 /\ UNCHANGED << recordPresent, closeSucceeded >>

RemoveOwnRecord == /\ pc = "RemoveOwnRecord"
                   /\ IF closeSucceeded /\ panePresence = "gone"
                         THEN /\ recordPresent' = FALSE
                         ELSE /\ TRUE
                              /\ UNCHANGED recordPresent
                   /\ pc' = "Done"
                   /\ UNCHANGED << closeSucceeded, panePresence >>

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == pc = "Done" /\ UNCHANGED vars

Next == CloseExactPane \/ ReadExactPane \/ RemoveOwnRecord
           \/ Terminating

Spec == Init /\ [][Next]_vars

Termination == <>(pc = "Done")

\* END TRANSLATION 

TypeOK == recordPresent \in BOOLEAN /\ closeSucceeded \in BOOLEAN
  /\ panePresence \in {"unread", "gone", "present", "unknown"}
UnconfirmedKeepsRecord == (~closeSucceeded \/ panePresence # "gone") => recordPresent
=============================================================================
