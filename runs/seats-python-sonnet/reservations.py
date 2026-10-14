"""Ticket reservations."""
import store

SEATS_PER_EVENT = 10


async def reserve_seat(event_id: str, customer_id: str) -> bool:
    """Try to reserve one seat. True if granted, False if sold out.

    The store has no atomic compare-and-set, so we never read-then-write.
    Instead we claim a seat with a single atomic INCR on a per-event claim
    counter: the returned value is our unique ticket number. If it is within
    capacity we own a seat; otherwise the event was already full. The counter
    may overshoot capacity under load, which is harmless since it is only
    compared against the limit.
    """
    claimed = await store.incr(f"event:{event_id}:seats_claimed")
    return claimed <= SEATS_PER_EVENT
