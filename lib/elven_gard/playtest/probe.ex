defmodule ElvenGard.Playtest.Probe do
  @moduledoc """
  Reads semantic game state through an adapter registered in `window.__gameTest`.

  The injected probe never mutates game state. Browser inputs still travel through
  Playwright so the application receives trusted keyboard and pointer events.
  """

  alias ElvenGard.Playtest.Page
  alias ElvenGard.Playtest.Driver.Node

  @ready_timeout 10_000

  ## Public API

  @spec source() :: String.t()
  def source() do
    :elvengard_playtest
    |> Application.app_dir("priv/probe/playtest_probe.js")
    |> File.read!()
  end

  @spec wait_until_ready(Page.t(), Keyword.t()) :: :ok | {:error, Node.error()}
  def wait_until_ready(%Page{} = page, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @ready_timeout)

    case Page.wait_for(page, "window.__gameTest?.ready() === true", timeout: timeout) do
      {:ok, true} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @spec call(Page.t(), String.t(), [Jason.Encoder.value()]) ::
          {:ok, Jason.Encoder.value()} | {:error, Node.error()}
  def call(%Page{} = page, method, arguments \\ [])
      when is_binary(method) and is_list(arguments) do
    Page.evaluate(
      page,
      "async ({method, arguments}) => window.__gameTest.call(method, ...arguments)",
      %{"method" => method, "arguments" => arguments}
    )
  end

  @spec wait_for_frames(Page.t(), pos_integer()) ::
          {:ok, non_neg_integer()} | {:error, Node.error()}
  def wait_for_frames(%Page{} = page, count) when is_integer(count) and count > 0 do
    Page.evaluate(page, "count => window.__gameTest.waitForFrames(count)", count)
  end
end
