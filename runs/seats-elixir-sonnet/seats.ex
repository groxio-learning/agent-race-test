defmodule Seats do
  @moduledoc """
  Ticket reservations. Each event has #{10} seats.

  State lives in an Agent: a map of event_id => %{customer_id => true}.
  All reads and writes go through the Agent process, so a reservation is
  an atomic check-and-update and concurrent callers can't oversell.
  """

  use Agent

  @capacity 10

  def capacity, do: @capacity

  @doc "Setup: starts the process that holds the seat state."
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, __MODULE__)
    Agent.start_link(fn -> %{} end, name: name)
  end

  @doc """
  Reserves a seat. Returns `:ok` or `{:error, :sold_out}`.
  A customer who already holds a seat for the event keeps that single seat
  (the call returns `:ok` without consuming another).
  """
  def reserve_seat(event_id, customer_id), do: reserve_seat(__MODULE__, event_id, customer_id)

  def reserve_seat(server, event_id, customer_id) do
    Agent.get_and_update(server, fn state ->
      holders = Map.get(state, event_id, MapSet.new())

      cond do
        MapSet.member?(holders, customer_id) ->
          {:ok, state}

        MapSet.size(holders) >= @capacity ->
          {{:error, :sold_out}, state}

        true ->
          {:ok, Map.put(state, event_id, MapSet.put(holders, customer_id))}
      end
    end)
  end
end
