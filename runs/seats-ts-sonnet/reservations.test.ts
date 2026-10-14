import { test, beforeEach } from "node:test";
import assert from "node:assert/strict";
import { reset } from "./store.ts";
import { reserveSeat } from "./reservations.ts";

beforeEach(() => reset());

test("first customer gets a seat", async () => {
  assert.equal(await reserveSeat("e1", "c1"), true);
});

test("10 sequential reservations succeed, the 11th fails", async () => {
  for (let i = 1; i <= 10; i++) {
    assert.equal(await reserveSeat("e1", `c${i}`), true, `customer ${i}`);
  }
  assert.equal(await reserveSeat("e1", "c11"), false);
  assert.equal(await reserveSeat("e1", "c12"), false);
});

test("events have independent inventory", async () => {
  for (let i = 0; i < 10; i++) await reserveSeat("a", `c${i}`);
  assert.equal(await reserveSeat("a", "late"), false);
  assert.equal(await reserveSeat("b", "late"), true);
});

test("concurrent reservations never oversell", async () => {
  const results = await Promise.all(
    Array.from({ length: 50 }, (_, i) => reserveSeat("hot", `c${i}`)),
  );
  assert.equal(results.filter(Boolean).length, 10);
  assert.equal(await reserveSeat("hot", "after"), false);
});

test("concurrent reservations with fewer than capacity all succeed", async () => {
  const results = await Promise.all(
    Array.from({ length: 6 }, (_, i) => reserveSeat("small", `c${i}`)),
  );
  assert.ok(results.every(Boolean));
});
