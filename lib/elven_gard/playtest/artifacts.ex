defmodule ElvenGard.Playtest.Artifacts do
  @moduledoc false

  require Logger

  alias ElvenGard.Playtest.{Context, EventCollector, Page, Suite}

  ## Public API

  @spec capture(Suite.t(), String.t()) :: [Path.t()]
  def capture(%Suite{} = suite, test_name) do
    directory = Path.join(suite.artifact_dir, sanitize(test_name))
    File.mkdir_p!(directory)

    player_artifacts =
      Enum.flat_map(suite.players, fn {name, player} ->
        screenshot = Path.join(directory, "#{name}.png")
        trace = Path.join(directory, "#{name}-trace.zip")

        [
          capture_operation("screenshot", name, screenshot, fn ->
            Page.screenshot(player.page, path: screenshot, full_page: true)
          end),
          capture_operation("trace", name, trace, fn ->
            Context.stop_tracing(player.context, path: trace)
          end)
        ]
      end)

    events_path = Path.join(directory, "events.json")
    events = EventCollector.events(suite.collector)
    File.write!(events_path, Jason.encode_to_iodata!(events, pretty: true))

    [events_path | Enum.reject(player_artifacts, &is_nil/1)]
  end

  ## Private functions

  defp capture_operation(operation, player, path, callback) do
    case callback.() do
      {:ok, _result} ->
        path

      {:error, error} ->
        Logger.error(
          "Playtest failed to capture #{operation} after a feature failure: " <>
            "error_code=artifact_capture_failed player=#{player} cause=#{inspect(error)}"
        )

        nil
    end
  end

  defp sanitize(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
