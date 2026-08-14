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
      <input id="name" />
      <script>
        window.events = []
        window.canvasPointerEvents = []
        window.inputEvents = []
        window.keyEvents = []
        window.pointerEvents = []
        window.readyForSpecial = false
        window.releaseMovement = false
        window.addEventListener("keydown", event => {
          window.events.push(["keydown", event.code])
          window.keyEvents.push(["keydown", event.code, performance.now()])
        })
        window.addEventListener("keyup", event => {
          window.events.push(["keyup", event.code])
          window.keyEvents.push(["keyup", event.code, performance.now()])
        })
        document.querySelector("#game").addEventListener("pointermove", event => {
          window.events.push(["pointermove", event.clientX, event.clientY])
        })
        document.querySelector("#game").addEventListener("pointerdown", () => {
          window.events.push(["pointerdown"])
          window.pointerEvents.push(["pointerdown", performance.now()])
          window.canvasPointerEvents.push(["pointerdown", performance.now()])
        })
        document.querySelector("#game").addEventListener("pointerup", () => {
          window.canvasPointerEvents.push(["pointerup", performance.now()])
        })
        window.addEventListener("pointerup", () => {
          window.events.push(["pointerup"])
          window.pointerEvents.push(["pointerup", performance.now()])
        })
        document.querySelector("#join").addEventListener("click", () => window.events.push(["click"]))
        document.querySelector("#join").addEventListener("pointerdown", () => {
          window.pointerEvents.push(["button-down", performance.now()])
        })
        document.querySelector("#join").addEventListener("pointerup", () => {
          window.pointerEvents.push(["button-up", performance.now()])
        })
        document.querySelector("#name").addEventListener("input", event => {
          window.inputEvents.push([event.target.value, performance.now()])
        })
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

    assert {:ok, page_click_started_at} = Page.evaluate(page, "performance.now()")
    assert {:ok, true} = Page.click(page, "#join")
    assert {:ok, page_click_finished_at} = Page.evaluate(page, "performance.now()")
    assert {:ok, true} = Page.fill(page, "#name", "Alice")
    assert {:ok, "Alice"} = Page.evaluate(page, "document.querySelector('#name').value")
    assert {:ok, true} = Page.paste(page, "#name", "opaque-invitation-token")

    assert {:ok, "opaque-invitation-token"} =
             Page.evaluate(page, "document.querySelector('#name').value")

    assert {:ok, true} = Page.fill(page, "#name", "Alice")
    assert {:ok, true} = Page.click(page, "#join")
    assert {:ok, key_press_started_at} = Page.evaluate(page, "performance.now()")
    assert {:ok, true} = Page.key_press(page, "KeyR")
    assert {:ok, key_press_finished_at} = Page.evaluate(page, "performance.now()")
    assert {:ok, key_hold_started_at} = Page.evaluate(page, "performance.now()")
    assert {:ok, true} = Page.key_hold_for(page, "KeyW", 40)
    assert {:ok, key_hold_finished_at} = Page.evaluate(page, "performance.now()")
    assert {:ok, true} = Page.key_down(page, "KeyD")
    assert {:ok, initial_events} = Page.evaluate(page, "window.events")
    assert ["click"] in initial_events
    assert ["keydown", "KeyD"] in initial_events

    assert {:ok, true} = Page.key_up(page, "KeyD")
    assert {:ok, pointer_move_started_at} = Page.evaluate(page, "performance.now()")
    assert {:ok, true} = Page.mouse_move(page, 120, 80)
    assert {:ok, pointer_move_finished_at} = Page.evaluate(page, "performance.now()")
    assert {:ok, mouse_click_started_at} = Page.evaluate(page, "performance.now()")
    assert {:ok, true} = Page.mouse_click(page)
    assert {:ok, mouse_click_finished_at} = Page.evaluate(page, "performance.now()")

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
    assert {:ok, canvas_pointer_events} = Page.evaluate(page, "window.canvasPointerEvents")
    assert ["keyup", "KeyD"] in events
    assert ["keydown", "KeyR"] in events
    assert ["keyup", "KeyR"] in events
    assert ["keydown", "KeyW"] in events
    assert ["keyup", "KeyW"] in events
    assert ["keydown", "KeyA"] in events
    assert ["keyup", "KeyA"] in events
    assert ["keydown", "KeyS"] in events
    assert ["keyup", "KeyS"] in events
    assert ["pointerdown"] in events
    assert ["pointerup"] in events
    assert List.last(events) == ["pointerup"]
    assert Enum.any?(events, &match?(["pointermove", 120, 80], &1))
    assert pointer_move_finished_at - pointer_move_started_at >= 35
    assert page_click_finished_at - page_click_started_at >= 105
    assert key_press_finished_at - key_press_started_at >= 105
    assert key_hold_finished_at - key_hold_started_at >= 75
    assert mouse_click_finished_at - mouse_click_started_at >= 105

    [["button-down", clicked_at], ["button-up", click_released_at] | _rest] = pointer_events
    assert click_released_at - clicked_at >= 70

    [["pointerdown", clicked_at], ["pointerup", click_released_at] | _rest] =
      canvas_pointer_events

    assert click_released_at - clicked_at < 25

    [["pointerdown", held_at], ["pointerup", released_at]] = Enum.take(pointer_events, -2)
    assert released_at - held_at >= 35

    assert {:ok, key_events} = Page.evaluate(page, "window.keyEvents")

    [["keydown", "KeyR", pressed_at], ["keyup", "KeyR", released_at] | _rest] =
      Enum.filter(key_events, &(Enum.at(&1, 1) == "KeyR"))

    assert released_at - pressed_at >= 70

    [["keydown", "KeyW", pressed_at], ["keyup", "KeyW", released_at]] =
      Enum.filter(key_events, &(Enum.at(&1, 1) == "KeyW"))

    assert released_at - pressed_at >= 35

    assert {:ok, input_events} = Page.evaluate(page, "window.inputEvents")
    [["A", typed_at] | _rest] = input_events
    ["Alice", completed_at] = List.last(input_events)
    assert completed_at - typed_at >= 100

    pointer_moves = Enum.filter(events, &match?(["pointermove", _x, _y], &1))
    assert length(pointer_moves) >= 6

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
