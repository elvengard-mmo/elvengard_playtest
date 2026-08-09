# ElvenGard Playtest

ExUnit-native testing for real-time browser games, WebGL, canvas and multiplayer applications.

Playtest keeps orchestration and assertions in Elixir while a supervised Node sidecar uses the official Playwright JavaScript API. Each simulated player receives an isolated browser context and a page with a read-only game probe injected before application code runs.

## Capabilities

- real Chromium, Firefox and WebKit browsers;
- independent `key_down` / `key_up` and precise pointer input;
- isolated multi-player sessions in one feature;
- bounded asynchronous browser concurrency for stable CI runs;
- semantic canvas assertions through `window.__gameTest`;
- console errors, page crashes and WebSocket frame events;
- screenshots, Playwright traces and event logs on failure;
- pinned runtime installation outside the consuming project.

## Installation

Add the Git dependency while the library is under active development:

```elixir
{:elvengard_playtest,
 github: "elvengard-mmo/elvengard_playtest",
 branch: "main",
 only: :test,
 runtime: false}
```

Install the pinned Playwright runtime and Chromium once:

```shell
MIX_ENV=test mix playtest.install
```

On a fresh Linux CI runner, install Chromium's system dependencies too:

```shell
MIX_ENV=test mix playtest.install --with-deps
```

This writes only to the user cache. It does not add frontend manifests or `node_modules` to the Phoenix application.

## Game adapter

Playtest injects `window.__gameTest` before the application loads. Register a read-only adapter from the game client:

```javascript
window.__gameTest?.register({
  state: () => authoritativeState,
  rendered: () => renderedState,
  metrics: () => renderer.stats(),
})
```

Inputs are not exposed through the adapter. Tests send trusted input through Playwright.

## ExUnit feature

```elixir
defmodule MyGame.MovementFeature do
  use ElvenGard.Playtest.Feature,
    players: [:alice, :bob],
    base_url: "http://127.0.0.1:4002"

  alias ElvenGard.Playtest.{Page, Probe}

  feature "movement is predicted locally", %{players: players} do
    assert :ok = Probe.wait_until_ready(players.alice.page)
    assert {:ok, before} = Probe.call(players.alice.page, "state")

    assert {:ok, true} = Page.key_down(players.alice.page, "KeyD")
    assert {:ok, _frame} = Probe.wait_for_frames(players.alice.page, 10)
    assert {:ok, true} = Page.key_up(players.alice.page, "KeyD")

    assert {:ok, after_move} = Probe.call(players.alice.page, "rendered")
    assert after_move["player"]["x"] > before["player"]["x"]
  end
end
```

Feature failures write one screenshot and trace per player plus `events.json` under `tmp/playtest`.

Playtest runs at most two browser processes concurrently by default while the
rest wait without disabling ExUnit async execution. Override it per suite with
`max_concurrency: 2` or globally with
`config :elvengard_playtest, max_concurrency: 2`.

## Runtime overrides

- `PLAYTEST_CACHE_DIR`: change the installation cache.
- `PLAYTEST_PLAYWRIGHT_PATH`: use an existing Playwright package.
- `PLAYTEST_BROWSER_PATH`: use an existing browser executable.

## Development

```shell
mix deps.get
mix playtest.install
mix format --check-formatted
mix compile --warnings-as-errors
mix test
```
