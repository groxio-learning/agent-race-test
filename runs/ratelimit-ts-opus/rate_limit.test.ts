import { test, beforeEach, afterEach, mock } from "node:test";
import assert from "node:assert/strict";

import { allowRequest, LIMIT } from "./rate_limit.ts";
import * as store from "./store.ts";

// Mock only Date. The store uses real setTimeout for simulated latency.
const START = Date.UTC(2026, 0, 1, 12, 0, 0); // exactly on a minute boundary

beforeEach(() => {
  store.reset();
  mock.timers.enable({ apis: ["Date"], now: START });
});

afterEach(() => {
  mock.timers.reset();
});

async function sequential(customerId: string, n: number): Promise<boolean[]> {
  const out: boolean[] = [];
  for (let i = 0; i < n; i++) out.push(await allowRequest(customerId));
  return out;
}

test("allows the first 100 requests in a minute", async () => {
  const results = await sequential("alice", LIMIT);
  assert.ok(results.every((r) => r === true));
});

test("rejects request 101 and beyond", async () => {
  await sequential("alice", LIMIT);
  assert.equal(await allowRequest("alice"), false);
  assert.equal(await allowRequest("alice"), false);
});

test("customers are limited independently", async () => {
  await sequential("alice", LIMIT);
  assert.equal(await allowRequest("alice"), false);
  assert.equal(await allowRequest("bob"), true);
});

test("limit resets in the next minute", async () => {
  await sequential("alice", LIMIT);
  assert.equal(await allowRequest("alice"), false);

  mock.timers.setTime(START + 59_999);
  assert.equal(await allowRequest("alice"), false, "still the same window");

  mock.timers.setTime(START + 60_000);
  assert.equal(await allowRequest("alice"), true, "new window");
});

test("concurrent requests never exceed the limit", async () => {
  // All requests in flight at once. A get-then-set implementation lets far
  // more than 100 through here; INCR must admit exactly 100.
  const results = await Promise.all(
    Array.from({ length: 250 }, () => allowRequest("alice")),
  );
  assert.equal(results.filter(Boolean).length, LIMIT);
});

test("concurrent bursts across many customers are each limited", async () => {
  const customers = ["a", "b", "c", "d", "e"];
  const calls = customers.flatMap((c) =>
    Array.from({ length: 150 }, () => allowRequest(c).then((ok) => [c, ok] as const)),
  );
  const results = await Promise.all(calls);
  for (const c of customers) {
    const allowed = results.filter(([id, ok]) => id === c && ok).length;
    assert.equal(allowed, LIMIT, `customer ${c}`);
  }
});

test("window keys get a TTL so old counters are cleaned up", async () => {
  await allowRequest("alice");
  // Jump well past the TTL; the old window's key should be gone.
  mock.timers.setTime(START + 10 * 60_000);
  const oldKey = `ratelimit:alice:${Math.floor(START / 60_000)}`;
  assert.equal(await store.get(oldKey), null);
});
