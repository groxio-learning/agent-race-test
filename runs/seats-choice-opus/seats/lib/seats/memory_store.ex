defmodule Seats.MemoryStore do
  @moduledoc """
  A tiny in-memory stand-in for a Redis-like key-value store.

  Supports `get/2`, `set/3`, `incr/2`, and `expire/3`. Every operation runs
  inside a single Agent process, so each call is atomic, just as each Redis
  command is atomic on the server.
  """

  use Agent

  def start_link(opts \\ []), do: Agent.start_link(fn -> %{} end, opts)

  @doc "Returns the value at `key`, or nil if missing or expired."
  def get(store, key) do
    Agent.get(store, fn data ->
      case live(data, key) do
        {value, _expires_at} -> value
        nil -> nil
      end
    end)
  end

  @doc "Sets `key` to `value`, clearing any expiry (like Redis SET)."
  def set(store, key, value) do
    Agent.update(store, &Map.put(&1, key, {value, nil}))
  end

  @doc "Atomically increments the integer at `key` (missing counts as 0); returns the new value."
  def incr(store, key) do
    result =
      Agent.get_and_update(store, fn data ->
        case live(data, key) || {0, nil} do
          {value, expires_at} when is_integer(value) ->
            {{:ok, value + 1}, Map.put(data, key, {value + 1, expires_at})}

          _not_an_integer ->
            {:not_an_integer, data}
        end
      end)

    # Raise in the caller, not inside the Agent, so the store stays up
    # (Redis likewise returns an error without disturbing the server).
    case result do
      {:ok, new} -> new
      :not_an_integer -> raise ArgumentError, "value at #{inspect(key)} is not an integer"
    end
  end

  @doc "Expires `key` after `seconds`. Returns true if the key exists."
  def expire(store, key, seconds) do
    Agent.get_and_update(store, fn data ->
      case live(data, key) do
        {value, _} -> {true, Map.put(data, key, {value, now_ms() + seconds * 1000})}
        nil -> {false, Map.delete(data, key)}
      end
    end)
  end

  defp live(data, key) do
    case Map.get(data, key) do
      {_value, expires_at} = entry when is_nil(expires_at) -> entry
      {_value, expires_at} = entry -> if expires_at > now_ms(), do: entry, else: nil
      nil -> nil
    end
  end

  defp now_ms, do: System.monotonic_time(:millisecond)
end
