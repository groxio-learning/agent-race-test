defmodule RateLimit do
  @moduledoc """
  Fixed-window rate limiter: 100 requests per customer per minute.

  Counts live in a public, named ETS table and are bumped with the atomic
  `:ets.update_counter/4`, so concurrent callers never lose an increment.

  Call `RateLimit.setup/0` once at startup. The table is owned by the calling
  process and disappears when that process exits, so call it from a
  long-lived process (e.g. your application's start-up or a supervisor child).
  """

  @table __MODULE__
  @limit 100
  @window_ms 60_000

  @doc "Creates the counter table. Idempotent."
  def setup do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    end

    :ok
  rescue
    # Lost a race with another process creating the table.
    ArgumentError -> :ok
  end

  @doc """
  Returns `true` if the request is allowed, `false` if the customer has
  already made #{@limit} requests in the current one-minute window.
  Rejected requests still count, but never flip an allowed one.
  """
  def allow_request(customer_id), do: allow_request(customer_id, now_ms())

  @doc false
  def allow_request(customer_id, now_ms) do
    window = div(now_ms, @window_ms)
    key = {customer_id, window}
    count = :ets.update_counter(@table, key, {2, 1}, {key, 0})

    # First hit in a new window: drop this customer's previous window row.
    if count == 1, do: :ets.delete(@table, {customer_id, window - 1})

    count <= @limit
  end

  @doc "Deletes all rows from windows older than the current one."
  def purge(now_ms \\ now_ms()) do
    window = div(now_ms, @window_ms)
    :ets.select_delete(@table, [{{{:_, :"$1"}, :_}, [{:<, :"$1", window}], [true]}])
    :ok
  end

  defp now_ms, do: System.system_time(:millisecond)
end
