import unittest

from kv_store import InMemoryKVStore
from reservations import reserve_seat, SEATS_PER_EVENT


class TestReserveSeat(unittest.TestCase):
    def setUp(self):
        self.store = InMemoryKVStore()

    def test_first_reservation_succeeds_with_seat_one(self):
        result = reserve_seat(self.store, "event-1", "alice")
        self.assertTrue(result.success)
        self.assertEqual(result.seat_number, 1)
        self.assertEqual(result.reason, "reserved")

    def test_fills_all_seats_then_sells_out(self):
        for i in range(SEATS_PER_EVENT):
            result = reserve_seat(self.store, "event-1", f"customer-{i}")
            self.assertTrue(result.success, f"expected seat {i + 1} to be available")
            self.assertEqual(result.seat_number, i + 1)

        sold_out_result = reserve_seat(self.store, "event-1", "one-too-many")
        self.assertFalse(sold_out_result.success)
        self.assertIsNone(sold_out_result.seat_number)
        self.assertEqual(sold_out_result.reason, "sold_out")

    def test_sold_out_event_does_not_leak_seats_on_retry(self):
        for i in range(SEATS_PER_EVENT):
            reserve_seat(self.store, "event-1", f"customer-{i}")

        # Try several more times after sold out; counter should not drift
        # upward and keep blocking everyone.
        for _ in range(3):
            result = reserve_seat(self.store, "event-1", "late-customer")
            self.assertFalse(result.success)
            self.assertEqual(result.reason, "sold_out")

    def test_same_customer_reserving_twice_keeps_same_seat(self):
        first = reserve_seat(self.store, "event-1", "alice")
        second = reserve_seat(self.store, "event-1", "alice")

        self.assertEqual(first.seat_number, second.seat_number)
        self.assertEqual(second.reason, "already_reserved")

        # And it shouldn't have consumed a second seat: 9 more customers
        # should still fit before sold out.
        for i in range(9):
            result = reserve_seat(self.store, "event-1", f"other-{i}")
            self.assertTrue(result.success)

        tenth_extra = reserve_seat(self.store, "event-1", "yet-another")
        self.assertFalse(tenth_extra.success)
        self.assertEqual(tenth_extra.reason, "sold_out")

    def test_events_have_independent_seat_pools(self):
        for i in range(SEATS_PER_EVENT):
            result = reserve_seat(self.store, "event-1", f"customer-{i}")
            self.assertTrue(result.success)
        self.assertFalse(reserve_seat(self.store, "event-1", "overflow").success)

        # event-2 is unaffected by event-1 selling out.
        result = reserve_seat(self.store, "event-2", "fresh-customer")
        self.assertTrue(result.success)
        self.assertEqual(result.seat_number, 1)

    def test_custom_seat_capacity(self):
        for i in range(2):
            result = reserve_seat(self.store, "small-event", f"customer-{i}", seats_per_event=2)
            self.assertTrue(result.success)

        result = reserve_seat(self.store, "small-event", "third-customer", seats_per_event=2)
        self.assertFalse(result.success)
        self.assertEqual(result.reason, "sold_out")


if __name__ == "__main__":
    unittest.main()
