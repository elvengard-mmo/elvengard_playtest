defmodule ElvenGard.Playtest.Installation do
  @moduledoc false

  @app_name "elvengard_playtest"

  ## Public API

  @spec cache_dir() :: Path.t()
  def cache_dir() do
    System.get_env("PLAYTEST_CACHE_DIR") ||
      @app_name
      |> String.to_charlist()
      |> then(&:filename.basedir(:user_cache, &1))
      |> List.to_string()
  end

  @spec playwright_path() :: Path.t() | nil
  def playwright_path() do
    path = Path.join([cache_dir(), "node_modules", "playwright"])
    if File.dir?(path), do: path
  end

  @spec manifest_paths() :: %{lock: Path.t(), package: Path.t()}
  def manifest_paths() do
    node_dir = Application.app_dir(:elvengard_playtest, "priv/node")

    %{
      lock: Path.join(node_dir, "package-lock.json"),
      package: Path.join(node_dir, "package.json")
    }
  end
end
