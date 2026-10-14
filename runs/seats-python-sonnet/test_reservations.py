import asyncio
import unittest

import store
from reservations import SEATS_PER_EVENT, reserve_seat


class ReserveSeatTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        store.reset()

    async def test_first_customer_gets_a_seat(self):
        self.assertTrue(await reserve_seat("e1", "c1"))

    async def test_sold_out_after_ten_sequential(self):
        for i in range(SEATS_PER_EVENT):
            self.assertTrue(await reserve_seat("e1", f"c{i}"))
        self.assertFalse(await reserve_seat("e1", "late"))
        self.assertFalse(await reserve_seat("e1", "later"))

    async def test_events_are_independent(self):
        for i in range(SEATS_PER_EVENT):
            await reserve_seat("e1", f"c{i}")
        self.assertFalse(await reserve_seat("e1", "x"))
        self.assertTrue(await reserve_seat("e2", "x"))

    async def test_concurrent_requests_never_oversell(self):
        results = await asyncio.gather(
            *(reserve_seat("hot", f"c{i}") for i in range(50))
        )
        self.assertEqual(sum(results), SEATS_PER_EVENT)

    async def test_concurrent_exactly_at_capacity(self):
        results = await asyncio.gather(
            *(reserve_seat("e", f"c{i}") for i in range(SEATS_PER_EVENT))
        )
        self.assertTrue(all(results))
        self.assertFalse(await reserve_seat("e", "extra"))


if __name__ == "__main__":
    unittest.main()
