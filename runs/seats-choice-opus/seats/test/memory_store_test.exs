defmodule Seats.MemoryStoreTest do
  use ExUnit.Case, async: true

  alias Seats.MemoryStore

  setup do
    {:ok, store} = MemoryStore.start_link()
    %{store: store}
  end

  test "get, set, incr", %{store: store} do
    assert MemoryStore.get(store, "k") == nil
    MemoryStore.set(store, "k", "v")
    assert MemoryStore.get(store, "k") == "v"
    assert MemoryStore.incr(store, "n") == 1
    assert MemoryStore.incr(store, "n") == 2
  end

  test "incr on a non-integer raises", %{store: store} do
    MemoryStore.set(store, "k", "v")
    assert_raise ArgumentError, fn -> MemoryStore.incr(store, "k") end
  end

  test "expire removes a key after its ttl", %{store: store} do
    MemoryStore.set(store, "k", "v")
    assert MemoryStore.expire(store, "k", 0) == true
    assert MemoryStore.get(store, "k") == nil
    assert MemoryStore.expire(store, "missing", 10) == false
  end

  test "expire keeps a key alive until its ttl", %{store: store} do
    MemoryStore.set(store, "k", "v")
    MemoryStore.expire(store, "k", 60)
    assert MemoryStore.get(store, "k") == "v"
  end
end
