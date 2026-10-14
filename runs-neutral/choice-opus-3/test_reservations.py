import threading
import unittest

from kvstore import InMemoryStore
from reservations import (
    ALREADY_RESERVED,
    RESERVED,
    SEATS_PER_EVENT,
    SOLD_OUT,
    reserve_seat,
    seats_remaining,
)


class FakeClock:
    """Manually advanced clock, so TTL tests do not have to sleep."""

    def __init__(self) -> None:
        self.now = 0.0

    def __call__(self) -> float:
        return self.now

    def advance(self, seconds: float) -> None:
        self.now += seconds


class ReserveSeatTest(unittest.TestCase):
    def setUp(self) -> None:
        self.store = InMemoryStore()

    def test_first_customer_gets_the_first_seat(self):
        result = reserve_seat(self.store, "gig-1", "alice")

        self.assertTrue(result.got_seat)
        self.assertEqual(RESERVED, result.status)
        self.assertEqual(1, result.seat_number)
        self.assertEqual(9, result.seats_remaining)

    def test_ten_customers_fill_the_event(self):
        seats = []
        for i in range(SEATS_PER_EVENT):
            result = reserve_seat(self.store, "gig-1", "cust-{}".format(i))
            self.assertEqual(RESERVED, result.status)
            seats.append(result.seat_number)

        self.assertEqual(list(range(1, 11)), seats)
        self.assertEqual(0, seats_remaining(self.store, "gig-1"))

    def test_eleventh_customer_is_sold_out(self):
        for i in range(SEATS_PER_EVENT):
            reserve_seat(self.store, "gig-1", "cust-{}".format(i))

        result = reserve_seat(self.store, "gig-1", "latecomer")

        self.assertFalse(result.got_seat)
        self.assertEqual(SOLD_OUT, result.status)
        self.assertIsNone(result.seat_number)
        self.assertEqual(0, result.seats_remaining)

    def test_further_attempts_after_sold_out_stay_sold_out(self):
        for i in range(SEATS_PER_EVENT + 5):
            reserve_seat(self.store, "gig-1", "cust-{}".format(i))

        for name in ("x", "y", "z"):
            self.assertEqual(SOLD_OUT, reserve_seat(self.store, "gig-1", name).status)

    def test_repeat_request_returns_the_same_seat_without_consuming_another(self):
        first = reserve_seat(self.store, "gig-1", "alice")
        second = reserve_seat(self.store, "gig-1", "alice")

        self.assertEqual(ALREADY_RESERVED, second.status)
        self.assertTrue(second.got_seat)
        self.assertEqual(first.seat_number, second.seat_number)
        self.assertEqual(9, seats_remaining(self.store, "gig-1"))

    def test_one_customer_cannot_exhaust_the_event(self):
        for _ in range(20):
            reserve_seat(self.store, "gig-1", "alice")

        self.assertEqual(9, seats_remaining(self.store, "gig-1"))
        self.assertEqual(RESERVED, reserve_seat(self.store, "gig-1", "bob").status)

    def test_sold_out_customer_can_retry_if_capacity_is_raised(self):
        for i in range(SEATS_PER_EVENT):
            reserve_seat(self.store, "gig-1", "cust-{}".format(i))
        self.assertEqual(SOLD_OUT, reserve_seat(self.store, "gig-1", "latecomer").status)

        # The failed attempt must not have left the customer marked as booked.
        upgraded = reserve_seat(self.store, "gig-1", "latecomer", capacity=20)
        self.assertEqual(RESERVED, upgraded.status)
        self.assertIsNotNone(upgraded.seat_number)

    def test_events_are_independent(self):
        for i in range(SEATS_PER_EVENT):
            reserve_seat(self.store, "gig-1", "cust-{}".format(i))

        result = reserve_seat(self.store, "gig-2", "cust-0")

        self.assertEqual(RESERVED, result.status)
        self.assertEqual(1, result.seat_number)
        self.assertEqual(0, seats_remaining(self.store, "gig-1"))
        self.assertEqual(9, seats_remaining(self.store, "gig-2"))

    def test_capacity_is_configurable(self):
        self.assertEqual(RESERVED, reserve_seat(self.store, "tiny", "a", capacity=1).status)
        self.assertEqual(SOLD_OUT, reserve_seat(self.store, "tiny", "b", capacity=1).status)

    def test_unknown_event_has_all_seats_free(self):
        self.assertEqual(10, seats_remaining(self.store, "never-touched"))

    def test_bad_arguments_are_rejected(self):
        with self.assertRaises(ValueError):
            reserve_seat(self.store, "", "alice")
        with self.assertRaises(ValueError):
            reserve_seat(self.store, "gig-1", "")
        with self.assertRaises(ValueError):
            reserve_seat(self.store, "gig-1", "alice", capacity=0)


