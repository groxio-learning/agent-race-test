"""Tiny in-memory stand-in for a Redis-like store: get, set, incr, expire."""
import threading
import time


class FakeRedis:
    def __init__(self, clock=time.monotonic):
        self._data = {}
        self._expires = {}
        self._lock = threading.Lock()
        self._clock = clock

    def _purge(self, key):
        exp = self._expires.get(key)
        if exp is not None and self._clock() >= exp:
            self._data.pop(key, None)
            self._expires.pop(key, None)

    def get(self, key):
        with self._lock:
            self._purge(key)
            return self._data.get(key)

    def set(self, key, value):
        with self._lock:
            self._data[key] = str(value)
            self._expires.pop(key, None)  # like Redis, SET clears the TTL

    def incr(self, key):
        """Atomic increment; returns the new value (missing key starts at 0)."""
        with self._lock:
            self._purge(key)
            n = int(self._data.get(key, "0")) + 1
            self._data[key] = str(n)
            return n

    def expire(self, key, seconds):
        with self._lock:
            self._purge(key)
            if key not in self._data:
                return False
            self._expires[key] = self._clock() + seconds
            return True
