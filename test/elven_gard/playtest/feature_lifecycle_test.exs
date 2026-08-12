defmodule ElvenGard.Playtest.FeatureLifecycleTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Playtest.{Browser, Concurrency, Feature, Suite}
  alias ElvenGard.Playtest.Driver.Node

  @tag timeout: 3_000
  test "feature cleanup delegates browser shutdown to its owning driver" do
    driver =
      start_supervised!(
        {Node,
         driver_path: fixture_path("stalled_close_driver.mjs"),
         node_path: System.find_executable("node"),
         owner: self()}
      )

    reference = Process.monitor(driver)

    gate = start_supervised!({Concurrency, name: nil})
    {:ok, lease} = Concurrency.checkout(gate, driver, 4)

    suite = %Suite{
      browser: %Browser{
        driver: driver,
        id: "browser-1",
        lease: lease,
        name: :chromium
      },
      driver: driver,
      players: %{}
    }

    contender = Task.async(fn -> Concurrency.checkout(gate, self(), 1) end)
    test_process = self()

    close_task =
      Task.async(fn ->
        send(test_process, {:feature_close_started, self()})

        receive do
          :continue_feature_close -> :ok
        end

        Feature.close(suite, timeout: 500)
      end)

    assert_receive {:feature_close_started, close_process}
    send(close_process, :continue_feature_close)
    assert_receive {:playtest_event, ^driver, "driver.close_requested", _params}
    assert Task.yield(contender, 0) == nil

    assert :ok = Task.await(close_task)
    assert_receive {:DOWN, ^reference, :process, ^driver, :normal}
    refute_receive {:playtest_event, ^driver, "browser.close_requested", _params}
    assert {:ok, _lease} = Task.await(contender)
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
