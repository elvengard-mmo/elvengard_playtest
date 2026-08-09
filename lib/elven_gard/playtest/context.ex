defmodule ElvenGard.Playtest.Context do
  @moduledoc """
  Represents an isolated Playwright browser context, normally one game player.
  """

  alias ElvenGard.Playtest.{Browser, Options, Page}
  alias ElvenGard.Playtest.Driver.Node

  @type t :: %__MODULE__{browser: Browser.t(), driver: pid(), id: String.t()}
  defstruct [:browser, :driver, :id]

  ## Public API

  @spec new(Browser.t(), Keyword.t()) :: {:ok, t()} | {:error, Node.error()}
  def new(%Browser{} = browser, opts \\ []) do
    params = opts |> Options.encode() |> Map.put("browser_id", browser.id)

    case Node.command(browser.driver, "context.new", params) do
      {:ok, %{"context_id" => id}} ->
        {:ok, %__MODULE__{browser: browser, driver: browser.driver, id: id}}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec new_page(t()) :: {:ok, Page.t()} | {:error, Node.error()}
  def new_page(%__MODULE__{} = context), do: Page.new(context)

  @spec close(t()) :: :ok | {:error, Node.error()}
  def close(%__MODULE__{} = context) do
    case Node.command(context.driver, "context.close", %{"context_id" => context.id}) do
      {:ok, true} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
