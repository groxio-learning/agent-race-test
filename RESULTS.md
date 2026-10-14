# Fair test results (2026-10-14)

Design and verbatim prompts: `PROMPTS.md` (recorded before any results). Each agent's code: `runs/<cell>/`. Results below come from each agent's own report and its own passing tests. The separate grader was skipped, because every agent wrote and passed its own concurrency test, and the interesting findings are design choices rather than counts.

## Summary

| Cell | Model | Correct under concurrency | Explained the race unprompted | Own concurrency test | Notes |
|---|---|---|---|---|---|
| seats-python | Sonnet | Yes (atomic incr, compare) | Yes | 50 concurrent, exactly 10 | customer_id unused |
| seats-python | Opus | Yes (atomic incr, compare) | Yes ("both read 9, both write 10") | 100 concurrent, plus 3 events | Declined to add a read-then-write repeat-customer check: would reintroduce the race; needs SETNX |
| seats-ts | Sonnet | Yes (atomic incr) | Yes | 50 concurrent | customer_id unused |
| seats-ts | Opus | Yes (atomic incr) | Yes | 100 concurrent ("the test that catches a get-then-set version") | Sketched a safe per-customer guard with rollback |
| seats-elixir | Sonnet | Yes (Agent.get_and_update) | Yes | 100 concurrent | Tracked customers in a MapSet inside the Agent; retries are idempotent |
| seats-elixir | Opus | Yes (GenServer.call) | Yes | 1,000 concurrent; 50 events x 30 | Proposed fix for one-seat-per-customer stays inside the owning process |
| ratelimit-python | Sonnet | Yes (per-minute key, atomic incr) | Yes | 250 concurrent, exactly 100 | Flagged boundary burst (up to 200) |
| ratelimit-python | Opus | Yes | Yes | 250 concurrent | Flagged boundary burst; denied requests still count |
| ratelimit-ts | Sonnet | Yes | Yes | 250 concurrent | Flagged boundary burst |
| ratelimit-ts | Opus | Yes | Yes | 250 concurrent; 5 customers x 150; faked only the clock so requests genuinely overlap | Flagged boundary burst |
| ratelimit-elixir | Sonnet | Yes (:ets.update_counter) | Yes | 1,000 concurrent | Warned that the ETS table dies with whatever process calls setup; left it to the caller |
| ratelimit-elixir | Opus | Yes (:ets.update_counter, capped) | Yes | 1,000 concurrent; 20 customers | Put the ETS table under a small supervised GenServer that owns it and cleans old minutes |
| seats-choice | Sonnet | Seat count yes; repeat customers NO | Yes | 50 threads | **Chose Python**: "any language fits... installed, no setup, quickest to read and run." Repeat-customer check is a get then set; knowingly shipped with a comment to "guard that upstream if it matters." |
| seats-choice | Opus | Yes | Yes | 500 concurrent | **Chose Elixir**: "reservations are a concurrency problem." Declined to add a half-safe one-seat-per-customer check. |

## Findings

1. **Asked for a feature, these agents did not write the classic check-then-act race.** 12 of 12 fixed-language runs were correct, explained the race without being asked, and wrote their own concurrency test. When the store offers an atomic increment, they use it. When the language offers a single owner for state, they use it. The constructed examples in `../state-examples/` show the bug is possible; they do not show agents write it. The article must not claim they do.
2. **The crack appears when requirements outgrow the tools.** "One seat per customer" needs an atomic operation the store doesn't offer. Opus agents declined to fake it. The Sonnet choice agent shipped a read-then-write with a comment deferring the risk. In a prototype that escapes the lab, that comment is where the bug lives.
3. **In Elixir, the same requirement growth stays safe.** More data inside the process that already owns the state opens no new gap (Sonnet's MapSet; Opus's proposed fix).
4. **Operations show up even here.** Sonnet's Elixir rate limiter left ETS table ownership to the caller (the table dies with its owner). Opus built a supervised owner. Neither was asked.
5. **Language choice split by model:** Sonnet chose Python for convenience; Opus chose Elixir for concurrency. These agents started in this repo's directory and may have loaded the project CLAUDE.md. The neutral rerun (below) mostly confirms the split, with one twist: Opus's first instinct was Go.

## Caveats

- One run per cell; small sample. Single model family (Claude Sonnet and Opus).
- The store client included an atomic incr by design, which makes the correct answer easy. That's fair, and it's also part of the finding.
- Fixed-language agents also started in this repo's directory (same CLAUDE.md caveat). Their prompts named the language, so the caveat matters less there, but it's not zero: the file's values could prime care.

## Neutral-directory rerun of the language choice

Run with the Claude Code CLI (`claude -p`, v2.1.220) from directories outside the repo: no project CLAUDE.md, empty user CLAUDE.md (a smoke test confirmed no CLAUDE.md in context). Same seats-choice prompt, verbatim. 3 runs per model. Script and code: `runs-neutral/`.

| Run | Language | Stated reason (paraphrased) | Repeat-customer handling |
|---|---|---|---|
| sonnet-1 | Python | runs anywhere on the stdlib; unittest and threading prove race-safety | Added unprompted. get customer key, then incr, then set: two simultaneous requests from one customer can take two seats. Its idempotency test is sequential, so it passes. |
| sonnet-2 | Python | short algorithm; stdlib proves the no-oversell guarantee | Same get-then-set pattern, same race. Its reply claims repeat calls are idempotent "instead of double-booking", which is true only sequentially. |
| sonnet-3 | Python | zero setup, readable reference implementation | Added SET NX to its own store and used it: race-safe. |
| opus-1 | Elixir | "Go was my first instinct but isn't installed here"; a GenServer is a faithful stand-in for Redis's single-threaded loop | Declined: a get-then-set imitation "would be the same race"; wrote a test asserting the limitation. |
| opus-2 | Elixir | "Go wasn't installed on this machine"; the oversell bug is a race and the BEAM let it test real concurrency | Declined: needs SETNX. Also flagged seats_available as advisory only. |
| opus-3 | Python | single function plus tests; stdlib covers concurrency with zero dependencies | Added unprompted, race-safe (an incr-returns-1 claim on the customer key), with a concurrent test: one customer clicking 25 times takes one seat. |

All six were correct on the seat count (atomic incr), and all six wrote a concurrency test.

### What the rerun shows

- **Sonnet chose Python 3 of 3 with no project context.** The original Sonnet choice result holds. Its reasons are convenience: zero setup, stdlib, readable.
- **Opus did not choose Elixir because of our CLAUDE.md.** With no project context it chose Elixir 2 of 3 and Python 1 of 3. But both Elixir runs say Go was the first instinct and wasn't installed. So the honest summary for Opus: it reasoned from the problem (concurrency) more than Sonnet did, its first pick was Go, and the machine's toolchain decided between Go and Elixir.
- **The original Opus "your choice" Elixir pick is consistent with the neutral runs**, so contamination is not needed to explain it, but it can't be ruled out for that single run.
- **The repeat-customer race appeared again, unprompted, in 2 of 3 Sonnet runs.** Nobody asked for one-seat-per-customer. Sonnet added it as a nicety, implemented it as a read then a write, tested it sequentially, and reported it as idempotent. Combined with the original Sonnet choice run, that's 3 of 4 Sonnet "your choice" runs shipping this race. 0 of 4 Opus runs did: two declined, two implemented it safely (opus-3 here; the original run declined).
- Small samples. One model family. Treat as illustration, consistent with the series' evidence bar.

