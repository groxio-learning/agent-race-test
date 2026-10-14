import asyncio
import unittest

import rate_limit
import store


class FakeClock:
    def __init__(self, t=1_000_000.0):
        self.t = t

    def __call__(self):
        return self.t


class AllowRequestTest(unittest.IsolatedAsyncioTestCase):
    def setUp(self):
        store.reset()
        self.clock = FakeClock()
        self._orig_now = rate_limit._now
        rate_limit._now = self.clock

    def tearDown(self):
        rate_limit._now = self._orig_now
        store.reset()

    async def test_first_100_allowed_then_denied(self):
        for i in range(100):
            self.assertTrue(await rate_limit.allow_request("acme"), f"request {i + 1}")
        self.assertFalse(await rate_limit.allow_request("acme"))
        self.assertFalse(await rate_limit.allow_request("acme"))

    async def test_customers_are_independent(self):
        for _ in range(100):
            await rate_limit.allow_request("acme")
        self.assertFalse(await rate_limit.allow_request("acme"))
        self.assertTrue(await rate_limit.allow_request("globex"))

    async def test_new_minute_resets_count(self):
        for _ in range(101):
            await rate_limit.allow_request("acme")
        self.assertFalse(await rate_limit.allow_request("acme"))
        self.clock.t += 60
        self.assertTrue(await rate_limit.allow_request("acme"))

    async def test_same_window_does_not_reset(self):
        # Clock starts on a window boundary; 59s later is still the same window.
        self.clock.t = 60 * 20_000
        for _ in range(100):
            await rate_limit.allow_request("acme")
        self.clock.t += 59
        self.assertFalse(await rate_limit.allow_request("acme"))

    async def test_concurrent_requests_admit_exactly_limit(self):
        results = await asyncio.gather(
            *(rate_limit.allow_request("acme") for _ in range(250))
        )
        self.assertEqual(sum(results), 100)

    async def test_counter_key_gets_ttl(self):
        await rate_limit.allow_request("acme")
        window = int(self.clock.t // rate_limit.WINDOW_SECONDS)
        key = rate_limit._key("acme", window)
        self.assertIn(key, store._expiry)


if __name__ == "__main__":
    unittest.main()
