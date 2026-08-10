defmodule ElvenGard.Playtest.Feature do
  @moduledoc """
  ExUnit integration that starts isolated real-browser players for each feature.

  Feature failures automatically preserve a screenshot, a Playwright trace and
  the captured browser event stream for every simulated player.
  """

  require Logger

  alias ElvenGard.Playtest.{Browser, Concurrency, Context, EventCollector, Player, Suite}
  alias ElvenGard.Playtest.Driver.Playwright

  defmacro __using__(opts) do
    async = Keyword.get(opts, :async, false)

    quote do
      use ExUnit.Case, async: unquote(async)

      import ElvenGard.Playtest.Feature, only: [feature: 3]

      setup context do
        ElvenGard.Playtest.Feature.setup(context, unquote(opts))
      end
    end
  end

  defmacro feature(message, context_pattern, do: block) do
    quote do
      test unquote(message), unquote(context_pattern) = playtest_context do
        try do
          result = unquote(block)
          ElvenGard.Playtest.Feature.assert_clean!(playtest_context.playtest)
          ElvenGard.Playtest.Feature.finish(playtest_context.playtest)
          result
        rescue
          exception ->
            stacktrace = __STACKTRACE__

            ElvenGard.Playtest.Artifacts.capture(
              playtest_context.playtest,
              to_string(playtest_context.test)
            )

            reraise exception, stacktrace
        catch
          kind, reason ->
            stacktrace = __STACKTRACE__

            ElvenGard.Playtest.Artifacts.capture(
              playtest_context.playtest,
              to_string(playtest_context.test)
            )

            :erlang.raise(kind, reason, stacktrace)
        after
          ElvenGard.Playtest.Feature.close(playtest_context.playtest)
        end
      end
    end
  end

  ## Public API

  @spec setup(map(), Keyword.t()) :: {:ok, map()}
  def setup(_test_context, opts) do
    collector = ExUnit.Callbacks.start_supervised!({EventCollector, owner: self()})

    driver =
      ExUnit.Callbacks.start_supervised!(
        {Playwright,
         owner: collector,
         node_path: Keyword.get(opts, :node_path),
         playwright_path: Keyword.get(opts, :playwright_path)}
      )

    browser = launch_browser!(driver, opts)
    players = start_players!(browser, opts)

    first_player = players |> Map.values() |> List.first()

    suite = %Suite{
      artifact_dir: Keyword.get(opts, :artifact_dir, "tmp/playtest"),
      browser: browser,
      collector: collector,
      driver: driver,
      players: players
    }

    {:ok,
     %{
       page: first_player.page,
       player: first_player,
       players: players,
       playtest: suite
     }}
  end

  @spec assert_clean!(Suite.t()) :: :ok
  def assert_clean!(%Suite{} = suite) do
    failures =
      suite.collector
      |> EventCollector.events()
      |> Enum.filter(&failure_event?/1)

    case failures do
      [] -> :ok
      _failures -> raise ExUnit.AssertionError, message: browser_failure_message(failures)
    end
  end

  @spec finish(Suite.t()) :: :ok
  def finish(%Suite{} = suite) do
    Enum.each(suite.players, fn {_name, player} ->
      case Context.stop_tracing(player.context) do
        {:ok, nil} -> :ok
        {:error, error} -> raise "Failed to stop Playtest tracing: #{inspect(error)}"
      end
    end)

    :ok
  end

  @spec close(Suite.t()) :: :ok
  def close(%Suite{} = suite) do
    close_driver(suite.driver)
  end

  ## Private functions

  defp launch_browser!(driver, opts) do
    launch_opts = [
      browser: Keyword.get(opts, :browser, :chromium),
      executable_path: Keyword.get(opts, :executable_path) || default_browser_path(),
      headless: Keyword.get(opts, :headless, true),
      max_concurrency: Keyword.get(opts, :max_concurrency, Concurrency.default_limit()),
      concurrency_weight: opts |> Keyword.get(:players, [:player]) |> length(),
      args:
        Keyword.get(opts, :browser_args, [
          "--no-sandbox",
          "--use-angle=swiftshader",
          "--enable-unsafe-swiftshader",
          "--ignore-gpu-blocklist",
          "--disable-background-timer-throttling",
          "--disable-backgrounding-occluded-windows",
          "--disable-renderer-backgrounding"
        ])
    ]

    case Browser.launch(driver, launch_opts) do
      {:ok, browser} -> browser
      {:error, error} -> raise "Failed to launch Playtest browser: #{inspect(error)}"
    end
  end

  defp start_players!(browser, opts) do
    names = Keyword.get(opts, :players, [:player])
    base_url = Keyword.get(opts, :base_url)
    context_opts = Keyword.get(opts, :context, viewport: %{width: 1_280, height: 800})

    Map.new(names, fn name ->
      {:ok, context} = Context.new(browser, context_opts)
      :ok = Context.install_probe(context)
      :ok = Context.start_tracing(context)
      {:ok, page} = Context.new_page(context)

      if base_url do
        {:ok, _response} = ElvenGard.Playtest.Page.visit(page, base_url)
      end

      {name, %Player{name: name, context: context, page: page}}
    end)
  end

  defp default_browser_path() do
    System.get_env("PLAYTEST_BROWSER_PATH")
  end

  defp close_driver(driver) do
    Playwright.stop(driver)
  catch
    :exit, {:noproc, _call} -> :ok
    :exit, reason -> log_close_error("driver", driver, reason)
  end

  defp log_close_error(resource, name, reason) do
    Logger.error(
      "Playtest failed to close #{resource} during feature cleanup: " <>
        "error_code=feature_cleanup_failed resource_name=#{inspect(name)} cause=#{inspect(reason)}"
    )
  end

  defp failure_event?(%{name: "page.error"}), do: true
  defp failure_event?(%{name: "page.crash"}), do: true
  defp failure_event?(%{name: "driver.protocol_error"}), do: true
  defp failure_event?(%{name: "page.console", params: %{"level" => "error"}}), do: true
  defp failure_event?(_event), do: false

  defp browser_failure_message(failures) do
    details = Enum.map_join(failures, "\n", &"  * #{&1.name}: #{inspect(&1.params)}")
    "Browser errors were captured during the Playtest feature:\n#{details}"
  end
end
