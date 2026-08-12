defmodule ElvenGard.Playtest.EventCollectorTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Playtest.EventCollector

  test "bounds high-volume diagnostics while retaining browser failures" do
    collector = start_supervised!({EventCollector, owner: self(), event_limit: 3})

    Enum.each(1..5, fn sequence ->
      send(
        collector,
        {:playtest_event, self(), "websocket.frame_received", %{"sequence" => sequence}}
      )
    end)

    send(collector, {
      :playtest_event,
      self(),
      "page.error",
      %{"message" => "render exploded"}
    })

    assert Enum.map(EventCollector.events(collector), & &1.name) == [
             "websocket.frame_received",
             "websocket.frame_received",
             "websocket.frame_received",
             "page.error"
           ]

    assert List.first(EventCollector.events(collector)).params["sequence"] == 3
  end
end
