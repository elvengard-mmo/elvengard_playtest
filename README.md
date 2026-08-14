# ElvenGard Playtest

ExUnit-native testing for real-time browser games, WebGL, canvas and multiplayer applications.

Playtest keeps orchestration and assertions in Elixir while a supervised Node sidecar uses the official Playwright JavaScript API. Each simulated player receives an isolated browser context and a page with a read-only game probe injected before application code runs.

## Capabilities

- real Chromium, Firefox and WebKit browsers;
- human-paced DOM clicks, typing, key presses, pointer movement and mouse clicks by default;
- independent `key_down` / `key_up`, timed or condition-bounded key and pointer holds for continuous game actions;
- isolated multi-player sessions in one feature;
- bounded asynchronous browser concurrency for stable CI runs;
- semantic canvas assertions through `window.__gameTest`;
- exact canvas-only video intervals independent from page setup and teardown;
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

## Human-paced inputs

High-level Page inputs use observable human timings by default so a real-time
game cannot miss a press between two render frames:

```elixir
{:ok, true} = Page.click(page, "#join")
{:ok, true} = Page.fill(page, "#player-name", "Alice")
{:ok, true} = Page.paste(page, "#invitation-code", invitation)
{:ok, true} = Page.key_press(page, "Space")
{:ok, true} = Page.mouse_click(page)
{:ok, true} = Page.key_hold_for(page, "KeyD", 250)
```

The defaults are centralized and can be configured without changing tests:

```elixir
config :elvengard_playtest, :human_input,
  click_delay: 80,
  key_press_delay: 80,
  minimum_hold_duration: 80,
  mouse_click_duration: 0,
  release_settle_delay: 40,
  pointer_move_delay: 40,
  pointer_move_steps: 6,
  typing_delay: 30
```

Each Page call also accepts the corresponding Playwright option (`:delay`,
`:duration`, `:minimum_duration_ms`, `:release_delay` or `:steps`) when a product
interaction needs a specific timing. A mouse click dispatches its physical down/up
atomically by default, then applies the human pacing delay after release. This keeps
a loaded realtime game from mistaking a click for a continuous hold without making
the test act faster than a person. Composite inputs then settle briefly so browser
event handlers and realtime transports can observe the released state before the
next action. Raw down/up primitives remain available for genuinely continuous
input; use the high-level helpers for clicks and presses.

`fill/4` models human typing one character at a time. Use `paste/4` for opaque
values a human would paste, such as invitation tokens, recovery codes or long
identifiers; it inserts the complete value atomically, dispatches the browser's
normal input event, then observes the configured human click delay.

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

## Exact canvas video

Use a canvas recording when a gameplay artifact must exclude menus, camera setup
and browser UI. The interval starts and stops explicitly, independently from the
page lifecycle:

```elixir
alias ElvenGard.Playtest.{CanvasVideo, Page, Video}

{:ok, recording} =
  Page.start_canvas_video(page, "#game-canvas-host canvas",
    fps: 60,
    video_bits_per_second: 8_000_000
  )

# Drive the real game through Page while the canvas is recorded.

{:ok, video} = CanvasVideo.stop(recording)
{:ok, "tmp/firebomb.webm"} = Video.save_as(video, "tmp/firebomb.webm")
:ok = Video.delete(video)
```

`CanvasVideo.cancel/1` stops and discards an interval when its surrounding
scenario fails.

Playwright trace screenshots are enabled by default. For multi-player canvas
games, continuous screenshots can be disabled while preserving DOM snapshots,
sources, network events and Playtest's final failure screenshot:

```elixir
use ElvenGard.Playtest.Feature,
  players: [:alice, :bob],
  tracing: [screenshots: false]
```

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
