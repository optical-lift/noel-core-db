# Expected process reassessment — Laundry first adapter
Held source only. Reuses accepted original Work/care result and existing evidence/current-state structures.
- Explicit total elapsed minutes from the accepted wash-start timestamp; never uses expectedMinutes (active effort).
- Requires same current physical observation and accepted original Work + Need + result. Source record is immutable; state pointer and expected reassessment are atomic.
- Only current signed Household governor may read/write. No cross-Person claim, new tables, generic timers, Work creation, Clock, recurrence or physical completion. Current process superseded by another physical observation does not expose the stale expectation.
- First estimate only; exact action replay supported, competing revised/stale action fails. User can set a time after the expected finish and receive due immediately; next real observation and interval revision require a subsequent governed increment.
- Current Laundry model has a single subject-level physical state, not independently identified loads. Do not claim simultaneous distinct process tracking.
- Test requirements: actual independent signed owner/member/outsider/anonymous sessions; accepted wash start (existing fixture including result policy), initial needs_interval, waiting and due, exact evidence and next_reassess_at, replay, conflicting action, no Work or care observation/result mutation, stale old observation, revoked session. Postconditions are structural only; not proof of execution. No live writes or release.

`validate_signed_process_reassessment.py` extends the previously passed signed original Work fixture proof, including a real one-minute waiting-to-due observation rather than modifying the database clock. Run only on a disposable clone with the existing corrected Laundry fixture and this candidate. This proof has not been executed. It requires an authorized protected carrier for the new exact package.


## Physical wash finish and drying initiation
Extend only the existing exact Household Need/Work/result guards. Human confirmation of wet laundry plus explicit carrier choice establishes original `begin_drying` (no invented date). Actual drying start uses its distinct source/result policy, not wash-start or generic Done. Existing wash-start history remains wash-start. Open wet-load Work cannot be overwritten by another ready observation. This is single-state tracking; actual dry completion, return-to-use and revised waiting estimates remain outside this candidate. The signed test now exercises the exact same original through observed finish, one drying Work, same Person reader, replay, denials and accepted drying start. No release until signed validation.
