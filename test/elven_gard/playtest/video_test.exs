defmodule ElvenGard.Playtest.VideoTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Playtest.{Browser, CanvasVideo, Context, Page, Video}
  alias ElvenGard.Playtest.Driver.Playwright

  @tag :tmp_dir
  test "saves a recorded page under a deterministic path", %{tmp_dir: tmp_dir} do
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
               args: ["--no-sandbox"]
             )

    raw_directory = Path.join(tmp_dir, "raw")
    File.mkdir_p!(raw_directory)

    assert {:ok, context} =
             Context.new(browser,
               viewport: %{width: 640, height: 360},
               record_video_dir: raw_directory,
               record_video_size: %{width: 640, height: 360}
             )

    assert {:ok, page} = Page.new(context)
    assert {:ok, video} = Page.video(page)

    assert {:ok, %{status: nil}} =
             Page.visit(page, "data:text/html,<body style='background:%2300ff66'></body>")

    assert {:ok, true} = Page.wait_for(page, "document.body.clientWidth === 640")
    assert :ok = Page.close(page)

    destination = Path.join(tmp_dir, "spell-preview.webm")
    assert {:ok, ^destination} = Video.save_as(video, destination)
    assert File.stat!(destination).size > 0
    assert :ok = Video.delete(video)
    assert :ok = Context.close(context)
    assert :ok = Browser.close(browser)
  end

  @tag :tmp_dir
  test "records an exact canvas interval without recording the surrounding page", %{
    tmp_dir: tmp_dir
  } do
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
               args: ["--no-sandbox"]
             )

    assert {:ok, context} = Context.new(browser, viewport: %{width: 640, height: 360})
    assert {:ok, page} = Page.new(context)

    html = """
    <canvas id="game" width="640" height="360"></canvas>
    <script>
      const canvas = document.querySelector('#game')
      const context = canvas.getContext('2d')
      const draw = now => {
        context.fillStyle = '#20263a'
        context.fillRect(0, 0, canvas.width, canvas.height)
        context.fillStyle = '#ff8a34'
        context.fillRect((now / 2) % canvas.width, 140, 80, 80)
        requestAnimationFrame(draw)
      }
      requestAnimationFrame(draw)
    </script>
    """

    assert {:ok, %{status: nil}} =
             Page.visit(page, "data:text/html;base64," <> Base.encode64(html))

    assert {:ok, recording} =
             Page.start_canvas_video(page, "#game",
               fps: 30,
               video_bits_per_second: 1_000_000
             )

    assert {:ok, true} =
             Page.evaluate(
               page,
               "duration => new Promise(resolve => setTimeout(() => resolve(true), duration))",
               500
             )

    assert {:ok, video} = CanvasVideo.stop(recording)
    destination = Path.join(tmp_dir, "canvas-preview.webm")
    assert {:ok, ^destination} = Video.save_as(video, destination)
    assert <<0x1A, 0x45, 0xDF, 0xA3, _rest::binary>> = File.read!(destination)
    assert File.stat!(destination).size > 1_000
    assert :ok = Video.delete(video)

    assert {:ok, cancelled} = Page.start_canvas_video(page, "#game")
    assert :ok = CanvasVideo.cancel(cancelled)

    assert {:error, %{"message" => unknown_recording}} = CanvasVideo.stop(cancelled)
    assert unknown_recording =~ "Unknown canvas recording"

    assert {:error, %{"message" => missing_canvas}} =
             Page.start_canvas_video(page, "#missing")

    assert missing_canvas =~ "did not match a canvas"
    assert :ok = Context.close(context)
    assert :ok = Browser.close(browser)
  end

  defp playwright_path() do
    System.get_env("PLAYTEST_PLAYWRIGHT_PATH") ||
      ElvenGard.Playtest.Installation.playwright_path() ||
      "/usr/lib/node_modules/playwright"
  end
end
