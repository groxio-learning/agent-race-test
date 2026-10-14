import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import * as store from "./store.ts";
import { reserveSeat, SEATS_PER_EVENT } from "./reservations.ts";

beforeEach(() => store.reset());

test("first ten reservations succeed, the eleventh is refused", async () => {
  for (let i = 0; i < SEATS_PER_EVENT; i++) {
    assert.equal(await reserveSeat("show", `c${i}`), true, `seat ${i + 1}`);
  }
  assert.equal(await reserveSeat("show", "late"), false);
  assert.equal(await reserveSeat("show", "later"), false);
});

test("concurrent requests never oversell", async () => {
  const results = await Promise.all(
    Array.from({ length: 100 }, (_, i) => reserveSeat("hot-show", `c${i}`)),
  );
  assert.equal(results.filter(Boolean).length, SEATS_PER_EVENT);
  assert.equal(results.filter((r) => !r).length, 100 - SEATS_PER_EVENT);
});

test("concurrent requests exactly at capacity all succeed", async () => {
  const results = await Promise.all(
    Array.from({ length: SEATS_PER_EVENT }, (_, i) => reserveSeat("exact", `c${i}`)),
  );
  assert.ok(results.every(Boolean));
  assert.equal(await reserveSeat("exact", "one-more"), false);
});

test("events have independent seat counts", async () => {
  await Promise.all(
    Array.from({ length: SEATS_PER_EVENT }, (_, i) => reserveSeat("a", `c${i}`)),
  );
  assert.equal(await reserveSeat("a", "x"), false);
  assert.equal(await reserveSeat("b", "x"), true);
});
