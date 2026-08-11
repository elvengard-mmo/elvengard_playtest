defmodule ElvenGard.Playtest.CanvasVideo do
  @moduledoc """
  An exact recording interval for one browser canvas.

  Canvas recordings start only when requested and stop independently from the
  page lifecycle. This is suited to deterministic gameplay clips where page
  setup, camera movement and browser UI must stay outside the artifact.
  """

  alias ElvenGard.Playtest.Video
  alias ElvenGard.Playtest.Driver.Node

  @type t :: %__MODULE__{
          driver: pid(),
          id: String.t(),
          mime_type: String.t(),
          width: pos_integer(),
          height: pos_integer(),
          fps: pos_integer()
        }
  defstruct [:driver, :id, :mime_type, :width, :height, :fps]

  ## Public API

  @spec stop(t()) :: {:ok, Video.t()} | {:error, Node.error()}
  def stop(%__MODULE__{} = recording) do
    case Node.command(recording.driver, "canvas_video.stop", %{"recording_id" => recording.id}) do
      {:ok, %{"video_id" => id}} -> {:ok, %Video{driver: recording.driver, id: id}}
      {:error, error} -> {:error, error}
    end
  end

  @spec cancel(t()) :: :ok | {:error, Node.error()}
  def cancel(%__MODULE__{} = recording) do
    case Node.command(recording.driver, "canvas_video.cancel", %{
           "recording_id" => recording.id
         }) do
      {:ok, true} -> :ok
      {:error, error} -> {:error, error}
    end
  end
end
