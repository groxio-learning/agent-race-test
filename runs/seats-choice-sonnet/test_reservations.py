import threading
import unittest

from fakeredis import FakeRedis
from reservations import reserve_seat, SEATS_PER_EVENT


class FakeRedisTest(unittest.TestCase):
    def test_get_set_incr(self):
        r = FakeRedis()
        self.assertIsNone(r.get("a"))
        self.assertEqual(r.incr("a"), 1)
        self.assertEqual(r.incr("a"), 2)
        r.set("b", 5)
        self.assertEqual(r.get("b"), "5")

    def test_expire(self):
        now = [0]
        r = FakeRedis(clock=lambda: now[0])
        r.set("k", "v")
        self.assertTrue(r.expire("k", 10))
        now[0] = 9
        self.assertEqual(r.get("k"), "v")
        now[0] = 10
        self.assertIsNone(r.get("k"))
        self.assertFalse(r.expire("missing", 1))


class ReserveSeatTest(unittest.TestCase):
    def test_first_customer_gets_seat_one(self):
        r = reserve_seat(FakeRedis(), "e1", "alice")
        self.assertTrue(r.ok)
        self.assertEqual(r.seat, 1)

    def test_ten_succeed_eleventh_sold_out(self):
        store = FakeRedis()
        results = [reserve_seat(store, "e1", "c%d" % i) for i in range(11)]
        self.assertTrue(all(x.ok for x in results[:10]))
        self.assertEqual([x.seat for x in results[:10]], list(range(1, 11)))
        self.assertFalse(results[10].ok)
        self.assertEqual(results[10].status, "sold_out")
        self.assertIsNone(results[10].seat)

    def test_stays_sold_out(self):
        store = FakeRedis()
        for i in range(10):
            reserve_seat(store, "e1", "c%d" % i)
        for i in range(10, 30):
            self.assertEqual(reserve_seat(store, "e1", "c%d" % i).status, "sold_out")

    def test_events_are_independent(self):
        store = FakeRedis()
        for i in range(10):
            reserve_seat(store, "e1", "c%d" % i)
        self.assertEqual(reserve_seat(store, "e1", "late").status, "sold_out")
        self.assertEqual(reserve_seat(store, "e2", "late").seat, 1)

    def test_same_customer_does_not_take_two_seats(self):
        store = FakeRedis()
        a = reserve_seat(store, "e1", "alice")
        b = reserve_seat(store, "e1", "alice")
        self.assertEqual(b.status, "already_reserved")
        self.assertEqual(b.seat, a.seat)
        self.assertEqual(reserve_seat(store, "e1", "bob").seat, 2)

    def test_existing_holder_still_gets_seat_when_sold_out(self):
        store = FakeRedis()
        for i in range(10):
            reserve_seat(store, "e1", "c%d" % i)
        again = reserve_seat(store, "e1", "c3")
        self.assertTrue(again.ok)
        self.assertEqual(again.seat, 4)

    def test_concurrent_callers_never_oversell_or_duplicate(self):
        store = FakeRedis()
        results, lock = [], threading.Lock()
        barrier = threading.Barrier(50)

        def worker(i):
            barrier.wait()
            res = reserve_seat(store, "e1", "c%d" % i)
            with lock:
                results.append(res)

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(50)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        winners = [x for x in results if x.ok]
        self.assertEqual(len(winners), SEATS_PER_EVENT)
        self.assertEqual(sorted(x.seat for x in winners), list(range(1, 11)))
        self.assertEqual(len(results) - len(winners), 40)


if __name__ == "__main__":
    unittest.main()
