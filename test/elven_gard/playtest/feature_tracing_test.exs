defmodule ElvenGard.Playtest.FeatureTracingTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Playtest.{Context, Feature, Page}

  test "feature tracing forwards canvas-friendly screenshot settings" do
    trace_path =
      Path.join(
        System.tmp_dir!(),
        "elvengard-playtest-trace-#{System.unique_integer([:positive])}.zip"
      )

    {:ok, %{players: players, playtest: suite}} =
      Feature.setup(%{},
        players: [:player],
        base_url: "data:text/html,<button id='trace-action'>Trace</button>",
        tracing: [screenshots: false],
        playwright_path: playwright_path(),
        executable_path: System.get_env("PLAYTEST_BROWSER_PATH")
      )

    on_exit(fn -> File.rm(trace_path) end)

    try do
      assert {:ok, true} = Page.click(players.player.page, "#trace-action")

      assert {:ok, ^trace_path} =
               Context.stop_tracing(players.player.context, path: trace_path)

      refute trace_path
             |> trace_entries!()
             |> Enum.any?(&String.ends_with?(&1, ".jpeg"))
    after
      Feature.close(suite)
    end
  end

  ## Private functions

  defp playwright_path() do
    System.get_env("PLAYTEST_PLAYWRIGHT_PATH") ||
      ElvenGard.Playtest.Installation.playwright_path() ||
      "/usr/lib/node_modules/playwright"
  end

  defp trace_entries!(path) do
    {:ok, entries} = :zip.list_dir(String.to_charlist(path))

    Enum.flat_map(entries, fn
      {:zip_file, name, _info, _comment, _offset, _compression} ->
        [List.to_string(name)]

      _directory ->
        []
    end)
  end
end
