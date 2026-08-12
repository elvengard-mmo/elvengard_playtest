defmodule ElvenGard.Playtest.Video do
  @moduledoc """
  A Playwright page recording that can be saved after its page is closed.

  Playwright finalizes recordings when their page or browser context closes.
  Keep the returned video reference, close the page, then save it under the
  deterministic artifact path owned by the caller.
  """

  alias ElvenGard.Playtest.Driver.Node

  @type t :: %__MODULE__{driver: pid(), id: String.t()}
  defstruct [:driver, :id]

  ## Public API

  @spec save_as(t(), Path.t()) :: {:ok, Path.t()} | {:error, Node.error()}
  def save_as(%__MODULE__{} = video, path) when is_binary(path) do
    case Node.command(video.driver, "video.save_as", %{"video_id" => video.id, "path" => path}) do
      {:ok, ^path} -> {:ok, path}
      {:error, error} -> {:error, error}
    end
  end

  @spec delete(t()) :: :ok | {:error, Node.error()}
  def delete(%__MODULE__{} = video) do
    case Node.command(video.driver, "video.delete", %{"video_id" => video.id}) do
      {:ok, true} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
