"""Per-customer rate limiting: 100 requests per minute.

Fixed-window counter kept in the key-value store. Each customer gets one
counter per calendar minute, keyed by the window number, so a new minute
starts a fresh count with no reset step.

Why INCR rather than GET-then-SET: the store is shared by every API process,
and requests for the same customer arrive concurrently. A read-check-write
sequence lets two requests both read 99 and both be admitted. INCR is atomic
in Redis, so every request gets a distinct count and exactly LIMIT of them
see a value <= LIMIT.

Tradeoff: a fixed window allows up to 2 * LIMIT requests across a window
boundary (100 at 0:59, 100 at 1:00). If that matters, switch to a sliding
window; it needs more store round trips per request.
"""
import time

import store

LIMIT = 100
WINDOW_SECONDS = 60

# Wall clock, not monotonic: window numbers must agree across processes and
# hosts. Tests replace this.
_now = time.time


def _key(customer_id, window):
    return f"ratelimit:{customer_id}:{window}"


async def allow_request(customer_id: str) -> bool:
    """Record one request for customer_id and return whether it is allowed."""
    window = int(_now() // WINDOW_SECONDS)
    key = _key(customer_id, window)

    count = await store.incr(key)
    if count == 1:
        # First request in this window creates the key; give it a TTL so old
        # windows don't accumulate. Slightly longer than the window to cover
        # clock skew between hosts. If this call is lost, the key is never
        # read again anyway (the window number moves on); it only leaks.
        await store.expire(key, WINDOW_SECONDS * 2)

    return count <= LIMIT