class ConcurrencyTest(unittest.TestCase):
    def test_a_rush_of_requests_sells_exactly_ten_seats(self):
        store = InMemoryStore()
        attempts = 100
        results = [None] * attempts
        start = threading.Barrier(attempts)

        def attempt(index):
            start.wait()
            results[index] = reserve_seat(store, "gig-1", "cust-{}".format(index))

        threads = [
            threading.Thread(target=attempt, args=(i,)) for i in range(attempts)
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        reserved = [r for r in results if r.status == RESERVED]
        sold_out = [r for r in results if r.status == SOLD_OUT]

        self.assertEqual(SEATS_PER_EVENT, len(reserved))
        self.assertEqual(attempts - SEATS_PER_EVENT, len(sold_out))
        # No seat number handed out twice, and all within range.
        seat_numbers = sorted(r.seat_number for r in reserved)
        self.assertEqual(list(range(1, SEATS_PER_EVENT + 1)), seat_numbers)

    def test_one_customer_clicking_many_times_takes_one_seat(self):
        store = InMemoryStore()
        attempts = 25
        results = [None] * attempts
        start = threading.Barrier(attempts)

        def attempt(index):
            start.wait()
            results[index] = reserve_seat(store, "gig-1", "alice")

        threads = [
            threading.Thread(target=attempt, args=(i,)) for i in range(attempts)
        ]
        for thread in threads:
            thread.start()
        for thread in threads:
            thread.join()

        self.assertEqual(1, len([r for r in results if r.status == RESERVED]))
        self.assertEqual(9, seats_remaining(store, "gig-1"))


class ExpiryTest(unittest.TestCase):
    def test_reservations_expire_after_the_ttl(self):
        clock = FakeClock()
        store = InMemoryStore(clock=clock)

        reserve_seat(store, "gig-1", "alice", ttl_seconds=60)
        self.assertEqual(9, seats_remaining(store, "gig-1"))

        clock.advance(59)
        self.assertEqual(9, seats_remaining(store, "gig-1"))

        clock.advance(2)
        self.assertEqual(10, seats_remaining(store, "gig-1"))
        # With the old keys gone, the event starts clean.
        again = reserve_seat(store, "gig-1", "alice")
        self.assertEqual(RESERVED, again.status)
        self.assertEqual(1, again.seat_number)

    def test_without_a_ttl_reservations_persist(self):
        clock = FakeClock()
        store = InMemoryStore(clock=clock)

        reserve_seat(store, "gig-1", "alice")
        clock.advance(10_000)

        self.assertEqual(9, seats_remaining(store, "gig-1"))
        self.assertEqual(ALREADY_RESERVED, reserve_seat(store, "gig-1", "alice").status)


class InMemoryStoreTest(unittest.TestCase):
    def setUp(self) -> None:
        self.clock = FakeClock()
        self.store = InMemoryStore(clock=self.clock)

    def test_get_missing_key_returns_none(self):
        self.assertIsNone(self.store.get("nope"))

    def test_values_are_stored_as_strings(self):
        self.store.set("k", 7)
        self.assertEqual("7", self.store.get("k"))

    def test_incr_treats_a_missing_key_as_zero(self):
        self.assertEqual(1, self.store.incr("counter"))
        self.assertEqual(2, self.store.incr("counter"))
        self.assertEqual("2", self.store.get("counter"))

    def test_expire_on_a_missing_key_returns_false(self):
        self.assertFalse(self.store.expire("nope", 10))

    def test_expired_key_reads_as_missing_and_incr_restarts(self):
        self.store.set("k", 5)
        self.store.expire("k", 10)
        self.clock.advance(10)

        self.assertIsNone(self.store.get("k"))
        self.assertEqual(1, self.store.incr("k"))

    def test_set_clears_an_existing_ttl(self):
        self.store.set("k", 1)
        self.store.expire("k", 10)
        self.store.set("k", 2)
        self.clock.advance(100)

        self.assertEqual("2", self.store.get("k"))

    def test_incr_preserves_an_existing_ttl(self):
        self.store.set("k", 1)
        self.store.expire("k", 10)
        self.store.incr("k")
        self.clock.advance(10)

        self.assertIsNone(self.store.get("k"))


if __name__ == "__main__":
    unittest.main()
