ExUnit.start()

defmodule ReservationsTest do
  use ExUnit.Case, async: true

  alias Reservations.MemoryStore

  setup do
    {:ok, store: MemoryStore.new()}
  end

  describe "reserve/4" do
    test "the first customer gets seat 1", %{store: store} do
      assert {:ok, 1} = Reservations.reserve(store, "concert", "alice")
    end

    test "fills every seat, handing out each number exactly once", %{store: store} do
      seats =
        for n <- 1..10 do
          assert {:ok, seat} = Reservations.reserve(store, "concert", "customer-#{n}")
          seat
        end

      assert Enum.sort(seats) == Enum.to_list(1..10)
    end

    test "reports sold out once all 10 seats are gone", %{store: store} do
      for n <- 1..10, do: {:ok, _} = Reservations.reserve(store, "concert", "customer-#{n}")

      assert {:error, :sold_out} = Reservations.reserve(store, "concert", "latecomer")
    end

    test "stays sold out across repeated attempts", %{store: store} do
      for n <- 1..10, do: {:ok, _} = Reservations.reserve(store, "concert", "customer-#{n}")

      for _ <- 1..50 do
        assert {:error, :sold_out} = Reservations.reserve(store, "concert", "latecomer")
      end

      # Rejected attempts must not have quietly handed out an 11th seat.
      assert Reservations.seat_holder(store, "concert", 11) == nil
    end

    test "records which customer holds which seat", %{store: store} do
      {:ok, alice_seat} = Reservations.reserve(store, "concert", "alice")
      {:ok, bob_seat} = Reservations.reserve(store, "concert", "bob")

      assert Reservations.seat_holder(store, "concert", alice_seat) == "alice"
      assert Reservations.seat_holder(store, "concert", bob_seat) == "bob"
      assert Reservations.seat_holder(store, "concert", 10) == nil
    end

    test "each event has its own seats", %{store: store} do
      for n <- 1..10, do: {:ok, _} = Reservations.reserve(store, "concert", "customer-#{n}")

      assert {:error, :sold_out} = Reservations.reserve(store, "concert", "alice")
      assert {:ok, 1} = Reservations.reserve(store, "matinee", "alice")
    end

    test "a customer calling twice gets two distinct seats", %{store: store} do
      assert {:ok, first} = Reservations.reserve(store, "concert", "alice")
      assert {:ok, second} = Reservations.reserve(store, "concert", "alice")

      refute first == second
    end

    test "honors a custom capacity", %{store: store} do
      assert {:ok, 1} = Reservations.reserve(store, "tiny", "alice", seats_per_event: 2)
      assert {:ok, 2} = Reservations.reserve(store, "tiny", "bob", seats_per_event: 2)

      assert {:error, :sold_out} =
               Reservations.reserve(store, "tiny", "carol", seats_per_event: 2)
    end

    test "does not oversell under concurrent demand", %{store: store} do
      results =
        1..200
        |> Task.async_stream(
          fn n -> Reservations.reserve(store, "concert", "customer-#{n}") end,
          max_concurrency: 50,
          ordered: false
        )
        |> Enum.map(fn {:ok, result} -> result end)

      seats = for {:ok, seat} <- results, do: seat
      sold_out = for {:error, :sold_out} <- results, do: :sold_out

      assert length(seats) == 10
      assert length(sold_out) == 190
      # No two winners share a seat number.
      assert Enum.sort(seats) == Enum.to_list(1..10)
    end

    test "seats freed by key expiry become available again", %{store: store} do
      {MemoryStore, handle} = store
      for n <- 1..10, do: {:ok, _} = Reservations.reserve(store, "concert", "customer-#{n}")
      assert {:error, :sold_out} = Reservations.reserve(store, "concert", "alice")

      MemoryStore.expire(handle, "event:concert:seats_taken", 0.02)
      Process.sleep(40)

      assert {:ok, 1} = Reservations.reserve(store, "concert", "alice")
    end
  end

  describe "seats_available/3" do
    test "counts down as seats are taken", %{store: store} do
      assert Reservations.seats_available(store, "concert") == 10

      {:ok, _} = Reservations.reserve(store, "concert", "alice")
      assert Reservations.seats_available(store, "concert") == 9

      for n <- 1..9, do: {:ok, _} = Reservations.reserve(store, "concert", "customer-#{n}")
      assert Reservations.seats_available(store, "concert") == 0
    end

    test "never goes negative, even after sold-out attempts", %{store: store} do
      for n <- 1..10, do: {:ok, _} = Reservations.reserve(store, "concert", "customer-#{n}")
      for _ <- 1..5, do: {:error, :sold_out} = Reservations.reserve(store, "concert", "late")

      assert Reservations.seats_available(store, "concert") == 0
    end
  end
end

defmodule Reservations.MemoryStoreTest do
  use ExUnit.Case, async: true

  alias Reservations.MemoryStore

  setup do
    {MemoryStore, handle} = MemoryStore.new()
    {:ok, store: handle}
  end

  test "get returns nil for an unknown key", %{store: store} do
    assert MemoryStore.get(store, "nope") == nil
  end

  test "set then get round-trips a value", %{store: store} do
    assert :ok = MemoryStore.set(store, "customer", "alice")
    assert MemoryStore.get(store, "customer") == "alice"
  end

  test "incr starts a missing key at 1 and counts up", %{store: store} do
    assert MemoryStore.incr(store, "count") == 1
    assert MemoryStore.incr(store, "count") == 2
    assert MemoryStore.get(store, "count") == 2
  end

  test "incr hands out every number exactly once under concurrency", %{store: store} do
    values =
      1..500
      |> Task.async_stream(fn _ -> MemoryStore.incr(store, "count") end,
        max_concurrency: 50,
        ordered: false
      )
      |> Enum.map(fn {:ok, value} -> value end)
      |> Enum.sort()

    assert values == Enum.to_list(1..500)
  end

  test "incr refuses a non-integer value and keeps serving", %{store: store} do
    MemoryStore.set(store, "customer", "alice")

    assert_raise ArgumentError, fn -> MemoryStore.incr(store, "customer") end

    assert MemoryStore.get(store, "customer") == "alice"
    assert MemoryStore.incr(store, "count") == 1
  end

  test "keys disappear after their TTL", %{store: store} do
    MemoryStore.set(store, "hold", "alice")
    MemoryStore.expire(store, "hold", 0.02)

    assert MemoryStore.get(store, "hold") == "alice"
    Process.sleep(40)
    assert MemoryStore.get(store, "hold") == nil
  end

  test "incr preserves an existing TTL", %{store: store} do
    MemoryStore.incr(store, "count")
    MemoryStore.expire(store, "count", 0.02)
    assert MemoryStore.incr(store, "count") == 2

    Process.sleep(40)
    assert MemoryStore.get(store, "count") == nil
  end

  test "set clears an existing TTL", %{store: store} do
    MemoryStore.set(store, "hold", "alice")
    MemoryStore.expire(store, "hold", 0.02)
    MemoryStore.set(store, "hold", "bob")

    Process.sleep(40)
    assert MemoryStore.get(store, "hold") == "bob"
  end

  test "expire on a missing key is a no-op", %{store: store} do
    assert :ok = MemoryStore.expire(store, "nope", 10)
    assert MemoryStore.get(store, "nope") == nil
  end
end
