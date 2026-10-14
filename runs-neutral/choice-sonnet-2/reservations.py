"""Seat reservation logic built on a Redis-like get/set/incr/expire store.

Each event has a fixed number of seats. Reservations are tracked with two
kinds of keys per event:

  event:{event_id}:reserved_count          -- atomic counter of seats taken
  event:{event_id}:customer:{customer_id}  -- seat number held by a customer

Using `incr` to claim a seat number keeps the "did I get a seat" check
race-free even if the store is shared by concurrent callers: incr is atomic,
so two callers can never be handed the same seat number. If the increment
pushes the count past capacity, we roll it back with a negative incr and
report SOLD_OUT instead.
"""

from collections import namedtuple
from enum import Enum

DEFAULT_SEATS_PER_EVENT = 10

ReservationOutcome = namedtuple("ReservationOutcome", ["status", "seat_number"])


class ReservationStatus(Enum):
    RESERVED = "reserved"
    ALREADY_RESERVED = "already_reserved"
    SOLD_OUT = "sold_out"


def _count_key(event_id):
    return f"event:{event_id}:reserved_count"


def _customer_key(event_id, customer_id):
    return f"event:{event_id}:customer:{customer_id}"


def reserve_seat(store, event_id, customer_id, seats_per_event=DEFAULT_SEATS_PER_EVENT, ttl_seconds=None):
    """Reserve one seat at `event_id` for `customer_id`.

    Returns a ReservationOutcome(status, seat_number). seat_number is None
    when status is SOLD_OUT. Calling this again for a customer who already
    holds a seat is idempotent: it returns ALREADY_RESERVED with their
    existing seat number instead of consuming another seat.

    If `ttl_seconds` is given, the underlying keys are set to expire after
    that many seconds (useful for releasing seats once an event has passed).
    """
    customer_key = _customer_key(event_id, customer_id)

    existing_seat = store.get(customer_key)
    if existing_seat is not None:
        return ReservationOutcome(ReservationStatus.ALREADY_RESERVED, int(existing_seat))

    count_key = _count_key(event_id)
    seat_number = store.incr(count_key)

    if seat_number > seats_per_event:
        store.incr(count_key, -1)  # roll back our claim; the event is full
        return ReservationOutcome(ReservationStatus.SOLD_OUT, None)

    store.set(customer_key, seat_number)

    if ttl_seconds is not None:
        store.expire(count_key, ttl_seconds)
        store.expire(customer_key, ttl_seconds)

    return ReservationOutcome(ReservationStatus.RESERVED, seat_number)
