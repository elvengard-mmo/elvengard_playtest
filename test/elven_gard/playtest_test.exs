defmodule ElvenGard.PlaytestTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Playtest.Installation

  test "ships matching pinned Node manifests" do
    manifests = Installation.manifest_paths()
    package = manifests.package |> File.read!() |> Jason.decode!()
    lock = manifests.lock |> File.read!() |> Jason.decode!()

    assert package["dependencies"]["playwright"] == "1.61.0"
    assert lock["packages"][""]["dependencies"]["playwright"] == "1.61.0"
  end
end
