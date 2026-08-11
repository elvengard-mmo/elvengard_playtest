defmodule ElvenGard.Playtest.Page do
  @moduledoc """
  Drives one page with precise browser-level inputs suitable for real-time games.
  """

  alias ElvenGard.Playtest.{Context, Options, Video}
  alias ElvenGard.Playtest.Driver.Node

  @type t :: %__MODULE__{context: Context.t(), driver: pid(), id: String.t()}
  defstruct [:context, :driver, :id]

  ## Public API

  @spec new(Context.t()) :: {:ok, t()} | {:error, Node.error()}
  def new(%Context{} = context) do
    case Node.command(context.driver, "page.new", %{"context_id" => context.id}) do
      {:ok, %{"page_id" => id}} ->
        {:ok, %__MODULE__{context: context, driver: context.driver, id: id}}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec visit(t(), String.t(), Keyword.t()) ::
          {:ok, %{status: non_neg_integer() | nil, url: String.t()}} | {:error, Node.error()}
  def visit(%__MODULE__{} = page, url, opts \\ []) when is_binary(url) do
    params =
      opts
      |> Options.encode()
      |> Map.merge(%{"page_id" => page.id, "url" => url})

    case Node.command(page.driver, "page.goto", params) do
      {:ok, %{"status" => status, "url" => final_url}} ->
        {:ok, %{status: status, url: final_url}}

      {:error, error} ->
        {:error, error}
    end
  end

  @spec click(t(), String.t(), Keyword.t()) :: {:ok, true} | {:error, Node.error()}
  def click(%__MODULE__{} = page, selector, opts \\ []) when is_binary(selector) do
    command(page, "page.click", opts, %{"selector" => selector})
  end

  @spec fill(t(), String.t(), String.t()) :: {:ok, true} | {:error, Node.error()}
  def fill(%__MODULE__{} = page, selector, value)
      when is_binary(selector) and is_binary(value) do
    command(page, "page.fill", [], %{"selector" => selector, "value" => value})
  end

  @spec visible?(t(), String.t()) :: {:ok, boolean()} | {:error, Node.error()}
  def visible?(%__MODULE__{} = page, selector) when is_binary(selector) do
    command(page, "locator.visible", [], %{"selector" => selector})
  end

  @spec text(t(), String.t()) :: {:ok, String.t() | nil} | {:error, Node.error()}
  def text(%__MODULE__{} = page, selector) when is_binary(selector) do
    command(page, "locator.text", [], %{"selector" => selector})
  end

  @spec attribute(t(), String.t(), String.t()) ::
          {:ok, String.t() | nil} | {:error, Node.error()}
  def attribute(%__MODULE__{} = page, selector, name)
      when is_binary(selector) and is_binary(name) do
    command(page, "locator.attribute", [], %{"selector" => selector, "name" => name})
  end

  @spec count(t(), String.t()) :: {:ok, non_neg_integer()} | {:error, Node.error()}
  def count(%__MODULE__{} = page, selector) when is_binary(selector) do
    command(page, "locator.count", [], %{"selector" => selector})
  end

  @spec wait_for_selector(t(), String.t(), Keyword.t()) :: {:ok, true} | {:error, Node.error()}
  def wait_for_selector(%__MODULE__{} = page, selector, opts \\ []) when is_binary(selector) do
    command(page, "locator.wait_for", opts, %{"selector" => selector})
  end

  @spec evaluate(t(), String.t(), Jason.Encoder.value()) ::
          {:ok, Jason.Encoder.value()} | {:error, Node.error()}
  def evaluate(%__MODULE__{} = page, expression, argument \\ nil) when is_binary(expression) do
    Node.command(page.driver, "page.evaluate", %{
      "page_id" => page.id,
      "expression" => expression,
      "argument" => argument
    })
  end

  @spec wait_for(t(), String.t(), Keyword.t()) :: {:ok, true} | {:error, Node.error()}
  def wait_for(%__MODULE__{} = page, expression, opts \\ []) when is_binary(expression) do
    command(page, "page.wait_for", opts, %{"expression" => expression})
  end

  @spec key_down(t(), String.t()) :: {:ok, true} | {:error, Node.error()}
  def key_down(%__MODULE__{} = page, key), do: command(page, "keyboard.down", [], %{"key" => key})

  @spec key_up(t(), String.t()) :: {:ok, true} | {:error, Node.error()}
  def key_up(%__MODULE__{} = page, key), do: command(page, "keyboard.up", [], %{"key" => key})

  @spec key_press(t(), String.t(), Keyword.t()) :: {:ok, true} | {:error, Node.error()}
  def key_press(%__MODULE__{} = page, key, opts \\ []) do
    command(page, "keyboard.press", opts, %{"key" => key})
  end

  @spec key_press_when(t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, true} | {:error, Node.error()}
  def key_press_when(%__MODULE__{} = page, key, expression, opts \\ [])
      when is_binary(key) and is_binary(expression) do
    command(page, "keyboard.press_when", opts, %{"key" => key, "expression" => expression})
  end

  @spec key_hold_until(t(), String.t(), String.t(), Keyword.t()) ::
          {:ok, true} | {:error, Node.error()}
  def key_hold_until(%__MODULE__{} = page, key, expression, opts \\ [])
      when is_binary(key) and is_binary(expression) do
    command(page, "keyboard.hold_until", opts, %{"key" => key, "expression" => expression})
  end

  @spec mouse_move(t(), number(), number(), Keyword.t()) :: {:ok, true} | {:error, Node.error()}
  def mouse_move(%__MODULE__{} = page, x, y, opts \\ []) when is_number(x) and is_number(y) do
    command(page, "mouse.move", opts, %{"x" => x, "y" => y})
  end

  @spec mouse_down(t(), Keyword.t()) :: {:ok, true} | {:error, Node.error()}
  def mouse_down(%__MODULE__{} = page, opts \\ []), do: command(page, "mouse.down", opts)

  @spec mouse_hold_until(t(), String.t(), Keyword.t()) :: {:ok, true} | {:error, Node.error()}
  def mouse_hold_until(%__MODULE__{} = page, expression, opts \\ [])
      when is_binary(expression) do
    command(page, "mouse.hold_until", opts, %{"expression" => expression})
  end

  @spec mouse_hold_for(t(), pos_integer(), Keyword.t()) :: {:ok, true} | {:error, Node.error()}
  def mouse_hold_for(%__MODULE__{} = page, duration_ms, opts \\ [])
      when is_integer(duration_ms) and duration_ms > 0 do
    command(page, "mouse.hold_for", opts, %{"duration_ms" => duration_ms})
  end

  @spec mouse_up(t(), Keyword.t()) :: {:ok, true} | {:error, Node.error()}
  def mouse_up(%__MODULE__{} = page, opts \\ []), do: command(page, "mouse.up", opts)

  @spec resize(t(), pos_integer(), pos_integer()) :: {:ok, true} | {:error, Node.error()}
  def resize(%__MODULE__{} = page, width, height)
      when is_integer(width) and width > 0 and is_integer(height) and height > 0 do
    command(page, "page.resize", [], %{"width" => width, "height" => height})
  end

  @spec screenshot(t(), Keyword.t()) :: {:ok, Path.t()} | {:error, Node.error()}
  def screenshot(%__MODULE__{} = page, opts) do
    command(page, "page.screenshot", opts)
  end

  @spec video(t()) :: {:ok, Video.t() | nil} | {:error, Node.error()}
  def video(%__MODULE__{} = page) do
    case command(page, "page.video", []) do
      {:ok, %{"video_id" => id}} -> {:ok, %Video{driver: page.driver, id: id}}
      {:ok, nil} -> {:ok, nil}
      {:error, error} -> {:error, error}
    end
  end

  @spec close(t()) :: :ok | {:error, Node.error()}
  def close(%__MODULE__{} = page) do
    case command(page, "page.close", []) do
      {:ok, true} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  ## Private functions

  defp command(page, method, opts, extra \\ %{}) do
    params = opts |> Options.encode() |> Map.merge(extra) |> Map.put("page_id", page.id)
    Node.command(page.driver, method, params)
  end
end
