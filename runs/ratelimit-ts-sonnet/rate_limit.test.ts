import { test, beforeEach, mock } from "node:test";
import assert from "node:assert/strict";
import { allowRequest } from "./rate_limit.ts";
import { reset } from "./store.ts";

beforeEach(() => {
  mock.timers.reset();
  reset();
});

test("allows the first 100 requests and rejects the 101st", async () => {
  for (let i = 0; i < 100; i++) {
    assert.equal(await allowRequest("a"), true, `request ${i + 1}`);
  }
  assert.equal(await allowRequest("a"), false);
  assert.equal(await allowRequest("a"), false);
});

test("customers are limited independently", async () => {
  for (let i = 0; i < 100; i++) await allowRequest("a");
  assert.equal(await allowRequest("a"), false);
  assert.equal(await allowRequest("b"), true);
});

test("concurrent requests cannot exceed the limit", async () => {
  const results = await Promise.all(
    Array.from({ length: 250 }, () => allowRequest("burst")),
  );
  assert.equal(results.filter(Boolean).length, 100);
  assert.equal(results.filter((r) => !r).length, 150);
});

test("limit resets in the next minute", async () => {
  const realNow = Date.now();
  const start = Math.ceil(realNow / 60_000) * 60_000; // a window boundary
  mock.timers.enable({ apis: ["Date"], now: start });
  for (let i = 0; i < 100; i++) await allowRequest("a");
  assert.equal(await allowRequest("a"), false);
  mock.timers.setTime(start + 59_999);
  assert.equal(await allowRequest("a"), false);
  mock.timers.setTime(start + 60_000);
  assert.equal(await allowRequest("a"), true);
});
