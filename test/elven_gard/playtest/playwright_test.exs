defmodule ElvenGard.Playtest.PlaywrightTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Playtest.{Browser, Context, Page}
  alias ElvenGard.Playtest.Driver.Playwright

  @html """
  <!doctype html>
  <html>
    <body>
      <canvas id="game" width="320" height="180"></canvas>
      <button id="join">Join</button>
      <script>
        window.events = []
        window.addEventListener("keydown", event => window.events.push(["keydown", event.code]))
        window.addEventListener("keyup", event => window.events.push(["keyup", event.code]))
        document.querySelector("#game").addEventListener("pointermove", event => {
          window.events.push(["pointermove", event.clientX, event.clientY])
        })
        document.querySelector("#join").addEventListener("click", () => window.events.push(["click"]))
      </script>
    </body>
  </html>
  """

  @tag :tmp_dir
  test "drives trusted game input and captures browser artifacts", %{tmp_dir: tmp_dir} do
    driver =
      start_supervised!(
        {Playwright,
         owner: self(),
         playwright_path: playwright_path(),
         node_path: System.find_executable("node")}
      )

    assert {:ok, browser} =
             Browser.launch(driver,
               browser: :chromium,
               executable_path: System.get_env("PLAYTEST_BROWSER_PATH"),
               headless: true,
               args: [
                 "--no-sandbox",
                 "--use-angle=swiftshader",
                 "--enable-unsafe-swiftshader",
                 "--ignore-gpu-blocklist"
               ]
             )

    assert {:ok, context} = Context.new(browser, viewport: %{width: 800, height: 600})
    assert {:ok, page} = Page.new(context)
    assert {:ok, %{status: nil}} = Page.visit(page, data_url(@html))
    assert {:ok, true} = Page.visible?(page, "#join")
    assert {:ok, "Join"} = Page.text(page, "#join")
    assert {:ok, "join"} = Page.attribute(page, "#join", "id")
    assert {:ok, 1} = Page.count(page, "canvas")
    assert {:ok, true} = Page.wait_for_selector(page, "#game")

    assert {:ok, true} = Page.click(page, "#join")
    assert {:ok, true} = Page.key_down(page, "KeyD")
    assert {:ok, [["click"], ["keydown", "KeyD"]]} = Page.evaluate(page, "window.events")

    assert {:ok, true} = Page.key_up(page, "KeyD")
    assert {:ok, true} = Page.mouse_move(page, 120, 80)

    assert {:ok, events} = Page.evaluate(page, "window.events")
    assert ["keyup", "KeyD"] in events
    assert Enum.any?(events, &match?(["pointermove", 120, 80], &1))

    screenshot = Path.join(tmp_dir, "game.png")
    assert {:ok, ^screenshot} = Page.screenshot(page, path: screenshot)
    assert File.stat!(screenshot).size > 0

    assert :ok = Browser.close(browser)
  end

  defp data_url(html) do
    "data:text/html;base64," <> Base.encode64(html)
  end

  defp playwright_path() do
    System.get_env("PLAYTEST_PLAYWRIGHT_PATH") ||
      ElvenGard.Playtest.Installation.playwright_path() ||
      "/usr/lib/node_modules/playwright"
  end
end
