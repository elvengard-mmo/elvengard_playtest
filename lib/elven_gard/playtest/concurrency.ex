defmodule ElvenGard.Playtest.Concurrency do
  @moduledoc """
  Capacity-aware process gate that prevents asynchronous browser features from
  exhausting CPU, file descriptors or graphics resources on one test runner.
  """

  use GenServer

  @default_limit 4

  @type lease :: reference()

  ## Public API

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, :ok)
      name -> GenServer.start_link(__MODULE__, :ok, name: name)
    end
  end

  @spec checkout(GenServer.server(), pid(), pos_integer(), pos_integer()) :: {:ok, lease()}
  def checkout(
        server \\ __MODULE__,
        owner \\ self(),
        limit \\ default_limit(),
        weight \\ 1
      )

  def checkout(server, owner, limit, weight)
      when is_pid(owner) and is_integer(limit) and limit > 0 and is_integer(weight) and weight > 0 do
    GenServer.call(server, {:checkout, owner, limit, weight}, :infinity)
  end

  @spec ensure_started() :: :ok
  def ensure_started() do
    case GenServer.start(__MODULE__, :ok, name: __MODULE__) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end
  end

  @spec checkin(lease()) :: :ok
  def checkin(lease) when is_reference(lease), do: checkin(__MODULE__, lease)

  @spec checkin(GenServer.server(), lease()) :: :ok
  def checkin(server, lease) when is_reference(lease) do
    GenServer.call(server, {:checkin, lease})
  end

  @spec default_limit() :: pos_integer()
  def default_limit() do
    Application.get_env(:elvengard_playtest, :max_concurrency, @default_limit)
  end

  ## GenServer callbacks

  @impl true
  def init(:ok) do
    {:ok, %{active: %{}, monitors: %{}, waiting: :queue.new()}}
  end

  @impl true
  def handle_call({:checkout, owner, limit, weight}, from, state) do
    if capacity_available?(state, limit, weight) do
      {lease, state} = grant(state, owner, weight)
      {:reply, {:ok, lease}, state}
    else
      waiting = :queue.in({from, owner, limit, weight}, state.waiting)
      {:noreply, %{state | waiting: waiting}}
    end
  end

  def handle_call({:checkin, lease}, _from, state) do
    state = release(state, lease)
    {:reply, :ok, grant_waiting(state)}
  end

  @impl true
  def handle_info({:DOWN, reference, :process, _owner, _reason}, state) do
    case Map.fetch(state.monitors, reference) do
      {:ok, lease} ->
        {:noreply, state |> release(lease) |> grant_waiting()}

      :error ->
        {:noreply, state}
    end
  end

  ## Private functions

  defp grant(state, owner, weight) do
    lease = make_ref()
    reference = Process.monitor(owner)

    state = %{
      state
      | active: Map.put(state.active, lease, {owner, reference, weight}),
        monitors: Map.put(state.monitors, reference, lease)
    }

    {lease, state}
  end

  defp release(state, lease) do
    case Map.pop(state.active, lease) do
      {nil, _active} ->
        state

      {{_owner, reference, _weight}, active} ->
        Process.demonitor(reference, [:flush])
        %{state | active: active, monitors: Map.delete(state.monitors, reference)}
    end
  end

  defp grant_waiting(state) do
    waiting = :queue.to_list(state.waiting)

    case Enum.split_while(waiting, fn {_from, _owner, limit, weight} ->
           not capacity_available?(state, limit, weight)
         end) do
      {_blocked, []} ->
        state

      {blocked, [{from, owner, _limit, weight} | remaining]} ->
        state = %{state | waiting: :queue.from_list(blocked ++ remaining)}
        {lease, state} = grant(state, owner, weight)
        GenServer.reply(from, {:ok, lease})
        grant_waiting(state)
    end
  end

  defp capacity_available?(%{active: active}, limit, weight) when map_size(active) == 0 do
    weight > 0 and limit > 0
  end

  defp capacity_available?(state, limit, weight) do
    used =
      Enum.reduce(state.active, 0, fn {_lease, {_owner, _reference, active_weight}}, acc ->
        acc + active_weight
      end)

    used + weight <= limit
  end
end
