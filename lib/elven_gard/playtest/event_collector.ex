defmodule ElvenGard.Playtest.EventCollector do
  @moduledoc false

  use GenServer

  @default_event_limit 2_048

  @type event :: %{name: String.t(), params: map()}

  defstruct [
    :owner,
    events: :queue.new(),
    event_limit: @default_event_limit,
    failures: [],
    forward_events: true
  ]

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
    {:ok,
     %__MODULE__{
       owner: Keyword.fetch!(opts, :owner),
       event_limit: Keyword.get(opts, :event_limit, @default_event_limit),
       forward_events: Keyword.get(opts, :forward_events, true)
     }}
  end

  @impl true
  def handle_call(:events, _from, state) do
    events = :queue.to_list(state.events) ++ Enum.reverse(state.failures)
    {:reply, events, state}
  end

  @impl true
  def handle_info({:playtest_event, driver, name, params} = message, state) do
    if state.forward_events, do: send(state.owner, message)
    event = %{name: name, params: Map.put(params, "driver", inspect(driver))}

    if failure_event?(event) do
      {:noreply, %{state | failures: [event | state.failures]}}
    else
      {:noreply, %{state | events: enqueue_bounded(state.events, event, state.event_limit)}}
    end
  end

  ## Private functions

  defp enqueue_bounded(events, event, limit) do
    events = :queue.in(event, events)
    if :queue.len(events) > limit, do: events |> :queue.drop(), else: events
  end

  defp failure_event?(%{name: "page.error"}), do: true
  defp failure_event?(%{name: "page.crash"}), do: true
  defp failure_event?(%{name: "driver.protocol_error"}), do: true
  defp failure_event?(%{name: "page.console", params: %{"level" => "error"}}), do: true
  defp failure_event?(_event), do: false
end
