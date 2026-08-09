defmodule ElvenGard.Playtest.ProbeTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Playtest.{Browser, Context, Page, Probe}
  alias ElvenGard.Playtest.Driver.Playwright

  @adapter_html """
  <!doctype html>
  <html>
    <body>
      <canvas id="game"></canvas>
      <script>
        window.__gameTest.register({
          state: () => ({player: {id: "one", x: 42}}),
          rendered: () => ({players: [{id: "one", x: 44}]}),
          metrics: () => ({meshes: 1})
        })
        console.warn("probe-ready")
      </script>
    </body>
  </html>
  """

  @tag :tmp_dir
  test "injects a read-only game probe and records diagnostic events", %{tmp_dir: tmp_dir} do
    driver = start_driver!()
    browser = launch_browser!(driver)
    context = new_context!(browser, "PlayerOne")

    assert :ok = Context.install_probe(context)
    assert :ok = Context.start_tracing(context)
    page = new_page!(context)
    assert {:ok, _response} = Page.visit(page, data_url(@adapter_html))
    assert :ok = Probe.wait_until_ready(page)

    assert {:ok, %{"player" => %{"id" => "one", "x" => 42}}} = Probe.call(page, "state")
    assert {:ok, %{"players" => [%{"x" => 44}]}} = Probe.call(page, "rendered")
    assert {:ok, %{"meshes" => 1}} = Probe.call(page, "metrics")
    assert {:ok, frame} = Probe.wait_for_frames(page, 2)
    assert is_integer(frame) and frame >= 2

    assert_receive {:playtest_event, ^driver, "page.console",
                    %{"level" => "warning", "text" => "probe-ready"}}

    assert {:ok, nil} =
             Page.evaluate(
               page,
               "() => { setTimeout(() => { throw new Error('render exploded') }, 0) }"
             )

    assert_receive {:playtest_event, ^driver, "page.error", error}
    assert error["message"] =~ "render exploded"

    trace = Path.join(tmp_dir, "trace.zip")
    assert {:ok, ^trace} = Context.stop_tracing(context, path: trace)
    assert File.stat!(trace).size > 0
  end

  test "isolates each simulated player in its own browser context" do
    driver = start_driver!()
    browser = launch_browser!(driver)
    first = browser |> new_context!("PlayerOne") |> new_page!()
    second = browser |> new_context!("PlayerTwo") |> new_page!()

    assert {:ok, "PlayerOne"} = Page.evaluate(first, "navigator.userAgent")
    assert {:ok, "PlayerTwo"} = Page.evaluate(second, "navigator.userAgent")
  end

  defp start_driver!() do
    start_supervised!(
      {Playwright,
       owner: self(),
       playwright_path:
         System.get_env("PLAYTEST_PLAYWRIGHT_PATH") || "/usr/lib/node_modules/playwright",
       node_path: System.find_executable("node")}
    )
  end

  defp launch_browser!(driver) do
    {:ok, browser} =
      Browser.launch(driver,
        browser: :chromium,
        executable_path:
          System.find_executable("google-chrome-stable") ||
            raise("A Chrome executable is required for Playtest integration tests"),
        headless: true,
        args: ["--no-sandbox"]
      )

    browser
  end

  defp new_context!(browser, user_agent) do
    {:ok, context} =
      Context.new(browser, viewport: %{width: 800, height: 600}, user_agent: user_agent)

    context
  end

  defp new_page!(context) do
    {:ok, page} = Page.new(context)
    page
  end

  defp data_url(html), do: "data:text/html;base64," <> Base.encode64(html)
end
