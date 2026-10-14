defmodule RateLimit do
  @moduledoc """
  Per-customer rate limiting: 100 requests per minute.

  Counts live in a named, public ETS table owned by a small GenServer.
  Each request does a single atomic `:ets.update_counter/4` on the key
  `{customer_id, window}`, where `window` is the current minute. That means
  `allow_request/1` runs in the caller's process, never serializes through a
  mailbox, and is safe under any amount of concurrency: two processes can
  never both observe "99" and both get in as the 100th request.

  The GenServer exists only to own the table (so it outlives callers) and to
  sweep expired windows once a minute so memory does not grow without bound.

  This is a fixed-window limiter. A customer can make up to 100 requests at
  the end of one minute and 100 more at the start of the next. If you need a
  strict "no more than 100 in any rolling 60 seconds" guarantee, use a
  sliding-window or token-bucket variant instead.

  Usage:

      {:ok, _pid} = RateLimit.start_link()
      RateLimit.allow_request("cust_42")  #=> true

  In an application, put `RateLimit` in your supervision tree instead of
  calling `start_link/1` by hand.
  """

  use GenServer

  @table __MODULE__
  @limit 100
  @window_ms 60_000

  ## Public API

  @doc "Starts the table owner. Call once (or supervise it) before `allow_request/1`."
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Alias for `start_link/1`, for callers who want a plain setup function."
  def setup, do: start_link()

  @doc """
  Returns `true` if this request is within the customer's limit, `false` otherwise.

  Rejected requests still increment the counter, but the count is capped at
  the limit plus one, so a hammering client cannot overflow anything and the
  answer stays `false` until the window rolls over.
  """
  def allow_request(customer_id) do
    allow_request(customer_id, System.system_time(:millisecond))
  end

  @doc false
  # Clock injected for tests.
  def allow_request(customer_id, now_ms) do
    key = {customer_id, div(now_ms, @window_ms)}
    # {position, increment, threshold, set_value}: increment by 1, but if the
    # result would exceed limit + 1, pin it at limit + 1.
    count = :ets.update_counter(@table, key, {2, 1, @limit + 1, @limit + 1}, {key, 0})
    count <= @limit
  end

  @doc "The per-minute limit."
  def limit, do: @limit

  @doc false
  # Removes every window older than the one containing `now_ms`.
  def sweep(now_ms \\ System.system_time(:millisecond)) do
    current = div(now_ms, @window_ms)
    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:<, :"$1", current}], [true]}])
  end

  ## GenServer callbacks

  @impl true
  def init(opts) do
    :ets.new(@table, [
      :named_table,
      :public,
      :set,
      read_concurrency: true,
      write_concurrency: true,
      decentralized_counters: true
    ])

    interval = Keyword.get(opts, :sweep_interval_ms, @window_ms)
    schedule_sweep(interval)
    {:ok, %{sweep_interval_ms: interval}}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep()
    schedule_sweep(state.sweep_interval_ms)
    {:noreply, state}
  end

  defp schedule_sweep(interval), do: Process.send_after(self(), :sweep, interval)
end
