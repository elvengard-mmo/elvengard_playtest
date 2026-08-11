defmodule ElvenGard.Playtest.Feature.TimeoutTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Playtest.Feature.Timeout

  test "resolves direct and accumulated ExUnit timeout attributes" do
    assert Timeout.resolve(nil, [timeout: 120_000], 60_000) == 120_000
    assert Timeout.resolve([[timeout: 90_000]], [timeout: 120_000], 60_000) == 90_000
    assert Timeout.resolve(%{timeout: :infinity}, nil, 60_000) == :infinity
  end

  test "falls back when neither the test nor module defines a timeout" do
    assert Timeout.resolve(nil, nil, 60_000) == 60_000
  end
end
