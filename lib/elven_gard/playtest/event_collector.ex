defmodule ElvenGard.Playtest.EventCollector do
  @moduledoc false

  use GenServer

  @type event :: %{name: String.t(), params: map()}

  defstruct [:owner, events: []]

  ## Public API

  @spec start_link(Keyword.t()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @spec events(GenServer.server()) :: [event()]
  def events(collector), do: GenServer.call(collector, :events)

  ## GenServer callbacks

  @impl true
  def init(opts) do
    {:ok, %__MODULE__{owner: Keyword.fetch!(opts, :owner)}}
  end

  @impl true
  def handle_call(:events, _from, state) do
    {:reply, Enum.reverse(state.events), state}
  end

  @impl true
  def handle_info({:playtest_event, driver, name, params} = message, state) do
    send(state.owner, message)
    event = %{name: name, params: Map.put(params, "driver", inspect(driver))}
    {:noreply, %{state | events: [event | state.events]}}
  end
end
