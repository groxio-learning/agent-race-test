defmodule Seats do
  @moduledoc """
  Seat reservations for events with a fixed capacity.

  The whole correctness argument rests on one atomic operation: `incr` on the
  event's seat counter. Every caller gets a distinct number back. Numbers 1..10
  are seats; anything higher means the event is sold out. There is no
  read-then-write window, so two customers can never be handed the same seat
  and the event can never be oversold, no matter how many requests arrive at
  once or how many app servers share the store.
  """

  @capacity 10

  @type result :: {:ok, seat :: pos_integer()} | {:error, :sold_out}

  def capacity, do: @capacity

  @doc """
  Reserves a seat at `event_id` for `customer_id`.

  Returns `{:ok, seat_number}` or `{:error, :sold_out}`.
  """
  @spec reserve(GenServer.server(), term(), term(), module()) :: result()
  def reserve(store, event_id, customer_id, store_mod \\ Seats.MemoryStore) do
    case store_mod.incr(store, counter_key(event_id)) do
      seat when seat <= @capacity ->
        store_mod.set(store, seat_key(event_id, seat), customer_id)
        {:ok, seat}

      _overflow ->
        # The counter keeps climbing past capacity; that is harmless and
        # avoids a decrement that could race with other callers.
        {:error, :sold_out}
    end
  end

  @doc "Returns the customer holding `seat` at `event_id`, or nil."
  def holder(store, event_id, seat, store_mod \\ Seats.MemoryStore) do
    store_mod.get(store, seat_key(event_id, seat))
  end

  defp counter_key(event_id), do: "event:#{event_id}:seats_taken"
  defp seat_key(event_id, seat), do: "event:#{event_id}:seat:#{seat}"
end
