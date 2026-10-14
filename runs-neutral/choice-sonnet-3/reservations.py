"""Seat reservation logic backed by a Redis-like key-value store.

Each event has a fixed number of seats (10 by default). Reserving a seat
atomically increments a per-event counter; if the counter exceeds the seat
limit, the increment is rolled back and the caller is told the event is
sold out. A per-customer key prevents the same customer from being counted
twice if they try to reserve again (e.g. a retried request).
"""

from dataclasses import dataclass
from typing import Optional

SEATS_PER_EVENT = 10


@dataclass
class ReservationResult:
    success: bool
    seat_number: Optional[int]
    reason: str  # "reserved", "already_reserved", or "sold_out"


def _seats_taken_key(event_id):
    return f"event:{event_id}:seats_taken"


def _customer_seat_key(event_id, customer_id):
    return f"event:{event_id}:customer:{customer_id}"


def reserve_seat(store, event_id, customer_id, seats_per_event=SEATS_PER_EVENT):
    """Reserve a seat for customer_id at event_id.

    Returns a ReservationResult. If the customer already holds a seat at
    this event, returns their existing seat rather than reserving another.
    """
    customer_key = _customer_seat_key(event_id, customer_id)

    existing_seat = store.get(customer_key)
    if existing_seat is not None:
        return ReservationResult(True, int(existing_seat), "already_reserved")

    count_key = _seats_taken_key(event_id)
    seat_number = store.incr(count_key)

    if seat_number > seats_per_event:
        store.incr(count_key, -1)  # roll back our increment
        return ReservationResult(False, None, "sold_out")

    claimed = store.set(customer_key, seat_number, nx=True)
    if not claimed:
        # Another concurrent call already reserved a seat for this
        # customer between our GET and our SET; give up the seat we
        # just claimed and report their existing one instead.
        store.incr(count_key, -1)
        existing_seat = store.get(customer_key)
        return ReservationResult(True, int(existing_seat), "already_reserved")

    return ReservationResult(True, seat_number, "reserved")
