defmodule ElvenGard.Playtest.ConcurrencyTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Playtest.Concurrency

  test "queues browser owners fairly at the requested capacity" do
    gate = start_supervised!({Concurrency, name: nil})
    assert :ok = Concurrency.checkout(gate, 1)
    parent = self()

    task =
      Task.async(fn ->
        send(parent, :waiting)
        :ok = Concurrency.checkout(gate, 1)
        send(parent, :acquired)
        Concurrency.checkin(gate)
      end)

    assert_receive :waiting
    refute_receive :acquired, 50
    assert :ok = Concurrency.checkin(gate)
    assert_receive :acquired
    assert :ok = Task.await(task)
  end

  test "releases capacity when a checked-out owner exits" do
    gate = start_supervised!({Concurrency, name: nil})
    parent = self()

    owner =
      spawn_link(fn ->
        :ok = Concurrency.checkout(gate, 1)
        send(parent, :checked_out)

        receive do
          :stop -> :ok
        end
      end)

    assert_receive :checked_out

    task = Task.async(fn -> Concurrency.checkout(gate, 1) end)
    send(owner, :stop)

    assert :ok = Task.await(task)
    assert :ok = Concurrency.checkin(gate, task.pid)
  end
end
