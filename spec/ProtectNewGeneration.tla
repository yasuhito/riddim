---------------------- MODULE ProtectNewGeneration ----------------------
(* --algorithm ProtectNewGeneration
variables recordGen = "old", newPublished = FALSE;

\* Three independent operations on the same name's ownership record.
\* Each labeled step holds the name lock, so comparison and deletion cannot
\* be interleaved with a cooperating publisher.
process properOldCleanup = "proper"
begin
  RemoveOld:
    if recordGen = "old" then
      recordGen := "none";
    end if;
end process;

process newStart = "new"
begin
  PublishNew:
    if recordGen = "none" then
      recordGen := "new";
      newPublished := TRUE;
    end if;
end process;

process delayedOldCleanup = "late"
variables expectedGen = "old";
begin
  RemoveIfOwn:
    if recordGen = expectedGen then
      recordGen := "none";
    end if;
end process;
end algorithm; *)
\* BEGIN TRANSLATION (chksum(pcal) = "43c8f5db" /\ chksum(tla) = "2b4cd272")
VARIABLES recordGen, newPublished, pc, expectedGen

vars == << recordGen, newPublished, pc, expectedGen >>

ProcSet == {"proper"} \cup {"new"} \cup {"late"}

Init == (* Global variables *)
        /\ recordGen = "old"
        /\ newPublished = FALSE
        (* Process delayedOldCleanup *)
        /\ expectedGen = "old"
        /\ pc = [self \in ProcSet |-> CASE self = "proper" -> "RemoveOld"
                                        [] self = "new" -> "PublishNew"
                                        [] self = "late" -> "RemoveIfOwn"]

RemoveOld == /\ pc["proper"] = "RemoveOld"
             /\ IF recordGen = "old"
                   THEN /\ recordGen' = "none"
                   ELSE /\ TRUE
                        /\ UNCHANGED recordGen
             /\ pc' = [pc EXCEPT !["proper"] = "Done"]
             /\ UNCHANGED << newPublished, expectedGen >>

properOldCleanup == RemoveOld

PublishNew == /\ pc["new"] = "PublishNew"
              /\ IF recordGen = "none"
                    THEN /\ recordGen' = "new"
                         /\ newPublished' = TRUE
                    ELSE /\ TRUE
                         /\ UNCHANGED << recordGen, newPublished >>
              /\ pc' = [pc EXCEPT !["new"] = "Done"]
              /\ UNCHANGED expectedGen

newStart == PublishNew

RemoveIfOwn == /\ pc["late"] = "RemoveIfOwn"
               /\ IF recordGen = expectedGen
                     THEN /\ recordGen' = "none"
                     ELSE /\ TRUE
                          /\ UNCHANGED recordGen
               /\ pc' = [pc EXCEPT !["late"] = "Done"]
               /\ UNCHANGED << newPublished, expectedGen >>

delayedOldCleanup == RemoveIfOwn

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == properOldCleanup \/ newStart \/ delayedOldCleanup
           \/ Terminating

Spec == Init /\ [][Next]_vars

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION 

TypeOK == recordGen \in {"none", "old", "new"} /\ newPublished \in BOOLEAN
NewRecordSurvives == newPublished => recordGen = "new"
=============================================================================
