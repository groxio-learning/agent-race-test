defmodule Tickets.Store do
  @moduledoc """
  The slice of a Redis-like key-value store that reservations need.

  Values are strings in and strings out, and `get/2` answers `nil` for a
  missing key, so a real Redis client can satisfy this behaviour without a
  translation layer. `Tickets.MemoryStore` is the local stand-in.
  """

  @typedoc "Whatever identifies one store: a pid, a registered name, a pool."
  @type conn :: term()

  @doc "Returns the value at `key`, or `nil` if it is missing or expired."
  @callback get(conn(), String.t()) :: String.t() | nil

  @doc "Stores `value` at `key`, clearing any TTL the key had."
  @callback set(conn(), String.t(), String.t()) :: :ok

  @doc """
  Atomically increments the integer at `key` and returns the new value.

  A missing key counts as 0, so the first caller sees 1. Any TTL on the key
  survives the increment.
  """
  @callback incr(conn(), String.t()) :: integer()

  @doc """
  Sets `key` to expire in `ttl_seconds`.

  A TTL of zero or less drops the key immediately, as Redis does.
  """
  @callback expire(conn(), String.t(), integer()) :: :ok
end
