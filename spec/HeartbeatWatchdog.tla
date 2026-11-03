-------------------------- MODULE HeartbeatWatchdog --------------------------
EXTENDS Naturals

\* Discrete seconds. Interval and Grace are the extension's WATCHDOG_INTERVAL
\* and BEAT_TIMEOUT; MaxStall/MaxStalls bound Pi suspensions; Horizon bounds time.
CONSTANTS Interval, Grace, MaxStall, MaxStalls, Horizon

(* --algorithm HeartbeatWatchdog
variables now = 0, pi = "running", stallLeft = 0, stalls = 0,
          watcher = "healthy", pipe = 0, killed = FALSE,
          verifiedAt = 0, lastTick = 0, piStalled = 0, nextDue = Interval,
          sinceFrame = 0;

define
  Max(a, b) == IF a > b THEN a ELSE b
  \* The latest death that still leaves room for every stall and detection.
  DieBy == Horizon - (Grace + 2 * Interval + MaxStalls * MaxStall)
  TypeOK == now \in 0..Horizon /\ pi \in {"running", "suspended"} /\
            stallLeft \in 0..MaxStall /\ stalls \in 0..MaxStalls /\
            watcher \in {"healthy", "dead"} /\ pipe \in 0..2 /\ killed \in BOOLEAN /\
            {verifiedAt, lastTick, piStalled, sinceFrame} \subseteq 0..Horizon
  \* Pi suspension alone never kills a watcher whose frames are queued.
  NoFalseKill == killed => watcher = "dead"
  \* Silence after the last handled frame is detected within the grace plus
  \* one tick of time Pi could run: an earlier stall is never credited to it.
  PromptDetection == watcher = "dead" /\ pipe = 0 /\ ~killed => sinceFrame <= Grace + Interval
  Detected == [](watcher = "dead" => <>killed)
end define;

\* Linux/Node scheduling, abstracted: time passes while Pi is suspended, or
\* when running Pi has no due tick and no readable frame. A healthy watcher
\* beats once per second into a pipe Pi reads only when it runs.
fair process clock = "clock"
begin
  Advance:
    while now < Horizon /\ ~killed do
      await pi = "suspended" \/ (pipe = 0 /\ now < nextDue);
      if pi = "running" then sinceFrame := sinceFrame + 1; end if;
      if watcher = "healthy" then pipe := IF pipe = 2 THEN 2 ELSE pipe + 1; end if;
      if pi = "suspended" then
        if stallLeft = 1 then pi := "running"; end if;
        stallLeft := stallLeft - 1;
      end if;
      now := now + 1;
    end while;
end process;

\* Swap-in, GC or synchronous work suspends Pi, including inside the frame's
\* own I/O callback. Pi resumes after the chosen bounded duration.
process host = "host"
begin
  Suspend:
    while stalls < MaxStalls do
      await pi = "running" /\ ~killed;
      with duration \in 1..MaxStall do
        pi := "suspended"; stallLeft := duration; stalls := stalls + 1;
      end with;
    end while;
end process;

process failure = "watcher"
begin
  Die:
    await now <= DieBy;
    watcher := "dead";
end process;

\* proc.stdout "data": a ready or beat frame. Both this and Tick may be
\* enabled when Pi resumes; TLC explores both orders.
fair process frames = "frames"
begin
  Frame:
    while ~killed do
      await pi = "running" /\ pipe > 0;
      pipe := pipe - 1; verifiedAt := now; piStalled := 0; lastTick := now;
      sinceFrame := 0;
    end while;
end process;

\* The watchdog setInterval callback; a late tick re-arms one interval later.
fair process watchdog = "watchdog"
begin
  Tick:
    while ~killed do
      await pi = "running" /\ now >= nextDue;
      piStalled := piStalled + Max(0, now - lastTick - Interval);
      lastTick := now; nextDue := now + Interval;
      if now - verifiedAt - piStalled > Grace then killed := TRUE; end if;
    end while;
end process;
end algorithm; *)
\* BEGIN TRANSLATION (chksum(pcal) = "72059c89" /\ chksum(tla) = "80d98fcd")
VARIABLES now, pi, stallLeft, stalls, watcher, pipe, killed, verifiedAt, 
          lastTick, piStalled, nextDue, sinceFrame, pc

(* define statement *)
Max(a, b) == IF a > b THEN a ELSE b

DieBy == Horizon - (Grace + 2 * Interval + MaxStalls * MaxStall)
TypeOK == now \in 0..Horizon /\ pi \in {"running", "suspended"} /\
          stallLeft \in 0..MaxStall /\ stalls \in 0..MaxStalls /\
          watcher \in {"healthy", "dead"} /\ pipe \in 0..2 /\ killed \in BOOLEAN /\
          {verifiedAt, lastTick, piStalled, sinceFrame} \subseteq 0..Horizon

NoFalseKill == killed => watcher = "dead"


PromptDetection == watcher = "dead" /\ pipe = 0 /\ ~killed => sinceFrame <= Grace + Interval
Detected == [](watcher = "dead" => <>killed)


vars == << now, pi, stallLeft, stalls, watcher, pipe, killed, verifiedAt, 
           lastTick, piStalled, nextDue, sinceFrame, pc >>

ProcSet == {"clock"} \cup {"host"} \cup {"watcher"} \cup {"frames"} \cup {"watchdog"}

