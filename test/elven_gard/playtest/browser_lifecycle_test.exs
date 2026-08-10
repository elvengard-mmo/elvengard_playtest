defmodule ElvenGard.Playtest.BrowserLifecycleTest do
  use ExUnit.Case, async: true

  alias ElvenGard.Playtest.Browser
  alias ElvenGard.Playtest.Driver.Playwright

  test "a stalled graceful close force-kills the owned browser process" do
    driver = start_driver!()

    assert {:ok, browser} = Browser.launch(driver, browser: :chromium)
    assert :ok = Browser.close(browser, timeout: 500)

    assert_receive {
      :playtest_event,
      ^driver,
      "browser.close_forced",
      %{"browser_pid" => browser_pid, "cause" => %{"code" => "timeout"}}
    }

    refute os_process_running?(browser_pid)
  end

  test "stopping a driver kills every browser process it still owns" do
    driver = start_driver!()

    assert {:ok, %{"browser_pid" => browser_pid}} =
             ElvenGard.Playtest.Driver.Node.command(driver, "browser.launch", %{
               "browser" => "chromium"
             })

    assert os_process_running?(browser_pid)
    assert :ok = Playwright.stop(driver)
    refute os_process_running?(browser_pid)
  end

  ## Private functions

  defp start_driver!() do
    start_supervised!(
      {Playwright,
       driver_path: driver_path(),
       node_path: System.find_executable("node"),
       owner: self(),
       playwright_path: fixture_path("fake_playwright.cjs")}
    )
  end

  defp driver_path() do
    Path.expand("../../../priv/node/driver.mjs", __DIR__)
  end

  defp fixture_path(name) do
    Path.expand("../../fixtures/#{name}", __DIR__)
  end

  defp os_process_running?(os_pid) do
    case File.read("/proc/#{os_pid}/stat") do
      {:ok, stat} -> not String.contains?(stat, ") Z ")
      {:error, :enoent} -> false
    end
  end
end
