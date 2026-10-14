"""Seat reservation logic for events, backed by a Redis-like key-value store.

The real dependency is anything exposing get/set/incr/expire with Redis
semantics (incr is atomic, even under concurrent clients). FakeRedis below
is a local stand-in with the same contract, so this module runs without a
real Redis server.
"""

import threading
import time
from dataclasses import dataclass
from typing import Optional

SEATS_PER_EVENT = 10


class FakeRedis:
    """Minimal in-memory stand-in for a Redis-like store.

    Only implements what reserve_seat() needs: get, set, incr, expire.
    incr is atomic across threads, matching Redis's single-threaded INCR
    guarantee -- that atomicity is what makes reserve_seat() race-safe.
    """

    def __init__(self, clock=time.monotonic):
        self._clock = clock
        self._values = {}
        self._expires_at = {}
        self._lock = threading.Lock()

    def _is_expired(self, key):
        deadline = self._expires_at.get(key)
        return deadline is not None and self._clock() >= deadline

    def get(self, key):
        with self._lock:
            if self._is_expired(key):
                self._values.pop(key, None)
                self._expires_at.pop(key, None)
                return None
            return self._values.get(key)

    def set(self, key, value):
        with self._lock:
            self._values[key] = value
            self._expires_at.pop(key, None)

    def incr(self, key, amount=1):
        with self._lock:
            if self._is_expired(key):
                self._values.pop(key, None)
                self._expires_at.pop(key, None)
            current = int(self._values.get(key, 0))
            current += amount
            self._values[key] = current
            return current

    def expire(self, key, ttl_seconds):
        with self._lock:
            if key in self._values:
                self._expires_at[key] = self._clock() + ttl_seconds


@dataclass
class ReservationResult:
    success: bool
    seat_number: Optional[int] = None
    reason: Optional[str] = None  # "reserved", "already_reserved", or "sold_out"


def reserve_seat(store, event_id, customer_id, total_seats=SEATS_PER_EVENT, ttl_seconds=None):
    """Reserve one seat for customer_id at event_id.

    Returns a ReservationResult telling the caller whether the customer got
    a seat (with seat_number) or the event is sold out. Calling this again
    for a customer who already holds a seat returns that same seat instead
    of consuming another one.

    Race-safety: seat allocation goes through a single atomic incr on a
    per-event counter, so concurrent callers can't overbook -- each caller
    gets a distinct count, and anyone pushing the count past total_seats
    rolls their own increment back.
    """
    counter_key = f"event:{event_id}:seats_reserved"
    customer_key = f"event:{event_id}:customer:{customer_id}"

    existing_seat = store.get(customer_key)
    if existing_seat is not None:
        return ReservationResult(True, seat_number=int(existing_seat), reason="already_reserved")

    seat_number = store.incr(counter_key)
    if ttl_seconds is not None and seat_number == 1:
        store.expire(counter_key, ttl_seconds)

    if seat_number > total_seats:
        store.incr(counter_key, -1)  # give the seat back; this caller didn't get one
        return ReservationResult(False, reason="sold_out")

    store.set(customer_key, seat_number)
    if ttl_seconds is not None:
        store.expire(customer_key, ttl_seconds)
    return ReservationResult(True, seat_number=seat_number, reason="reserved")
