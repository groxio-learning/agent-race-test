import { incr, expire } from "./store.ts";

export const LIMIT = 100;
export const WINDOW_MS = 60_000;

/**
 * Fixed-window rate limiter: LIMIT requests per customer per WINDOW_MS.
 *
 * The window number is part of the key, so each window gets a fresh counter
 * and correctness never depends on the TTL. The TTL only reclaims memory.
 * We use the store's atomic incr and decide from its return value. A
 * get-then-set would let concurrent requests all read the same count and
 * overshoot the limit.
 */
export async function allowRequest(customerId: string): Promise<boolean> {
  const window = Math.floor(Date.now() / WINDOW_MS);
  const key = `ratelimit:${customerId}:${window}`;
  const count = await incr(key);
  if (count === 1) {
    // First hit in this window. Keep the key past the window's end, then let it go.
    await expire(key, (WINDOW_MS * 2) / 1000);
  }
  return count <= LIMIT;
}
