Code.require_file("rate_limit.ex", __DIR__)

ExUnit.start()

defmodule RateLimitTest do
  # Not async: the ETS table is a single named table.
  use ExUnit.Case, async: false

  @minute 60_000
  # A fixed time at the start of a minute boundary.
  @t0 div(System.system_time(:millisecond), @minute) * @minute

  setup do
    start_supervised!(RateLimit)
    :ok
  end

  test "allows the first 100 requests in a minute and rejects the 101st" do
    results = for _ <- 1..100, do: RateLimit.allow_request("a", @t0)
    assert Enum.all?(results)
    refute RateLimit.allow_request("a", @t0)
    refute RateLimit.allow_request("a", @t0 + 59_999)
  end

  test "the real-clock function works" do
    assert RateLimit.allow_request("real")
  end

  test "customers are counted independently" do
    for _ <- 1..100, do: RateLimit.allow_request("a", @t0)
    refute RateLimit.allow_request("a", @t0)
    assert RateLimit.allow_request("b", @t0)
  end

  test "the limit resets in the next minute" do
    for _ <- 1..101, do: RateLimit.allow_request("a", @t0)
    refute RateLimit.allow_request("a", @t0 + 30_000)
    assert RateLimit.allow_request("a", @t0 + @minute)
  end

  test "rejected requests do not grow the counter without bound" do
    for _ <- 1..1_000, do: RateLimit.allow_request("a", @t0)
    [{_, count}] = :ets.lookup(RateLimit, {"a", div(@t0, @minute)})
    assert count == RateLimit.limit() + 1
  end

  test "exactly 100 succeed under heavy concurrency" do
    allowed =
      1..1_000
      |> Task.async_stream(fn _ -> RateLimit.allow_request("hot", @t0) end,
        max_concurrency: 200
      )
      |> Enum.count(fn {:ok, ok?} -> ok? end)

    assert allowed == 100
  end

  test "concurrent customers each get exactly 100" do
    counts =
      for(c <- 1..20, _ <- 1..150, do: c)
      |> Enum.shuffle()
      |> Task.async_stream(fn c -> {c, RateLimit.allow_request(c, @t0)} end,
        max_concurrency: 100
      )
      |> Enum.reduce(%{}, fn {:ok, {c, ok?}}, acc ->
        Map.update(acc, c, if(ok?, do: 1, else: 0), &(&1 + if(ok?, do: 1, else: 0)))
      end)

    assert map_size(counts) == 20
    assert Enum.all?(counts, fn {_c, n} -> n == 100 end)
  end

  test "sweep removes expired windows and keeps the current one" do
    RateLimit.allow_request("old", @t0)
    RateLimit.allow_request("new", @t0 + @minute)

    assert RateLimit.sweep(@t0 + @minute) == 1
    assert :ets.lookup(RateLimit, {"old", div(@t0, @minute)}) == []
    assert [_] = :ets.lookup(RateLimit, {"new", div(@t0, @minute) + 1})
  end
end
