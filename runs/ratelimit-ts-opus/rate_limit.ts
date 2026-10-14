// Per-customer rate limiting: 100 requests per minute.
//
// Fixed-window counter. Each customer gets one counter per calendar minute,
// keyed by the window index, e.g. "ratelimit:cust_42:29123456".
//
// Why INCR and not GET-then-SET: GET/compare/SET is a read-modify-write across
// two round trips, so concurrent requests all read the same count and all get
// through. INCR is atomic in the store, so every request receives a distinct
// count and exactly LIMIT of them see a value <= LIMIT.
//
// Why the window index lives in the key: a new minute means a new key, so the
// count resets without depending on TTL timing. The TTL only garbage-collects
// old keys. If the process dies between INCR and EXPIRE, the orphaned key
// can't affect any future window; it just lingers.
//
// Known trade-off of fixed windows: a customer can burst up to 2 * LIMIT
// across a window boundary (100 at 0:59, 100 at 1:00).

import * as store from "./store.ts";

export const LIMIT = 100;
export const WINDOW_SECONDS = 60;

export async function allowRequest(customerId: string): Promise<boolean> {
  const window = Math.floor(Date.now() / (WINDOW_SECONDS * 1000));
  const key = `ratelimit:${customerId}:${window}`;

  const count = await store.incr(key);
  if (count === 1) {
    // First request in this window: make sure the key eventually goes away.
    await store.expire(key, WINDOW_SECONDS * 2);
  }
  return count <= LIMIT;
}
