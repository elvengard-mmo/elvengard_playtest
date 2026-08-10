defmodule ElvenGard.Playtest.Concurrency do
  @moduledoc """
  Fair process gate that prevents asynchronous browser features from exhausting
  CPU, file descriptors or graphics resources on one test runner.
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

  @spec checkout(GenServer.server(), pid(), pos_integer()) :: {:ok, lease()}
  def checkout(server \\ __MODULE__, owner \\ self(), limit \\ default_limit())

  def checkout(server, owner, limit)
      when is_pid(owner) and is_integer(limit) and limit > 0 do
    GenServer.call(server, {:checkout, owner, limit}, :infinity)
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
  def handle_call({:checkout, owner, limit}, from, state) do
    if map_size(state.active) < limit do
      {lease, state} = grant(state, owner)
      {:reply, {:ok, lease}, state}
    else
      waiting = :queue.in({from, owner, limit}, state.waiting)
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

  defp grant(state, owner) do
    lease = make_ref()
    reference = Process.monitor(owner)

    state = %{
      state
      | active: Map.put(state.active, lease, {owner, reference}),
        monitors: Map.put(state.monitors, reference, lease)
    }

    {lease, state}
  end

  defp release(state, lease) do
    case Map.pop(state.active, lease) do
      {nil, _active} ->
        state

      {{_owner, reference}, active} ->
        Process.demonitor(reference, [:flush])
        %{state | active: active, monitors: Map.delete(state.monitors, reference)}
    end
  end

  defp grant_waiting(state) do
    case :queue.out(state.waiting) do
      {:empty, _waiting} ->
        state

      {{:value, {from, owner, limit}}, waiting} ->
        state = %{state | waiting: waiting}

        if map_size(state.active) < limit do
          {lease, state} = grant(state, owner)
          GenServer.reply(from, {:ok, lease})
          grant_waiting(state)
        else
          %{state | waiting: :queue.in_r({from, owner, limit}, waiting)}
        end
    end
  end
end
