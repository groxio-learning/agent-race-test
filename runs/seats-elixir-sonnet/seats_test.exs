Code.require_file("seats.ex", __DIR__)
ExUnit.start()

defmodule SeatsTest do
  use ExUnit.Case, async: true

  setup do
    pid = start_supervised!({Seats, name: nil}, id: make_ref())
    {:ok, server: pid}
  end

  test "first ten customers get seats, the eleventh is sold out", %{server: s} do
    for i <- 1..10, do: assert(Seats.reserve_seat(s, "e1", i) == :ok)
    assert Seats.reserve_seat(s, "e1", 11) == {:error, :sold_out}
    assert Seats.reserve_seat(s, "e1", 12) == {:error, :sold_out}
  end

  test "events are independent", %{server: s} do
    for i <- 1..10, do: Seats.reserve_seat(s, "a", i)
    assert Seats.reserve_seat(s, "a", 99) == {:error, :sold_out}
    assert Seats.reserve_seat(s, "b", 99) == :ok
  end

  test "same customer twice does not use two seats", %{server: s} do
    for _ <- 1..20, do: assert(Seats.reserve_seat(s, "e", :alice) == :ok)
    for i <- 1..9, do: assert(Seats.reserve_seat(s, "e", i) == :ok)
    assert Seats.reserve_seat(s, "e", :late) == {:error, :sold_out}
  end

  test "existing holder still gets :ok when sold out", %{server: s} do
    for i <- 1..10, do: Seats.reserve_seat(s, "e", i)
    assert Seats.reserve_seat(s, "e", 3) == :ok
  end

  test "concurrent reservations never oversell", %{server: s} do
    results =
      1..100
      |> Task.async_stream(fn i -> Seats.reserve_seat(s, "hot", i) end, max_concurrency: 50)
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.count(results, &(&1 == :ok)) == 10
    assert Enum.count(results, &(&1 == {:error, :sold_out})) == 90
  end

  test "default named server works" do
    start_supervised!(Seats)
    assert Seats.reserve_seat("named", 1) == :ok
  end
end
