defmodule ElvenGard.Playtest.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [ElvenGard.Playtest.Concurrency]
    Supervisor.start_link(children, strategy: :one_for_one, name: ElvenGard.Playtest.Supervisor)
  end
end
