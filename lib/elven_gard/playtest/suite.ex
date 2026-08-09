defmodule ElvenGard.Playtest.Suite do
  @moduledoc false

  alias ElvenGard.Playtest.{Browser, Player}

  @type t :: %__MODULE__{
          artifact_dir: Path.t(),
          browser: Browser.t(),
          collector: pid(),
          driver: pid(),
          players: %{required(atom()) => Player.t()}
        }

  defstruct [:artifact_dir, :browser, :collector, :driver, players: %{}]
end
