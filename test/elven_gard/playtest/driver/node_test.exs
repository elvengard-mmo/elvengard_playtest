defmodule ElvenGard.Playtest.Driver.NodeTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Playtest.Driver.Node

  @fixture Path.expand("../../../fixtures/echo_driver.mjs", __DIR__)

  describe "command/4" do
    test "correlates responses with their callers" do
      driver = start_supervised!({Node, driver_path: @fixture, owner: self()})

      assert {:ok, %{"value" => 42}} = Node.command(driver, "echo", %{"value" => 42})
    end

    test "forwards asynchronous driver events to the owner" do
      driver = start_supervised!({Node, driver_path: @fixture, owner: self()})

      assert {:ok, true} = Node.command(driver, "emit", %{"player" => "one"})

      assert_receive {:playtest_event, ^driver, "fixture.event", %{"player" => "one"}}
    end

    test "returns structured driver errors" do
      driver = start_supervised!({Node, driver_path: @fixture, owner: self()})

      assert {:error, %{"code" => "unknown_method", "message" => message}} =
               Node.command(driver, "missing")

      assert message == "Unknown method: missing"
    end
  end
end
