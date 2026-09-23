-------------------------- MODULE ClaimOneName --------------------------
Actors == {"A", "B"}

(* --algorithm ClaimOneName
variables recordOwner = "none", published = {};

process caller \in Actors
variables sawEmpty = FALSE;
begin
  Check:
    sawEmpty := (recordOwner = "none");
  Publish:
    \* The record's no-replace publication is one atomic operation.
    \* Both callers may have seen it empty at Check, but only one can publish.
    if sawEmpty /\ recordOwner = "none" then
      recordOwner := self;
      published := published \cup {self};
    end if;
end process;
end algorithm; *)
\* BEGIN TRANSLATION (chksum(pcal) = "e4867523" /\ chksum(tla) = "8bf42656")
VARIABLES recordOwner, published, pc, sawEmpty

vars == << recordOwner, published, pc, sawEmpty >>

ProcSet == (Actors)

Init == (* Global variables *)
        /\ recordOwner = "none"
        /\ published = {}
        (* Process caller *)
        /\ sawEmpty = [self \in Actors |-> FALSE]
        /\ pc = [self \in ProcSet |-> "Check"]

Check(self) == /\ pc[self] = "Check"
               /\ sawEmpty' = [sawEmpty EXCEPT ![self] = (recordOwner = "none")]
               /\ pc' = [pc EXCEPT ![self] = "Publish"]
               /\ UNCHANGED << recordOwner, published >>

Publish(self) == /\ pc[self] = "Publish"
                 /\ IF sawEmpty[self] /\ recordOwner = "none"
                       THEN /\ recordOwner' = self
                            /\ published' = (published \cup {self})
                       ELSE /\ TRUE
                            /\ UNCHANGED << recordOwner, published >>
                 /\ pc' = [pc EXCEPT ![self] = "Done"]
                 /\ UNCHANGED sawEmpty

caller(self) == Check(self) \/ Publish(self)

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == (\E self \in Actors: caller(self))
           \/ Terminating

Spec == Init /\ [][Next]_vars

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION 

TypeOK == recordOwner \in Actors \cup {"none"} /\ published \subseteq Actors
NeverTwoPublished == ~("A" \in published /\ "B" \in published)
RecordMatchesPublication ==
  (recordOwner = "none" /\ published = {}) \/
  (recordOwner \in Actors /\ published = {recordOwner})
=============================================================================
