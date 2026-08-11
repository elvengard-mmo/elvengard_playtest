defmodule ElvenGard.Playtest.FeatureLifecycleTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Playtest.{Browser, Feature, Suite}
  alias ElvenGard.Playtest.Driver.Node

  @tag timeout: 2_000
  test "feature cleanup stops its driver without awaiting a stalled browser close" do
    driver =
      start_supervised!(
        {Node,
         driver_path: fixture_path("stalled_close_driver.mjs"),
         node_path: System.find_executable("node"),
         owner: self()}
      )

    reference = Process.monitor(driver)

    suite = %Suite{
      browser: %Browser{
        driver: driver,
        id: "browser-1",
        lease: make_ref(),
        name: :chromium
      },
      driver: driver,
      players: %{}
    }

    assert :ok = Feature.close(suite)
    assert_receive {:DOWN, ^reference, :process, ^driver, :normal}
  end

  test "feature execution owns a timeout that starts after setup" do
    assert :completed = Feature.run(100, fn -> :completed end)

    assert_raise ExUnit.TimeoutError, ~r/Playtest feature timed out after 10ms/, fn ->
      Feature.run(10, fn ->
        receive do
          :never -> :completed
        end
      end)
    end
  end

  test "feature execution preserves callback exceptions and their stacktraces" do
    assert_raise ArgumentError, "product assertion", fn ->
      Feature.run(100, fn -> raise ArgumentError, "product assertion" end)
    end
  end

  ## Private functions

  defp fixture_path(name) do
    Path.expand("../../fixtures/#{name}", __DIR__)
  end
end
