defmodule ElvenGard.Playtest.Concurrency do
  @moduledoc """
  Fair process gate that prevents asynchronous browser features from exhausting
  CPU, file descriptors or graphics resources on one test runner.
  """

  use GenServer

  @default_limit 4

  ## Public API

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.get(opts, :name, __MODULE__) do
      nil -> GenServer.start_link(__MODULE__, :ok)
      name -> GenServer.start_link(__MODULE__, :ok, name: name)
    end
  end

  @spec checkout(GenServer.server(), pos_integer()) :: :ok
  def checkout(server \\ __MODULE__, limit \\ default_limit())

  def checkout(server, limit) when is_integer(limit) and limit > 0 do
    GenServer.call(server, {:checkout, limit}, :infinity)
  end

  @spec checkin(GenServer.server(), pid()) :: :ok
  def checkin(server \\ __MODULE__, owner \\ self()) when is_pid(owner) do
    GenServer.call(server, {:checkin, owner})
  end

  @spec default_limit() :: pos_integer()
  def default_limit() do
    Application.get_env(:elvengard_playtest, :max_concurrency, @default_limit)
  end

  ## GenServer callbacks

  @impl true
  def init(:ok) do
    {:ok, %{active: %{}, waiting: :queue.new()}}
  end

  @impl true
  def handle_call({:checkout, limit}, from, state) do
    if map_size(state.active) < limit do
      {:reply, :ok, grant(state, from)}
    else
      waiting = :queue.in({from, limit}, state.waiting)
      {:noreply, %{state | waiting: waiting}}
    end
  end

  def handle_call({:checkin, owner}, _from, state) do
    state = release(state, owner)
    {:reply, :ok, grant_waiting(state)}
  end

  @impl true
  def handle_info({:DOWN, reference, :process, owner, _reason}, state) do
    case state.active do
      %{^owner => ^reference} -> {:noreply, state |> release(owner) |> grant_waiting()}
      _active -> {:noreply, state}
    end
  end

  ## Private functions

  defp grant(state, {owner, _tag}) do
    reference = Process.monitor(owner)
    put_in(state.active[owner], reference)
  end

  defp release(state, owner) do
    case Map.pop(state.active, owner) do
      {nil, _active} ->
        state

      {reference, active} ->
        Process.demonitor(reference, [:flush])
        %{state | active: active}
    end
  end

  defp grant_waiting(state) do
    case :queue.out(state.waiting) do
      {:empty, _waiting} ->
        state

      {{:value, {from, limit}}, waiting} ->
        state = %{state | waiting: waiting}

        if map_size(state.active) < limit do
          GenServer.reply(from, :ok)
          state |> grant(from) |> grant_waiting()
        else
          %{state | waiting: :queue.in_r({from, limit}, waiting)}
        end
    end
  end
end
