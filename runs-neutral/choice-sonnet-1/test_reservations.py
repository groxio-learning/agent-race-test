import threading
import unittest

from reservations import FakeRedis, SEATS_PER_EVENT, reserve_seat


class ReserveSeatTests(unittest.TestCase):
    def setUp(self):
        self.store = FakeRedis()

    def test_fills_event_up_to_capacity(self):
        for i in range(SEATS_PER_EVENT):
            result = reserve_seat(self.store, "event-1", f"customer-{i}")
            self.assertTrue(result.success)
            self.assertEqual(result.seat_number, i + 1)

    def test_eleventh_customer_is_sold_out(self):
        for i in range(SEATS_PER_EVENT):
            reserve_seat(self.store, "event-1", f"customer-{i}")

        result = reserve_seat(self.store, "event-1", "customer-overflow")

        self.assertFalse(result.success)
        self.assertEqual(result.reason, "sold_out")
        self.assertIsNone(result.seat_number)

    def test_counter_does_not_overshoot_after_sold_out(self):
        for i in range(SEATS_PER_EVENT):
            reserve_seat(self.store, "event-1", f"customer-{i}")
        reserve_seat(self.store, "event-1", "customer-overflow-1")
        reserve_seat(self.store, "event-1", "customer-overflow-2")

        self.assertEqual(self.store.get("event:event-1:seats_reserved"), SEATS_PER_EVENT)

    def test_same_customer_reserving_twice_keeps_same_seat(self):
        first = reserve_seat(self.store, "event-1", "customer-1")
        second = reserve_seat(self.store, "event-1", "customer-1")

        self.assertEqual(first.seat_number, second.seat_number)
        self.assertEqual(second.reason, "already_reserved")
        # the repeat call must not consume a second seat
        self.assertEqual(self.store.get("event:event-1:seats_reserved"), 1)

    def test_events_have_independent_seat_pools(self):
        for i in range(SEATS_PER_EVENT):
            reserve_seat(self.store, "event-1", f"customer-{i}")

        result = reserve_seat(self.store, "event-2", "customer-0")

        self.assertTrue(result.success)
        self.assertEqual(result.seat_number, 1)

    def test_concurrent_reservations_never_overbook(self):
        num_customers = 50
        results = [None] * num_customers

        def worker(index):
            results[index] = reserve_seat(self.store, "event-1", f"customer-{index}")

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(num_customers)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        successes = [r for r in results if r.success]
        sold_out = [r for r in results if not r.success]

        self.assertEqual(len(successes), SEATS_PER_EVENT)
        self.assertEqual(len(sold_out), num_customers - SEATS_PER_EVENT)
        self.assertEqual(sorted(r.seat_number for r in successes), list(range(1, SEATS_PER_EVENT + 1)))

    def test_reservation_window_resets_after_ttl(self):
        # ttl_seconds models a timed reservation window (e.g. a flash sale):
        # the counter's TTL is armed by the first reservation, so once it
        # lapses the whole event's window resets and seats free up again.
        fake_time = [1000.0]
        store = FakeRedis(clock=lambda: fake_time[0])

        first = reserve_seat(store, "event-1", "customer-1", ttl_seconds=60)
        self.assertTrue(first.success)
        self.assertEqual(first.seat_number, 1)

        fake_time[0] += 61  # advance past the TTL

        second = reserve_seat(store, "event-1", "customer-1", ttl_seconds=60)
        self.assertTrue(second.success)
        self.assertEqual(second.reason, "reserved")
        self.assertEqual(second.seat_number, 1)


if __name__ == "__main__":
    unittest.main()
