defmodule Reservations.Store do
  @moduledoc """
  The slice of a Redis-like key/value store that reservations need.

  A store is referenced as a `{module, handle}` pair so the reservation logic
  can run against the in-memory stand-in in tests and a real Redis client in
  production without changing.

  `incr/2` must be atomic: two concurrent callers must never receive the same
  number back. That single guarantee is what keeps seats from being oversold.
  """

  @type handle :: term()
  @type t :: {module(), handle()}
  @type key :: String.t()
  @type value :: integer() | String.t()

  @doc "Returns the value at `key`, or nil if absent or expired."
  @callback get(handle(), key()) :: value() | nil

  @doc "Stores `value` at `key`, clearing any TTL."
  @callback set(handle(), key(), value()) :: :ok

  @doc "Atomically increments the integer at `key` and returns the new value."
  @callback incr(handle(), key()) :: integer()

  @doc "Sets a time-to-live, in seconds, on an existing `key`."
  @callback expire(handle(), key(), ttl_seconds :: number()) :: :ok
end

defmodule Reservations do
  @moduledoc """
  Seat reservations for events with a fixed number of seats.

  Each event keeps a counter in the store. Reserving means atomically
  incrementing that counter and reading the number you got back: numbers 1
  through `seats_per_event` are seats, anything higher means the event is sold
  out. Because the decision rides on the value the store handed back, and not on
  a separate read, concurrent callers can't both claim the last seat.
  """

  alias Reservations.Store

  @seats_per_event 10

  # Keys hang around long enough to outlive the event itself, then clean
  # themselves up so the store doesn't accumulate counters forever.
  @event_ttl_seconds 30 * 24 * 60 * 60

  @type event_id :: String.t()
  @type customer_id :: String.t()
  @type seat :: pos_integer()

  @doc """
  Reserves one seat at `event_id` for `customer_id`.

  Returns `{:ok, seat_number}` if the customer got a seat, or
  `{:error, :sold_out}` if every seat is already taken.

  Each call claims a seat, so calling twice for the same customer gives them two
  seats. Callers that retry on failure should key off the returned seat number
  rather than calling again blindly.
  """
  @spec reserve(Store.t(), event_id(), customer_id(), keyword()) ::
          {:ok, seat()} | {:error, :sold_out}
  def reserve({mod, handle}, event_id, customer_id, opts \\ []) do
    seats_per_event = Keyword.get(opts, :seats_per_event, @seats_per_event)
    counter = counter_key(event_id)

    seat = mod.incr(handle, counter)

    # First reservation for this event creates the key, so that's where the TTL
    # goes. Later increments inherit it.
    if seat == 1, do: mod.expire(handle, counter, @event_ttl_seconds)

    if seat <= seats_per_event do
      holder = holder_key(event_id, seat)
      mod.set(handle, holder, customer_id)
      mod.expire(handle, holder, @event_ttl_seconds)
      {:ok, seat}
    else
      # The counter overshoots capacity as sold-out attempts arrive. That costs
      # nothing: this comparison is what gates seats, so an inflated counter
      # stays sold out instead of wrapping back around into availability.
      {:error, :sold_out}
    end
  end

  @doc """
  Returns how many seats are left at `event_id`.

  Advisory only — a seat can be taken between this call and the next
  `reserve/4`. Use it for display, not for deciding whether to reserve.
  """
  @spec seats_available(Store.t(), event_id(), keyword()) :: non_neg_integer()
  def seats_available({mod, handle}, event_id, opts \\ []) do
    seats_per_event = Keyword.get(opts, :seats_per_event, @seats_per_event)
    taken = mod.get(handle, counter_key(event_id)) || 0
    max(seats_per_event - taken, 0)
  end

  @doc "Returns the customer holding `seat` at `event_id`, or nil if unclaimed."
  @spec seat_holder(Store.t(), event_id(), seat()) :: customer_id() | nil
  def seat_holder({mod, handle}, event_id, seat) do
    mod.get(handle, holder_key(event_id, seat))
  end

  @doc "Seats per event, used when no `:seats_per_event` option is given."
  def seats_per_event, do: @seats_per_event

  defp counter_key(event_id), do: "event:#{event_id}:seats_taken"
  defp holder_key(event_id, seat), do: "event:#{event_id}:seat:#{seat}"
