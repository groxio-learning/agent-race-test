import asyncio
import unittest
from unittest import mock

import rate_limit
import store


class AllowRequestTests(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        store.reset()
        self.clock = 1_000_000 * 60.0  # start of a window
        p = mock.patch.object(rate_limit, "_now", lambda: self.clock)
        p.start()
        self.addCleanup(p.stop)

    async def test_allows_up_to_limit_then_blocks(self):
        for _ in range(100):
            self.assertTrue(await rate_limit.allow_request("a"))
        self.assertFalse(await rate_limit.allow_request("a"))
        self.assertFalse(await rate_limit.allow_request("a"))

    async def test_customers_are_independent(self):
        for _ in range(100):
            await rate_limit.allow_request("a")
        self.assertFalse(await rate_limit.allow_request("a"))
        self.assertTrue(await rate_limit.allow_request("b"))

    async def test_new_window_resets_count(self):
        for _ in range(101):
            await rate_limit.allow_request("a")
        self.assertFalse(await rate_limit.allow_request("a"))
        self.clock += 60
        self.assertTrue(await rate_limit.allow_request("a"))

    async def test_concurrent_requests_allow_exactly_limit(self):
        results = await asyncio.gather(
            *(rate_limit.allow_request("a") for _ in range(250))
        )
        self.assertEqual(results.count(True), 100)
        self.assertEqual(results.count(False), 150)

    async def test_counter_gets_ttl(self):
        await rate_limit.allow_request("a")
        key = f"ratelimit:a:{int(self.clock // 60)}"
        self.assertIn(key, store._expiry)


if __name__ == "__main__":
    unittest.main()
