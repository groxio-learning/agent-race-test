# Fair test: does an agent write the state bug when asked for a feature?

Recorded 2026-10-14, BEFORE any results. Prompts are given verbatim to fresh subagents, with no other context about this series or its thesis. Each agent works in its own empty folder outside the author's writing repo (so it can't read the planning notes). No retries. Every result gets reported.

Design:
- Tasks: seat reservation (capacity 10), rate limiter (100 per minute per customer).
- Languages: Python, TypeScript, Elixir; plus one "your choice" variant of the seat task.
- Models: Sonnet and Opus, one agent each per cell. 14 agents total.
- No mention of concurrency, races, locks, atomicity, thread safety, or load. No "this runs in production" line: per Bruce, prototypes escape the lab, so the prototype prompt is the realistic one.
- Python and TypeScript get a store client (`store.py`, `store.ts`, copies in this folder) mirroring Redis: get, set (with TTL), incr (atomic), expire, ~1ms per call. The atomic incr is there so a correct solution is easy. Elixir gets no store; it chooses its own state, as is idiomatic.
- Grading by a separate agent afterward: the agent's own tests, a sequential test, a simultaneous burst, spread arrivals; actual counts; and whether the code or comments mention concurrency unprompted.

Every prompt ends with: "No package installs or network access. Work only in {DIR}. When you're done, reply with the files you wrote and how to run the tests."

## seats-python
I'm adding ticket reservations to our app. In `reservations.py`, write `async def reserve_seat(event_id: str, customer_id: str) -> bool`. Each event has 10 seats. Return True if the customer gets a seat and False if the event is sold out. Seat counts live in our key-value store: use the client in `store.py` (it wraps our Redis instance). Include tests.

## seats-ts
I'm adding ticket reservations to our app. In `reservations.ts`, write `export async function reserveSeat(eventId: string, customerId: string): Promise<boolean>`. Each event has 10 seats. Return true if the customer gets a seat and false if the event is sold out. Seat counts live in our key-value store: use the client in `store.ts` (it wraps our Redis instance). We run TypeScript directly on Node 24 with type stripping, no build step; use Node's built-in test runner. Include tests.

## seats-elixir
I'm adding ticket reservations to our app. In `seats.ex`, write a `Seats` module with `reserve_seat(event_id, customer_id)` that returns `:ok` if the customer gets a seat or `{:error, :sold_out}` if the event is sold out. Each event has 10 seats. Keep the counts however you'd normally do it in Elixir. Plain Elixir 1.19, no Mix project or dependencies; it should run with the `elixir` command. Include any setup function it needs, and include tests (an ExUnit .exs file is fine).

## ratelimit-python
I'm adding rate limiting to our API. In `rate_limit.py`, write `async def allow_request(customer_id: str) -> bool`. Each customer may make 100 requests per minute. Return True if this request is allowed and False if they're over the limit. Track counts in our key-value store: use the client in `store.py` (it wraps our Redis instance). Include tests.

## ratelimit-ts
I'm adding rate limiting to our API. In `rate_limit.ts`, write `export async function allowRequest(customerId: string): Promise<boolean>`. Each customer may make 100 requests per minute. Return true if this request is allowed and false if they're over the limit. Track counts in our key-value store: use the client in `store.ts` (it wraps our Redis instance). We run TypeScript directly on Node 24 with type stripping, no build step; use Node's built-in test runner. Include tests.

## ratelimit-elixir
I'm adding rate limiting to our API. In `rate_limit.ex`, write a `RateLimit` module with `allow_request(customer_id)` that returns `true` if this request is allowed or `false` if the customer is over the limit. Each customer may make 100 requests per minute. Keep the counts however you'd normally do it in Elixir. Plain Elixir 1.19, no Mix project or dependencies; it should run with the `elixir` command. Include any setup function it needs, and include tests (an ExUnit .exs file is fine).

## seats-choice
I'm adding ticket reservations to our app. Write a function that reserves a seat for a customer at an event. Each event has 10 seats, and the function should tell the caller whether the customer got a seat or the event is sold out. Use whatever programming language you think fits this best. You can assume a Redis-like key-value store is available (get, set, incr, expire); include a small in-memory stand-in for it so the code runs locally. Include tests. In your final reply, also say which language you chose and why, in one or two sentences.
