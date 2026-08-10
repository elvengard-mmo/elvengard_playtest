defmodule ElvenGard.Playtest.Driver.Playwright do
  @moduledoc """
  Starts the bundled Node sidecar backed by Playwright's public JavaScript API.
  """

  alias ElvenGard.Playtest.{Driver.Node, Installation}

  @type option ::
          {:driver_path, Path.t()}
          | {:node_path, Path.t() | nil}
          | {:owner, pid()}
          | {:playwright_path, Path.t() | nil}

  ## Public API

  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary,
      shutdown: 10_000,
      type: :worker
    }
  end

  @spec start_link([option()]) :: GenServer.on_start()
  def start_link(opts \\ []) do
    driver_path =
      Keyword.get_lazy(opts, :driver_path, fn ->
        Application.app_dir(:elvengard_playtest, "priv/node/driver.mjs")
      end)

    env =
      case Keyword.get(opts, :playwright_path) || System.get_env("PLAYTEST_PLAYWRIGHT_PATH") ||
             Installation.playwright_path() do
        nil -> %{}
        path -> %{"PLAYTEST_PLAYWRIGHT_PATH" => Path.expand(path)}
      end

    node_opts =
      [
        driver_path: driver_path,
        env: env,
        owner: Keyword.get(opts, :owner, self())
      ]
      |> maybe_put(:node_path, Keyword.get(opts, :node_path))

    Node.start_link(node_opts)
  end

  @spec stop(pid(), timeout()) :: :ok
  def stop(driver, timeout \\ 5_000) when is_pid(driver) do
    GenServer.stop(driver, :normal, timeout)
  end

  ## Private functions

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