end

defmodule Reservations.MemoryStore do
  @moduledoc """
  In-memory stand-in for Redis, so this runs locally with nothing installed.

  State lives in a single GenServer, which is what makes `incr/2` atomic: every
  increment is one serialized message, so no two callers see the same value.
  Keys expire lazily — an expired key is dropped the next time it's touched.
  """

  @behaviour Reservations.Store

  use GenServer

  @doc "Starts a store and returns the `{module, handle}` pair reservations take."
  @spec new() :: Reservations.Store.t()
  def new do
    {:ok, pid} = start_link()
    {__MODULE__, pid}
  end

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, :ok, opts)

  @impl Reservations.Store
  def get(pid, key), do: GenServer.call(pid, {:get, key})

  @impl Reservations.Store
  def set(pid, key, value), do: GenServer.call(pid, {:set, key, value})

  @impl Reservations.Store
  def incr(pid, key) do
    case GenServer.call(pid, {:incr, key}) do
      {:ok, value} ->
        value

      # Redis answers INCR on a non-numeric value with an error and keeps
      # serving, so the store survives and the bad caller is the one that fails.
      {:error, {:not_an_integer, value}} ->
        raise ArgumentError, "value at #{inspect(key)} is not an integer: #{inspect(value)}"
    end
  end

  @impl Reservations.Store
  def expire(pid, key, ttl_seconds), do: GenServer.call(pid, {:expire, key, ttl_seconds})

  @impl GenServer
  def init(:ok), do: {:ok, %{}}

  @impl GenServer
  def handle_call({:get, key}, _from, state) do
    case fetch_live(state, key) do
      {:ok, value, state} -> {:reply, value, state}
      {:expired, state} -> {:reply, nil, state}
    end
  end

  @impl GenServer
  def handle_call({:set, key, value}, _from, state) do
    {:reply, :ok, Map.put(state, key, {value, :never})}
  end

  @impl GenServer
  def handle_call({:incr, key}, _from, state) do
    {current, expires_at, state} =
      case fetch_live(state, key) do
        {:ok, nil, state} -> {0, :never, state}
        {:ok, value, state} -> {value, expiry(state, key), state}
        {:expired, state} -> {0, :never, state}
      end

    if is_integer(current) do
      next = current + 1
      {:reply, {:ok, next}, Map.put(state, key, {next, expires_at})}
    else
      {:reply, {:error, {:not_an_integer, current}}, state}
    end
  end

  @impl GenServer
  def handle_call({:expire, key, ttl_seconds}, _from, state) do
    case fetch_live(state, key) do
      {:ok, nil, state} ->
        {:reply, :ok, state}

      {:ok, value, state} ->
        expires_at = now_ms() + round(ttl_seconds * 1000)
        {:reply, :ok, Map.put(state, key, {value, expires_at})}

      {:expired, state} ->
        {:reply, :ok, state}
    end
  end

  defp fetch_live(state, key) do
    case Map.fetch(state, key) do
      :error -> {:ok, nil, state}
      {:ok, {value, :never}} -> {:ok, value, state}
      # Monotonic time can be negative, so only the type is worth guarding on.
      {:ok, {value, at}} when is_integer(at) -> check_expiry(state, key, value, at)
    end
  end

  defp check_expiry(state, key, value, expires_at) do
    if now_ms() >= expires_at do
      {:expired, Map.delete(state, key)}
    else
      {:ok, value, state}
    end
  end

  defp expiry(state, key) do
    case Map.fetch(state, key) do
      {:ok, {_value, expires_at}} -> expires_at
      :error -> :never
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
