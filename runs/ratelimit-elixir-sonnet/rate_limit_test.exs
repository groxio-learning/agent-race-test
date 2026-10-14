Code.require_file("rate_limit.ex", __DIR__)

ExUnit.start()

defmodule RateLimitTest do
  use ExUnit.Case, async: false

  @t0 1_000 * 60_000

  setup do
    RateLimit.setup()
    :ets.delete_all_objects(RateLimit)
    :ok
  end

  test "allows the first 100 requests and rejects the 101st" do
    for _ <- 1..100, do: assert(RateLimit.allow_request("a", @t0))
    refute RateLimit.allow_request("a", @t0)
    refute RateLimit.allow_request("a", @t0 + 59_999)
  end

  test "customers are independent" do
    for _ <- 1..100, do: RateLimit.allow_request("a", @t0)
    refute RateLimit.allow_request("a", @t0)
    assert RateLimit.allow_request("b", @t0)
  end

  test "limit resets in the next minute" do
    for _ <- 1..101, do: RateLimit.allow_request("a", @t0)
    assert RateLimit.allow_request("a", @t0 + 60_000)
  end

  test "setup is idempotent" do
    assert :ok = RateLimit.setup()
    assert :ok = RateLimit.setup()
  end

  test "purge removes old windows only" do
    RateLimit.allow_request("a", @t0)
    RateLimit.allow_request("b", @t0 + 60_000)
    RateLimit.purge(@t0 + 60_000)
    assert :ets.tab2list(RateLimit) |> length() == 1
  end

  test "default clock variant works" do
    assert RateLimit.allow_request("real-clock")
  end

  test "concurrent callers get exactly 100 allowed" do
    results =
      1..1_000
      |> Task.async_stream(fn _ -> RateLimit.allow_request("hot", @t0) end,
        max_concurrency: 100
      )
      |> Enum.map(fn {:ok, r} -> r end)

    assert Enum.count(results, & &1) == 100
  end
end
