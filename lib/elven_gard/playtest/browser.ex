defmodule ElvenGard.Playtest.Browser do
  @moduledoc """
  Owns one Playwright browser process shared by isolated test contexts.
  """

  alias ElvenGard.Playtest.{Concurrency, Context, Options}
  alias ElvenGard.Playtest.Driver.Node

  @type t :: %__MODULE__{
          driver: pid(),
          id: String.t(),
          lease: Concurrency.lease(),
          name: atom()
        }
  defstruct [:driver, :id, :lease, :name]

  ## Public API

  @spec launch(pid(), Keyword.t()) :: {:ok, t()} | {:error, Node.error()}
  def launch(driver, opts \\ []) do
    {limit, opts} = Keyword.pop(opts, :max_concurrency, Concurrency.default_limit())
    {weight, opts} = Keyword.pop(opts, :concurrency_weight, 1)
    browser_name = Keyword.get(opts, :browser, :chromium)
    params = opts |> Keyword.put(:browser, browser_name) |> Options.encode()
    :ok = Concurrency.ensure_started()
    {:ok, lease} = Concurrency.checkout(Concurrency, driver, limit, weight)

    case Node.command(driver, "browser.launch", params) do
      {:ok, %{"browser_id" => id}} ->
        {:ok, %__MODULE__{driver: driver, id: id, lease: lease, name: browser_name}}

      {:error, error} ->
        :ok = Concurrency.checkin(Concurrency, lease)
        {:error, error}
    end
  end

  @spec new_context(t(), Keyword.t()) :: {:ok, Context.t()} | {:error, Node.error()}
  def new_context(%__MODULE__{} = browser, opts \\ []) do
    Context.new(browser, opts)
  end

  @spec close(t()) :: :ok | {:error, Node.error()}
  def close(%__MODULE__{} = browser) do
    try do
      case Node.command(browser.driver, "browser.close", %{"browser_id" => browser.id}) do
        {:ok, true} -> :ok
        {:error, error} -> {:error, error}
      end
    after
      :ok = Concurrency.checkin(Concurrency, browser.lease)
    end
  end
end
