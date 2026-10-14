"""A minimal in-memory stand-in for a Redis-like key-value store.

Implements just the primitives reservations.py needs: get, set, incr, expire.
A single lock makes each call atomic, mirroring the fact that real Redis
executes each command atomically on its single event loop.
"""

import threading
import time


class InMemoryStore:
    def __init__(self):
        self._data = {}  # key -> [value, expires_at_or_None]
        self._lock = threading.Lock()

    def get(self, key):
        """Return the value at `key` as a string, or None if absent/expired (like real Redis)."""
        with self._lock:
            self._drop_if_expired(key)
            entry = self._data.get(key)
            return entry[0] if entry else None

    def set(self, key, value):
        with self._lock:
            self._data[key] = [str(value), None]

    def incr(self, key, amount=1):
        """Atomically add `amount` to the integer at `key` (default 0) and return the new value."""
        with self._lock:
            self._drop_if_expired(key)
            entry = self._data.get(key)
            current = int(entry[0]) if entry else 0
            new_value = current + amount
            if entry:
                entry[0] = str(new_value)
            else:
                self._data[key] = [str(new_value), None]
            return new_value

    def expire(self, key, ttl_seconds):
        """Set a TTL (in seconds) on an existing key. Returns False if the key doesn't exist."""
        with self._lock:
            self._drop_if_expired(key)
            if key not in self._data:
                return False
            self._data[key][1] = time.time() + ttl_seconds
            return True

    def _drop_if_expired(self, key):
        entry = self._data.get(key)
        if entry is not None and entry[1] is not None and time.time() >= entry[1]:
            del self._data[key]
