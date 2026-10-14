"""Per-customer rate limiting: fixed one-minute windows backed by the store."""
import time

import store

LIMIT = 100
WINDOW_SECONDS = 60


def _now() -> float:
    return time.time()


async def allow_request(customer_id: str) -> bool:
    """Return True if this request is within the customer's limit.

    Uses a fixed window: one counter per customer per wall-clock minute. The
    counter is bumped with the store's atomic incr, so concurrent requests
    each get a distinct count and exactly LIMIT of them are allowed. (A
    get-then-set would let concurrent requests read the same value and
    undercount.)
    """
    window = int(_now() // WINDOW_SECONDS)
    key = f"ratelimit:{customer_id}:{window}"
    count = await store.incr(key)
    if count == 1:
        # First hit in this window: let the counter clean itself up. The
        # window id is in the key, so a missed expire can't leak counts into
        # a later window; it only leaves a stale key behind.
        await store.expire(key, WINDOW_SECONDS)
    return count <= LIMIT
