"""Seat reservations backed by the key-value store."""
import store

SEATS_PER_EVENT = 10


def _seats_key(event_id: str) -> str:
    return f"event:{event_id}:seats_taken"


async def reserve_seat(event_id: str, customer_id: str) -> bool:
    """Try to reserve one seat for customer_id at event_id.

    Returns True if a seat was claimed, False if the event is sold out.

    The claim is a single atomic INCR. A get-then-set version would let
    concurrent callers both read 9 and both write 10, overselling the
    event. INCR hands every caller a distinct ticket number, so exactly
    SEATS_PER_EVENT callers see a value <= SEATS_PER_EVENT. Callers who
    lose push the counter past the limit; that is harmless because the
    counter is only ever compared against the limit.
    """
    taken = await store.incr(_seats_key(event_id))
    return taken <= SEATS_PER_EVENT
