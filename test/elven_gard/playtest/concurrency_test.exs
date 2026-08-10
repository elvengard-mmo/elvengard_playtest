defmodule ElvenGard.Playtest.ConcurrencyTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Playtest.Concurrency

  test "defaults to four concurrent browser leases" do
    assert Concurrency.default_limit() == 4
  end

  test "can be started lazily by runtime-disabled test dependencies" do
    assert :ok = Concurrency.ensure_started()
    assert is_pid(Process.whereis(Concurrency))
  end

  test "queues browser owners fairly at the requested capacity" do
    gate = start_supervised!({Concurrency, name: nil})
    assert {:ok, lease} = Concurrency.checkout(gate, self(), 1)
    parent = self()

    task =
      Task.async(fn ->
        send(parent, :waiting)
        {:ok, task_lease} = Concurrency.checkout(gate, self(), 1)
        send(parent, :acquired)
        Concurrency.checkin(gate, task_lease)
      end)

    assert_receive :waiting
    refute_receive :acquired, 50
    assert :ok = Concurrency.checkin(gate, lease)
    assert_receive :acquired
    assert :ok = Task.await(task)
  end

  test "grants four independent leases before applying backpressure" do
    gate = start_supervised!({Concurrency, name: nil})
    leases = Enum.map(1..4, fn _index -> Concurrency.checkout(gate, self(), 4) end)
    assert Enum.all?(leases, &match?({:ok, lease} when is_reference(lease), &1))
    parent = self()

    contender =
      Task.async(fn ->
        {:ok, contender_lease} = Concurrency.checkout(gate, self(), 4)
        send(parent, :four_slot_contender_acquired)
        Concurrency.checkin(gate, contender_lease)
      end)

    refute_receive :four_slot_contender_acquired, 50
    [{:ok, released_lease} | remaining] = leases
    assert :ok = Concurrency.checkin(gate, released_lease)
    assert_receive :four_slot_contender_acquired
    assert :ok = Task.await(contender)

    Enum.each(remaining, fn {:ok, lease} -> assert :ok = Concurrency.checkin(gate, lease) end)
  end

  test "holds capacity until the resource owner exits instead of the checkout caller" do
    gate = start_supervised!({Concurrency, name: nil})
    parent = self()

    resource_owner =
      start_supervised!(
        Supervisor.child_spec(
          {Task,
           fn ->
             receive do
               :stop -> :ok
             end
           end},
          id: :resource_owner
        )
      )

    checkout_caller =
      Task.async(fn ->
        {:ok, lease} = Concurrency.checkout(gate, resource_owner, 1)
        send(parent, {:checked_out, lease})
        {:ok, lease}
      end)

    assert_receive {:checked_out, lease}
    assert {:ok, ^lease} = Task.await(checkout_caller)

    contender =
      Task.async(fn ->
        {:ok, contender_lease} = Concurrency.checkout(gate, self(), 1)
        send(parent, :contender_acquired)
        Concurrency.checkin(gate, contender_lease)
      end)

    refute_receive :contender_acquired, 50
    send(resource_owner, :stop)
    assert_receive :contender_acquired
    assert :ok = Task.await(contender)
  end
end
