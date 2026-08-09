defmodule ElvenGard.PlaytestTest do
  use ExUnit.Case
  doctest ElvenGard.Playtest

  test "greets the world" do
    assert ElvenGard.Playtest.hello() == :world
  end
end
