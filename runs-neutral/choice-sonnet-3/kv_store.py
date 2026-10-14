"""A tiny in-memory stand-in for a Redis-like key-value store.

Supports just enough of the Redis API (GET, SET with NX/EX, INCRBY, EXPIRE)
for the seat-reservation logic in reservations.py. Swap this out for a real
redis-py client in production; the reservation code only relies on this
interface, not on this implementation.
"""

import time


class InMemoryKVStore:
    def __init__(self):
        self._values = {}
        self._expires_at = {}

    def _is_expired(self, key):
        deadline = self._expires_at.get(key)
        return deadline is not None and time.time() >= deadline

    def _evict_if_expired(self, key):
        if self._is_expired(key):
            self._values.pop(key, None)
            self._expires_at.pop(key, None)

    def get(self, key):
        self._evict_if_expired(key)
        return self._values.get(key)

    def set(self, key, value, nx=False, ex=None):
        """Set key to value. If nx=True, only set when key doesn't already
        exist (mirrors Redis SET ... NX), returning False without writing
        otherwise. ex sets a TTL in seconds (mirrors Redis SET ... EX)."""
        self._evict_if_expired(key)
        if nx and key in self._values:
            return False
        self._values[key] = value
        if ex is not None:
            self._expires_at[key] = time.time() + ex
        else:
            self._expires_at.pop(key, None)
        return True

    def incr(self, key, amount=1):
        """Atomically increment key by amount (default 1) and return the new
        value, mirroring Redis INCRBY. Missing keys start at 0."""
        self._evict_if_expired(key)
        new_value = int(self._values.get(key, 0)) + amount
        self._values[key] = new_value
        return new_value

    def expire(self, key, seconds):
        self._evict_if_expired(key)
        if key not in self._values:
            return False
        self._expires_at[key] = time.time() + seconds
        return True
