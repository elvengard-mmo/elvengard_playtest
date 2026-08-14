defmodule ElvenGard.Playtest.HumanInput do
  @moduledoc """
  Central defaults for trusted inputs that must remain observable by browser games.

  Every delay can be overridden per Page call or globally through the
  `:human_input` application configuration.
  """

  @defaults [
    click_delay: 80,
    key_press_delay: 80,
    minimum_hold_duration: 80,
    mouse_click_duration: 0,
    release_settle_delay: 40,
    pointer_move_delay: 40,
    pointer_move_steps: 6,
    typing_delay: 30
  ]

  @type option_name ::
          :click_delay
          | :key_press_delay
          | :minimum_hold_duration
          | :mouse_click_duration
          | :release_settle_delay
          | :pointer_move_delay
          | :pointer_move_steps
          | :typing_delay

  ## Public API

  @spec default(option_name()) :: non_neg_integer()
  def default(name) do
    :elvengard_playtest
    |> Application.get_env(:human_input, [])
    |> Keyword.get(name, Keyword.fetch!(@defaults, name))
  end

  @spec put_default(Keyword.t(), atom(), option_name()) :: Keyword.t()
  def put_default(opts, option, input_name) do
    Keyword.put_new(opts, option, default(input_name))
  end
end
