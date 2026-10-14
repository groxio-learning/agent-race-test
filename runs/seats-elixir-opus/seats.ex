defmodule Seats do
  @moduledoc """
  Ticket reservations. Each event has 10 seats.

  Seat counts live in a single GenServer. Every reservation is a
  `GenServer.call/2`, so the check ("is a seat left?") and the update
  ("take it") happen together inside one process, one message at a time.
  Two customers racing for the last seat cannot both win.

  Start it with `Seats.start_link/1` (or put `Seats` in a supervision tree).
  """

  use GenServer

  @capacity 10

  # Client API

  @doc "Starts the seat server, registered under the module name by default."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, :ok, name: name)
  end

  @doc "The number of seats every event has."
  def capacity, do: @capacity

  @doc """
  Reserves one seat for `customer_id` at `event_id`.

  Returns `:ok` when a seat was taken, or `{:error, :sold_out}` when
  the event has no seats left.
  """
  def reserve_seat(server \\ __MODULE__, event_id, customer_id) do
    GenServer.call(server, {:reserve, event_id, customer_id})
  end

  @doc "Seats still available for `event_id`."
  def available(server \\ __MODULE__, event_id) do
    GenServer.call(server, {:available, event_id})
  end

  # Server callbacks

  @impl true
  def init(:ok), do: {:ok, %{}}

  @impl true
  def handle_call({:reserve, event_id, _customer_id}, _from, sold) do
    case Map.get(sold, event_id, 0) do
      taken when taken < @capacity ->
        {:reply, :ok, Map.put(sold, event_id, taken + 1)}

      _full ->
        {:reply, {:error, :sold_out}, sold}
    end
  end

  def handle_call({:available, event_id}, _from, sold) do
    {:reply, @capacity - Map.get(sold, event_id, 0), sold}
  end
end
