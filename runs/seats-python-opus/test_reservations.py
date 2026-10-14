import asyncio
import unittest

import store
from reservations import SEATS_PER_EVENT, reserve_seat


class ReserveSeatTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        store.reset()

    async def test_first_customer_gets_a_seat(self):
        self.assertTrue(await reserve_seat("concert", "alice"))

    async def test_sequential_sells_exactly_ten(self):
        results = [await reserve_seat("concert", f"c{i}") for i in range(15)]
        self.assertEqual(results, [True] * 10 + [False] * 5)

    async def test_sold_out_stays_sold_out(self):
        for i in range(SEATS_PER_EVENT):
            self.assertTrue(await reserve_seat("concert", f"c{i}"))
        for i in range(5):
            self.assertFalse(await reserve_seat("concert", f"late{i}"))

    async def test_concurrent_requests_never_oversell(self):
        results = await asyncio.gather(
            *(reserve_seat("concert", f"c{i}") for i in range(100))
        )
        self.assertEqual(sum(results), SEATS_PER_EVENT)

    async def test_events_are_independent(self):
        for i in range(SEATS_PER_EVENT):
            await reserve_seat("concert", f"c{i}")
        self.assertFalse(await reserve_seat("concert", "x"))
        self.assertTrue(await reserve_seat("play", "x"))

    async def test_concurrent_across_events(self):
        coros = [reserve_seat(e, f"c{i}") for e in ("a", "b", "c") for i in range(30)]
        results = await asyncio.gather(*coros)
        for n, e in enumerate(("a", "b", "c")):
            self.assertEqual(sum(results[n * 30:(n + 1) * 30]), SEATS_PER_EVENT)


if __name__ == "__main__":
    unittest.main()
