Code.require_file("seats.ex", __DIR__)

ExUnit.start()

defmodule SeatsTest do
  use ExUnit.Case, async: false

  setup do
    start_supervised!(Seats)
    :ok
  end

  test "a customer gets a seat at a fresh event" do
    assert Seats.reserve_seat("concert", "alice") == :ok
    assert Seats.available("concert") == 9
  end

  test "the eleventh reservation is sold out" do
    for n <- 1..10, do: assert(Seats.reserve_seat("concert", "c#{n}") == :ok)

    assert Seats.reserve_seat("concert", "late") == {:error, :sold_out}
    assert Seats.available("concert") == 0
  end

  test "events have independent counts" do
    for n <- 1..10, do: :ok = Seats.reserve_seat("a", "c#{n}")

    assert Seats.reserve_seat("a", "x") == {:error, :sold_out}
    assert Seats.reserve_seat("b", "x") == :ok
    assert Seats.available("b") == 9
  end

  test "concurrent reservations never oversell" do
    results =
      1..1_000
      |> Task.async_stream(fn n -> Seats.reserve_seat("hot", "c#{n}") end,
        max_concurrency: 200
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.count(results, &(&1 == :ok)) == 10
    assert Enum.count(results, &(&1 == {:error, :sold_out})) == 990
    assert Seats.available("hot") == 0
  end

  test "concurrent reservations across many events" do
    results =
      for event <- 1..50, n <- 1..30 do
        Task.async(fn -> {event, Seats.reserve_seat(event, n)} end)
      end
      |> Task.await_many()

    oks = for {event, :ok} <- results, do: event
    freq = Enum.frequencies(oks)

    assert map_size(freq) == 50
    assert Enum.all?(freq, fn {_event, count} -> count == 10 end)
  end
end
