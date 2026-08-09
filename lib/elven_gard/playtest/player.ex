defmodule ElvenGard.Playtest.Player do
  @moduledoc """
  One isolated browser context and page representing a simulated player.
  """

  alias ElvenGard.Playtest.{Context, Page}

  @type t :: %__MODULE__{name: atom(), context: Context.t(), page: Page.t()}
  defstruct [:name, :context, :page]
end
