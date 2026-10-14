defmodule Tickets.MemoryStore do
  @moduledoc """
  An in-memory stand-in for a Redis-like store, so the code runs locally.

  Every command goes through one GenServer, which serializes them the way a
  single-threaded Redis server would. That is the property `incr/2` depends
  on: concurrent callers each get a distinct number back.

  Keys expire lazily. Nothing sweeps the table on a timer; an expired key is
  noticed and dropped the next time someone touches it, which is also how
  Redis behaves from a client's point of view.

  Pass a `:clock` (a 0-arity fun returning milliseconds) to drive expiry from
  a test instead of the system clock.
  """

  @behaviour Tickets.Store

  use GenServer

  @type option :: {:clock, (-> integer())} | GenServer.option()

  @doc """
  Starts a store.

  Accepts `:clock` plus the usual `GenServer.start_link/3` options, so
  `name: MyStore` works as expected.
  """
  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {clock, opts} = Keyword.pop(opts, :clock, &monotonic_ms/0)
    GenServer.start_link(__MODULE__, clock, opts)
  end

  @impl Tickets.Store
  def get(conn, key), do: GenServer.call(conn, {:get, key})

  @impl Tickets.Store
  def set(conn, key, value), do: GenServer.call(conn, {:set, key, value})

  @impl Tickets.Store
  def incr(conn, key), do: GenServer.call(conn, {:incr, key})

  @impl Tickets.Store
  def expire(conn, key, ttl_seconds), do: GenServer.call(conn, {:expire, key, ttl_seconds})

  @impl GenServer
  def init(clock), do: {:ok, %{data: %{}, clock: clock}}

  @impl GenServer
  def handle_call({:get, key}, _from, state) do
    state = drop_if_expired(state, key)

    case state.data do
      %{^key => {value, _expires_at}} -> {:reply, value, state}
      _ -> {:reply, nil, state}
    end
  end

  @impl GenServer
  def handle_call({:set, key, value}, _from, state) do
    {:reply, :ok, put(state, key, to_string(value), :never)}
  end

  @impl GenServer
  def handle_call({:incr, key}, _from, state) do
    state = drop_if_expired(state, key)

    {current, expires_at} =
      case state.data do
        %{^key => {value, expires_at}} -> {String.to_integer(value), expires_at}
        _ -> {0, :never}
      end

    incremented = current + 1
    {:reply, incremented, put(state, key, Integer.to_string(incremented), expires_at)}
  end

  @impl GenServer
  def handle_call({:expire, key, ttl_seconds}, _from, state) when ttl_seconds <= 0 do
    {:reply, :ok, %{state | data: Map.delete(state.data, key)}}
  end

  @impl GenServer
  def handle_call({:expire, key, ttl_seconds}, _from, state) do
    state = drop_if_expired(state, key)

    case state.data do
      %{^key => {value, _expires_at}} ->
        expires_at = state.clock.() + ttl_seconds * 1000
        {:reply, :ok, put(state, key, value, expires_at)}

      # Redis will not put a TTL on a key that is not there.
      _ ->
        {:reply, :ok, state}
    end
  end

  defp put(state, key, value, expires_at) do
    %{state | data: Map.put(state.data, key, {value, expires_at})}
  end

  defp drop_if_expired(state, key) do
    case state.data do
      %{^key => {_value, expires_at}} when is_integer(expires_at) ->
        if state.clock.() >= expires_at do
          %{state | data: Map.delete(state.data, key)}
        else
          state
        end

      _ ->
        state
    end
  end

  defp monotonic_ms, do: System.monotonic_time(:millisecond)
end
