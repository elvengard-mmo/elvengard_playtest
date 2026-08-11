defmodule ElvenGard.Playtest.VideoTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Playtest.{Browser, Context, Page, Video}
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

  defp playwright_path() do
    System.get_env("PLAYTEST_PLAYWRIGHT_PATH") ||
      ElvenGard.Playtest.Installation.playwright_path() ||
      "/usr/lib/node_modules/playwright"
  end
end
