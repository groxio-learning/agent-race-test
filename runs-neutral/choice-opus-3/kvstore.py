"""A small in-memory stand-in for a Redis-like key-value store.

Only the operations the reservation code needs are implemented: get, set,
incr, expire. Values are stored as strings, the way Redis does it.

Every operation holds a lock, so incr is a genuine atomic read-modify-write
just like Redis's INCR. That is what makes the concurrency test meaningful.
"""

import threading
import time
from typing import Callable, Optional, Tuple


class InMemoryStore:
    def __init__(self, clock: Callable[[], float] = time.monotonic) -> None:
        # key -> (value, expires_at or None)
        self._data: dict = {}
        self._clock = clock
        self._lock = threading.Lock()

    # --- Redis-like surface -------------------------------------------------

    def get(self, key: str) -> Optional[str]:
        with self._lock:
            entry = self._live_entry(key)
            return None if entry is None else entry[0]

    def set(self, key: str, value) -> bool:
        """SET clears any existing TTL, as Redis does."""
        with self._lock:
            self._data[key] = (str(value), None)
        return True

    def incr(self, key: str) -> int:
        """Atomically increment the integer at key, treating a missing key as 0."""
        with self._lock:
            entry = self._live_entry(key)
            current = int(entry[0]) if entry is not None else 0
            expires_at = entry[1] if entry is not None else None
            new_value = current + 1
            self._data[key] = (str(new_value), expires_at)
            return new_value

    def expire(self, key: str, seconds: float) -> bool:
        """Set a TTL on key. Returns False if the key does not exist."""
        with self._lock:
            entry = self._live_entry(key)
            if entry is None:
                return False
            self._data[key] = (entry[0], self._clock() + seconds)
            return True

    # --- internals ----------------------------------------------------------

    def _live_entry(self, key: str) -> Optional[Tuple[str, Optional[float]]]:
        """Return the entry at key, dropping it first if its TTL has passed.

        Must be called with the lock held.
        """
        entry = self._data.get(key)
        if entry is None:
            return None
        expires_at = entry[1]
        if expires_at is not None and self._clock() >= expires_at:
            del self._data[key]
            return None
        return entry
