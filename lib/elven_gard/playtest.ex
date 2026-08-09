defmodule ElvenGard.Playtest do
  @moduledoc """
  ExUnit-native testing for real-time browser games and canvas applications.

  Playtest keeps test orchestration in Elixir while delegating browser control to
  the official Playwright JavaScript library through a supervised Node sidecar.
  """

  alias ElvenGard.Playtest.Driver.Playwright

  ## Public API

  @spec start_driver(Keyword.t()) :: GenServer.on_start()
  def start_driver(opts \\ []) do
    Playwright.start_link(opts)
  end
end
