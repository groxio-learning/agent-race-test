"""Seat reservations backed by a Redis-like store."""

SEATS_PER_EVENT = 10


class Reservation:
    """Result of reserve_seat: .ok, .seat (1..10 or None), .status."""

    def __init__(self, status, seat=None):
        self.status = status  # "reserved", "already_reserved", or "sold_out"
        self.seat = seat

    @property
    def ok(self):
        return self.status in ("reserved", "already_reserved")

    def __eq__(self, other):
        return (self.status, self.seat) == (other.status, other.seat)

    def __repr__(self):
        return "Reservation(%r, seat=%r)" % (self.status, self.seat)


def reserve_seat(store, event_id, customer_id, capacity=SEATS_PER_EVENT):
    """Reserve one seat at event_id for customer_id.

    The seat number comes from a single atomic INCR, so two concurrent callers
    can never receive the same seat, and nobody gets seat > capacity.
    A rejected caller still bumps the counter; that is harmless because every
    value above capacity means "sold out".

    A customer who already holds a seat gets the same seat back instead of
    consuming another. (That get/set pair is not atomic, so two simultaneous
    requests from the SAME customer could both take a seat; guard against it
    upstream, e.g. with a per-customer lock or SET NX, if that matters.)
    """
    holder_key = "event:%s:customer:%s" % (event_id, customer_id)
    existing = store.get(holder_key)
    if existing is not None:
        return Reservation("already_reserved", int(existing))

    seat = store.incr("event:%s:seats_taken" % event_id)
    if seat > capacity:
        return Reservation("sold_out")

    store.set(holder_key, seat)
    return Reservation("reserved", seat)
