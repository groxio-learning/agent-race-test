"""Async client for our key-value store (Redis).

This in-memory version mirrors the production client's API and latency
so code can be developed and tested locally.
"""
import asyncio
import time

_data = {}
_expiry = {}
_LATENCY = 0.001  # one network round trip


def _alive(key):
    exp = _expiry.get(key)
    if exp is not None and time.monotonic() >= exp:
        _data.pop(key, None)
        _expiry.pop(key, None)
    return key in _data


async def get(key):
    """Return the integer stored at key, or None."""
    await asyncio.sleep(_LATENCY)
    return _data.get(key) if _alive(key) else None


async def set(key, value, ttl_seconds=None):
    """Store an integer at key, optionally expiring after ttl_seconds."""
    await asyncio.sleep(_LATENCY)
    _data[key] = value
    if ttl_seconds is None:
        _expiry.pop(key, None)
    else:
        _expiry[key] = time.monotonic() + ttl_seconds


async def incr(key):
    """Increment the integer at key by 1 (starting from 0) and return the new value."""
    await asyncio.sleep(_LATENCY)
    _alive(key)
    _data[key] = _data.get(key, 0) + 1
    return _data[key]


async def expire(key, seconds):
    """Set key to expire after the given number of seconds."""
    await asyncio.sleep(_LATENCY)
    if _alive(key):
        _expiry[key] = time.monotonic() + seconds


def reset():
    """Clear all data (for tests)."""
    _data.clear()
    _expiry.clear()
