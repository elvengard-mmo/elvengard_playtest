defmodule ElvenGard.Playtest.Browser do
  @moduledoc """
  Owns one Playwright browser process shared by isolated test contexts.
  """

  alias ElvenGard.Playtest.{Options, Context}
  alias ElvenGard.Playtest.Driver.Node

  @type t :: %__MODULE__{driver: pid(), id: String.t(), name: atom()}
  defstruct [:driver, :id, :name]

  ## Public API

  @spec launch(pid(), Keyword.t()) :: {:ok, t()} | {:error, Node.error()}
  def launch(driver, opts \\ []) do
    browser_name = Keyword.get(opts, :browser, :chromium)
    params = opts |> Keyword.put(:browser, browser_name) |> Options.encode()

    case Node.command(driver, "browser.launch", params) do
      {:ok, %{"browser_id" => id}} ->
        {:ok, %__MODULE__{driver: driver, id: id, name: browser_name}}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec new_context(t(), Keyword.t()) :: {:ok, Context.t()} | {:error, Node.error()}
  def new_context(%__MODULE__{} = browser, opts \\ []) do
    Context.new(browser, opts)
  end

  @spec close(t()) :: :ok | {:error, Node.error()}
  def close(%__MODULE__{} = browser) do
    case Node.command(browser.driver, "browser.close", %{"browser_id" => browser.id}) do
      {:ok, true} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
