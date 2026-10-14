defmodule Tickets.Reservations do
  @moduledoc """
  Reserving seats at an event.

  ## How a seat is claimed

  The whole design turns on one move: `INCR` on the event's counter is the
  claim. It is atomic, it returns a number nobody else will get, and that
  number *is* the seat. A caller who gets 7 back owns seat 7 and can write
  to seat 7's key without coordinating with anyone.

  The obvious alternative — read the count, compare it to the capacity, write
  the count back — is two round trips with a gap in the middle. Two callers
  can both read 9 and both decide they have the last seat. No amount of
  care on the client fixes that; the check and the claim have to be one
  operation, which is what `INCR` gives us.

  ## Why the counter is never decremented

  Reservation 11 increments the counter to 11 and is then told the event is
  sold out, which leaves the counter one past capacity. That is deliberate.
  Rolling it back would reopen the race the counter exists to close: between
  the decrement and the next caller's increment, a seat would look free that
  is not. The counter only ever ratchets upward, so once it passes capacity
  every later caller is correctly refused.

  The cost is that the counter is not a seat count once an event sells out —
  it is a count of *attempts*. `seats_remaining/2` accounts for that, and
  nothing else reads the raw number.

  ## Assumptions worth naming

  Reserving twice for the same customer yields two seats; there is no
  per-customer deduplication. Adding it safely needs a compare-and-set
  primitive (`SETNX`), which is outside the four operations
  `Tickets.Store` exposes, and a `get`-then-`set` imitation would be exactly
  the race described above. If one-seat-per-customer is a rule you need,
  that behaviour belongs in `Tickets.Store` first.
  """

  alias Tickets.Reservation

  @seats_per_event 10

  # Long enough to outlive any real event, short enough that abandoned
  # events do not accumulate in the store forever.
  @key_ttl_seconds 30 * 24 * 60 * 60

  @typedoc "A store to work against: its module plus its connection."
  @type store :: {module(), Tickets.Store.conn()}

  @doc "How many seats each event has."
  @spec seats_per_event() :: pos_integer()
  def seats_per_event, do: @seats_per_event

  @doc """
  Reserves one seat at `event_id` for `customer_id`.

  Returns `{:ok, %Tickets.Reservation{}}` with the seat number the customer
  got, or `{:error, :sold_out}` once the event's #{@seats_per_event} seats
  are gone. Safe to call concurrently: each successful call returns a
  different seat.

  ## Examples

      iex> {:ok, conn} = Tickets.MemoryStore.start_link()
      iex> {:ok, reservation} =
      ...>   Tickets.Reservations.reserve_seat({Tickets.MemoryStore, conn}, "show-1", "alice")
      iex> reservation.seat
      1

  """
  @spec reserve_seat(store(), String.t(), String.t()) ::
          {:ok, Reservation.t()} | {:error, :sold_out}
  def reserve_seat({mod, conn}, event_id, customer_id) do
    counter = counter_key(event_id)

    case mod.incr(conn, counter) do
      seat when seat <= @seats_per_event ->
        # This caller owns `seat` outright, so these writes race with nobody.
        mod.expire(conn, counter, @key_ttl_seconds)
        mod.set(conn, seat_key(event_id, seat), customer_id)
        mod.expire(conn, seat_key(event_id, seat), @key_ttl_seconds)

        {:ok, %Reservation{event_id: event_id, customer_id: customer_id, seat: seat}}

      _past_capacity ->
        {:error, :sold_out}
    end
  end

  @doc """
  Returns how many seats are still open at `event_id`.

  This is a snapshot for display, not a reservation: a seat it reports as
  open can be taken before the caller acts on it. `reserve_seat/3` is the
  only thing that decides whether a customer gets in.
  """
  @spec seats_remaining(store(), String.t()) :: non_neg_integer()
  def seats_remaining({mod, conn}, event_id) do
    claimed =
      case mod.get(conn, counter_key(event_id)) do
        nil -> 0
        value -> String.to_integer(value)
      end

    # `claimed` can exceed capacity once an event sells out; see the note on
    # why the counter is never rolled back.
    max(@seats_per_event - claimed, 0)
  end

  @doc """
  Returns the id of the customer holding `seat` at `event_id`, or `nil`.
  """
  @spec seat_holder(store(), String.t(), pos_integer()) :: String.t() | nil
  def seat_holder({mod, conn}, event_id, seat) do
    mod.get(conn, seat_key(event_id, seat))
  end

  defp counter_key(event_id), do: "event:#{event_id}:seats_claimed"
  defp seat_key(event_id, seat), do: "event:#{event_id}:seat:#{seat}"
end
