defmodule SeatsTest do
  use ExUnit.Case, async: true

  alias Seats.MemoryStore

  setup do
    {:ok, store} = MemoryStore.start_link()
    %{store: store}
  end

  test "the first ten customers get seats 1 through 10", %{store: store} do
    results = for c <- 1..10, do: Seats.reserve(store, "show", "cust-#{c}")
    assert results == for(s <- 1..10, do: {:ok, s})
  end

  test "the eleventh customer is told the event is sold out", %{store: store} do
    for c <- 1..10, do: {:ok, _} = Seats.reserve(store, "show", "cust-#{c}")

    assert Seats.reserve(store, "show", "cust-11") == {:error, :sold_out}
    assert Seats.reserve(store, "show", "cust-12") == {:error, :sold_out}
  end

  test "each seat records the customer who reserved it", %{store: store} do
    {:ok, seat} = Seats.reserve(store, "show", "alice")
    assert Seats.holder(store, "show", seat) == "alice"
    assert Seats.holder(store, "show", 2) == nil
  end

  test "events have independent capacity", %{store: store} do
    for c <- 1..10, do: {:ok, _} = Seats.reserve(store, "a", "cust-#{c}")

    assert Seats.reserve(store, "a", "late") == {:error, :sold_out}
    assert Seats.reserve(store, "b", "late") == {:ok, 1}
  end

  test "concurrent requests never oversell or double-book", %{store: store} do
    results =
      1..500
      |> Task.async_stream(&Seats.reserve(store, "rush", "cust-#{&1}"),
        max_concurrency: 500,
        ordered: false
      )
      |> Enum.map(fn {:ok, result} -> result end)

    seats = for {:ok, seat} <- results, do: seat
    assert Enum.sort(seats) == Enum.to_list(1..10)
    assert Enum.count(results, &(&1 == {:error, :sold_out})) == 490

    holders = for s <- 1..10, do: Seats.holder(store, "rush", s)
    assert Enum.all?(holders, &is_binary/1)
    assert length(Enum.uniq(holders)) == 10
  end
end
