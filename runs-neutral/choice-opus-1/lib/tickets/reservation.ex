defmodule Tickets.Reservation do
  @moduledoc "One customer holding one numbered seat at one event."

  @enforce_keys [:event_id, :customer_id, :seat]
  defstruct [:event_id, :customer_id, :seat]

  @type t :: %__MODULE__{
          event_id: String.t(),
          customer_id: String.t(),
          seat: pos_integer()
        }
end
