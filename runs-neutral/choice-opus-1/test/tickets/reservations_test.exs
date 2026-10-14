defmodule Tickets.ReservationsTest do
  use ExUnit.Case, async: true

  alias Tickets.MemoryStore
  alias Tickets.Reservations

  doctest Tickets.Reservations

  @event "show-1"

  setup do
    conn = start_supervised!(MemoryStore)
    {:ok, store: {MemoryStore, conn}}
  end

  describe "reserve_seat/3" do
    test "gives the first customer seat 1", %{store: store} do
      assert {:ok, reservation} = Reservations.reserve_seat(store, @event, "alice")
      assert reservation.seat == 1
      assert reservation.event_id == @event
      assert reservation.customer_id == "alice"
    end

    test "hands out every seat once, in order", %{store: store} do
      seats =
        for n <- 1..10 do
          assert {:ok, reservation} = Reservations.reserve_seat(store, @event, "customer-#{n}")
          reservation.seat
        end

      assert seats == Enum.to_list(1..10)
    end

    test "reports sold out once the tenth seat is gone", %{store: store} do
      for n <- 1..10, do: {:ok, _} = Reservations.reserve_seat(store, @event, "customer-#{n}")

      assert Reservations.reserve_seat(store, @event, "eleventh") == {:error, :sold_out}
    end

    test "stays sold out for every later customer", %{store: store} do
      for n <- 1..10, do: {:ok, _} = Reservations.reserve_seat(store, @event, "customer-#{n}")

      # The counter is past capacity now. It must keep refusing rather than
      # wrapping around or handing out seat 11.
      for n <- 11..20 do
        assert Reservations.reserve_seat(store, @event, "customer-#{n}") == {:error, :sold_out}
      end
    end

    test "records which customer holds each seat", %{store: store} do
      {:ok, alice} = Reservations.reserve_seat(store, @event, "alice")
      {:ok, bob} = Reservations.reserve_seat(store, @event, "bob")

      assert Reservations.seat_holder(store, @event, alice.seat) == "alice"
      assert Reservations.seat_holder(store, @event, bob.seat) == "bob"
      assert Reservations.seat_holder(store, @event, 3) == nil
    end

    test "sells each event's seats independently", %{store: store} do
      for n <- 1..10, do: {:ok, _} = Reservations.reserve_seat(store, "sold-out-show", "c-#{n}")

      assert Reservations.reserve_seat(store, "sold-out-show", "alice") == {:error, :sold_out}
      assert {:ok, reservation} = Reservations.reserve_seat(store, "other-show", "alice")
      assert reservation.seat == 1
    end

    test "lets one customer hold more than one seat", %{store: store} do
      # Documents a deliberate limitation: there is no per-customer
      # deduplication, because doing it safely needs a SETNX-style primitive.
      {:ok, first} = Reservations.reserve_seat(store, @event, "alice")
      {:ok, second} = Reservations.reserve_seat(store, @event, "alice")

      assert first.seat == 1
      assert second.seat == 2
    end

    test "gives each seat to exactly one of many concurrent callers", %{store: store} do
      {reserved, refused} =
        1..50
        |> Task.async_stream(
          fn n -> Reservations.reserve_seat(store, @event, "customer-#{n}") end,
          max_concurrency: 50,
          ordered: false
        )
        |> Enum.map(fn {:ok, result} -> result end)
        |> Enum.split_with(&match?({:ok, _}, &1))

      assert length(reserved) == 10
      assert length(refused) == 40
      assert Enum.all?(refused, &(&1 == {:error, :sold_out}))

      # Sorted equality proves no seat was handed out twice and none was skipped.
      seats = Enum.map(reserved, fn {:ok, reservation} -> reservation.seat end)
      assert Enum.sort(seats) == Enum.to_list(1..10)
    end
  end

  describe "seats_remaining/2" do
    test "starts at the full capacity", %{store: store} do
      assert Reservations.seats_remaining(store, @event) == 10
    end

    test "counts down as seats go", %{store: store} do
      {:ok, _} = Reservations.reserve_seat(store, @event, "alice")
      assert Reservations.seats_remaining(store, @event) == 9

      {:ok, _} = Reservations.reserve_seat(store, @event, "bob")
      assert Reservations.seats_remaining(store, @event) == 8
    end

    test "floors at zero even after refused attempts inflate the counter", %{store: store} do
      for n <- 1..25, do: Reservations.reserve_seat(store, @event, "customer-#{n}")

      assert Reservations.seats_remaining(store, @event) == 0
    end
  end

  describe "key expiry" do
    test "frees an event's keys once their TTL passes" do
      {clock, advance} = controllable_clock()

      conn =
        start_supervised!(
          Supervisor.child_spec({MemoryStore, [clock: clock]}, id: :clock_driven_store)
        )

      store = {MemoryStore, conn}

      {:ok, reservation} = Reservations.reserve_seat(store, @event, "alice")
      assert reservation.seat == 1
      assert Reservations.seats_remaining(store, @event) == 9

      advance.(31 * 24 * 60 * 60 * 1000)

      assert Reservations.seats_remaining(store, @event) == 10
      assert Reservations.seat_holder(store, @event, 1) == nil
      assert {:ok, %{seat: 1}} = Reservations.reserve_seat(store, @event, "bob")
    end

    test "keeps an event's keys while the TTL is still running" do
      {clock, advance} = controllable_clock()

      conn =
        start_supervised!(
          Supervisor.child_spec({MemoryStore, [clock: clock]}, id: :clock_driven_store)
        )

      store = {MemoryStore, conn}

      {:ok, _} = Reservations.reserve_seat(store, @event, "alice")

      advance.(29 * 24 * 60 * 60 * 1000)

      assert Reservations.seats_remaining(store, @event) == 9
      assert Reservations.seat_holder(store, @event, 1) == "alice"
    end
  end

  # A clock the test moves by hand, so expiry is tested without sleeping.
  defp controllable_clock do
    agent = start_supervised!({Agent, fn -> 0 end})

    clock = fn -> Agent.get(agent, & &1) end
    advance = fn ms -> Agent.update(agent, &(&1 + ms)) end

    {clock, advance}
  end
end
