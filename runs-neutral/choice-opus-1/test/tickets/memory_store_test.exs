defmodule Tickets.MemoryStoreTest do
  @moduledoc """
  Tests for the stand-in store itself.

  These pin down the Redis behaviours `Tickets.Reservations` leans on, so a
  swap to a real Redis client has something to be checked against.
  """

  use ExUnit.Case, async: true

  alias Tickets.MemoryStore

  setup do
    agent = start_supervised!({Agent, fn -> 0 end})
    clock = fn -> Agent.get(agent, & &1) end
    conn = start_supervised!({MemoryStore, [clock: clock]})

    {:ok, conn: conn, advance: fn ms -> Agent.update(agent, &(&1 + ms)) end}
  end

  describe "get/2 and set/3" do
    test "get answers nil for a key that was never set", %{conn: conn} do
      assert MemoryStore.get(conn, "nope") == nil
    end

    test "set then get round-trips a value", %{conn: conn} do
      assert MemoryStore.set(conn, "customer", "alice") == :ok
      assert MemoryStore.get(conn, "customer") == "alice"
    end

    test "set overwrites what was there", %{conn: conn} do
      :ok = MemoryStore.set(conn, "customer", "alice")
      :ok = MemoryStore.set(conn, "customer", "bob")

      assert MemoryStore.get(conn, "customer") == "bob"
    end
  end

  describe "incr/2" do
    test "treats a missing key as zero, so the first caller gets 1", %{conn: conn} do
      assert MemoryStore.incr(conn, "count") == 1
    end

    test "returns each successive value", %{conn: conn} do
      assert Enum.map(1..5, fn _ -> MemoryStore.incr(conn, "count") end) == [1, 2, 3, 4, 5]
    end

    test "never returns the same value twice under concurrency", %{conn: conn} do
      values =
        1..100
        |> Task.async_stream(fn _ -> MemoryStore.incr(conn, "count") end,
          max_concurrency: 50,
          ordered: false
        )
        |> Enum.map(fn {:ok, value} -> value end)

      assert Enum.sort(values) == Enum.to_list(1..100)
    end

    test "leaves the counter readable as a string", %{conn: conn} do
      MemoryStore.incr(conn, "count")
      MemoryStore.incr(conn, "count")

      assert MemoryStore.get(conn, "count") == "2"
    end
  end

  describe "expire/3" do
    test "a key reads as missing once its TTL has passed", %{conn: conn, advance: advance} do
      :ok = MemoryStore.set(conn, "customer", "alice")
      :ok = MemoryStore.expire(conn, "customer", 60)

      advance.(59_000)
      assert MemoryStore.get(conn, "customer") == "alice"

      advance.(1_000)
      assert MemoryStore.get(conn, "customer") == nil
    end

    test "a non-positive TTL drops the key immediately", %{conn: conn} do
      :ok = MemoryStore.set(conn, "customer", "alice")

      assert MemoryStore.expire(conn, "customer", 0) == :ok
      assert MemoryStore.get(conn, "customer") == nil
    end

    test "does nothing when the key is not there", %{conn: conn, advance: advance} do
      assert MemoryStore.expire(conn, "ghost", 60) == :ok

      # The TTL must not resurrect the key as an empty value.
      assert MemoryStore.get(conn, "ghost") == nil

      :ok = MemoryStore.set(conn, "ghost", "alice")
      advance.(120_000)
      assert MemoryStore.get(conn, "ghost") == "alice"
    end

    test "set clears a TTL that was already on the key", %{conn: conn, advance: advance} do
      :ok = MemoryStore.set(conn, "customer", "alice")
      :ok = MemoryStore.expire(conn, "customer", 60)
      :ok = MemoryStore.set(conn, "customer", "bob")

      advance.(120_000)
      assert MemoryStore.get(conn, "customer") == "bob"
    end

    test "incr keeps a TTL that was already on the key", %{conn: conn, advance: advance} do
      MemoryStore.incr(conn, "count")
      :ok = MemoryStore.expire(conn, "count", 60)

      assert MemoryStore.incr(conn, "count") == 2

      advance.(120_000)
      assert MemoryStore.get(conn, "count") == nil
    end

    test "incr after expiry starts over from 1", %{conn: conn, advance: advance} do
      MemoryStore.incr(conn, "count")
      MemoryStore.incr(conn, "count")
      :ok = MemoryStore.expire(conn, "count", 60)

      advance.(60_000)

      assert MemoryStore.incr(conn, "count") == 1
    end
  end
end
