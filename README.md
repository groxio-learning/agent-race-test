# agent-race-test

A small, informal experiment: when you ask a coding agent for an ordinary feature, does it write a concurrency bug?

**This is not an exhaustive study.** It is one light exploration, run on one afternoon, with one model family (Claude Sonnet and Opus), small samples, and one run per cell. It shows one example of a mistake an agent made. It is published so readers can see exactly what was asked and exactly what came back, and judge for themselves.

It accompanies *The Bug Your Agent Can't See*, part of Bruce Tate's LinkedIn series on choosing programming languages in the age of coding agents.

## What we did

- 20 fresh agents got plain feature requests: reserve a seat at an event (capacity 10), or rate-limit an API (100 requests per minute per customer). The prompts never mention concurrency, races, locks, atomicity, or load.
- 12 runs named the language (Python, TypeScript, Elixir; Sonnet and Opus). 8 runs said "use whatever programming language you think fits this best."
- Python and TypeScript agents got a Redis-like store client with an atomic `incr`, so the correct answer was easy to write.
- The prompts were written down before any results came in. Every result is reported, including the ones that cut against the hypothesis.

Prompts, verbatim: [PROMPTS.md](PROMPTS.md). Results and caveats: [RESULTS.md](RESULTS.md).

## What we found

- On the textbook case, every agent got it right: it used the atomic increment or a single owning process, explained the race without being asked, and wrote its own concurrency test.
- 3 of 20 runs still shipped a race. All three were in Python, the language Sonnet chose for itself every time it was given the choice. All three were in a feature nobody asked for (one seat per customer), written as a read followed by a write, tested one request at a time, and described as safe.
- No Opus run shipped the race. Two declined to implement the unrequested feature because a read-then-write version "would be the same race."

## Layout

- `runs/` holds the 14 original runs, one folder per cell (`<task>-<language>-<model>`). Those agents started inside the author's writing repo and may have loaded its CLAUDE.md, which discusses Elixir.
- `runs-neutral/` holds 6 reruns of the "your choice" prompt, made with the Claude Code CLI from directories with no CLAUDE.md. `run.sh` is the exact script, and each folder's `_reply.txt` is the agent's full final reply. Local filesystem paths in `run.sh` and in the replies were replaced with `<workdir>`; nothing else in any reply was edited. Set `N` in `run.sh` to a directory of your own before running it.
- `store.py` and `store.ts` are the store clients given to the Python and TypeScript agents.

Each run's own tests are in its folder. Python runs use the standard library (`python3 -m unittest`). TypeScript runs use Node 24 (`node --test`). Elixir runs use Elixir 1.19 (`elixir <file>_test.exs`, or `mix test` where a Mix project was created).

## Reproducing

Agent output varies from run to run. Rerunning the prompts will not give identical code, and may not give the same counts. That is part of the point: a bug that shows up some of the time is the kind that ships.
