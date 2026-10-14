"""Seat reservations for events, backed by a Redis-like key-value store.

Each event has a fixed number of seats (10 by default). `reserve_seat` either
hands the customer a seat number or reports that the event is sold out.

Two keys per event, both manipulated only through INCR so the logic stays
correct when many requests arrive at once:

  event:{event_id}:seats_claimed        monotonic ticket counter
  event:{event_id}:customer:{cust_id}   per-customer claim ("has this customer
                                        already taken a seat?")
  event:{event_id}:customer:{cust_id}:seat   the seat number they hold

The ticket counter is never decremented, so it can drift above capacity when
sold-out requests pile in. That is harmless: the sold-out test is
`ticket > capacity`, which keeps being true, and reporting clamps the counter
to capacity. Taking a ticket by INCR (rather than read-then-write) is what
prevents two customers from being handed the same last seat.
"""

from dataclasses import dataclass
from typing import Optional

SEATS_PER_EVENT = 10

RESERVED = "reserved"
ALREADY_RESERVED = "already_reserved"
SOLD_OUT = "sold_out"


@dataclass(frozen=True)
class Reservation:
    """The outcome of a reservation attempt."""

    status: str
    seat_number: Optional[int]
    seats_remaining: int

    @property
    def got_seat(self) -> bool:
        """True when the customer holds a seat, whether or not this call booked it."""
        return self.status in (RESERVED, ALREADY_RESERVED)


def reserve_seat(
    store,
    event_id: str,
    customer_id: str,
    capacity: int = SEATS_PER_EVENT,
    ttl_seconds: Optional[float] = None,
) -> Reservation:
    """Reserve one seat at `event_id` for `customer_id`.

    Returns a Reservation whose status is:
      - "reserved"         this call booked a seat; seat_number is set
      - "already_reserved" the customer already had a seat; no second seat taken
      - "sold_out"         every seat is gone

    `ttl_seconds`, if given, expires the event's keys that long after the first
    reservation, so finished events do not linger in the store.
    """
    if not event_id:
        raise ValueError("event_id is required")
    if not customer_id:
        raise ValueError("customer_id is required")
    if capacity < 1:
        raise ValueError("capacity must be at least 1")

    seats_key = _seats_key(event_id)
    customer_key = _customer_key(event_id, customer_id)
    seat_number_key = customer_key + ":seat"

    # Claim the customer slot first. INCR returning 1 means we are the only
    # caller to have claimed it, so a retry or a double-click cannot consume a
    # second seat.
    if store.incr(customer_key) > 1:
        held_seat = store.get(seat_number_key)
        return Reservation(
            status=ALREADY_RESERVED,
            seat_number=int(held_seat) if held_seat is not None else None,
            seats_remaining=_seats_remaining(store, event_id, capacity),
        )

    ticket = store.incr(seats_key)
    if ticket > capacity:
        # No seat was booked, so give the customer slot back. The ticket
        # counter stays where it is; see the module docstring.
        store.set(customer_key, 0)
        return Reservation(status=SOLD_OUT, seat_number=None, seats_remaining=0)

    store.set(seat_number_key, ticket)
    if ttl_seconds is not None:
        for key in (seats_key, customer_key, seat_number_key):
            store.expire(key, ttl_seconds)

    return Reservation(
        status=RESERVED, seat_number=ticket, seats_remaining=capacity - ticket
    )


def seats_remaining(store, event_id: str, capacity: int = SEATS_PER_EVENT) -> int:
    """How many seats are still available at `event_id`."""
    return _seats_remaining(store, event_id, capacity)


def _seats_remaining(store, event_id: str, capacity: int) -> int:
    raw = store.get(_seats_key(event_id))
    claimed = int(raw) if raw is not None else 0
    return max(0, capacity - min(claimed, capacity))


def _seats_key(event_id: str) -> str:
    return "event:{}:seats_claimed".format(event_id)


def _customer_key(event_id: str, customer_id: str) -> str:
    return "event:{}:customer:{}".format(event_id, customer_id)
