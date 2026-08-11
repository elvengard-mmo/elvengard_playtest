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
        window.pointerEvents = []
        window.readyForSpecial = false
        window.releaseMovement = false
        window.addEventListener("keydown", event => window.events.push(["keydown", event.code]))
        window.addEventListener("keyup", event => window.events.push(["keyup", event.code]))
        document.querySelector("#game").addEventListener("pointermove", event => {
          window.events.push(["pointermove", event.clientX, event.clientY])
        })
        document.querySelector("#game").addEventListener("pointerdown", () => {
          window.events.push(["pointerdown"])
          window.pointerEvents.push(["pointerdown", performance.now()])
        })
        window.addEventListener("pointerup", () => {
          window.events.push(["pointerup"])
          window.pointerEvents.push(["pointerup", performance.now()])
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
    assert {:ok, nil} = Page.video(page)
    assert {:ok, %{status: nil}} = Page.visit(page, data_url(@html))
    assert {:ok, true} = Page.visible?(page, "#join")
    assert {:ok, "Join"} = Page.text(page, "#join")
    assert {:ok, "join"} = Page.attribute(page, "#join", "id")
    assert {:ok, 1} = Page.count(page, "canvas")
    assert {:ok, true} = Page.wait_for_selector(page, "#game")

    assert {:ok, true} = Page.click(page, "#join")
    assert {:ok, true} = Page.key_down(page, "KeyD")
    assert {:ok, initial_events} = Page.evaluate(page, "window.events")
    assert ["click"] in initial_events
    assert ["keydown", "KeyD"] in initial_events

    assert {:ok, true} = Page.key_up(page, "KeyD")
    assert {:ok, true} = Page.mouse_move(page, 120, 80)

    pending_press =
      Task.async(fn ->
        Page.key_press_when(page, "KeyR", "window.readyForSpecial === true",
          timeout: 1_000,
          polling: 10
        )
      end)

    _state = :sys.get_state(driver)
    assert {:ok, true} = Page.evaluate(page, "window.readyForSpecial = true")
    assert {:ok, true} = Task.await(pending_press)

    pending_hold =
      Task.async(fn ->
        Page.key_hold_until(page, "KeyA", "window.releaseMovement === true",
          timeout: 1_000,
          polling: 10
        )
      end)

    _state = :sys.get_state(driver)
    assert {:ok, true} = Page.evaluate(page, "window.releaseMovement = true")
    assert {:ok, true} = Task.await(pending_hold)

    assert {:error, %{"code" => "TimeoutError"}} =
             Page.key_hold_until(page, "KeyS", "false", timeout: 20, polling: 10)

    assert {:ok, true} =
             Page.mouse_hold_until(
               page,
               "window.events.some(event => event[0] === 'pointerdown')",
               timeout: 1_000,
               polling: 10
             )

    assert {:error, %{"code" => "TimeoutError"}} =
             Page.mouse_hold_until(page, "false", timeout: 20, polling: 10)

    assert {:ok, true} = Page.mouse_hold_for(page, 40)

    assert {:ok, events} = Page.evaluate(page, "window.events")
    assert {:ok, pointer_events} = Page.evaluate(page, "window.pointerEvents")
    assert ["keyup", "KeyD"] in events
    assert ["keydown", "KeyR"] in events
    assert ["keyup", "KeyR"] in events
    assert ["keydown", "KeyA"] in events
    assert ["keyup", "KeyA"] in events
    assert ["keydown", "KeyS"] in events
    assert ["keyup", "KeyS"] in events
    assert ["pointerdown"] in events
    assert ["pointerup"] in events
    assert List.last(events) == ["pointerup"]
    assert Enum.any?(events, &match?(["pointermove", 120, 80], &1))

    [["pointerdown", held_at], ["pointerup", released_at]] = Enum.take(pointer_events, -2)
    assert released_at - held_at >= 35

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
