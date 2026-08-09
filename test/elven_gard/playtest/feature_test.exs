defmodule ElvenGard.Playtest.FeatureTest do
  use ElvenGard.Playtest.Feature,
    async: true,
    players: [:alpha, :bravo],
    base_url:
      "data:text/html;base64," <>
        Base.encode64("""
        <!doctype html>
        <script>
          window.__gameTest.register({state: () => ({ready: true})})
          window.keys = []
          addEventListener("keydown", event => window.keys.push(event.code))
        </script>
        """),
    playwright_path:
      System.get_env("PLAYTEST_PLAYWRIGHT_PATH") || "/usr/lib/node_modules/playwright",
    executable_path: System.find_executable("google-chrome-stable")

  alias ElvenGard.Playtest.{Page, Probe}

  feature "starts one isolated probed page per simulated player", %{players: players} do
    assert Map.keys(players) |> Enum.sort() == [:alpha, :bravo]

    Enum.each(players, fn {name, player} ->
      assert player.name == name
      assert :ok = Probe.wait_until_ready(player.page)
      assert {:ok, %{"ready" => true}} = Probe.call(player.page, "state")
    end)

    assert {:ok, true} = Page.key_down(players.alpha.page, "KeyD")
    assert {:ok, ["KeyD"]} = Page.evaluate(players.alpha.page, "window.keys")
    assert {:ok, []} = Page.evaluate(players.bravo.page, "window.keys")
    assert {:ok, true} = Page.key_up(players.alpha.page, "KeyD")
  end
end
