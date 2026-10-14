import threading
import time
import unittest

from kv_store import InMemoryStore
from reservations import ReservationStatus, reserve_seat


class TestReserveSeat(unittest.TestCase):
    def setUp(self):
        self.store = InMemoryStore()

    def test_first_ten_customers_get_seats_one_through_ten(self):
        seats = []
        for i in range(10):
            outcome = reserve_seat(self.store, "concert-1", f"customer-{i}")
            self.assertEqual(outcome.status, ReservationStatus.RESERVED)
            seats.append(outcome.seat_number)
        self.assertEqual(sorted(seats), list(range(1, 11)))

    def test_eleventh_customer_is_sold_out(self):
        for i in range(10):
            reserve_seat(self.store, "concert-1", f"customer-{i}")

        outcome = reserve_seat(self.store, "concert-1", "customer-11")

        self.assertEqual(outcome.status, ReservationStatus.SOLD_OUT)
        self.assertIsNone(outcome.seat_number)
        # the failed attempt must not have permanently consumed a seat slot
        self.assertEqual(self.store.get("event:concert-1:reserved_count"), "10")

    def test_reserving_twice_for_the_same_customer_is_idempotent(self):
        first = reserve_seat(self.store, "concert-1", "customer-0")
        second = reserve_seat(self.store, "concert-1", "customer-0")

        self.assertEqual(first.status, ReservationStatus.RESERVED)
        self.assertEqual(second.status, ReservationStatus.ALREADY_RESERVED)
        self.assertEqual(first.seat_number, second.seat_number)
        # still only one seat consumed
        self.assertEqual(self.store.get("event:concert-1:reserved_count"), "1")

    def test_events_have_independent_seat_pools(self):
        for i in range(10):
            reserve_seat(self.store, "concert-1", f"customer-{i}")

        outcome = reserve_seat(self.store, "concert-2", "customer-0")

        self.assertEqual(outcome.status, ReservationStatus.RESERVED)
        self.assertEqual(outcome.seat_number, 1)

    def test_concurrent_reservations_never_oversell(self):
        attempts = 50
        results = [None] * attempts

        def attempt(i):
            results[i] = reserve_seat(self.store, "concert-1", f"customer-{i}")

        threads = [threading.Thread(target=attempt, args=(i,)) for i in range(attempts)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        reserved = [r for r in results if r.status == ReservationStatus.RESERVED]
        sold_out = [r for r in results if r.status == ReservationStatus.SOLD_OUT]

        self.assertEqual(len(reserved), 10)
        self.assertEqual(len(sold_out), attempts - 10)
        self.assertEqual(sorted(r.seat_number for r in reserved), list(range(1, 11)))

    def test_ttl_expires_the_reservation_keys(self):
        reserve_seat(self.store, "concert-1", "customer-0", ttl_seconds=0.05)

        self.assertIsNotNone(self.store.get("event:concert-1:customer:customer-0"))
        time.sleep(0.1)
        self.assertIsNone(self.store.get("event:concert-1:customer:customer-0"))
        self.assertIsNone(self.store.get("event:concert-1:reserved_count"))


if __name__ == "__main__":
    unittest.main()
