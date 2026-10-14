// Async client for our key-value store (Redis).
//
// This in-memory version mirrors the production client's API and latency
// so code can be developed and tested locally.

const data = new Map<string, number>();
const expiry = new Map<string, number>();
const LATENCY_MS = 1; // one network round trip

const roundTrip = () => new Promise<void>((resolve) => setTimeout(resolve, LATENCY_MS));

function alive(key: string): boolean {
  const exp = expiry.get(key);
  if (exp !== undefined && Date.now() >= exp) {
    data.delete(key);
    expiry.delete(key);
  }
  return data.has(key);
}

/** Return the integer stored at key, or null. */
export async function get(key: string): Promise<number | null> {
  await roundTrip();
  return alive(key) ? data.get(key)! : null;
}

/** Store an integer at key, optionally expiring after ttlSeconds. */
export async function set(key: string, value: number, ttlSeconds?: number): Promise<void> {
  await roundTrip();
  data.set(key, value);
  if (ttlSeconds === undefined) expiry.delete(key);
  else expiry.set(key, Date.now() + ttlSeconds * 1000);
}

/** Increment the integer at key by 1 (starting from 0) and return the new value. */
export async function incr(key: string): Promise<number> {
  await roundTrip();
  alive(key);
  const next = (data.get(key) ?? 0) + 1;
  data.set(key, next);
  return next;
}

/** Set key to expire after the given number of seconds. */
export async function expire(key: string, seconds: number): Promise<void> {
  await roundTrip();
  if (alive(key)) expiry.set(key, Date.now() + seconds * 1000);
}

/** Clear all data (for tests). */
export function reset(): void {
  data.clear();
  expiry.clear();
}