Init == (* Global variables *)
        /\ now = 0
        /\ pi = "running"
        /\ stallLeft = 0
        /\ stalls = 0
        /\ watcher = "healthy"
        /\ pipe = 0
        /\ killed = FALSE
        /\ verifiedAt = 0
        /\ lastTick = 0
        /\ piStalled = 0
        /\ nextDue = Interval
        /\ sinceFrame = 0
        /\ pc = [self \in ProcSet |-> CASE self = "clock" -> "Advance"
                                        [] self = "host" -> "Suspend"
                                        [] self = "watcher" -> "Die"
                                        [] self = "frames" -> "Frame"
                                        [] self = "watchdog" -> "Tick"]

Advance == /\ pc["clock"] = "Advance"
           /\ IF now < Horizon /\ ~killed
                 THEN /\ pi = "suspended" \/ (pipe = 0 /\ now < nextDue)
                      /\ IF pi = "running"
                            THEN /\ sinceFrame' = sinceFrame + 1
                            ELSE /\ TRUE
                                 /\ UNCHANGED sinceFrame
                      /\ IF watcher = "healthy"
                            THEN /\ pipe' = (IF pipe = 2 THEN 2 ELSE pipe + 1)
                            ELSE /\ TRUE
                                 /\ pipe' = pipe
                      /\ IF pi = "suspended"
                            THEN /\ IF stallLeft = 1
                                       THEN /\ pi' = "running"
                                       ELSE /\ TRUE
                                            /\ pi' = pi
                                 /\ stallLeft' = stallLeft - 1
                            ELSE /\ TRUE
                                 /\ UNCHANGED << pi, stallLeft >>
                      /\ now' = now + 1
                      /\ pc' = [pc EXCEPT !["clock"] = "Advance"]
                 ELSE /\ pc' = [pc EXCEPT !["clock"] = "Done"]
                      /\ UNCHANGED << now, pi, stallLeft, pipe, sinceFrame >>
           /\ UNCHANGED << stalls, watcher, killed, verifiedAt, lastTick, 
                           piStalled, nextDue >>

clock == Advance

Suspend == /\ pc["host"] = "Suspend"
           /\ IF stalls < MaxStalls
                 THEN /\ pi = "running" /\ ~killed
                      /\ \E duration \in 1..MaxStall:
                           /\ pi' = "suspended"
                           /\ stallLeft' = duration
                           /\ stalls' = stalls + 1
                      /\ pc' = [pc EXCEPT !["host"] = "Suspend"]
                 ELSE /\ pc' = [pc EXCEPT !["host"] = "Done"]
                      /\ UNCHANGED << pi, stallLeft, stalls >>
           /\ UNCHANGED << now, watcher, pipe, killed, verifiedAt, lastTick, 
                           piStalled, nextDue, sinceFrame >>

host == Suspend

Die == /\ pc["watcher"] = "Die"
       /\ now <= DieBy
       /\ watcher' = "dead"
       /\ pc' = [pc EXCEPT !["watcher"] = "Done"]
       /\ UNCHANGED << now, pi, stallLeft, stalls, pipe, killed, verifiedAt, 
                       lastTick, piStalled, nextDue, sinceFrame >>

failure == Die

Frame == /\ pc["frames"] = "Frame"
         /\ IF ~killed
               THEN /\ pi = "running" /\ pipe > 0
                    /\ pipe' = pipe - 1
                    /\ verifiedAt' = now
                    /\ piStalled' = 0
                    /\ lastTick' = now
                    /\ sinceFrame' = 0
                    /\ pc' = [pc EXCEPT !["frames"] = "Frame"]
               ELSE /\ pc' = [pc EXCEPT !["frames"] = "Done"]
                    /\ UNCHANGED << pipe, verifiedAt, lastTick, piStalled, 
                                    sinceFrame >>
         /\ UNCHANGED << now, pi, stallLeft, stalls, watcher, killed, nextDue >>

frames == Frame

Tick == /\ pc["watchdog"] = "Tick"
        /\ IF ~killed
              THEN /\ pi = "running" /\ now >= nextDue
                   /\ piStalled' = piStalled + Max(0, now - lastTick - Interval)
                   /\ lastTick' = now
                   /\ nextDue' = now + Interval
                   /\ IF now - verifiedAt - piStalled' > Grace
                         THEN /\ killed' = TRUE
                         ELSE /\ TRUE
                              /\ UNCHANGED killed
                   /\ pc' = [pc EXCEPT !["watchdog"] = "Tick"]
              ELSE /\ pc' = [pc EXCEPT !["watchdog"] = "Done"]
                   /\ UNCHANGED << killed, lastTick, piStalled, nextDue >>
        /\ UNCHANGED << now, pi, stallLeft, stalls, watcher, pipe, verifiedAt, 
                        sinceFrame >>

watchdog == Tick

(* Allow infinite stuttering to prevent deadlock on termination. *)
Terminating == /\ \A self \in ProcSet: pc[self] = "Done"
               /\ UNCHANGED vars

Next == clock \/ host \/ failure \/ frames \/ watchdog
           \/ Terminating

Spec == /\ Init /\ [][Next]_vars
        /\ WF_vars(clock)
        /\ WF_vars(frames)
        /\ WF_vars(watchdog)

Termination == <>(\A self \in ProcSet: pc[self] = "Done")

\* END TRANSLATION 
=============================================================================
