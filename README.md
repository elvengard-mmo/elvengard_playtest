# ElvenGard Playtest

ExUnit-native testing for real-time browser games, WebGL, canvas and multiplayer applications.

Playtest keeps orchestration and assertions in Elixir while a supervised Node sidecar uses the official Playwright JavaScript API. Each simulated player receives an isolated browser context and a page with a read-only game probe injected before application code runs.

## Capabilities

- real Chromium, Firefox and WebKit browsers;
- independent `key_down` / `key_up`, condition-bounded key holds, synchronized key presses and timed or condition-bounded pointer holds;
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

    assert {:ok, true} =
             Page.key_hold_until(
               players.alice.page,
               "KeyD",
               "window.__gameTest.call('rendered').player.x > #{before["player"]["x"] + 20}",
               timeout: 5_000
             )

    assert {:ok, after_move} = Probe.call(players.alice.page, "rendered")
    assert after_move["player"]["x"] > before["player"]["x"]
  end
end
```

Feature failures write one screenshot and trace per player plus `events.json` under `tmp/playtest`.

Playtest runs up to four browser capacity slots at a time by default while the
rest wait without disabling ExUnit async execution. Override it per suite with
`max_concurrency: 8` or globally with
`config :elvengard_playtest, max_concurrency: 8`.

Multiplayer features consume one capacity slot per isolated player context, so
the limit tracks active game renderers rather than undercounting a multi-page
browser as a single unit.

Capacity belongs to the supervised driver rather than the ExUnit process. A
feature cleanup stops that ownership tree as one unit, and the lease is only
released when the driver terminates. This avoids waiting on an unbounded
Playwright browser-close handshake or overlapping the next browser launch with
an unfinished driver teardown. Cleanup first closes the browser gracefully
within a fixed deadline, then force-kills the owned browser process through
Playwright before stopping the sidecar if that deadline is exceeded.

Feature execution has its own timeout that starts after browser and player
setup. Configure it on the feature case when a real-time scenario needs a
larger product-action budget:

```elixir
use ElvenGard.Playtest.Feature,
  players: [:alice, :bob],
  feature_timeout: 120_000
```

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
